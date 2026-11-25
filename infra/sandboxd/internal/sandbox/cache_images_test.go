package sandbox

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/checkout"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// copyingAgent stands in for the runner-cache agent: it holds the masters in
// masters by scope, lends the generation in older when it is set (an older
// master its node kept) and the grant's otherwise, and counts the copies it
// made.
type copyingAgent struct {
	mu      sync.Mutex
	masters map[string]string
	older   map[string]int64
	copies  map[string]int
	gate    chan struct{}
}

func (a *copyingAgent) CacheImage(_ context.Context, grant protocol.CacheGrant, held []int64, dst string, _ int64) (int64, bool, error) {
	if a.gate != nil {
		<-a.gate
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	data, ok := a.masters[grant.Scope]
	if !ok {
		return 0, false, checkout.ErrCold
	}
	generation := grant.BaseGeneration
	if g := a.older[grant.Scope]; g > 0 {
		generation = g
	}
	if slices.Contains(held, generation) {
		return generation, false, nil
	}
	a.copies[grant.Scope]++
	return generation, true, os.WriteFile(dst, []byte(data), 0o600)
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
	for waiting := 0; waiting < 1; {
		h.m.cacheImages.mu.Lock()
		if running := h.m.cacheImages.copying["a"]; running != nil {
			waiting = running.waiters
		}
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
		return filepath.Join(h.m.cfg.CacheImageDir, grantedImageName(scope, 2))
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

// A node whose agent kept only an older master of the granted lineage, as its
// prefetch does between refreshes, gets that cache, named and reported by its
// generation, and later grants of other heads that the agent answers with the
// same generation reuse the copy instead of streaming it again.
func TestCacheGrantAttachesAnOlderMasterOfTheLineage(t *testing.T) {
	ctx := context.Background()
	h := newHarness(t)
	h.m.builder.CacheDrive = true
	h.m.cfg.CacheImageDir = filepath.Join(h.dataDir, "cache-images")
	if err := os.MkdirAll(h.m.cfg.CacheImageDir, 0o700); err != nil {
		t.Fatal(err)
	}
	h.m.cfg.CacheImagesBytes = 1 << 30
	agent := &copyingAgent{masters: map[string]string{"a": "generation 39"}, older: map[string]int64{"a": 39}, copies: map[string]int{}}
	h.m.cacheImages.source = agent
	create := func(id string, generation int64) (protocol.CreateResult, error) {
		grant := grantFor("a")
		grant.BaseGeneration = generation
		return h.m.Create(ctx, protocol.CreateArgs{SandboxID: id, Template: "default", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: 10, CacheGrant: grant})
	}

	res, err := create("first", 41)
	if err != nil || res.CacheGeneration != 39 {
		t.Fatalf("a grant of 41 on a node holding 39 attached generation %d: %v", res.CacheGeneration, err)
	}
	if data, _ := os.ReadFile(filepath.Join(vm.RootDir(h.jailBase, "first"), "cache.ext4")); string(data) != "generation 39" {
		t.Fatalf("the cache drive holds %q", data)
	}
	if !vm.Exists(filepath.Join(h.m.cfg.CacheImageDir, grantedImageName("a", 39))) || vm.Exists(filepath.Join(h.m.cfg.CacheImageDir, grantedImageName("a", 41))) {
		t.Fatal("the copy must be named by the generation it holds, not the grant's")
	}
	if res, err := create("second", 42); err != nil || res.CacheGeneration != 39 || agent.copies["a"] != 1 {
		t.Fatalf("a later head answered with the held generation got %d after %d copies: %v", res.CacheGeneration, agent.copies["a"], err)
	}

	// Once the agent holds the head, the node copies it and reports it.
	agent.older["a"], agent.masters["a"] = 0, "generation 43"
	if res, err := create("third", 43); err != nil || res.CacheGeneration != 43 || agent.copies["a"] != 2 {
		t.Fatalf("the head's own master attached generation %d after %d copies: %v", res.CacheGeneration, agent.copies["a"], err)
	}
	if res, err := create("fourth", 43); err != nil || res.CacheGeneration != 43 || agent.copies["a"] != 2 {
		t.Fatalf("a copy of the granted head must be used without asking: %d after %d copies: %v", res.CacheGeneration, agent.copies["a"], err)
	}

	// An agent lending a generation newer than the grant is refused.
	agent.older["a"] = 50
	if _, err := create("fifth", 44); !errors.Is(err, ErrCacheImage) {
		t.Fatalf("a lent generation past the grant answered %v", err)
	}

	// A create that fails after the grant reports no cache it attached.
	agent.older["a"] = 0
	grant := grantFor("a")
	grant.BaseGeneration = 43
	res, err = h.m.Create(ctx, protocol.CreateArgs{SandboxID: "sixth", Template: "missing", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: 10, CacheGrant: grant})
	if err == nil || res.CacheGeneration != 0 {
		t.Fatalf("a failed create reported generation %d: %v", res.CacheGeneration, err)
	}
}
