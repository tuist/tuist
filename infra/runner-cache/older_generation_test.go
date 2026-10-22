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

func TestAPFSMountsAnOlderGenerationWhenItsBaseIsNotLocal(t *testing.T) {
	b, _ := newAPFS(t)
	remote := &headTransfer{heads: map[string]Identity{}, errs: map[string]error{}}
	b.Transfer = remote
	scope := strings.Repeat("a", 64)
	installMaster(t, &b.LocalImages, first, scope, 1, time.Now())
	installMaster(t, &b.LocalImages, first, scope, 4, time.Now())
	if err := os.WriteFile(b.master(installMaster(t, &b.LocalImages, first, scope, 2, time.Now())), []byte("generation 2"), 0600); err != nil {
		t.Fatal(err)
	}
	slot := Slot{Identity: identity(second), PodUID: "pod"}
	slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = head(3).BaseGeneration, head(3).ImageDigest, head(3).ContentDigest

	if err := b.Attach(context.Background(), slot, apfsPath(t, b, slot)); err != nil {
		t.Fatal(err)
	}
	if len(remote.downloads()) != 0 {
		t.Fatal("downloaded the base inside the job's budget instead of mounting an older master")
	}
	if data, _ := os.ReadFile(filepath.Join(apfsPath(t, b, slot), SharedImageName)); string(data) != "generation 2" {
		t.Fatalf("cloned %q, want the newest older generation", data)
	}
	if got := b.MountedGeneration(slot); got != 2 {
		t.Fatalf("mounted generation = %d, want 2", got)
	}
	if err := b.Delete(slot, apfsPath(t, b, slot)); err != nil {
		t.Fatal(err)
	}
	if exists(b.image(slot) + ".base") {
		t.Fatal("left the mounted generation behind")
	}
}

func TestAPFSStartsEmptyWhenOnlyAnotherLineageIsLocal(t *testing.T) {
	b, _ := newAPFS(t)
	remote := &headTransfer{heads: map[string]Identity{}, errs: map[string]error{}}
	b.Transfer = remote
	installMaster(t, &b.LocalImages, first, strings.Repeat("b", 64), 1, time.Now())
	slot := Slot{Identity: identity(second), PodUID: "pod"}
	slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = head(3).BaseGeneration, head(3).ImageDigest, head(3).ContentDigest

	if err := b.Attach(context.Background(), slot, apfsPath(t, b, slot)); err != nil {
		t.Fatal(err)
	}
	if len(remote.downloads()) != 0 || b.MountedGeneration(slot) != 0 || !b.Cold(slot) {
		t.Fatal("did not start empty", remote.downloads(), b.MountedGeneration(slot))
	}
}

func TestStoreRecordsTheGenerationAJobActuallyMounted(t *testing.T) {
	b, _ := newAPFS(t)
	b.Transfer = &headTransfer{heads: map[string]Identity{}, errs: map[string]error{}}
	installMaster(t, &b.LocalImages, first, strings.Repeat("a", 64), 1, time.Now())
	store, err := Open(b.Root, b)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	id := identity(second)
	id.BaseGeneration, id.ImageDigest, id.ContentDigest = head(2).BaseGeneration, head(2).ImageDigest, head(2).ContentDigest
	if _, err := store.Acquire(context.Background(), id, "job", "pod"); err != nil {
		t.Fatal(err)
	}
	slots, err := store.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	if len(slots) != 1 || slots[0].MountedGeneration != 1 {
		t.Fatalf("journal = %+v", slots)
	}
}

func TestReplaceKeepsAStaleMasterUntilItsSuccessorIsLocal(t *testing.T) {
	b, remote := newRefreshing(t)
	b.RefreshWithin = 0
	scope := strings.Repeat("a", 64)
	stale := installMaster(t, b, first, scope, 1, time.Now())
	remote.heads[scope] = head(2)
	var asked []Identity
	queued := true
	b.Replace = func(next Identity) bool {
		asked = append(asked, next)
		return queued
	}

	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	if !exists(b.master(stale)) || len(asked) != 1 || asked[0].BaseGeneration != 2 || asked[0].ID != first || asked[0].ContentDigest != head(2).ContentDigest {
		t.Fatal("stale master was not kept while its successor downloads", asked)
	}
	if len(remote.downloads()) != 0 {
		t.Fatal("maintenance downloaded in the foreground")
	}

	installMaster(t, b, first, scope, 2, time.Now())
	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	if exists(b.master(stale)) {
		t.Fatal("stale master outlived its local successor")
	}

	other := installMaster(t, b, second, strings.Repeat("b", 64), 1, time.Now())
	remote.heads[other.Scope] = head(2)
	queued = false
	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	if exists(b.master(other)) {
		t.Fatal("kept a stale master whose successor could not be queued")
	}

	idle := installMaster(t, b, third, strings.Repeat("c", 64), 1, time.Now().Add(-25*time.Hour))
	remote.heads[idle.Scope] = head(2)
	queued = true
	asked = nil
	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	if exists(b.master(idle)) || len(asked) != 0 {
		t.Fatal("fetched a successor for a master no job used in the last day", asked)
	}
}

func TestLocalMountsAnOlderGenerationWhenItsBaseIsNotLocal(t *testing.T) {
	b, _ := newLocal(t)
	unmountEmpties(b)
	remote := &headTransfer{heads: map[string]Identity{}, errs: map[string]error{}}
	b.Transfer = remote
	scope := strings.Repeat("a", 64)
	installMaster(t, b, first, scope, 1, time.Now())
	installMaster(t, b, first, scope, 4, time.Now())
	if err := os.WriteFile(b.master(installMaster(t, b, first, scope, 2, time.Now())), []byte("generation 2"), 0600); err != nil {
		t.Fatal(err)
	}
	slot := Slot{Identity: identity(second), PodUID: "pod"}
	slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = head(3).BaseGeneration, head(3).ImageDigest, head(3).ContentDigest
	path := t.TempDir()

	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	if len(remote.downloads()) != 0 {
		t.Fatal("downloaded the base inside the job's budget instead of mounting an older master")
	}
	if data, _ := os.ReadFile(b.image(slot)); string(data) != "generation 2" {
		t.Fatalf("cloned %q, want the newest older generation", data)
	}
	if b.MountedGeneration(slot) != 2 || b.Cold(slot) {
		t.Fatalf("mounted generation = %d, want 2", b.MountedGeneration(slot))
	}
	if err := b.Delete(slot, path); err != nil {
		t.Fatal(err)
	}
	if exists(b.image(slot) + ".base") {
		t.Fatal("left the mounted generation behind")
	}
}

func TestLocalPublishesChangesOnTopOfAnOlderGeneration(t *testing.T) {
	b, remote := newLocal(t)
	remote.generation = 3
	installMaster(t, b, first, strings.Repeat("a", 64), 1, time.Now())
	slot := warmSlot(second, "pod")
	slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = head(2).BaseGeneration, head(2).ImageDigest, head(2).ContentDigest
	path := t.TempDir()
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	jobWrote(t, path)

	if err := b.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	if remote.uploads != 1 {
		t.Fatalf("uploads = %d, want 1", remote.uploads)
	}
}

func TestLocalNeverKeepsAnUnchangedOlderGenerationAsItsBaseMaster(t *testing.T) {
	b, remote := newLocal(t)
	installMaster(t, b, first, strings.Repeat("a", 64), 1, time.Now())
	slot := warmSlot(second, "pod")
	slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = head(2).BaseGeneration, head(2).ImageDigest, head(2).ContentDigest
	path := t.TempDir()
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}

	if err := b.Seal(slot, path); !errors.Is(err, ErrUnchanged) {
		t.Fatal(err)
	}
	if remote.uploads != 0 || b.HasMaster(slot.Identity) {
		t.Fatal("generation 1's content became generation 2's master")
	}
}

func TestLinuxStoreRecordsTheGenerationAJobActuallyMounted(t *testing.T) {
	b, remote := newLocal(t)
	installMaster(t, b, first, strings.Repeat("a", 64), 1, time.Now())
	store, err := Open(b.Root, b)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	id := identity(second)
	id.BaseGeneration, id.ImageDigest, id.ContentDigest = head(2).BaseGeneration, head(2).ImageDigest, head(2).ContentDigest
	warm, err := store.Acquire(context.Background(), id, "job", "pod")
	if err != nil {
		t.Fatal(err)
	}
	slots, err := store.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	if !warm || remote.downloads != 0 || len(slots) != 1 || slots[0].MountedGeneration != 1 {
		t.Fatalf("warm = %v, journal = %+v", warm, slots)
	}
}
