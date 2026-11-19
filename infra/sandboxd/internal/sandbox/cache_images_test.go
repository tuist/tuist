package sandbox

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/checkout"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// copyingAgent stands in for the runner-cache agent: it holds the masters in
// masters by scope and counts the copies it made.
type copyingAgent struct {
	mu      sync.Mutex
	masters map[string]string
	copies  map[string]int
	gate    chan struct{}
}

func (a *copyingAgent) CacheImage(_ context.Context, grant protocol.CacheGrant, dst string, _ int64) error {
	if a.gate != nil {
		<-a.gate
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	data, ok := a.masters[grant.Scope]
	if !ok {
		return checkout.ErrCold
	}
	a.copies[grant.Scope]++
	return os.WriteFile(dst, []byte(data), 0o600)
}

func grantFor(scope string) *protocol.CacheGrant {
	return &protocol.CacheGrant{ID: "11111111-1111-4111-8111-111111111111", Scope: scope, BaseGeneration: 2, ImageDigest: strings.Repeat("c", 40), ContentDigest: strings.Repeat("b", 64)}
}

func TestCacheGrantCopiesTheMasterOncePerNode(t *testing.T) {
	ctx := context.Background()
	h := newHarness(t)
	h.m.builder.CacheDrive = true
	create := func(id string, grant *protocol.CacheGrant) error {
		_, err := h.m.Create(ctx, protocol.CreateArgs{SandboxID: id, Template: "default", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: 10, CacheGrant: grant})
		return err
	}
	if err := create("off", grantFor("a")); !errors.Is(err, ErrCacheImage) {
		t.Fatalf("a daemon that copies no cache images answered %v", err)
	}

	h.m.cfg.CacheImageDir = filepath.Join(h.dataDir, "cache-images")
	if err := os.MkdirAll(h.m.cfg.CacheImageDir, 0o700); err != nil {
		t.Fatal(err)
	}
	// Room for one copy: every new copy evicts the ones no create is using.
	h.m.cfg.CacheImagesBytes = 1
	agent := &copyingAgent{masters: map[string]string{"a": "cache a", "b": "cache b"}, copies: map[string]int{}, gate: make(chan struct{})}
	h.m.cacheImages.source = agent
	operator := filepath.Join(h.m.cfg.CacheImageDir, "go-cache")
	if err := os.WriteFile(operator, []byte("placed by hand"), 0o600); err != nil {
		t.Fatal(err)
	}

	var wg sync.WaitGroup
	errs := make([]error, 2)
	for i, id := range []string{"first", "second"} {
		wg.Add(1)
		go func() {
			defer wg.Done()
			errs[i] = create(id, grantFor("a"))
		}()
	}
	// Both creates wait on the copy before the agent answers.
	for pinned := 0; pinned < 2; {
		h.m.cacheImages.mu.Lock()
		pinned = h.m.cacheImages.pins[grantedImageName(*grantFor("a"))]
		h.m.cacheImages.mu.Unlock()
		time.Sleep(time.Millisecond)
	}
	close(agent.gate)
	wg.Wait()
	if errs[0] != nil || errs[1] != nil {
		t.Fatalf("creates: %v", errs)
	}
	if agent.copies["a"] != 1 {
		t.Fatalf("two creates of one head copied it %d times", agent.copies["a"])
	}
	for _, id := range []string{"first", "second"} {
		if data, _ := os.ReadFile(filepath.Join(vm.RootDir(h.jailBase, id), "cache.ext4")); string(data) != "cache a" {
			t.Fatalf("%s's cache drive holds %q", id, data)
		}
	}

	if err := create("cold", grantFor("missing")); !errors.Is(err, ErrCacheCold) {
		t.Fatalf("a head the node does not hold answered %v", err)
	}
	if err := create("third", grantFor("b")); err != nil {
		t.Fatal(err)
	}
	named := func(scope string) string {
		return filepath.Join(h.m.cfg.CacheImageDir, grantedImageName(*grantFor(scope)))
	}
	if vm.Exists(named("a")) || !vm.Exists(named("b")) || !vm.Exists(operator) {
		t.Fatal("eviction must drop the unused copy, keep the one in use and leave operator images")
	}
	if data, _ := os.ReadFile(filepath.Join(vm.RootDir(h.jailBase, "first"), "cache.ext4")); string(data) != "cache a" {
		t.Fatal("evicting a copy must not touch the sandboxes cloned from it")
	}
	if err := create("fourth", grantFor("a")); err != nil || agent.copies["a"] != 2 {
		t.Fatalf("an evicted head must be copied again: %v, %d copies", err, agent.copies["a"])
	}
	if entries, _ := filepath.Glob(filepath.Join(h.m.cfg.CacheImageDir, partialImagePrefix+"*")); len(entries) != 0 {
		t.Fatalf("copies left %v behind", entries)
	}

	// A copy nobody used for the TTL goes even with room to spare, so the
	// cache of a cleared volume or a deleted account does not linger.
	h.m.cfg.CacheImagesBytes, h.m.cfg.CacheImagesTTL = 1<<30, time.Hour
	stale := time.Now().Add(-2 * time.Hour)
	for _, path := range []string{named("a"), operator} {
		if err := os.Chtimes(path, stale, stale); err != nil {
			t.Fatal(err)
		}
	}
	h.m.ExpireCacheImages()
	if vm.Exists(named("a")) || !vm.Exists(operator) {
		t.Fatal("expiry must drop unused copies and leave operator images")
	}
}
