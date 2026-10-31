package diskallocator

import (
	"fmt"
	"sort"
)

const GiB = uint64(1024 * 1024 * 1024)

// Volume identifies a physical replica, not an account's logical data size.
type Volume struct {
	ID      string `json:"id"`
	Path    string `json:"path"`
	Floor   uint64 `json:"floor_bytes"`
	Ceiling uint64 `json:"ceiling_bytes"`
}

type Sample struct {
	Volume
	Used    uint64 `json:"used_bytes"`
	Current uint64 `json:"current_bytes"`
	Demand  uint64 `json:"demand_bytes"`
}

// Targets divides spare capacity equally among replicas that need it. Floors
// remain charged even when unused; saturated ceilings leave their surplus to
// the remaining replicas. A target is never permission to raise a quota.
func Targets(capacity uint64, samples []Sample) (map[string]uint64, error) {
	ordered := append([]Sample(nil), samples...)
	sort.Slice(ordered, func(i, j int) bool { return ordered[i].ID < ordered[j].ID })
	targets := make(map[string]uint64, len(samples))
	remaining := capacity
	for _, s := range ordered {
		if s.ID == "" || s.Floor == 0 || s.Ceiling < s.Floor {
			return nil, fmt.Errorf("invalid floor/ceiling for %q", s.ID)
		}
		if _, exists := targets[s.ID]; exists {
			return nil, fmt.Errorf("duplicate volume %q", s.ID)
		}
		if s.Floor > remaining {
			return nil, fmt.Errorf("disk floors exceed usable capacity")
		}
		remaining -= s.Floor
		targets[s.ID] = s.Floor
	}
	for remaining > 0 {
		active := make([]Sample, 0, len(ordered))
		for _, s := range ordered {
			if targets[s.ID] < min(s.Ceiling, max(s.Floor, s.Demand)) {
				active = append(active, s)
			}
		}
		if len(active) == 0 {
			break
		}
		share := max(uint64(1), remaining/uint64(len(active)))
		for _, s := range active {
			extra := min(share, min(s.Ceiling, max(s.Floor, s.Demand))-targets[s.ID], remaining)
			targets[s.ID] += extra
			remaining -= extra
		}
	}
	return targets, nil
}

func charged(samples []Sample) (uint64, error) {
	var total uint64
	for _, s := range samples {
		value := max(s.Used, s.Current)
		if ^uint64(0)-total < value {
			return 0, fmt.Errorf("disk accounting overflow")
		}
		total += value
	}
	return total, nil
}
