package network

import (
	"errors"
	"sync"
)

// Slots hands out slot indexes. A slot decides a sandbox's veth name, its
// /30 and its jail uid, so it is persisted in the sandbox metadata and
// re-reserved on startup.
type Slots struct {
	mu   sync.Mutex
	used map[int]bool
	max  int
}

func NewSlots(max int) *Slots {
	if max <= 0 || max > MaxSlots {
		max = MaxSlots
	}
	return &Slots{used: map[int]bool{}, max: max}
}

var ErrNoFreeSlot = errors.New("no free network slot")

// Allocate returns the lowest free slot.
func (s *Slots) Allocate() (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := 0; i < s.max; i++ {
		if !s.used[i] {
			s.used[i] = true
			return i, nil
		}
	}
	return 0, ErrNoFreeSlot
}

// Reserve marks a specific slot used. It fails if the slot is taken.
func (s *Slots) Reserve(slot int) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if slot < 0 || slot >= s.max {
		return errors.New("slot out of range")
	}
	if s.used[slot] {
		return errors.New("slot already reserved")
	}
	s.used[slot] = true
	return nil
}

func (s *Slots) Release(slot int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.used, slot)
}

func (s *Slots) InUse() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.used)
}
