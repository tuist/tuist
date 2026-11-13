package sandbox

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"errors"
	"sync"
	"time"
)

// ErrClaimRefused answers a claim with no pending exec for its sandbox or
// a nonce that does not match it.
var ErrClaimRefused = errors.New("claim refused")

// Claims hands server-granted execs to a direct caller. An exec that
// carries a claim waits here until the caller presents the claim's nonce
// with the value of one environment variable, or until the claim expires
// unused. The command, the rest of its environment and its timeout stay
// the server's. Each claim is single-use.
type Claims struct {
	mu      sync.Mutex
	pending map[string]*claim
	// changed is closed and replaced whenever a claim is registered.
	changed chan struct{}
}

type claim struct {
	digest [sha256.Size]byte
	offers chan claimOffer
}

type claimOffer struct {
	value   string
	outcome chan ClaimOutcome
}

// ClaimOutcome is the claimed command's exit code and standard output.
type ClaimOutcome struct {
	ExitCode int
	Stdout   []byte
	Err      error
}

func NewClaims() *Claims {
	return &Claims{pending: map[string]*claim{}, changed: make(chan struct{})}
}

// wait registers a claim and blocks until it is claimed, it expires or ctx
// ends. ok is false when it expired unclaimed.
func (c *Claims) wait(ctx context.Context, sandboxID string, digest [sha256.Size]byte, timeout time.Duration) (offer claimOffer, ok bool, err error) {
	c.mu.Lock()
	if _, exists := c.pending[sandboxID]; exists {
		c.mu.Unlock()
		return offer, false, errors.New("exec: a claim is already pending for this sandbox")
	}
	pending := &claim{digest: digest, offers: make(chan claimOffer, 1)}
	c.pending[sandboxID] = pending
	close(c.changed)
	c.changed = make(chan struct{})
	c.mu.Unlock()

	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case offer = <-pending.offers:
		return offer, true, nil
	case <-timer.C:
	case <-ctx.Done():
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.pending[sandboxID] == pending {
		delete(c.pending, sandboxID)
	}
	// Claim delivers its offer under the lock, so one that won the race
	// with the expiry is visible here.
	select {
	case offer = <-pending.offers:
		return offer, true, nil
	default:
		return offer, false, ctx.Err()
	}
}

// Claim runs the pending exec of a sandbox with value for its claimed
// variable and returns the command's outcome. A claim granted to the caller
// may reach it before the server's exec reaches this node, so Claim waits
// up to registration for the exec to register.
func (c *Claims) Claim(ctx context.Context, sandboxID string, nonce []byte, value string, registration time.Duration) (ClaimOutcome, error) {
	digest := sha256.Sum256(nonce)
	deadline := time.NewTimer(registration)
	defer deadline.Stop()
	for {
		c.mu.Lock()
		pending := c.pending[sandboxID]
		if pending != nil {
			if subtle.ConstantTimeCompare(pending.digest[:], digest[:]) != 1 {
				c.mu.Unlock()
				return ClaimOutcome{}, ErrClaimRefused
			}
			delete(c.pending, sandboxID)
			offer := claimOffer{value: value, outcome: make(chan ClaimOutcome, 1)}
			pending.offers <- offer
			c.mu.Unlock()
			select {
			case outcome := <-offer.outcome:
				return outcome, nil
			case <-ctx.Done():
				return ClaimOutcome{}, ctx.Err()
			}
		}
		changed := c.changed
		c.mu.Unlock()
		select {
		case <-changed:
		case <-deadline.C:
			return ClaimOutcome{}, ErrClaimRefused
		case <-ctx.Done():
			return ClaimOutcome{}, ctx.Err()
		}
	}
}
