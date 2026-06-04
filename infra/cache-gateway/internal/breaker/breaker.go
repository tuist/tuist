// Package breaker is a small health-gated circuit breaker. When the
// backend (object store / index) fails repeatedly, the breaker opens and
// the gateway fails open: coordination calls return a pass-through
// signal so the runner transparently uses GitHub's hosted cache instead
// of seeing an error.
package breaker

import (
	"sync"
	"time"
)

// State is the breaker's current state.
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

// Breaker trips to Open after failureThreshold consecutive failures and
// recovers through a single HalfOpen probe after cooldown.
type Breaker struct {
	mu               sync.Mutex
	state            State
	consecutiveFails int
	openedAt         time.Time

	failureThreshold int
	cooldown         time.Duration
	now              func() time.Time
}

// New builds a breaker. failureThreshold is the number of consecutive
// failures that trips it; cooldown is how long it stays open before
// admitting a probe.
func New(failureThreshold int, cooldown time.Duration) *Breaker {
	if failureThreshold < 1 {
		failureThreshold = 1
	}
	return &Breaker{
		state:            Closed,
		failureThreshold: failureThreshold,
		cooldown:         cooldown,
		now:              time.Now,
	}
}

// Allow reports whether a request may proceed. A false result means the
// caller should fail open (pass through to GitHub).
func (b *Breaker) Allow() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	switch b.state {
	case Closed:
		return true
	case Open:
		if b.now().Sub(b.openedAt) >= b.cooldown {
			b.state = HalfOpen
			return true // admit a single probe
		}
		return false
	case HalfOpen:
		// While half-open, only the in-flight probe is admitted; further
		// calls wait until it resolves.
		return false
	default:
		return true
	}
}

// RecordSuccess marks a backend success, closing the breaker.
func (b *Breaker) RecordSuccess() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.consecutiveFails = 0
	b.state = Closed
}

// RecordFailure marks a backend failure, possibly opening the breaker.
func (b *Breaker) RecordFailure() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.consecutiveFails++
	if b.state == HalfOpen || b.consecutiveFails >= b.failureThreshold {
		b.state = Open
		b.openedAt = b.now()
	}
}

// State returns the current state (for metrics).
func (b *Breaker) State() State {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.state
}
