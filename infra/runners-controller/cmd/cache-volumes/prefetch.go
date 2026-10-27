package main

import (
	"context"
	"sync"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// One download per node, with a bounded FIFO of lineages. Keep the newest
// requested generation per lineage: dropping requests while a large unrelated
// download runs can otherwise leave a busy node serving old snapshots forever.
// Attach still never waits for network I/O. Queued identities are hints only;
// the server reauthorizes downloads, and a later attach/maintenance reconstructs
// demand after a restart. The shared transfer bounds stalls and retries.
type prefetcher struct {
	mu      sync.Mutex
	active  *cachevolumes.Identity
	pending []cachevolumes.Identity
	restore func(context.Context, cachevolumes.Slot) error
	local   func(cachevolumes.Identity) bool
	observe cachevolumes.Observer
}

const prefetchQueueLimit = 64

func (p *prefetcher) start(identity cachevolumes.Identity) bool {
	if p == nil || identity.BaseGeneration == 0 || (p.local != nil && p.local(identity)) {
		return false
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.active == nil {
		p.active = &identity
		go p.work(identity)
		return true
	}
	if p.active.Scope == identity.Scope && p.active.BaseGeneration >= identity.BaseGeneration {
		return false
	}
	for i, pending := range p.pending {
		if pending.Scope == identity.Scope {
			if pending.BaseGeneration >= identity.BaseGeneration {
				return false
			}
			p.pending[i] = identity
			return true
		}
	}
	if len(p.pending) == prefetchQueueLimit {
		return false
	}
	p.pending = append(p.pending, identity)
	return true
}

func (p *prefetcher) work(identity cachevolumes.Identity) {
	for {
		if p.local == nil || !p.local(identity) {
			done := p.observe.For(cachevolumes.Slot{Identity: identity}).Start("prefetch", "remote")
			done(p.restore(context.Background(), cachevolumes.Slot{Identity: identity}))
		}
		p.mu.Lock()
		if len(p.pending) == 0 {
			p.active = nil
			p.mu.Unlock()
			return
		}
		identity, p.pending = p.pending[0], p.pending[1:]
		current := identity
		p.active = &current
		p.mu.Unlock()
	}
}
