package cachevolumes

import (
	"context"
	"os"
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

func (b *LocalImages) refreshMasters() {
	for job := range b.refresh.jobs {
		b.refreshMaster(job)
		b.refresh.pending.Delete(job.master)
	}
}

func (b *LocalImages) refreshMaster(job refreshJob) {
	ctx, cancel := context.WithTimeout(context.Background(), refreshBudget)
	defer cancel()
	done := b.Observe.Start("refresh", "remote")
	err := b.RefreshMaster(ctx, job.next)
	unlock := b.lock(job.stale.Scope)
	defer unlock()
	if err == nil {
		// Carry the last use over so a master no job attaches is not refreshed
		// on every publication until it ages out.
		err = os.Chtimes(b.master(job.next), job.usedAt, job.usedAt)
	}
	done(err)
	_ = removeMaster(job.master)
}

func removeMaster(path string) error {
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	_ = os.Remove(path + ".json")
	return nil
}
