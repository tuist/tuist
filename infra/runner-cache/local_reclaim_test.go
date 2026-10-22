package cachevolumes

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestAdmissionReclaimsLocalMastersBeforeSharedDisk(t *testing.T) {
	root := t.TempDir()
	master := filepath.Join(root, "masters", strings.Repeat("a", 64), "cache.img")
	if err := os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(master, nil, 0600); err != nil {
		t.Fatal(err)
	}
	free := uint64(0)
	b := &LocalImages{Root: root, FreeBytes: func(string) (uint64, error) { return free, nil }}
	calls := 0
	b.Reclaim = func(_ context.Context, minimum uint64) error {
		calls++
		if _, err := os.Stat(master); !os.IsNotExist(err) {
			t.Fatal("shared reclamation ran before local eviction", err)
		}
		free = minimum
		return nil
	}
	if err := b.reserveBytes(context.Background(), 20); err != nil {
		t.Fatal(err)
	}
	if err := b.reserveBytes(context.Background(), 20); err != nil || calls != 1 {
		t.Fatal("unnecessarily reclaimed shared disk", calls, err)
	}
}

func TestSharedReclamationMustActuallyFreeSpace(t *testing.T) {
	b := &LocalImages{Root: t.TempDir(), FreeBytes: func(string) (uint64, error) { return 0, nil }}
	b.Reclaim = func(context.Context, uint64) error { return nil }
	if err := b.reserveBytes(context.Background(), 20); !errors.Is(err, ErrCapacity) {
		t.Fatal("accepted reclamation without recovering space", err)
	}
	b.Reclaim = func(context.Context, uint64) error { return context.Canceled }
	if err := b.reserveBytes(context.Background(), 20); !errors.Is(err, context.Canceled) {
		t.Fatal("lost reclamation failure", err)
	}
}

// A background prefetch holding space gives it back before admission evicts a
// master that jobs on this host still clone from.
func TestAdmissionDisplacesSpeculativeWorkBeforeEvicting(t *testing.T) {
	root := t.TempDir()
	master := filepath.Join(root, "masters", strings.Repeat("a", 64), "cache.img")
	if err := os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(master, nil, 0600); err != nil {
		t.Fatal(err)
	}
	free := uint64(0)
	b := &LocalImages{Root: root, FreeBytes: func(string) (uint64, error) { return free, nil }}
	b.Displace = func(context.Context) bool {
		free = 20
		return true
	}
	if err := b.reserveBytes(context.Background(), 20); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(master); err != nil {
		t.Fatal("evicted a master although displacing the prefetch made room", err)
	}
}

// installedBytes reports free space as if each installed master held per bytes
// of a disk that started full with initial masters.
func installedBytes(root string, initial int, per uint64) func(string) (uint64, error) {
	return func(string) (uint64, error) {
		masters, err := filepath.Glob(filepath.Join(root, "masters", "*", "*.img"))
		if err != nil || len(masters) > initial {
			return 0, err
		}
		return uint64(initial-len(masters)) * per, nil
	}
}

// Nothing clones a generation once a newer one of its lineage is local, so it
// goes before another lineage's only copy, however recently it was touched.
func TestAdmissionEvictsSupersededGenerationsFirst(t *testing.T) {
	b, _ := newLocal(t)
	b.Transfer = &headTransfer{heads: map[string]Identity{}, errs: map[string]error{}}
	only := installMaster(t, b, first, strings.Repeat("b", 64), 1, time.Now().Add(-3*time.Hour))
	superseded := installMaster(t, b, second, strings.Repeat("a", 64), 1, time.Now().Add(-2*time.Hour))
	newest := installMaster(t, b, second, strings.Repeat("a", 64), 2, time.Now().Add(-time.Hour))
	b.FreeBytes = installedBytes(b.Root, 3, 20)

	if err := b.reserveBytes(context.Background(), 20); err != nil {
		t.Fatal(err)
	}
	if exists(b.master(superseded)) || !exists(b.master(only)) || !exists(b.master(newest)) {
		t.Fatal("evicted a lineage's only copy before a superseded generation")
	}
}

// A copy the host downloaded only because it had free space goes before one a
// job on this host cloned or published, even when the job's is older. Once a
// job clones it, it counts as used like any other.
func TestAdmissionEvictsSpeculativePrefetchesBeforeUsedMasters(t *testing.T) {
	b, remote := newAPFS(t)
	remote.source = filepath.Join(t.TempDir(), "archive")
	if err := os.WriteFile(remote.source, []byte("prefetched"), 0600); err != nil {
		t.Fatal(err)
	}
	published := installMaster(t, &b.LocalImages, first, strings.Repeat("a", 64), 1, time.Now().Add(-70*time.Minute))
	spare := func(scope string) Slot {
		slot := Slot{Identity: identity(second)}
		slot.Scope = scope
		slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = head(1).BaseGeneration, head(1).ImageDigest, head(1).ContentDigest
		if err := b.PrefetchSpare(context.Background(), slot); err != nil {
			t.Fatal(err)
		}
		return slot
	}
	cloned := spare(strings.Repeat("b", 64))
	speculative := spare(strings.Repeat("c", 64))
	job := Slot{Identity: cloned.Identity, PodUID: "pod"}
	job.ID = third
	if err := b.Attach(context.Background(), job, apfsPath(t, b, job)); err != nil || b.Cold(job) {
		t.Fatal("did not clone the prefetched master", err)
	}
	old := time.Now().Add(-10 * time.Minute)
	if err := os.Chtimes(b.master(cloned), old, old); err != nil {
		t.Fatal(err)
	}
	b.FreeBytes = installedBytes(b.Root, 3, 20)

	if err := b.reserveBytes(context.Background(), 20); err != nil {
		t.Fatal(err)
	}
	if exists(b.master(speculative)) || !exists(b.master(published)) || !exists(b.master(cloned)) {
		t.Fatal("evicted a master a job used before a speculative prefetch")
	}
	if err := b.reserveBytes(context.Background(), 40); err != nil {
		t.Fatal(err)
	}
	if exists(b.master(published)) || !exists(b.master(cloned)) {
		t.Fatal("a cloned prefetch did not count as used")
	}
}

// A job's own lineage is evicted last: its clone shares the master's blocks, so
// removing it frees little, and a job still attaching would lose its base.
func TestAdmissionKeepsTheLineageAJobIsAttaching(t *testing.T) {
	b, _ := newAPFS(t)
	b.Transfer = &headTransfer{heads: map[string]Identity{}, errs: map[string]error{}}
	own := installMaster(t, &b.LocalImages, first, strings.Repeat("a", 64), 1, time.Now().Add(-2*time.Hour))
	other := installMaster(t, &b.LocalImages, second, strings.Repeat("b", 64), 1, time.Now().Add(-time.Hour))
	b.FreeBytes = installedBytes(b.Root, 2, 20_000_000_000)
	store, err := Open(b.Root, b)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	b.InUse = store.InUse

	id := own.Identity
	id.ID = third
	warm, err := store.Acquire(context.Background(), id, "job", "pod")
	if err != nil {
		t.Fatal(err)
	}
	if !warm || !exists(b.master(own)) || exists(b.master(other)) {
		t.Fatal("admission evicted the master the attaching job clones", warm)
	}
}

// The successor a spare prefetch downloads for a lineage jobs used here is not
// speculative; one that follows a speculative copy still is.
func TestSparePrefetchOfAUsedLineageCountsAsUsed(t *testing.T) {
	b, remote := newAPFS(t)
	remote.source = filepath.Join(t.TempDir(), "archive")
	if err := os.WriteFile(remote.source, []byte("prefetched"), 0600); err != nil {
		t.Fatal(err)
	}
	successor := func(scope string, generation int64) Slot {
		slot := Slot{Identity: identity(second)}
		slot.Scope = scope
		slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = head(generation).BaseGeneration, head(generation).ImageDigest, head(generation).ContentDigest
		if err := b.PrefetchSpare(context.Background(), slot); err != nil {
			t.Fatal(err)
		}
		return slot
	}
	installMaster(t, &b.LocalImages, first, strings.Repeat("a", 64), 1, time.Now())
	if used := successor(strings.Repeat("a", 64), 2); speculative(b.master(used)) {
		t.Fatal("the successor of a used master is speculative")
	}
	if guess := successor(strings.Repeat("b", 64), 1); !speculative(b.master(guess)) {
		t.Fatal("a lineage no job used here is not speculative")
	}
	if next := successor(strings.Repeat("b", 64), 2); !speculative(b.master(next)) {
		t.Fatal("the successor of a speculative copy counts as used")
	}
}
