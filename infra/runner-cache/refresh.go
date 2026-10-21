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
	if b.RefreshWithin <= 0 || time.Since(usedAt) >= b.RefreshWithin || head.BaseGeneration <= stale.BaseGeneration {
		return false
	}
	next := stale
	next.BaseGeneration, next.ImageDigest, next.ContentDigest = head.BaseGeneration, head.ImageDigest, head.ContentDigest
	if !validHead(next.Identity) || !scopePattern.MatchString(next.Scope) {
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
	ctx, cancel := context.WithTimeout(context.Background(), refreshBudget)
	done := b.Observe.For(job.next).Start("refresh", "remote")
	ctx = WithSubject(ctx, SubjectOf(job.next))
	b.refresh.active.Store(job.stale.Scope, struct{}{})
	err := b.reserve(ctx)
	if err == nil {
		err = b.restoreRefresh(ctx, job)
	}
	b.refresh.active.Delete(job.stale.Scope)
	cancel()
	done(err)
	unlock := b.lock(job.stale.Scope)
	defer unlock()
	if _, err := os.Stat(job.master); err == nil {
		_ = b.evictMaster(job.master, EvictSuperseded, "head_generation", job.next.BaseGeneration)
	}
}

// restoreRefresh installs the newer master under the scope lock. Only a master
// it installed inherits the stale master's last use, so a master no job attaches
// is not refreshed on every publication until it ages out, and a master a job
// restored or cloned meanwhile keeps its own.
func (b *LocalImages) restoreRefresh(ctx context.Context, job refreshJob) error {
	unlock, err := b.lockContext(ctx, job.stale.Scope)
	if err != nil {
		return err
	}
	defer unlock()
	master := b.master(job.next)
	if _, err := os.Stat(master); err == nil {
		return nil
	} else if !os.IsNotExist(err) {
		return err
	}
	if err := b.restoreMaster(ctx, job.next, master); err != nil {
		return err
	}
	usedAt := job.usedAt
	if info, err := os.Stat(job.master); err == nil && info.ModTime().After(usedAt) {
		usedAt = info.ModTime()
	}
	return os.Chtimes(master, usedAt, usedAt)
}

func removeMaster(path string) error {
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	_ = os.Remove(path + ".json")
	return nil
}
