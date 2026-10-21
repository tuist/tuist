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
)

// PrefetchMaster queues a HEAD the server listed for this host's fleet, behind
// any master a job asked for. Reports whether it is queued or already here.
func (c *CustomVolumes) PrefetchMaster(identity cachevolumes.Identity) bool {
	if c == nil {
		return false
	}
	return c.prefetch.Load().start(identity, false) != nil
}

// customPrefetcher restores immutable masters in the background, one at a time
// so a single 40 GB disk reservation covers the work. Jobs never wait on it. A
// master a job asked for but did not get in time goes ahead of masters the
// server listed for this host, and only the former may evict local masters. A
// master already queued or downloading is joined rather than fetched twice.
// Shutdown releases waiters and joins the worker.
type customPrefetcher struct {
	ctx    context.Context
	budget time.Duration
	// restore may evict local masters only for a master a job asked for.
	restore func(ctx context.Context, slot cachevolumes.Slot, requested bool) error
	has     func(cachevolumes.Identity) bool

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
	done      chan struct{}
}

func newCustomPrefetcher(ctx context.Context, restore func(context.Context, cachevolumes.Slot, bool) error, has func(cachevolumes.Identity) bool) *customPrefetcher {
	p := &customPrefetcher{
		ctx:        ctx,
		budget:     customPrefetchBudget,
		restore:    restore,
		has:        has,
		pending:    map[string]*customPrefetch{},
		failed:     map[string]time.Time{},
		requested:  make(chan *customPrefetch, customPrefetchQueue),
		background: make(chan *customPrefetch, customPrefetchQueue),
	}
	p.wait.Go(p.work)
	return p
}

// start queues a master and returns a channel closed once it is installed, has
// failed or was dropped. Nil when nothing was queued: a cold identity, a full
// queue or a stopped prefetcher.
func (p *customPrefetcher) start(identity cachevolumes.Identity, requested bool) <-chan struct{} {
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
	job := &customPrefetch{identity: identity, requested: requested, done: make(chan struct{})}
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
	for {
		var job *customPrefetch
		select {
		case job = <-p.requested:
		default:
			select {
			case job = <-p.requested:
			case job = <-p.background:
			case <-p.ctx.Done():
				return
			}
		}
		if p.ctx.Err() != nil {
			p.finish(job, nil)
			return
		}
		ctx, cancel := context.WithTimeout(p.ctx, p.budget)
		done := cachevolumes.Observer(observeCustomCache).Start("prefetch", "remote")
		err := p.restore(ctx, cachevolumes.Slot{Identity: job.identity}, job.requested)
		done(err)
		cancel()
		if errors.Is(err, cachevolumes.ErrDownloadIncomplete) && p.requeue(job) {
			continue
		}
		p.finish(job, err)
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
