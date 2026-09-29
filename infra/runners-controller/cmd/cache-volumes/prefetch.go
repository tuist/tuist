package main

import (
	"context"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// One bounded attempt per node, with no waiting queue. This gives a cold host a
// chance to warm up without extending the requesting job's acquisition budget.
type prefetcher struct {
	slots   chan struct{}
	restore func(context.Context, cachevolumes.Slot) error
	observe cachevolumes.Observer
	budget  time.Duration
}

func (p *prefetcher) start(identity cachevolumes.Identity) bool {
	if p == nil || identity.BaseGeneration == 0 {
		return false
	}
	select {
	case p.slots <- struct{}{}:
	default:
		return false
	}
	go func() {
		defer func() { <-p.slots }()
		ctx, cancel := context.WithTimeout(context.Background(), p.budget)
		defer cancel()
		done := p.observe.Start("prefetch", "remote")
		done(p.restore(ctx, cachevolumes.Slot{Identity: identity}))
	}()
	return true
}
