package diskallocator

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type Backend interface {
	// Read returns kernel usage/limits and capacity available to the listed
	// projects after reserves and all unlisted projects' commitments.
	Read([]Volume) ([]Sample, uint64, error)
	SetLimit(Volume, uint64) error
}

type Budget struct {
	Version     int    `json:"version"`
	VolumeID    string `json:"volume_id"`
	Generation  uint64 `json:"generation"`
	ExpiresMS   int64  `json:"expires_ms"`
	Floor       uint64 `json:"floor_bytes"`
	Ceiling     uint64 `json:"ceiling_bytes"`
	Current     uint64 `json:"current_bytes"`
	Target      uint64 `json:"target_bytes"`
	AllowWrites bool   `json:"allow_writes"`
}

type Agent struct {
	Backend    Backend
	ControlDir string
	// Demand holds a recently observed working set through quiet intervals.
	// A restart may forget demand, but never the kernel's existing commitments.
	demand      map[string]demandSample
	generation  uint64
	allowWrites bool
}

type demandSample struct {
	bytes uint64
	at    time.Time
}

const quotaUnit = uint64(1024 * 1024)

func ValidateVolumes(volumes []Volume) error {
	seen := map[string]bool{}
	paths := map[string]bool{}
	for _, v := range volumes {
		if v.ID == "" || strings.ContainsAny(v.ID, "/\\") || v.ID == "." || v.ID == ".." || len(v.ID) > 200 {
			return fmt.Errorf("invalid volume identity %q", v.ID)
		}
		if seen[v.ID] || paths[v.Path] || !filepath.IsAbs(v.Path) || v.Floor < 4*GiB || v.Ceiling < v.Floor || v.Ceiling > 1<<50 || v.Floor%quotaUnit != 0 || v.Ceiling%quotaUnit != 0 {
			return fmt.Errorf("invalid or duplicate volume %q", v.ID)
		}
		seen[v.ID], paths[v.Path] = true, true
	}
	return nil
}

func (a *Agent) Reconcile(volumes []Volume, now time.Time) ([]Budget, error) {
	if err := ValidateVolumes(volumes); err != nil {
		return nil, err
	}
	samples, capacity, err := a.Backend.Read(volumes)
	if err != nil {
		return nil, err
	}
	if len(samples) != len(volumes) {
		return nil, fmt.Errorf("incomplete quota observation")
	}
	if a.demand == nil {
		a.demand = map[string]demandSample{}
	}
	active := make(map[string]bool, len(volumes))
	for _, v := range volumes {
		active[v.ID] = true
	}
	for id := range a.demand {
		if !active[id] {
			delete(a.demand, id)
		}
	}
	for i := range samples {
		s := &samples[i]
		// Invert the runtime's metadata/staging/rotation allowance. Merely
		// adding a fixed margin can repeatedly shrink a quiet useful cache:
		// each smaller ring reduces occupancy and asks for another shrink.
		staging := min(s.Floor/4, 2*GiB)
		wanted := min(s.Ceiling, max(s.Floor, (s.Used*100+96)/97+staging+2*GiB))
		if s.Used >= s.Current/10*7 {
			wanted = min(s.Ceiling, max(wanted, s.Current+max(GiB, s.Current/4)))
		}
		previous := a.demand[s.ID]
		if wanted >= previous.bytes || now.Sub(previous.at) >= 5*time.Minute {
			previous = demandSample{wanted, now}
			a.demand[s.ID] = previous
		}
		s.Demand = previous.bytes
	}
	targets, err := Targets(capacity, samples)
	floorsFit := err == nil
	if err != nil {
		// Unexpected external use may make even floors unsustainable. Stop
		// writes, but still ask runtimes to reclaim down to their floors.
		targets = map[string]uint64{}
		for _, s := range samples {
			targets[s.ID] = s.Floor
		}
	}
	for id, target := range targets {
		targets[id] = target / quotaUnit * quotaUnit
	}
	total, chargeErr := charged(samples)
	if chargeErr != nil {
		return nil, chargeErr
	}
	a.allowWrites = err == nil && total <= capacity
	// Shrinks precede increases. The runtime receives the lower target while
	// the old kernel allowance remains charged. A read-back is the commit.
	sort.Slice(samples, func(i, j int) bool { return samples[i].ID < samples[j].ID })
	a.generation = max(a.generation+1, uint64(now.UnixNano()))
	for _, s := range samples {
		target := targets[s.ID]
		if target < s.Current {
			if err := a.publish(s, target, now); err != nil {
				return nil, err
			}
			if s.Used <= target {
				if err := a.Backend.SetLimit(s.Volume, target); err != nil {
					return nil, err
				}
			}
		}
	}
	// Reread even when no shrink was necessary: concurrent non-tenant writes
	// and retained/open files can reduce the physical headroom.
	samples, capacity, err = a.Backend.Read(volumes)
	if err != nil {
		return nil, err
	}
	for i, s := range samples {
		total, err := charged(samples)
		if err != nil {
			return nil, err
		}
		target := targets[s.ID]
		if target > s.Current && total <= capacity {
			increase := min(target-s.Current, capacity-total) / quotaUnit * quotaUnit
			if increase > 0 {
				if err := a.Backend.SetLimit(s.Volume, s.Current+increase); err != nil {
					return nil, err
				}
				// Charge immediately; no second replica can spend this space.
				samples[i].Current = s.Current + increase
			}
		}
	}
	samples, capacity, err = a.Backend.Read(volumes)
	if err != nil {
		return nil, err
	}
	total, err = charged(samples)
	if err != nil {
		return nil, err
	}
	a.allowWrites = floorsFit && total <= capacity
	budgets := make([]Budget, 0, len(samples))
	for _, s := range samples {
		target := min(targets[s.ID], s.Current)
		if err := a.publish(s, target, now); err != nil {
			return nil, err
		}
		budgets = append(budgets, a.budget(s, target, now))
	}
	return budgets, nil
}

func (a *Agent) budget(s Sample, target uint64, now time.Time) Budget {
	return Budget{1, s.ID, a.generation, now.Add(15 * time.Second).UnixMilli(), s.Floor, s.Ceiling, s.Current, target, a.allowWrites}
}

func (a *Agent) publish(s Sample, target uint64, now time.Time) error {
	a.generation++
	data, err := json.Marshal(a.budget(s, target, now))
	if err != nil {
		return err
	}
	if err := os.MkdirAll(a.ControlDir, 0755); err != nil {
		return err
	}
	file, err := os.CreateTemp(a.ControlDir, ".budget-")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if err = file.Chmod(0644); err == nil {
		_, err = file.Write(data)
	}
	if err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(file.Name(), filepath.Join(a.ControlDir, s.ID+".json"))
}
