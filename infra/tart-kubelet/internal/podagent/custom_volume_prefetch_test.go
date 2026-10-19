package podagent

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func warmCustomIdentity(scope string, generation int64) cachevolumes.Identity {
	return cachevolumes.Identity{
		ID: "11111111-1111-4111-8111-111111111111", Account: 1, Scope: strings.Repeat(scope, 64),
		BaseGeneration: generation, ImageDigest: strings.Repeat("b", 40), ContentDigest: strings.Repeat("c", 64),
	}
}

func waitClosed(t *testing.T, done <-chan struct{}, what string) {
	t.Helper()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal(what)
	}
}

func TestCustomPrefetchJoinsDuplicatesAndServesWaitingJobsFirst(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	release := make(chan struct{})
	started := make(chan struct{}, 4)
	var mu sync.Mutex
	var order []string
	p := newCustomPrefetcher(ctx, func(_ context.Context, slot cachevolumes.Slot, urgent bool) error {
		if urgent != (slot.Scope[0] != 'a' && slot.Scope[0] != 'b') {
			t.Error("lost a download's urgency", slot.Scope[:1], urgent)
		}
		mu.Lock()
		order = append(order, slot.Scope[:1])
		mu.Unlock()
		started <- struct{}{}
		if slot.Scope[0] == 'a' {
			<-release
		}
		return nil
	}, func(identity cachevolumes.Identity) bool { return identity.Scope[0] == 'z' })
	defer func() {
		cancel()
		p.wait.Wait()
	}()

	if p.start(cachevolumes.Identity{Scope: strings.Repeat("a", 64)}, true) != nil {
		t.Fatal("queued a cold identity")
	}
	if p.start(warmCustomIdentity("z", 1), true) != installed {
		t.Fatal("queued a master that is already on the host")
	}
	running := p.start(warmCustomIdentity("a", 1), false)
	waitClosed(t, func() <-chan struct{} {
		done := make(chan struct{})
		go func() { <-started; close(done) }()
		return done
	}(), "first download never started")
	listed := p.start(warmCustomIdentity("b", 1), false)
	waiting := p.start(warmCustomIdentity("c", 1), true)
	if p.start(warmCustomIdentity("b", 1), true) != listed {
		t.Fatal("downloaded the same master twice")
	}
	if p.start(warmCustomIdentity("b", 2), false) == listed {
		t.Fatal("joined another generation")
	}
	close(release)
	for _, done := range []<-chan struct{}{running, waiting, listed} {
		waitClosed(t, done, "prefetch never finished")
	}
	mu.Lock()
	defer mu.Unlock()
	if got := strings.Join(order[:3], ""); got != "acb" {
		t.Fatal("a waiting job did not go first", order)
	}
}

func TestCustomPrefetchBoundsEachDownload(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	finished := make(chan error, 1)
	p := &customPrefetcher{ctx: ctx, budget: 20 * time.Millisecond, pending: map[string]*customPrefetch{},
		urgent: make(chan *customPrefetch, 1), background: make(chan *customPrefetch, 1),
		restore: func(ctx context.Context, _ cachevolumes.Slot, _ bool) error {
			<-ctx.Done()
			finished <- ctx.Err()
			return ctx.Err()
		}}
	p.wait.Go(p.work)
	waitClosed(t, p.start(warmCustomIdentity("a", 1), true), "unbounded prefetch")
	if err := <-finished; !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal(err)
	}
	cancel()
	p.wait.Wait()
}

func TestCustomPrefetchShutdownReleasesWaiters(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	started := make(chan struct{})
	p := newCustomPrefetcher(ctx, func(ctx context.Context, _ cachevolumes.Slot, _ bool) error {
		close(started)
		<-ctx.Done()
		return ctx.Err()
	}, nil)
	running := p.start(warmCustomIdentity("a", 1), true)
	<-started
	queued := p.start(warmCustomIdentity("b", 1), false)
	cancel()
	waitClosed(t, running, "running prefetch outlived shutdown")
	waitClosed(t, queued, "queued waiter never released")
	p.wait.Wait()
	if p.start(warmCustomIdentity("c", 1), true) != nil {
		t.Fatal("queued work after shutdown")
	}
}

type recordingCustomBackend struct {
	cachevolumes.Backend
	installed atomic.Bool
	sawMaster atomic.Bool
}

func (b *recordingCustomBackend) Attach(ctx context.Context, _ cachevolumes.Slot, _ string) error {
	b.sawMaster.Store(b.installed.Load())
	return ctx.Err()
}
func (b *recordingCustomBackend) Measure(cachevolumes.Slot, string) (int64, int64, error) {
	return 0, 20_000_000_000, nil
}

func customMailbox(t *testing.T, identity cachevolumes.Identity, requestAge time.Duration) (*CustomVolumes, *recordingCustomBackend, *corev1.Pod, string) {
	t.Helper()
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "job", Namespace: "runners", UID: "job-uid"}}
	share := filepath.Join(root, "pods", string(pod.UID))
	if err := os.MkdirAll(share, 0755); err != nil {
		t.Fatal(err)
	}
	request := filepath.Join(share, "cache.request")
	if err := os.WriteFile(request, []byte(`{"key":"deps","uid":501}`), 0600); err != nil {
		t.Fatal(err)
	}
	modified := time.Now().Add(-requestAge)
	if err := os.Chtimes(request, modified, modified); err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(identity)
	}))
	t.Cleanup(server.Close)
	backend := &recordingCustomBackend{}
	store, err := cachevolumes.Open(root, backend)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close() })
	c := &CustomVolumes{Root: root, URL: server.URL, HTTP: server.Client(), Node: "host", Namespace: "runners", Store: store,
		tokenValue: "token", tokenUntil: time.Now().Add(time.Hour)}
	return c, backend, pod, request + ".response"
}

func readCustomResponse(t *testing.T, path string) map[string]any {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var response map[string]any
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatal(err)
	}
	return response
}

func TestCustomMailboxWaitsForAMasterThisHostLacks(t *testing.T) {
	identity := warmCustomIdentity("a", 2)
	c, backend, pod, response := customMailbox(t, identity, 0)
	ctx, cancel := context.WithCancel(context.Background())
	p := newCustomPrefetcher(ctx, func(context.Context, cachevolumes.Slot, bool) error {
		time.Sleep(50 * time.Millisecond)
		backend.installed.Store(true)
		return nil
	}, func(cachevolumes.Identity) bool { return backend.installed.Load() })
	defer func() {
		cancel()
		p.wait.Wait()
	}()
	c.prefetch.Store(p)
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	got := readCustomResponse(t, response)
	if got["id"] != identity.ID || got["warm"] != true || !backend.sawMaster.Load() {
		t.Fatal("job did not wait for the master", got)
	}
}

func TestCustomMailboxExplainsTimeoutAndKeepsDownloading(t *testing.T) {
	identity := warmCustomIdentity("a", 2)
	c, _, pod, response := customMailbox(t, identity, customAcquireBudget-100*time.Millisecond)
	ctx, cancel := context.WithCancel(context.Background())
	release := make(chan struct{})
	interrupted := make(chan bool, 1)
	p := newCustomPrefetcher(ctx, func(ctx context.Context, _ cachevolumes.Slot, _ bool) error {
		select {
		case <-release:
			interrupted <- false
		case <-ctx.Done():
			interrupted <- true
		}
		return ctx.Err()
	}, nil)
	defer func() {
		cancel()
		p.wait.Wait()
	}()
	c.prefetch.Store(p)
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	got := readCustomResponse(t, response)
	if got["error"] != "unavailable" || got["reason"] != "timeout" {
		t.Fatal(got)
	}
	close(release)
	if <-interrupted {
		t.Fatal("the download stopped with the job's deadline")
	}
}
