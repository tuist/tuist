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

func TestCustomPrefetchJoinsDuplicatesAndServesRequestedMastersFirst(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	release := make(chan struct{})
	started := make(chan struct{}, 4)
	var mu sync.Mutex
	var order []string
	p := newCustomPrefetcher(ctx, func(_ context.Context, slot cachevolumes.Slot, requested bool) error {
		if requested != (slot.Scope[0] != 'a' && slot.Scope[0] != 'b') {
			t.Error("lost whether a job requested a download", slot.Scope[:1], requested)
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
	if p.start(warmCustomIdentity("z", 1), true) != resolved {
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
		t.Fatal("a requested master did not go first", order)
	}
}

func TestCustomPrefetchBoundsEachDownload(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	finished := make(chan error, 1)
	p := &customPrefetcher{ctx: ctx, budget: 20 * time.Millisecond, pending: map[string]*customPrefetch{}, failed: map[string]time.Time{},
		requested: make(chan *customPrefetch, 1), background: make(chan *customPrefetch, 1),
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

// slowCustomBackend restores until the request deadline when slow is set.
type slowCustomBackend struct {
	cachevolumes.Backend
	slow atomic.Bool
}

func (b *slowCustomBackend) Attach(ctx context.Context, _ cachevolumes.Slot, _ string) error {
	if b.slow.Load() {
		<-ctx.Done()
	}
	return ctx.Err()
}
func (b *slowCustomBackend) Measure(cachevolumes.Slot, string) (int64, int64, error) {
	return 0, 20_000_000_000, nil
}

func customMailbox(t *testing.T, identity cachevolumes.Identity, requestAge time.Duration) (*CustomVolumes, *slowCustomBackend, *corev1.Pod, string) {
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
	backend := &slowCustomBackend{}
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

func TestCustomMailboxNeverWaitsOnABackgroundDownload(t *testing.T) {
	identity := warmCustomIdentity("a", 2)
	c, _, pod, response := customMailbox(t, identity, 0)
	ctx, cancel := context.WithCancel(context.Background())
	release := make(chan struct{})
	p := newCustomPrefetcher(ctx, func(context.Context, cachevolumes.Slot, bool) error {
		<-release
		return nil
	}, nil)
	defer func() {
		close(release)
		cancel()
		p.wait.Wait()
	}()
	c.prefetch.Store(p)
	p.start(identity, false)
	started := time.Now()
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	if time.Since(started) > time.Second {
		t.Fatal("the job waited on a background download")
	}
	if got := readCustomResponse(t, response); got["id"] != identity.ID {
		t.Fatal(got)
	}
}

func TestCustomMailboxQueuesATimedOutMasterAndExplains(t *testing.T) {
	identity := warmCustomIdentity("a", 2)
	c, backend, pod, response := customMailbox(t, identity, customAcquireBudget-100*time.Millisecond)
	backend.slow.Store(true)
	ctx, cancel := context.WithCancel(context.Background())
	release := make(chan struct{})
	interrupted := make(chan bool, 1)
	p := newCustomPrefetcher(ctx, func(ctx context.Context, _ cachevolumes.Slot, requested bool) error {
		if !requested {
			t.Error("a master the job asked for was queued as speculative")
		}
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

func TestCustomPrefetchWaitsBeforeRetryingAFailedDownload(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	var attempts atomic.Int32
	p := newCustomPrefetcher(ctx, func(context.Context, cachevolumes.Slot, bool) error {
		attempts.Add(1)
		return errors.New("object store unavailable")
	}, nil)
	defer func() {
		cancel()
		p.wait.Wait()
	}()
	identity := warmCustomIdentity("a", 2)
	waitClosed(t, p.start(identity, false), "failed download never finished")
	if p.start(identity, true) != resolved || attempts.Load() != 1 {
		t.Fatal("retried a failed download right away")
	}
	p.mu.Lock()
	p.failed[prefetchKey(identity)] = time.Now().Add(-customPrefetchRetry)
	p.mu.Unlock()
	waitClosed(t, p.start(identity, true), "retry never finished")
	if attempts.Load() != 2 {
		t.Fatal("did not retry after the backoff", attempts.Load())
	}
}

func TestCustomReportsTheGenerationAJobMounted(t *testing.T) {
	var got map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(&got)
		_, _ = w.Write([]byte(`{"action":"keep"}`))
	}))
	defer server.Close()
	c := &CustomVolumes{Root: t.TempDir(), URL: server.URL, HTTP: server.Client(), Node: "host", tokenValue: "token", tokenUntil: time.Now().Add(time.Hour)}
	slot := cachevolumes.Slot{Identity: warmCustomIdentity("a", 3), PodUID: "pod", State: "sealed", MountedGeneration: 2}
	if _, err := c.report(slot, true); err != nil {
		t.Fatal(err)
	}
	if got["mounted_generation"] != float64(2) {
		t.Fatal("mounted generation not reported", got)
	}
	slot.MountedGeneration = 0
	if _, err := c.report(slot, true); err != nil {
		t.Fatal(err)
	}
	if got["mounted_generation"] != nil {
		t.Fatal("reported a mounted generation for a job that got its base", got)
	}
}

func TestCustomMailboxQueuesTheHeadAfterAnOlderMount(t *testing.T) {
	identity := warmCustomIdentity("a", 2)
	c, _, pod, response := customMailbox(t, identity, 0)
	ctx, cancel := context.WithCancel(context.Background())
	fetched := make(chan bool, 1)
	p := newCustomPrefetcher(ctx, func(_ context.Context, slot cachevolumes.Slot, requested bool) error {
		if slot.BaseGeneration == identity.BaseGeneration {
			fetched <- requested
		}
		return nil
	}, func(cachevolumes.Identity) bool { return false })
	defer func() {
		cancel()
		p.wait.Wait()
	}()
	c.prefetch.Store(p)
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	if got := readCustomResponse(t, response); got["id"] != identity.ID {
		t.Fatal(got)
	}
	select {
	case requested := <-fetched:
		if !requested {
			t.Fatal("the HEAD a job asked for was queued as speculative")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("the HEAD was not fetched after the job mounted without it")
	}
}
