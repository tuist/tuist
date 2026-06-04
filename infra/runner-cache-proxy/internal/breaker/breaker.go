// Package breaker is the proxy's health-gated circuit breaker. It trips
// the proxy to full pass-through (route CacheService to genuine GitHub)
// when the cache-gateway is unhealthy, unreachable, or repeatedly failing
// live requests, so backend faults degrade to GitHub's hosted cache
// rather than to broken workflows.
package breaker

import (
	"context"
	"sync"
	"time"
)

// State is the breaker's state for metrics.
type State int

const (
	Closed State = iota
	Open
	HalfOpen
)

func (s State) String() string {
	switch s {
	case Open:
		return "open"
	case HalfOpen:
		return "half_open"
	default:
		return "closed"
	}
}

// Breaker gates routing on two signals: a periodic health probe and a
// live consecutive-failure count. Either can trip it open.
type Breaker struct {
	mu               sync.Mutex
	healthy          bool
	consecutiveFails int
	openedAt         time.Time
	tripped          bool

	failureThreshold int
	cooldown         time.Duration
	now              func() time.Time
}

// New builds a breaker. failureThreshold is the live consecutive-failure
// count that trips it; cooldown is how long it stays open before
// admitting a probe.
func New(failureThreshold int, cooldown time.Duration) *Breaker {
	if failureThreshold < 1 {
		failureThreshold = 1
	}
	return &Breaker{
		healthy:          true,
		failureThreshold: failureThreshold,
		cooldown:         cooldown,
		now:              time.Now,
	}
}

// Allow reports whether CacheService traffic may be routed to the gateway.
// false means fail open to GitHub.
func (b *Breaker) Allow() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	if !b.healthy {
		return false
	}
	if !b.tripped {
		return true
	}
	if b.now().Sub(b.openedAt) >= b.cooldown {
		// Admit a single probe by clearing the trip; a subsequent
		// failure re-trips.
		b.tripped = false
		b.consecutiveFails = 0
		return true
	}
	return false
}

// RecordSuccess clears the live failure count.
func (b *Breaker) RecordSuccess() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.consecutiveFails = 0
	b.tripped = false
}

// RecordFailure records a live request failure, possibly tripping.
func (b *Breaker) RecordFailure() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.consecutiveFails++
	if b.consecutiveFails >= b.failureThreshold {
		b.tripped = true
		b.openedAt = b.now()
	}
}

// SetHealthy is called by the health prober.
func (b *Breaker) SetHealthy(healthy bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.healthy = healthy
}

// State returns the current state for metrics.
func (b *Breaker) State() State {
	b.mu.Lock()
	defer b.mu.Unlock()
	if !b.healthy || b.tripped {
		return Open
	}
	return Closed
}

// RunProber periodically calls probe and updates health until ctx is done.
func (b *Breaker) RunProber(ctx context.Context, probe func(context.Context) bool, interval time.Duration) {
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			b.SetHealthy(probe(ctx))
		}
	}
}
