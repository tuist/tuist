package macos

import (
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"sigs.k8s.io/controller-runtime/pkg/client"
)

const (
	cardLoginBackoffStart = time.Minute
	cardLoginBackoffCap   = time.Hour
)

// cardLoginBackoff spaces out logins a card has refused: a card may block an
// account after repeated failures, and a blocked account needs someone at the
// card. Each refusal doubles the wait, from a minute up to an hour. A success,
// a new generation of the object or a change to its annotations starts over.
// It is held in memory, so a new leader starts over too.
type cardLoginBackoff struct {
	mu      sync.Mutex
	now     func() time.Time
	entries map[string]*cardLoginBackoffEntry
}

type cardLoginBackoffEntry struct {
	epoch    string
	failures int
	until    time.Time
}

// cardBackoffKey and cardBackoffEpoch identify an object and the version of
// it a backoff applies to.
func cardBackoffKey(o client.Object) string {
	return o.GetNamespace() + "/" + o.GetName()
}

func cardBackoffEpoch(o client.Object) string {
	annotations := o.GetAnnotations()
	keys := make([]string, 0, len(annotations))
	for k := range annotations {
		keys = append(keys, k+"="+annotations[k])
	}
	sort.Strings(keys)
	return fmt.Sprintf("%d|%s", o.GetGeneration(), strings.Join(keys, ","))
}

func (b *cardLoginBackoff) clock() time.Time {
	if b.now != nil {
		return b.now()
	}
	return time.Now()
}

func (b *cardLoginBackoff) entry(o client.Object) *cardLoginBackoffEntry {
	if b.entries == nil {
		b.entries = map[string]*cardLoginBackoffEntry{}
	}
	epoch := cardBackoffEpoch(o)
	e, ok := b.entries[cardBackoffKey(o)]
	if !ok || e.epoch != epoch {
		e = &cardLoginBackoffEntry{epoch: epoch}
		b.entries[cardBackoffKey(o)] = e
	}
	return e
}

// wait is how long logins to the object's card are still held off.
func (b *cardLoginBackoff) wait(o client.Object) time.Duration {
	b.mu.Lock()
	defer b.mu.Unlock()
	if d := b.entry(o).until.Sub(b.clock()); d > 0 {
		return d
	}
	return 0
}

// refused records a refused login and returns how long the next is held off.
func (b *cardLoginBackoff) refused(o client.Object) time.Duration {
	b.mu.Lock()
	defer b.mu.Unlock()
	e := b.entry(o)
	delay := cardLoginBackoffStart
	for i := 0; i < e.failures && delay < cardLoginBackoffCap; i++ {
		delay *= 2
	}
	if delay > cardLoginBackoffCap {
		delay = cardLoginBackoffCap
	}
	e.failures++
	e.until = b.clock().Add(delay)
	return delay
}

// succeeded clears the object's backoff.
func (b *cardLoginBackoff) succeeded(o client.Object) {
	b.mu.Lock()
	defer b.mu.Unlock()
	delete(b.entries, cardBackoffKey(o))
}
