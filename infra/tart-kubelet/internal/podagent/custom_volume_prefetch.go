package podagent

import (
	"context"
	"strconv"
	"sync"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

const (
	// customAcquireBudget bounds how long a job waits for its volume. A warm
	// volume whose master is not on this host downloads first, which takes about
	// a minute for 10 GB of data: less than the cold install the job would run.
	customAcquireBudget  = 3 * time.Minute
	customPrefetchBudget = 5 * time.Minute
	customPrefetchQueue  = 16
)

// PrefetchMaster queues a HEAD the server listed for this host's fleet, behind
// any master a job is waiting on. Reports whether it is queued or already here.
func (c *CustomVolumes) PrefetchMaster(identity cachevolumes.Identity) bool {
	if c == nil {
		return false
	}
	return c.prefetch.Load().start(identity, false) != nil
}

// customPrefetcher restores immutable masters in the background, one at a time
// so a single 40 GB disk reservation covers the work. A job waiting on a master
// goes ahead of masters the server listed for this host. A master already
// queued or downloading is joined rather than fetched twice, and a download a
// job stopped waiting for keeps going so a later job on this host finds it.
// Shutdown releases waiters and joins the worker.
type customPrefetcher struct {
	ctx    context.Context
	budget time.Duration
	// restore may evict local masters only for a job waiting on the download.
	restore func(ctx context.Context, slot cachevolumes.Slot, urgent bool) error
	has     func(cachevolumes.Identity) bool

	mu         sync.Mutex
	stopped    bool
	pending    map[string]*customPrefetch
	urgent     chan *customPrefetch
	background chan *customPrefetch
	wait       sync.WaitGroup
}

var installed = func() <-chan struct{} {
	done := make(chan struct{})
	close(done)
	return done
}()

type customPrefetch struct {
	identity cachevolumes.Identity
	urgent   bool
	done     chan struct{}
}

func newCustomPrefetcher(ctx context.Context, restore func(context.Context, cachevolumes.Slot, bool) error, has func(cachevolumes.Identity) bool) *customPrefetcher {
	p := &customPrefetcher{
		ctx:        ctx,
		budget:     customPrefetchBudget,
		restore:    restore,
		has:        has,
		pending:    map[string]*customPrefetch{},
		urgent:     make(chan *customPrefetch, customPrefetchQueue),
		background: make(chan *customPrefetch, customPrefetchQueue),
	}
	p.wait.Go(p.work)
	return p
}

// start queues a master and returns a channel closed once it is installed, has
// failed or was dropped. Nil when nothing was queued: a cold identity, a full
// queue or a stopped prefetcher.
func (p *customPrefetcher) start(identity cachevolumes.Identity, urgent bool) <-chan struct{} {
	if p == nil || identity.BaseGeneration <= 0 {
		return nil
	}
	if p.has != nil && p.has(identity) {
		return installed
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
	job := &customPrefetch{identity: identity, urgent: urgent, done: make(chan struct{})}
	queue := p.background
	if urgent {
		queue = p.urgent
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
		case job = <-p.urgent:
		default:
			select {
			case job = <-p.urgent:
			case job = <-p.background:
			case <-p.ctx.Done():
				return
			}
		}
		if p.ctx.Err() != nil {
			p.finish(job)
			return
		}
		ctx, cancel := context.WithTimeout(p.ctx, p.budget)
		done := cachevolumes.Observer(observeCustomCache).Start("prefetch", "remote")
		done(p.restore(ctx, cachevolumes.Slot{Identity: job.identity}, job.urgent))
		cancel()
		p.finish(job)
	}
}

func (p *customPrefetcher) finish(job *customPrefetch) {
	p.mu.Lock()
	delete(p.pending, prefetchKey(job.identity))
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
