package cachevolumes

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type headTransfer struct {
	testTransfer
	mu         sync.Mutex
	heads      map[string]Identity
	errs       map[string]error
	downloaded []Slot
	started    chan struct{}
	release    chan struct{}
}

func (h *headTransfer) Head(slot Slot) (Identity, error) {
	if err := h.errs[slot.Scope]; err != nil {
		return Identity{}, err
	}
	return h.heads[slot.Scope], nil
}

func (h *headTransfer) Download(_ context.Context, slot Slot, path string) error {
	h.mu.Lock()
	h.downloaded = append(h.downloaded, slot)
	h.mu.Unlock()
	if h.started != nil {
		h.started <- struct{}{}
		<-h.release
	}
	return os.WriteFile(path, []byte("refreshed"), 0600)
}

func (h *headTransfer) downloads() []Slot {
	h.mu.Lock()
	defer h.mu.Unlock()
	return append([]Slot(nil), h.downloaded...)
}

func newRefreshing(t *testing.T) (*LocalImages, *headTransfer) {
	t.Helper()
	b, _ := newLocal(t)
	remote := &headTransfer{heads: map[string]Identity{}, errs: map[string]error{}}
	b.Transfer = remote
	b.RefreshMaster = b.Prefetch
	b.RefreshWithin = time.Hour
	return b, remote
}

func head(generation int64) Identity {
	return Identity{BaseGeneration: generation, ImageDigest: strings.Repeat(fmt.Sprint(generation), 40), ContentDigest: fmt.Sprintf("%064x", generation)}
}

func installMaster(t *testing.T, b *LocalImages, id, scope string, generation int64, usedAt time.Time) Slot {
	t.Helper()
	slot := Slot{Identity: identity(id)}
	slot.Scope = scope
	slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = head(generation).BaseGeneration, head(generation).ImageDigest, head(generation).ContentDigest
	master := b.master(slot)
	if err := os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(master, []byte("stale"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := b.recordMaster(slot, master); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(master, usedAt, usedAt); err != nil {
		t.Fatal(err)
	}
	return slot
}

func eventually(t *testing.T, condition func() bool) {
	t.Helper()
	for deadline := time.Now().Add(5 * time.Second); time.Now().Before(deadline); time.Sleep(10 * time.Millisecond) {
		if condition() {
			return
		}
	}
	t.Fatal("condition not reached")
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func TestRecentlyUsedStaleMasterIsRefreshedToTheHeadBeforeRemoval(t *testing.T) {
	b, remote := newRefreshing(t)
	scope := strings.Repeat("a", 64)
	usedAt := time.Now().Add(-10 * time.Minute).Truncate(time.Second)
	stale := installMaster(t, b, first, scope, 1, usedAt)
	remote.heads[scope] = head(2)
	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	next := stale
	next.Identity.BaseGeneration, next.ImageDigest, next.ContentDigest = 2, head(2).ImageDigest, head(2).ContentDigest
	eventually(t, func() bool { return exists(b.master(next)) && !exists(b.master(stale)) })
	if data, _ := os.ReadFile(b.master(next)); string(data) != "refreshed" {
		t.Fatal("installed unexpected master", string(data))
	}
	if exists(b.master(stale) + ".json") {
		t.Fatal("retained stale master record")
	}
	downloads := remote.downloads()
	if len(downloads) != 1 || downloads[0].ID != first || downloads[0].BaseGeneration != 2 || downloads[0].ContentDigest != head(2).ContentDigest {
		t.Fatalf("downloaded %+v", downloads)
	}
	info, err := os.Stat(b.master(next))
	if err != nil || !info.ModTime().Equal(usedAt) {
		t.Fatal("refresh changed the last use", err)
	}
	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	if len(remote.downloads()) != 1 || !exists(b.master(next)) {
		t.Fatal("current master was refreshed again or removed")
	}
}

func TestStaleMasterIsRemovedWhenItCannotBeRefreshed(t *testing.T) {
	for name, configure := range map[string]func(*LocalImages, *headTransfer, string){
		"unused within the window": func(*LocalImages, *headTransfer, string) {},
		"head without digests": func(b *LocalImages, remote *headTransfer, scope string) {
			remote.heads[scope] = Identity{BaseGeneration: 2}
		},
		"refresh disabled": func(b *LocalImages, _ *headTransfer, _ string) { b.RefreshMaster = nil },
		"lineage cleared":  func(_ *LocalImages, remote *headTransfer, scope string) { remote.errs[scope] = ErrConflict },
	} {
		t.Run(name, func(t *testing.T) {
			b, remote := newRefreshing(t)
			scope := strings.Repeat("a", 64)
			usedAt := time.Now().Add(-time.Minute)
			if name == "unused within the window" {
				usedAt = time.Now().Add(-2 * time.Hour)
			}
			stale := installMaster(t, b, first, scope, 1, usedAt)
			remote.heads[scope] = head(2)
			configure(b, remote, scope)
			if err := b.Maintain(); err != nil {
				t.Fatal(err)
			}
			if exists(b.master(stale)) || exists(b.master(stale)+".json") {
				t.Fatal("retained stale master")
			}
			if len(remote.downloads()) != 0 {
				t.Fatal("refreshed", remote.downloads())
			}
		})
	}
}

func TestFailedRefreshStillRemovesTheStaleMaster(t *testing.T) {
	b, remote := newRefreshing(t)
	scope := strings.Repeat("a", 64)
	stale := installMaster(t, b, first, scope, 1, time.Now())
	remote.heads[scope] = head(2)
	b.RefreshMaster = func(context.Context, Slot) error { return errors.New("download failed") }
	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	eventually(t, func() bool { return !exists(b.master(stale)) })
}

func TestMaintenanceContinuesPastAnUnreachableLineage(t *testing.T) {
	b, remote := newRefreshing(t)
	b.RefreshMaster = nil
	unreachable, cleared := strings.Repeat("a", 64), strings.Repeat("b", 64)
	kept := installMaster(t, b, first, unreachable, 1, time.Now())
	removed := installMaster(t, b, second, cleared, 1, time.Now())
	remote.errs[unreachable] = errors.New("unreachable")
	remote.errs[cleared] = ErrConflict
	if err := b.Maintain(); err == nil {
		t.Fatal("hid the unreachable lineage")
	}
	if !exists(b.master(kept)) {
		t.Fatal("removed a master it could not validate")
	}
	if exists(b.master(removed)) {
		t.Fatal("stopped before the cleared lineage")
	}
}

func TestRunningRefreshDoesNotBlockMaintenanceOrAdmission(t *testing.T) {
	b, remote := newRefreshing(t)
	remote.started, remote.release = make(chan struct{}, 1), make(chan struct{})
	var free atomic.Uint64
	free.Store(1 << 40)
	b.FreeBytes = func(string) (uint64, error) { return free.Load(), nil }
	scope := strings.Repeat("a", 64)
	stale := installMaster(t, b, first, scope, 1, time.Now().Add(-time.Minute))
	remote.heads[scope] = head(2)
	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	<-remote.started
	free.Store(0)
	maintained, admitted := make(chan error, 1), make(chan error, 1)
	go func() { maintained <- b.Maintain() }()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		admitted <- b.reserve(ctx)
	}()
	for _, check := range []struct {
		result <-chan error
		want   error
	}{{maintained, nil}, {admitted, ErrCapacity}} {
		select {
		case err := <-check.result:
			if !errors.Is(err, check.want) {
				t.Fatal(err)
			}
		case <-time.After(time.Second):
			t.Fatal("waited behind the refresh download")
		}
	}
	if !exists(b.master(stale)) || len(remote.downloads()) != 1 {
		t.Fatal("evicted or refreshed the master again during its refresh")
	}
	close(remote.release)
	next := stale
	next.Identity.BaseGeneration, next.ImageDigest, next.ContentDigest = 2, head(2).ImageDigest, head(2).ContentDigest
	eventually(t, func() bool { return exists(b.master(next)) && !exists(b.master(stale)) })
}

func TestStaleMasterIsRemovedWhenTheHeadIsAlreadyLocal(t *testing.T) {
	b, remote := newRefreshing(t)
	scope := strings.Repeat("a", 64)
	stale := installMaster(t, b, first, scope, 1, time.Now().Add(-time.Hour/2))
	publishedAt := time.Now().Truncate(time.Second)
	current := installMaster(t, b, second, scope, 2, publishedAt)
	remote.heads[scope] = head(2)
	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	if exists(b.master(stale)) || len(remote.downloads()) != 0 {
		t.Fatal("refreshed into a master that was already local")
	}
	if info, err := os.Stat(b.master(current)); err != nil || !info.ModTime().Equal(publishedAt) {
		t.Fatal("changed the current master's last use", err)
	}
}

func TestStaleMasterIsRemovedWhenTheRefreshQueueIsFull(t *testing.T) {
	b, remote := newRefreshing(t)
	b.refresh.once.Do(func() { b.refresh.jobs = make(chan refreshJob) })
	scope := strings.Repeat("a", 64)
	stale := installMaster(t, b, first, scope, 1, time.Now())
	remote.heads[scope] = head(2)
	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	if exists(b.master(stale)) {
		t.Fatal("kept a master it could not queue")
	}
	if _, queued := b.refresh.pending.Load(b.master(stale)); queued {
		t.Fatal("left the master marked as queued")
	}
}
