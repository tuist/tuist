package podagent

import (
	"context"
	"encoding/json"
	"errors"
	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	authenticationv1 "k8s.io/api/authentication/v1"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes/fake"
	ktesting "k8s.io/client-go/testing"
)

func TestCustomVolumeWriterFence(t *testing.T) {
	for _, tc := range []struct {
		name                                       string
		pod, running, apiError, runtimeError, want bool
	}{
		{name: "terminal pod still exists", pod: true},
		{name: "API gone VM alive", running: true},
		{name: "API error", apiError: true},
		{name: "runtime error", runtimeError: true},
		{name: "both fences", want: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			kube := fake.NewSimpleClientset()
			if tc.pod {
				_, _ = kube.CoreV1().Pods("runners").Create(context.Background(), &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "job", Namespace: "runners", UID: "uid"}, Status: corev1.PodStatus{Phase: corev1.PodSucceeded}}, metav1.CreateOptions{})
			}
			if tc.apiError {
				kube.PrependReactor("get", "pods", func(ktesting.Action) (bool, runtime.Object, error) { return true, nil, errors.New("API unavailable") })
			}
			c := &CustomVolumes{Kube: kube, Namespace: "runners", Running: func(_ context.Context, vm string) (bool, error) {
				if vm != "runners-job" {
					t.Fatal(vm)
				}
				if tc.runtimeError {
					return false, errors.New("pgrep unavailable")
				}
				return tc.running, nil
			}}
			got, err := c.gone("job", "uid")
			if got != tc.want {
				t.Fatalf("gone=%t want %t", got, tc.want)
			}
			if (tc.apiError || tc.runtimeError) != (err != nil) {
				t.Fatal(err)
			}
		})
	}
}

func TestCustomVolumeMailboxUsesHostIdentity(t *testing.T) {
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "host-pod", Namespace: "runners", UID: "host-uid"}}
	share := filepath.Join(root, "pods", string(pod.UID))
	if err := os.MkdirAll(share, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(share, "cache.request"), []byte(`{"key":"gradle","uid":501,"pod_name":"victim","node_name":"victim","platform":"linux"}`), 0600); err != nil {
		t.Fatal(err)
	}
	id := "11111111-1111-4111-8111-111111111111"
	scope := strings.Repeat("a", 64)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/authorize" || r.Header.Get("Authorization") != "Bearer host-only" {
			t.Error("unexpected request")
		}
		var got map[string]any
		if err := json.NewDecoder(r.Body).Decode(&got); err != nil {
			t.Error(err)
		}
		if got["pod_name"] != "host-pod" || got["pod_uid"] != "host-uid" || got["node_name"] != "host-node" || got["architecture"] != "arm64" || got["uid"] != float64(501) || got["platform"] != nil {
			t.Errorf("untrusted identity: %v", got)
		}
		_ = json.NewEncoder(w).Encode(cachevolumes.Identity{ID: id, Scope: scope, Account: 1, UID: 501})
	}))
	defer server.Close()
	kube := fake.NewSimpleClientset()
	kube.PrependReactor("create", "serviceaccounts", func(action ktesting.Action) (bool, runtime.Object, error) {
		if action.GetSubresource() != "token" || action.GetNamespace() != "runners" {
			t.Error("unexpected token request")
		}
		return true, &authenticationv1.TokenRequest{Status: authenticationv1.TokenRequestStatus{Token: "host-only"}}, nil
	})
	backend := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{Root: root, SizeGB: 20, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }}, Create: func(_ context.Context, p string, _ int64) error { return os.WriteFile(p, nil, 0600) }}
	if err := backend.Init(); err != nil {
		t.Fatal(err)
	}
	store, err := cachevolumes.Open(root, backend)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	c := &CustomVolumes{Root: root, URL: server.URL, HTTP: server.Client(), Node: "host-node", Namespace: "runners", ServiceAccount: "cache-agent", Kube: kube, Store: store}
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(share, "cache.request.response"))
	if err != nil {
		t.Fatal(err)
	}
	var response map[string]any
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatal(err)
	}
	if response["id"] != id || response["directory"] != scope {
		t.Fatal(string(data))
	}
	// An exposed file is not proof that the guest successfully mounted it.
	action, err := c.report(cachevolumes.Slot{Identity: cachevolumes.Identity{ID: id, Scope: scope}, PodUID: "host-uid", State: "active"}, false)
	if err != nil || action != "hold" {
		t.Fatalf("unmounted report: %s %v", action, err)
	}
}

func TestCustomVolumeReusesAndRefreshesHostToken(t *testing.T) {
	kube := fake.NewSimpleClientset()
	requests := 0
	kube.PrependReactor("create", "serviceaccounts", func(ktesting.Action) (bool, runtime.Object, error) {
		requests++
		return true, &authenticationv1.TokenRequest{Status: authenticationv1.TokenRequestStatus{Token: "host-only", ExpirationTimestamp: metav1.NewTime(time.Now().Add(time.Minute))}}, nil
	})
	c := &CustomVolumes{Kube: kube, Namespace: "runners", ServiceAccount: "cache-agent"}
	for range 2 {
		if token, err := c.token(context.Background()); err != nil || token != "host-only" {
			t.Fatal(token, err)
		}
	}
	if requests != 1 {
		t.Fatalf("minted %d tokens before expiry", requests)
	}
	if time.Until(c.tokenUntil) > 31*time.Second {
		t.Fatal("ignored API token expiration")
	}
	c.tokenUntil = time.Now().Add(-time.Second)
	if _, err := c.token(context.Background()); err != nil {
		t.Fatal(err)
	}
	if requests != 2 {
		t.Fatal("did not refresh expiring token")
	}
}

func TestCustomAdmissionGuardHonorsCancellation(t *testing.T) {
	m, _ := m2L(t)
	m.mu.Lock()
	defer m.mu.Unlock()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	c := &CustomVolumes{Builtins: m}
	if _, err := c.guard(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal(err)
	}
}

func TestCustomColdAdmissionBesideBuiltinOnM2(t *testing.T) {
	m, be := m2L(t)
	be.perMaster = 29 * gib
	seedMaster(t, m, "3")
	m.reserved = map[string]bool{"running-builtin": true}
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Builtins: m}
	slot := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111"}}
	finish, err := c.reserve(context.Background(), slot)
	if err != nil {
		t.Fatalf("20 GB cold volume fits beside a 30 GiB builtin reservation and 29 GiB master: %v", err)
	}
	if got := c.reservedBytes(); got != customCapacity {
		t.Fatalf("cold creation reserved %d bytes", got)
	}
	other := slot
	other.ID = "22222222-2222-4222-8222-222222222222"
	if _, err := c.reserve(context.Background(), other); !errors.Is(err, cachevolumes.ErrCapacity) {
		t.Fatalf("concurrent allocation ignored reservation: %v", err)
	}
	finish(false)
	slot.BaseGeneration = 1
	if _, err := c.reserve(context.Background(), slot); !errors.Is(err, cachevolumes.ErrCapacity) {
		t.Fatalf("restore ignored archive headroom: %v", err)
	}
}

func TestConvergenceReservesSpaceBesideCustomVolumes(t *testing.T) {
	m, _ := m2L(t)
	m.CustomReserved = func() uint64 { return 40 * gib }
	key := masterKey{account: "42", volume: ReservedTuistCacheVolume}
	if _, err := m.PrepareConvergeSpace(key, 25*gib, 25*gib, false, func(error) {}); !errors.Is(err, errNoRoomToConverge) {
		t.Fatalf("custom reservation ignored: %v", err)
	}
	m.CustomReserved = func() uint64 { return 0 }
	r, err := m.PrepareConvergeSpace(key, 25*gib, 25*gib, false, func(error) {})
	if err != nil {
		t.Fatal(err)
	}
	defer r.Release()
}

func TestCustomFreeBytesCountsOutstandingConvergence(t *testing.T) {
	m, _ := m2L(t)
	c := &CustomVolumes{Builtins: m, Root: m.Root}
	before, err := c.freeBytes("")
	if err != nil {
		t.Fatal(err)
	}
	m.converging = &convergeReservation{}
	m.converging.outstanding.Store(int64(10 * gib))
	after, err := c.freeBytes("")
	if err != nil || before-after != 10*gib {
		t.Fatal(before, after, err)
	}
}

func TestCustomShareAvailableBeforeWorkerStarts(t *testing.T) {
	m, be := m2L(t)
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Builtins: m}
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "job", UID: "uid"}}
	share, err := c.Share(pod)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(share); err != nil {
		t.Fatal(err)
	}
	owner, err := os.ReadFile(filepath.Join(c.Root, "owners", "uid"))
	if err != nil || string(owner) != "job" {
		t.Fatal(string(owner), err)
	}
	be.notMounted = true
	if _, err := c.Share(pod); err == nil {
		t.Fatal("shared unmounted cache filesystem")
	}
}

func TestCustomReservationUsesRemainingCapacityAndStopsWithVM(t *testing.T) {
	m, be := m2L(t)
	be.perMaster = 15_000_000_000
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Builtins: m, Namespace: "runners"}
	backend := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{Root: c.Root, SizeGB: 20, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }}, Reserve: c.reserve, Create: func(_ context.Context, path string, _ int64) error {
		if !m.mu.TryLock() {
			t.Error("built-in admission blocked during create")
		} else {
			m.mu.Unlock()
		}
		return os.WriteFile(path, nil, 0600)
	}}
	if err := backend.Init(); err != nil {
		t.Fatal(err)
	}
	store, err := cachevolumes.Open(c.Root, backend)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	c.Store = store
	id := cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111", Scope: strings.Repeat("a", 64), Account: 1}
	if _, err := store.Acquire(context.Background(), id, "job", "uid"); err != nil {
		t.Fatal(err)
	}
	if got := c.reservedBytes(); got != 5_000_000_000 {
		t.Fatal("double counted image allocation", got)
	}
	// Reconstruct the same reservation from the journal after an agent restart.
	c.reservations = nil
	c.Running = func(context.Context, string) (bool, error) { return true, nil }
	if err := c.refreshReservations(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := c.reservedBytes(); got != 5_000_000_000 {
		t.Fatal("lost reservation after restart", got)
	}
	c.Running = func(context.Context, string) (bool, error) { return false, nil }
	if err := c.refreshReservations(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := c.reservedBytes(); got != 0 {
		t.Fatal("stopped VM still reserves growth", got)
	}
	if _, err := os.Stat(filepath.Join(c.Root, "images", id.ID+".img")); err != nil {
		t.Fatal("removed pending image", err)
	}
}

func TestCustomPrefetchHasIndependentDeadlineAndNoQueue(t *testing.T) {
	started := make(chan struct{})
	finished := make(chan error, 1)
	p := &customPrefetcher{ctx: context.Background(), slots: make(chan struct{}, 1), budget: 20 * time.Millisecond, restore: func(ctx context.Context, _ cachevolumes.Slot) error {
		close(started)
		<-ctx.Done()
		finished <- ctx.Err()
		return ctx.Err()
	}}
	if p.start(cachevolumes.Identity{}) {
		t.Fatal("prefetching empty master")
	}
	if !p.start(cachevolumes.Identity{BaseGeneration: 1}) {
		t.Fatal("did not start")
	}
	<-started
	if p.start(cachevolumes.Identity{BaseGeneration: 1}) {
		t.Fatal("queued another prefetch")
	}
	select {
	case err := <-finished:
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("unbounded prefetch")
	}
	p.wait.Wait()
}

func TestCustomAdmissionLockWaitUsesRequestDeadline(t *testing.T) {
	m, _ := m2L(t)
	c := &CustomVolumes{Root: m.Root, Builtins: m}
	m.mu.Lock()
	defer m.mu.Unlock()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if _, err := c.freeBytesContext(ctx, ""); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal(err)
	}
}

// The same Store used by the scheduler blocks real Attach/Seal calls here, so
// this catches accidental reintroduction of a shared mailbox/publication loop.
type blockingCustomBackend struct {
	cachevolumes.Backend
	attachStarted, sealStarted chan struct{}
	release                    chan struct{}
}

func (b *blockingCustomBackend) Attach(ctx context.Context, slot cachevolumes.Slot, _ string) error {
	if slot.PodName == "slow" {
		close(b.attachStarted)
		select {
		case <-b.release:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return nil
}
func (b *blockingCustomBackend) Measure(cachevolumes.Slot, string) (int64, int64, error) {
	return 0, 20_000_000_000, nil
}
func (b *blockingCustomBackend) Seal(cachevolumes.Slot, string) error {
	close(b.sealStarted)
	<-b.release
	return nil
}

func TestCustomMailboxesProgressDuringSlowRestoreAndPublication(t *testing.T) {
	for _, operation := range []string{"restore", "publish"} {
		t.Run(operation, func(t *testing.T) {
			m, _ := m2L(t)
			root := filepath.Join(m.Root, "custom")
			backend := &blockingCustomBackend{attachStarted: make(chan struct{}), sealStarted: make(chan struct{}), release: make(chan struct{})}
			store, err := cachevolumes.Open(root, backend)
			if err != nil {
				t.Fatal(err)
			}
			defer store.Close()
			id := func(slow bool) cachevolumes.Identity {
				if slow {
					return cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111", Scope: strings.Repeat("a", 64), Account: 1, CanPublish: true}
				}
				return cachevolumes.Identity{ID: "22222222-2222-4222-8222-222222222222", Scope: strings.Repeat("b", 64), Account: 1}
			}
			kube := fake.NewSimpleClientset()
			addPod := func(name string) {
				pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "runners", UID: types.UID(name), Labels: map[string]string{"tuist.dev/runner": "true"}}, Spec: corev1.PodSpec{NodeName: "host"}, Status: corev1.PodStatus{Phase: corev1.PodRunning}}
				if _, err := kube.CoreV1().Pods("runners").Create(context.Background(), pod, metav1.CreateOptions{}); err != nil {
					t.Fatal(err)
				}
				path := filepath.Join(root, "pods", name)
				if err := os.MkdirAll(path, 0755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(path, "cache.request"), []byte(`{"key":"gradle","uid":501}`), 0600); err != nil {
					t.Fatal(err)
				}
			}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				var input struct {
					Pod string `json:"pod_name"`
				}
				_ = json.NewDecoder(r.Body).Decode(&input)
				if r.URL.Path == "/authorize" {
					_ = json.NewEncoder(w).Encode(id(input.Pod == "slow"))
				} else {
					_, _ = w.Write([]byte(`{"action":"seal"}`))
				}
			}))
			defer server.Close()
			c := &CustomVolumes{Root: root, Store: store, Kube: kube, Node: "host", Namespace: "runners", Builtins: m, URL: server.URL, HTTP: server.Client(), tokenValue: "token", tokenUntil: time.Now().Add(time.Hour), Running: func(context.Context, string) (bool, error) { return false, nil }}
			requests, reports := make(chan time.Time), make(chan time.Time)
			ctx, cancel := context.WithCancel(context.Background())
			stopped := make(chan struct{})
			go func() { defer close(stopped); _ = c.serve(ctx, requests, reports) }()
			// Release publication before waiting for shutdown; mailbox restores are canceled.
			defer func() {
				cancel()
				close(backend.release)
				<-stopped
			}()
			var started <-chan struct{}
			if operation == "restore" {
				addPod("slow")
				requests <- time.Now()
				started = backend.attachStarted
			} else {
				if _, err := store.Acquire(ctx, id(true), "finished", "finished"); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(root, "pods", "finished", id(true).Scope, ".mounted"), []byte(id(true).ID), 0600); err != nil {
					t.Fatal(err)
				}
				reports <- time.Now()
				started = backend.sealStarted
			}
			select {
			case <-started:
			case <-time.After(3 * time.Second):
				t.Fatal("slow operation never started")
			}
			addPod("fast")
			requests <- time.Now()
			deadline := time.After(3 * time.Second)
			for {
				data, err := os.ReadFile(filepath.Join(root, "pods", "fast", "cache.request.response"))
				if err == nil {
					if !strings.Contains(string(data), id(false).ID) {
						t.Fatalf("fast request failed: %s", data)
					}
					break
				}
				select {
				case <-deadline:
					t.Fatal("unrelated mailbox blocked behind slow work")
				case <-time.After(10 * time.Millisecond):
				}
			}
		})
	}
}

func TestCustomReservationRefreshPreservesConcurrentAdmission(t *testing.T) {
	m, _ := m2L(t)
	root := filepath.Join(m.Root, "custom")
	backend := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{Root: root, SizeGB: 20, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }}, Create: func(_ context.Context, p string, _ int64) error { return os.WriteFile(p, nil, 0600) }}
	if err := backend.Init(); err != nil {
		t.Fatal(err)
	}
	store, err := cachevolumes.Open(root, backend)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	id := cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111", Scope: strings.Repeat("a", 64), Account: 1}
	if _, err := store.Acquire(context.Background(), id, "old", "old"); err != nil {
		t.Fatal(err)
	}
	started, release := make(chan struct{}), make(chan struct{})
	c := &CustomVolumes{Root: root, Builtins: m, Store: store, Running: func(context.Context, string) (bool, error) { close(started); <-release; return false, nil }}
	finished := make(chan error, 1)
	go func() { finished <- c.refreshReservations(context.Background()) }()
	<-started
	pending := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "22222222-2222-4222-8222-222222222222"}}
	releaseReservation, err := c.reserve(context.Background(), pending)
	if err != nil {
		close(release)
		<-finished
		t.Fatal(err)
	}
	close(release)
	if err := <-finished; err != nil {
		t.Fatal(err)
	}
	if got := c.reservedBytes(); got != customCapacity {
		t.Fatal("lost in-flight reservation", got)
	}
	releaseReservation(false)
}
