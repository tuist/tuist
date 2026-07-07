package podagent

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestWriteEndpoint(t *testing.T) {
	dir := t.TempDir()
	if err := WriteEndpoint(dir, "192.168.64.1", 4000); err != nil {
		t.Fatalf("WriteEndpoint: %v", err)
	}
	b, err := os.ReadFile(filepath.Join(dir, RunnerCacheEndpointFile))
	if err != nil {
		t.Fatalf("read marker: %v", err)
	}
	if got := strings.TrimSpace(string(b)); got != "http://192.168.64.1:4000" {
		t.Fatalf("endpoint marker = %q, want http://192.168.64.1:4000", got)
	}
}

// fakeKura is a KuraProcess that never execs anything.
type fakeKura struct {
	mu      sync.Mutex
	ready   bool
	stopped bool
	exited  bool
	spec    KuraSpec
}

func (f *fakeKura) Ready(context.Context) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.ready
}

func (f *fakeKura) Exited() bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.exited
}

func (f *fakeKura) die() {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.exited = true
}

func (f *fakeKura) Stop() error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.stopped = true
	f.exited = true
	return nil
}

// fakeStarter records every spec it is asked to start and hands back a fakeKura.
type fakeStarter struct {
	mu    sync.Mutex
	specs []KuraSpec
	procs []*fakeKura
	ready bool
	err   error
}

func (s *fakeStarter) start(_ context.Context, _ string, spec KuraSpec) (KuraProcess, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.err != nil {
		return nil, s.err
	}
	p := &fakeKura{ready: s.ready, spec: spec}
	s.specs = append(s.specs, spec)
	s.procs = append(s.procs, p)
	return p, nil
}

func newManager(s *fakeStarter) *HostKuraManager {
	return &HostKuraManager{
		Root:       "/cache",
		KuraBinary: "/usr/local/bin/kura",
		BasePort:   4000,
		Start:      s.start,
	}
}

func TestHostKura_EnsureStartsOnceAndIsIdempotent(t *testing.T) {
	s := &fakeStarter{ready: true}
	m := newManager(s)
	ctx := context.Background()

	port, ready, err := m.Ensure(ctx, "acct-a")
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if port != 4000 || !ready {
		t.Fatalf("got port=%d ready=%v, want 4000/true", port, ready)
	}

	// Second Ensure for the same account must reuse the process (no restart).
	port2, _, err := m.Ensure(ctx, "acct-a")
	if err != nil {
		t.Fatalf("Ensure #2: %v", err)
	}
	if port2 != port {
		t.Fatalf("port changed on second Ensure: %d != %d", port2, port)
	}
	if len(s.specs) != 1 {
		t.Fatalf("started %d processes, want 1 (idempotent)", len(s.specs))
	}
}

func TestHostKura_DistinctAccountsGetDistinctPortBlocks(t *testing.T) {
	s := &fakeStarter{ready: true}
	m := newManager(s)
	ctx := context.Background()

	a, _, _ := m.Ensure(ctx, "acct-a")
	b, _, _ := m.Ensure(ctx, "acct-b")
	if a != 4000 || b != 4003 {
		t.Fatalf("got a=%d b=%d, want 4000/4003 (blocks of %d)", a, b, portsPerNode)
	}
}

func TestHostKura_SpecCarriesDataDirTenantAndPeer(t *testing.T) {
	s := &fakeStarter{ready: true}
	m := newManager(s)
	m.PeerURLFor = func(id string) string { return "http://em.pn:7443/" + id }

	if _, _, err := m.Ensure(context.Background(), "acct-a"); err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	got := s.specs[0]
	if got.DataDir != "/cache/accounts/acct-a/current" {
		t.Errorf("DataDir=%q", got.DataDir)
	}
	if got.AccountID != "acct-a" {
		t.Errorf("AccountID=%q", got.AccountID)
	}
	if got.PeerURL != "http://em.pn:7443/acct-a" {
		t.Errorf("PeerURL=%q", got.PeerURL)
	}
}

func TestHostKura_StopReleasesPortForReuse(t *testing.T) {
	s := &fakeStarter{ready: true}
	m := newManager(s)
	ctx := context.Background()

	a, _, _ := m.Ensure(ctx, "acct-a")
	if err := m.Stop("acct-a"); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if m.Running("acct-a") {
		t.Fatal("account still running after Stop")
	}
	if !s.procs[0].stopped {
		t.Fatal("process was not asked to Stop")
	}
	// A fresh account should reclaim the freed block (lowest free base).
	c, _, _ := m.Ensure(ctx, "acct-c")
	if c != a {
		t.Fatalf("freed port not reused: got %d, want %d", c, a)
	}
}

func TestHostKura_StartErrorFreesTheBlock(t *testing.T) {
	s := &fakeStarter{err: errors.New("boom")}
	m := newManager(s)
	if _, _, err := m.Ensure(context.Background(), "acct-a"); err == nil {
		t.Fatal("expected start error")
	}
	// The failed allocation must not leak: switch to a working starter and the
	// next account gets the base port.
	s.err = nil
	s.ready = true
	port, _, err := m.Ensure(context.Background(), "acct-a")
	if err != nil {
		t.Fatalf("Ensure after recovery: %v", err)
	}
	if port != 4000 {
		t.Fatalf("port=%d after freed failed alloc, want 4000", port)
	}
}

func TestHostKura_EnsureRestartsDiedProcess(t *testing.T) {
	s := &fakeStarter{ready: true}
	m := newManager(s)
	ctx := context.Background()

	port, _, err := m.Ensure(ctx, "acct-a")
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	s.procs[0].die() // crash/OOM

	// A subsequent Ensure must respawn on the SAME port block, not hand back the
	// corpse, so the endpoint the reconciler already wrote stays valid.
	port2, ready, err := m.Ensure(ctx, "acct-a")
	if err != nil {
		t.Fatalf("Ensure after death: %v", err)
	}
	if port2 != port {
		t.Fatalf("restart moved the port: %d != %d", port2, port)
	}
	if !ready {
		t.Fatal("fresh process should be ready")
	}
	if len(s.specs) != 2 {
		t.Fatalf("expected a restart (2 starts), got %d", len(s.specs))
	}
	if !s.procs[0].stopped {
		t.Fatal("died process was not reaped on restart")
	}
}

func TestHostKura_RestartFailureFreesBlock(t *testing.T) {
	s := &fakeStarter{ready: true}
	m := newManager(s)
	ctx := context.Background()

	port, _, _ := m.Ensure(ctx, "acct-a")
	s.procs[0].die()

	s.mu.Lock()
	s.err = errors.New("exec failed")
	s.mu.Unlock()
	if _, _, err := m.Ensure(ctx, "acct-a"); err == nil {
		t.Fatal("expected restart error")
	}
	if m.Running("acct-a") {
		t.Fatal("account should be forgotten after a failed restart")
	}

	// The freed block must be reclaimable by a fresh account.
	s.mu.Lock()
	s.err = nil
	s.mu.Unlock()
	p2, _, err := m.Ensure(ctx, "acct-b")
	if err != nil {
		t.Fatalf("Ensure acct-b: %v", err)
	}
	if p2 != port {
		t.Fatalf("freed block not reused: got %d, want %d", p2, port)
	}
}

func TestHostKura_LeastRecentlyUsedPicksColdest(t *testing.T) {
	s := &fakeStarter{ready: true}
	m := newManager(s)
	base := time.Unix(1000, 0)
	tick := base
	m.nowFn = func() time.Time { return tick }
	ctx := context.Background()

	tick = base
	_, _, _ = m.Ensure(ctx, "acct-a")
	tick = base.Add(time.Minute)
	_, _, _ = m.Ensure(ctx, "acct-b")
	// Touch a so b becomes the coldest.
	tick = base.Add(2 * time.Minute)
	m.Touch("acct-a")

	if got := m.LeastRecentlyUsed(); got != "acct-b" {
		t.Fatalf("LRU=%q, want acct-b", got)
	}
}

func TestHostKura_EnsureRejectsUnsafeAccountID(t *testing.T) {
	m := newManager(&fakeStarter{ready: true})
	if _, _, err := m.Ensure(context.Background(), "../escape"); err == nil {
		t.Fatal("expected unsafe account id to be rejected")
	}
}
