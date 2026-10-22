package main

import (
	"context"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// One bounded attempt per node, with no waiting queue. An attach never
// downloads, so a job that found no local copy of its saved version warms this
// host for the next one without extending its own acquisition budget.
type prefetcher struct {
	slots   chan struct{}
	restore func(context.Context, cachevolumes.Slot) error
	// local reports whether the identity's master is already on this host.
	local   func(cachevolumes.Identity) bool
	observe cachevolumes.Observer
	budget  time.Duration
	// installed counts each master it installs.
	installed func(reason string, bytes int64)
}

func (p *prefetcher) start(identity cachevolumes.Identity) bool {
	if p == nil || identity.BaseGeneration == 0 || (p.local != nil && p.local(identity)) {
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
		done := p.observe.For(cachevolumes.Slot{Identity: identity}).Start("prefetch", "remote")
		err := p.restore(ctx, cachevolumes.Slot{Identity: identity})
		done(err)
		if err == nil && p.installed != nil {
			p.installed("job", identity.HeadSizeBytes)
		}
	}()
	return true
}
