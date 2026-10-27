package main

import (
	"context"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// One attempt per node, with no waiting queue. An attach never downloads, so a
// job that found no local copy of its saved version warms this host for the
// next one without extending its own acquisition budget. A prefetch has no
// deadline: its download ends when it stalls or runs out of attempts.
type prefetcher struct {
	slots   chan struct{}
	restore func(context.Context, cachevolumes.Slot) error
	// local reports whether the identity's master is already on this host.
	local   func(cachevolumes.Identity) bool
	observe cachevolumes.Observer
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
		done := p.observe.For(cachevolumes.Slot{Identity: identity}).Start("prefetch", "remote")
		done(p.restore(context.Background(), cachevolumes.Slot{Identity: identity}))
	}()
	return true
}
