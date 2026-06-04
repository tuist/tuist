package router

import (
	"sync"
	"time"
)

// DecisionCache makes a routing decision sticky per logical transfer so
// we never half-intercept an entry: once a (srcIP, sni) pair has resolved
// to a target, follow-up connections inherit it until the TTL lapses.
type DecisionCache struct {
	mu      sync.Mutex
	entries map[string]decision
	ttl     time.Duration
	now     func() time.Time
}

type decision struct {
	target  Target
	expires time.Time
}

// NewDecisionCache builds a cache with the given stickiness window.
func NewDecisionCache(ttl time.Duration) *DecisionCache {
	return &DecisionCache{
		entries: map[string]decision{},
		ttl:     ttl,
		now:     time.Now,
	}
}

// Resolve returns the sticky target for key, computing and caching it via
// compute on a miss or expiry.
func (c *DecisionCache) Resolve(key string, compute func() Target) Target {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := c.now()
	if d, ok := c.entries[key]; ok && now.Before(d.expires) {
		return d.target
	}
	t := compute()
	c.entries[key] = decision{target: t, expires: now.Add(c.ttl)}
	return t
}
