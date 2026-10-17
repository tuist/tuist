package cachevolumes

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// Publishing a generation makes every other host's master of that lineage
// stale. Removing it leaves the next job there to download the new master inside
// its foreground budget. A recently used stale master is instead refreshed in the
// background: the newer master is restored first, and the stale one is removed
// afterwards whether or not the refresh succeeded.
const (
	refreshBudget = 5 * time.Minute
	refreshQueue  = 64
)

type refreshJob struct {
	master string
	stale  Slot
	next   Slot
	usedAt time.Time
}

type refresher struct {
	once    sync.Once
	jobs    chan refreshJob
	pending sync.Map
	// active holds the scope whose lock the running refresh keeps for its download.
	active sync.Map
}

// queueRefresh reports whether the stale master stays until its refresh finishes.
func (b *LocalImages) queueRefresh(master string, stale Slot, head Identity, usedAt time.Time) bool {
	if b.RefreshMaster == nil || time.Since(usedAt) >= b.RefreshWithin || head.BaseGeneration <= stale.BaseGeneration {
		return false
	}
	next := stale
	next.BaseGeneration, next.ImageDigest, next.ContentDigest = head.BaseGeneration, head.ImageDigest, head.ContentDigest
	if !validHead(next.Identity) {
		return false
	}
	if _, err := os.Stat(b.master(next)); err == nil {
		return false
	}
	if _, queued := b.refresh.pending.LoadOrStore(master, struct{}{}); queued {
		return true
	}
	b.refresh.once.Do(func() {
		b.refresh.jobs = make(chan refreshJob, refreshQueue)
		go b.refreshMasters()
	})
	select {
	case b.refresh.jobs <- refreshJob{master: master, stale: stale, next: next, usedAt: usedAt}:
		return true
	default:
		b.refresh.pending.Delete(master)
		return false
	}
}

// refreshing reports whether a running refresh download holds a master's scope
// lock. Maintenance and admission skip it instead of waiting minutes. The scope
// is marked before the refresh takes admission, so admission never misses it.
func (b *LocalImages) refreshing(master string) bool {
	_, ok := b.refresh.active.Load(filepath.Base(filepath.Dir(master)))
	return ok
}

func (b *LocalImages) refreshMasters() {
	for job := range b.refresh.jobs {
		b.refreshMaster(job)
		b.refresh.pending.Delete(job.master)
	}
}

func (b *LocalImages) refreshMaster(job refreshJob) {
	master := b.master(job.next)
	if _, err := os.Stat(master); os.IsNotExist(err) {
		ctx, cancel := context.WithTimeout(context.Background(), refreshBudget)
		done := b.Observe.Start("refresh", "remote")
		b.refresh.active.Store(job.stale.Scope, struct{}{})
		err = b.RefreshMaster(ctx, job.next)
		b.refresh.active.Delete(job.stale.Scope)
		cancel()
		if err == nil {
			// Carry the last use over so a master no job attaches is not refreshed
			// on every publication until it ages out.
			err = os.Chtimes(master, job.usedAt, job.usedAt)
		}
		done(err)
	}
	unlock := b.lock(job.stale.Scope)
	defer unlock()
	_ = removeMaster(job.master)
}

func removeMaster(path string) error {
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	_ = os.Remove(path + ".json")
	return nil
}
