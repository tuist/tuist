package cachevolumes

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func warmSlot(id, pod string) Slot {
	slot := Slot{Identity: identity(id), PodUID: pod}
	slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = 1, strings.Repeat("b", 40), strings.Repeat("c", 64)
	return slot
}

func TestAPFSStartsEmptyInsteadOfDownloadingWhenNoCopyIsLocal(t *testing.T) {
	b, remote := newAPFS(t)
	slot := warmSlot(first, "pod")

	if err := b.Attach(context.Background(), slot, apfsPath(t, b, slot)); err != nil {
		t.Fatal(err)
	}
	if remote.downloads != 0 {
		t.Fatal("downloaded inside the job's budget")
	}
	if data, _ := os.ReadFile(filepath.Join(apfsPath(t, b, slot), SharedImageName)); string(data) != "cold APFS" {
		t.Fatalf("attached %q, want an empty image", data)
	}
	if !b.Cold(slot) || b.MountedGeneration(slot) != 0 {
		t.Fatal("an empty start was not recorded")
	}
}

func TestAPFSAttachNeedsOnlyOneImageOfSpaceWhenItNeverDownloads(t *testing.T) {
	b, _ := newAPFS(t)
	b.FreeBytes = func(string) (uint64, error) { return 20_000_000_000, nil }
	slot := warmSlot(first, "pod")

	if err := b.Attach(context.Background(), slot, apfsPath(t, b, slot)); err != nil {
		t.Fatal("a warm attach without a download still required archive headroom:", err)
	}
}

func TestAPFSWithholdsAnEmptyStartFromPublication(t *testing.T) {
	b, remote := newAPFS(t)
	slot := warmSlot(first, "pod")
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	detached(t, path, slot.ID)

	if err := b.Seal(slot, path); !errors.Is(err, ErrWithheld) {
		t.Fatal("an empty start would replace the saved version:", err)
	}
	if remote.uploads != 0 {
		t.Fatal("uploaded an empty start")
	}
	if err := b.Delete(slot, path); err != nil {
		t.Fatal(err)
	}
	if exists(b.image(slot) + ".cold") {
		t.Fatal("left the empty-start marker behind")
	}
}

func TestStoreReportsAnEmptyStartAsAMissAndDiscardsIt(t *testing.T) {
	b, _ := newAPFS(t)
	store, err := Open(b.Root, b)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	slot := warmSlot(first, "pod")

	warm, err := store.Acquire(context.Background(), slot.Identity, "job", "pod")
	if err != nil {
		t.Fatal(err)
	}
	if warm {
		t.Fatal("an empty start was reported as a cache hit")
	}
	detached(t, store.activePath(slot), slot.ID)
	finished := func(string, string) (bool, error) { return true, nil }
	if err := store.Reconcile(finished, func(Slot, bool) (string, error) { return "seal", nil }); err != nil {
		t.Fatal(err)
	}
	slots, err := store.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	if len(slots) != 1 || slots[0].Warm || slots[0].State != "deleted" {
		t.Fatalf("journal = %+v", slots)
	}
}

func TestAPFSAttachDoesNotWaitForABackgroundDownloadOfItsVolume(t *testing.T) {
	b, _ := newAPFS(t)
	remote := &headTransfer{heads: map[string]Identity{}, errs: map[string]error{}, started: make(chan struct{}), release: make(chan struct{})}
	b.Transfer = remote
	older := installMaster(t, &b.LocalImages, first, strings.Repeat("a", 64), 1, time.Now())
	next := warmSlot(second, "pod")
	next.BaseGeneration, next.ImageDigest, next.ContentDigest = head(2).BaseGeneration, head(2).ImageDigest, head(2).ContentDigest
	prefetched := make(chan error, 1)
	go func() { prefetched <- b.Prefetch(context.Background(), next) }()
	<-remote.started
	defer func() {
		close(remote.release)
		if err := <-prefetched; err != nil {
			t.Error(err)
		}
	}()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := b.Attach(ctx, next, apfsPath(t, b, next)); err != nil {
		t.Fatal("the job waited for the background download:", err)
	}
	if b.MountedGeneration(next) != older.BaseGeneration {
		t.Fatal("did not mount the older local copy")
	}
}

type blockingHeads struct {
	headTransfer
	asked, answer chan struct{}
}

func (h *blockingHeads) Head(slot Slot) (Identity, error) {
	h.asked <- struct{}{}
	<-h.answer
	return h.headTransfer.Head(slot)
}

func TestMaintenanceAsksTheServerWithoutHoldingTheVolume(t *testing.T) {
	b, _ := newAPFS(t)
	remote := &blockingHeads{headTransfer: headTransfer{heads: map[string]Identity{}, errs: map[string]error{}}, asked: make(chan struct{}), answer: make(chan struct{})}
	b.Transfer = remote
	saved := installMaster(t, &b.LocalImages, first, strings.Repeat("a", 64), 1, time.Now())
	remote.heads[saved.Scope] = saved.Identity
	maintained := make(chan error, 1)
	go func() { maintained <- b.Maintain() }()
	<-remote.asked
	defer func() {
		close(remote.answer)
		if err := <-maintained; err != nil {
			t.Error(err)
		}
	}()

	slot := warmSlot(second, "pod")
	slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = saved.BaseGeneration, saved.ImageDigest, saved.ContentDigest
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := b.Attach(ctx, slot, apfsPath(t, b, slot)); err != nil {
		t.Fatal("the job waited for maintenance's server request:", err)
	}
}

func TestPrefetchLeavesNoStagingBehind(t *testing.T) {
	b, _ := newAPFS(t)
	remote := &headTransfer{heads: map[string]Identity{}, errs: map[string]error{}}
	b.Transfer = remote
	slot := warmSlot(first, "")
	remote.fail = true
	if err := b.Prefetch(context.Background(), slot); err == nil {
		t.Fatal("a failed download succeeded")
	}
	remote.fail = false
	if err := b.Prefetch(context.Background(), slot); err != nil {
		t.Fatal(err)
	}
	if !b.HasMaster(slot.Identity) {
		t.Fatal("prefetched copy was not installed")
	}
	staged, _ := filepath.Glob(filepath.Join(b.Root, "staging", "*"))
	if len(staged) != 0 {
		t.Fatal("left downloads behind:", staged)
	}
}

func TestAPFSPublishesAnEmptyStartTheServerLetReplaceItsHead(t *testing.T) {
	b, remote := newAPFS(t)
	slot := warmSlot(first, "pod")
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	detached(t, path, slot.ID)
	slot.PublishCold = true

	if err := b.Seal(slot, path); err != nil {
		t.Fatal("withheld an empty start the server let replace its head:", err)
	}
	if remote.uploads != 1 {
		t.Fatalf("uploads = %d, want 1", remote.uploads)
	}
	if masters, _ := filepath.Glob(filepath.Join(b.Root, "masters", slot.Scope, "*.img")); len(masters) != 1 {
		t.Fatal("the accepted branch did not become a master")
	}
}

func TestStorePublishesAnEmptyStartOnlyWhenTheServerSaysPublish(t *testing.T) {
	for _, tc := range []struct {
		action, state string
		uploads       int
	}{
		{action: "seal", state: "deleted"},
		{action: "publish", state: "sealed", uploads: 1},
	} {
		t.Run(tc.action, func(t *testing.T) {
			b, remote := newAPFS(t)
			store, err := Open(b.Root, b)
			if err != nil {
				t.Fatal(err)
			}
			defer store.Close()
			slot := warmSlot(first, "pod")
			if _, err := store.Acquire(context.Background(), slot.Identity, "job", "pod"); err != nil {
				t.Fatal(err)
			}
			detached(t, store.activePath(slot), slot.ID)
			finished := func(string, string) (bool, error) { return true, nil }
			if err := store.Reconcile(finished, func(Slot, bool) (string, error) { return tc.action, nil }); err != nil {
				t.Fatal(err)
			}
			slots, err := store.Snapshot()
			if err != nil {
				t.Fatal(err)
			}
			if len(slots) != 1 || slots[0].State != tc.state || remote.uploads != tc.uploads {
				t.Fatalf("journal = %+v, uploads = %d", slots, remote.uploads)
			}
		})
	}
}

func TestAPFSStillWithholdsAFullEmptyStartTheServerLetPublish(t *testing.T) {
	b, remote := newAPFS(t)
	slot := warmSlot(first, "pod")
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	detached(t, path, slot.ID)
	usage, _ := json.Marshal(map[string]any{"id": slot.ID, "used_bytes": 19_900_000_000, "capacity_bytes": 20_000_000_000})
	if err := os.WriteFile(filepath.Join(path, ".usage"), usage, 0644); err != nil {
		t.Fatal(err)
	}
	slot.PublishCold = true

	if err := b.Seal(slot, path); !errors.Is(err, ErrFull) {
		t.Fatal("published a full empty start:", err)
	}
	if remote.uploads != 0 {
		t.Fatal("uploaded a full empty start")
	}
}

func TestLocalStartsEmptyInsteadOfDownloadingWhenNoCopyIsLocal(t *testing.T) {
	b, remote := newLocal(t)
	slot := warmSlot(first, "pod")

	if err := b.Attach(context.Background(), slot, t.TempDir()); err != nil {
		t.Fatal(err)
	}
	if remote.downloads != 0 {
		t.Fatal("downloaded inside the job's budget")
	}
	if data, _ := os.ReadFile(b.image(slot)); string(data) != "empty filesystem" {
		t.Fatalf("attached %q, want an empty image", data)
	}
	if !b.Cold(slot) || b.MountedGeneration(slot) != 0 {
		t.Fatal("an empty start was not recorded")
	}
}

func TestLocalWithholdsAnEmptyStartFromPublication(t *testing.T) {
	b, remote := newLocal(t)
	unmountEmpties(b)
	slot := warmSlot(first, "pod")
	path := t.TempDir()
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	jobWrote(t, path)

	if err := b.Seal(slot, path); !errors.Is(err, ErrWithheld) {
		t.Fatal("an empty start would replace the saved version:", err)
	}
	if remote.uploads != 0 {
		t.Fatal("uploaded an empty start")
	}
	if err := b.Delete(slot, path); err != nil {
		t.Fatal(err)
	}
	if exists(b.image(slot) + ".cold") {
		t.Fatal("left the empty-start marker behind")
	}
}

func TestLocalPublishesAnEmptyStartTheServerLetReplaceItsHead(t *testing.T) {
	b, remote := newLocal(t)
	remote.generation = 2
	slot := warmSlot(first, "pod")
	path := t.TempDir()
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	jobWrote(t, path)
	slot.PublishCold = true

	if err := b.Seal(slot, path); err != nil {
		t.Fatal("withheld an empty start the server let replace its head:", err)
	}
	if remote.uploads != 1 {
		t.Fatalf("uploads = %d, want 1", remote.uploads)
	}
	if masters, _ := filepath.Glob(filepath.Join(b.Root, "masters", slot.Scope, "*.img")); len(masters) != 1 {
		t.Fatal("the accepted branch did not become a master")
	}
}

func TestLocalNeverKeepsAnUnchangedEmptyStartAsItsBaseMaster(t *testing.T) {
	b, remote := newLocal(t)
	slot := warmSlot(first, "pod")
	path := t.TempDir()
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	slot.PublishCold = true

	if err := b.Seal(slot, path); !errors.Is(err, ErrUnchanged) {
		t.Fatal(err)
	}
	if remote.uploads != 0 || b.HasMaster(slot.Identity) {
		t.Fatal("an empty image became the saved version's master")
	}
}

func TestAPFSNeverKeepsAnUnchangedEmptyStartAsItsBaseMaster(t *testing.T) {
	b, remote := newAPFS(t)
	slot := warmSlot(first, "pod")
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	usage, _ := json.Marshal(map[string]any{"id": slot.ID, "used_bytes": 3, "capacity_bytes": 20_000_000_000, "changed": false})
	if err := os.WriteFile(filepath.Join(path, ".usage"), usage, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(path, ".detached"), []byte(slot.ID), 0644); err != nil {
		t.Fatal(err)
	}
	slot.PublishCold = true

	if err := b.Seal(slot, path); !errors.Is(err, ErrUnchanged) {
		t.Fatal(err)
	}
	if remote.uploads != 0 || b.HasMaster(slot.Identity) {
		t.Fatal("an empty image became the saved version's master")
	}
}

func TestStoreReportsALinuxEmptyStartAsAMissAndDiscardsIt(t *testing.T) {
	b, remote := newLocal(t)
	unmountEmpties(b)
	store, err := Open(b.Root, b)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	slot := warmSlot(first, "pod")

	warm, err := store.Acquire(context.Background(), slot.Identity, "job", "pod")
	if err != nil {
		t.Fatal(err)
	}
	if warm || remote.downloads != 0 {
		t.Fatal("an empty start was reported as a cache hit or downloaded", remote.downloads)
	}
	jobWrote(t, store.activePath(slot))
	finished := func(string, string) (bool, error) { return true, nil }
	if err := store.Reconcile(finished, func(Slot, bool) (string, error) { return "seal", nil }); err != nil {
		t.Fatal(err)
	}
	slots, err := store.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	if len(slots) != 1 || slots[0].Warm || slots[0].State != "deleted" || remote.uploads != 0 {
		t.Fatalf("journal = %+v, uploads = %d", slots, remote.uploads)
	}
}

func TestLocalAttachDoesNotWaitForABackgroundDownloadOfItsVolume(t *testing.T) {
	b, _ := newLocal(t)
	remote := &headTransfer{heads: map[string]Identity{}, errs: map[string]error{}, started: make(chan struct{}), release: make(chan struct{})}
	b.Transfer = remote
	older := installMaster(t, b, first, strings.Repeat("a", 64), 1, time.Now())
	next := warmSlot(second, "pod")
	next.BaseGeneration, next.ImageDigest, next.ContentDigest = head(2).BaseGeneration, head(2).ImageDigest, head(2).ContentDigest
	prefetched := make(chan error, 1)
	go func() { prefetched <- b.Prefetch(context.Background(), next) }()
	<-remote.started
	defer func() {
		close(remote.release)
		if err := <-prefetched; err != nil {
			t.Error(err)
		}
	}()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := b.Attach(ctx, next, t.TempDir()); err != nil {
		t.Fatal("the job waited for the background download:", err)
	}
	if b.MountedGeneration(next) != older.BaseGeneration {
		t.Fatal("did not mount the older local copy")
	}
}

func TestLocalAttachDoesNotWaitForARefreshOfItsVolume(t *testing.T) {
	b, remote := newRefreshing(t)
	remote.started, remote.release = make(chan struct{}, 1), make(chan struct{})
	scope := strings.Repeat("a", 64)
	stale := installMaster(t, b, first, scope, 1, time.Now().Add(-time.Minute))
	remote.heads[scope] = head(2)
	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	<-remote.started
	next := warmSlot(second, "pod")
	next.BaseGeneration, next.ImageDigest, next.ContentDigest = head(2).BaseGeneration, head(2).ImageDigest, head(2).ContentDigest
	defer func() {
		close(remote.release)
		eventually(t, func() bool { return b.HasMaster(next.Identity) && !exists(b.master(stale)) })
	}()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := b.Attach(ctx, next, t.TempDir()); err != nil {
		t.Fatal("the job waited for the refresh download:", err)
	}
	if b.MountedGeneration(next) != stale.BaseGeneration {
		t.Fatal("did not mount the stale local copy")
	}
}

func TestConcurrentFetchesOfOneMasterDownloadItOnce(t *testing.T) {
	b, _ := newLocal(t)
	remote := &headTransfer{heads: map[string]Identity{}, errs: map[string]error{}, started: make(chan struct{}, 2), release: make(chan struct{})}
	b.Transfer = remote
	slot := warmSlot(first, "")
	prefetched, again := make(chan error, 1), make(chan error, 1)
	go func() { prefetched <- b.Prefetch(context.Background(), slot) }()
	<-remote.started
	go func() { again <- b.Prefetch(context.Background(), slot) }()

	select {
	case err := <-again:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		close(remote.release)
		t.Fatal("a second fetch downloaded the master again")
	}
	close(remote.release)
	if err := <-prefetched; err != nil {
		t.Fatal(err)
	}
	if len(remote.downloads()) != 1 || !b.HasMaster(slot.Identity) {
		t.Fatal("downloads =", len(remote.downloads()))
	}
}

// unmountEmpties makes the fake unmount leave the mountpoint empty, as a real
// one does once the volume's files are no longer visible there.
func unmountEmpties(b *LocalImages) {
	b.Unmount = func(_, path string) error {
		entries, err := os.ReadDir(path)
		for _, entry := range entries {
			err = errors.Join(err, os.RemoveAll(filepath.Join(path, entry.Name())))
		}
		return err
	}
}
