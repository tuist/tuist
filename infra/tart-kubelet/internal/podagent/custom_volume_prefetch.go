package podagent

import (
	"context"
	"errors"
	"strconv"
	"sync"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

const (
	// customAcquireBudget bounds how long a job waits for its volume. A master
	// that does not arrive in time is downloaded in the background instead.
	customAcquireBudget  = 25 * time.Second
	customAuthorizeRetry = time.Second
	// customSettleInterval and customSettleWindow pace reconciliation after a
	// runner Pod stops, until its VM is gone and its branch can be published.
	customSettleInterval = 5 * time.Second
	customSettleWindow   = 2 * time.Minute
	customPrefetchBudget = 5 * time.Minute
	customPrefetchQueue  = 16
	// customPrefetchRetry spaces out attempts at a master whose download failed.
	customPrefetchRetry = 10 * time.Minute
	// customPrefetchIdleBudgets is how many budgets in a row may end without
	// receiving archive bytes (finishing the archive, expanding it) before a
	// master counts as failed.
	customPrefetchIdleBudgets = 3
	// customPrefetchJobPoll is how often a background download held back for
	// the host's jobs asks again; customPrefetchJobWaitCap bounds how long it
	// waits for them, as stageJobWaitCap does for staging, so a host that
	// always runs a job still warms its masters.
	customPrefetchJobPoll    = 30 * time.Second
	customPrefetchJobWaitCap = 20 * time.Minute
)

// PrefetchMaster queues a HEAD the server listed for this host's fleet, behind
// any master a job asked for, under the reason the server listed it for.
// Reports whether it is queued or already here.
func (c *CustomVolumes) PrefetchMaster(identity cachevolumes.Identity, reason string) bool {
	if c == nil {
		return false
	}
	if reason != prefetchPrewarm {
		reason = prefetchRecent
	}
	prefetch := c.prefetch.Load()
	// An older copy of the lineage is held: a job mounts it and asks for its
	// HEAD itself, so the listing does not download every generation beside it.
	if prefetch != nil && c.images != nil && c.images.HoldsLineage(identity) {
		return true
	}
	return prefetch.queue(identity, false, reason) != nil
}

// Why a master was prefetched, the label of the prefetched-bytes metric.
const (
	prefetchJob     = "job"
	prefetchRefresh = "refresh"
	prefetchPrewarm = "prewarm"
	prefetchRecent  = "recent"
)

// customPrefetcher restores immutable masters in the background, one at a time
// so a single disk reservation covers the work. Jobs never wait on it. A
// master a job asked for but did not get in time goes ahead of masters the
// server listed for this host, and only the former may evict local masters. A
// master already queued or downloading is joined rather than fetched twice.
// Shutdown releases waiters and joins the worker.
//
// Every download runs with throttled disk I/O (withThrottledIO), and the
// masters the server listed wait while a runner on the host runs a job
// (busy): on 2026-11-27 rack hosts prefetched 650 to 1,500 GB a day at 100
// to 400 MB/s, and a job's test-product extraction on the same SSD ran 2 to
// 4 times slower during those bursts.
type customPrefetcher struct {
	ctx    context.Context
	budget time.Duration
	// restore may evict local masters only for a master a job asked for.
	restore func(ctx context.Context, slot cachevolumes.Slot, requested bool) error
	has     func(cachevolumes.Identity) bool
	// busy reports whether a runner on the host runs a job; nil never is.
	busy func(context.Context) bool
	// pause overrides customPrefetchJobPoll in tests.
	pause         time.Duration
	deferredSince time.Time

	mu         sync.Mutex
	stopped    bool
	pending    map[string]*customPrefetch
	failed     map[string]time.Time
	requested  chan *customPrefetch
	background chan *customPrefetch
	wait       sync.WaitGroup
}

// resolved is returned when there is nothing to wait for: the master is already
// here, or its last download failed too recently to try again.
var resolved = func() <-chan struct{} {
	done := make(chan struct{})
	close(done)
	return done
}()

type customPrefetch struct {
	identity  cachevolumes.Identity
	requested bool
	reason    string
	done      chan struct{}
	// idleBudgets counts budgets in a row that ended without archive bytes.
	idleBudgets int
}

func newCustomPrefetcher(ctx context.Context, restore func(context.Context, cachevolumes.Slot, bool) error, has func(cachevolumes.Identity) bool, busy func(context.Context) bool) *customPrefetcher {
	p := &customPrefetcher{
		ctx:        ctx,
		budget:     customPrefetchBudget,
		restore:    restore,
		has:        has,
		busy:       busy,
		pause:      customPrefetchJobPoll,
		pending:    map[string]*customPrefetch{},
		failed:     map[string]time.Time{},
		requested:  make(chan *customPrefetch, customPrefetchQueue),
		background: make(chan *customPrefetch, customPrefetchQueue),
	}
	p.wait.Go(p.work)
	return p
}

// start queues a master a job asked for (requested) or a newer HEAD of a local
// master; see queue.
func (p *customPrefetcher) start(identity cachevolumes.Identity, requested bool) <-chan struct{} {
	reason := prefetchRefresh
	if requested {
		reason = prefetchJob
	}
	return p.queue(identity, requested, reason)
}

// queue queues a master and returns a channel closed once it is installed, has
// failed or was dropped. Nil when nothing was queued: a cold identity, a full
// queue or a stopped prefetcher.
func (p *customPrefetcher) queue(identity cachevolumes.Identity, requested bool, reason string) <-chan struct{} {
	if p == nil || identity.BaseGeneration <= 0 {
		return nil
	}
	if p.has != nil && p.has(identity) {
		return resolved
	}
	key := prefetchKey(identity)
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.stopped {
		return nil
	}
	if job, ok := p.pending[key]; ok {
		return job.done
	}
	if at, ok := p.failed[key]; ok && time.Since(at) < customPrefetchRetry {
		return resolved
	}
	job := &customPrefetch{identity: identity, requested: requested, reason: reason, done: make(chan struct{})}
	queue := p.background
	if requested {
		queue = p.requested
	}
	select {
	case queue <- job:
	default:
		return nil
	}
	p.pending[key] = job
	return job.done
}

func (p *customPrefetcher) work() {
	defer p.drain()
	// held is a background master waiting for the host's jobs to finish. It
	// stays pending, so drain releases its waiters.
	var held *customPrefetch
	for {
		var job *customPrefetch
		select {
		case job = <-p.requested:
		default:
			if held == nil {
				select {
				case job = <-p.requested:
				case held = <-p.background:
				case <-p.ctx.Done():
					return
				}
			}
			if job == nil {
				if !p.deferForJobs() {
					job, held = held, nil
				} else {
					select {
					case job = <-p.requested:
					case <-time.After(p.pause):
						continue
					case <-p.ctx.Done():
						return
					}
				}
			}
		}
		if p.ctx.Err() != nil {
			p.finish(job, nil)
			return
		}
		ctx, cancel := context.WithTimeout(p.ctx, p.budget)
		slot := cachevolumes.Slot{Identity: job.identity}
		subject := cachevolumes.SubjectOf(slot)
		if !job.requested && subject.Key == "" {
			// A HEAD from the fleet listing does not say whether its volume is managed.
			subject.Kind = ""
		}
		done := cachevolumes.Observer(observeCustomCache).With(subject).Start("prefetch", "remote")
		var err error
		withThrottledIO(func() { err = p.restore(ctx, slot, job.requested) })
		budgetEnded := errors.Is(err, cachevolumes.ErrDownloadIncomplete) || (err != nil && errors.Is(ctx.Err(), context.DeadlineExceeded))
		done(err)
		cancel()
		if err == nil && job.identity.HeadSizeBytes > 0 {
			customCachePrefetchedBytes.WithLabelValues(job.reason).Add(float64(job.identity.HeadSizeBytes))
		}
		// The budget is a turn, not a limit: the download keeps its archive and
		// resumes behind the masters queued since. A budget that ended without
		// archive bytes (the archive was complete and still expanding, or a slow
		// server request) resumes too, a few times, instead of waiting out
		// customPrefetchRetry as a failure.
		if errors.Is(err, cachevolumes.ErrDownloadIncomplete) {
			job.idleBudgets = 0
		} else if budgetEnded {
			job.idleBudgets++
		}
		if budgetEnded && job.idleBudgets < customPrefetchIdleBudgets && p.requeue(job) {
			continue
		}
		p.finish(job, err)
	}
}

// deferForJobs reports whether a background master waits for the host's
// jobs: true while a runner runs one, until customPrefetchJobWaitCap after the
// worker first waited for them.
func (p *customPrefetcher) deferForJobs() bool {
	if p.busy == nil || !p.busy(p.ctx) {
		p.deferredSince = time.Time{}
		return false
	}
	if p.deferredSince.IsZero() {
		p.deferredSince = time.Now()
	}
	return time.Since(p.deferredSince) < customPrefetchJobWaitCap
}

// holdForJobs returns whether background work waits for the host's jobs:
// true while busy reports a running job, until customPrefetchJobWaitCap after
// it first waited for them, as deferForJobs does for master prefetch.
func holdForJobs(busy func(context.Context) bool) func(context.Context) bool {
	var mu sync.Mutex
	var since time.Time
	return func(ctx context.Context) bool {
		mu.Lock()
		defer mu.Unlock()
		if !busy(ctx) {
			since = time.Time{}
			return false
		}
		if since.IsZero() {
			since = time.Now()
		}
		return time.Since(since) < customPrefetchJobWaitCap
	}
}

// requeue puts a download its budget cut short behind the masters queued since,
// still pending, so it resumes from the bytes it received once they had a turn.
func (p *customPrefetcher) requeue(job *customPrefetch) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.stopped || p.ctx.Err() != nil {
		return false
	}
	queue := p.background
	if job.requested {
		queue = p.requested
	}
	select {
	case queue <- job:
		return true
	default:
		return false
	}
}

func (p *customPrefetcher) finish(job *customPrefetch, err error) {
	key := prefetchKey(job.identity)
	p.mu.Lock()
	delete(p.pending, key)
	for failed, at := range p.failed {
		if time.Since(at) >= customPrefetchRetry {
			delete(p.failed, failed)
		}
	}
	if err != nil && p.ctx.Err() == nil {
		p.failed[key] = time.Now()
	} else {
		delete(p.failed, key)
	}
	p.mu.Unlock()
	close(job.done)
}

// drain stops accepting work and releases everyone still waiting on a queued
// master. Queuing happens under the same lock, so no job lands after it.
func (p *customPrefetcher) drain() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.stopped = true
	for _, job := range p.pending {
		close(job.done)
	}
	p.pending = map[string]*customPrefetch{}
}

func prefetchKey(identity cachevolumes.Identity) string {
	return identity.Scope + "/" + strconv.FormatInt(identity.BaseGeneration, 10)
}
