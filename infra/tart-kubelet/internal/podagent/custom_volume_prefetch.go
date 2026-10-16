package podagent

import (
	"context"
	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	"sync"
	"time"
)

// A missed foreground deadline may warm one master in the background, without
// queuing work or extending the job's deadline. Shutdown joins the worker.
type customPrefetcher struct {
	ctx     context.Context
	slots   chan struct{}
	budget  time.Duration
	restore func(context.Context, cachevolumes.Slot) error
	wait    sync.WaitGroup
}

func (p *customPrefetcher) start(identity cachevolumes.Identity) bool {
	if p == nil || identity.BaseGeneration == 0 {
		return false
	}
	select {
	case p.slots <- struct{}{}:
	default:
		return false
	}
	p.wait.Add(1)
	go func() {
		defer p.wait.Done()
		defer func() { <-p.slots }()
		ctx, cancel := context.WithTimeout(p.ctx, p.budget)
		defer cancel()
		done := cachevolumes.Observer(observeCustomCache).Start("prefetch", "remote")
		done(p.restore(ctx, cachevolumes.Slot{Identity: identity}))
	}()
	return true
}
