package scaling

// PoolDemand is one pool's input to the fleet-capacity allocation.
// All pools in a single AllocateFleet call share one capacity
// budget (the contention domain): for Linux that's the schedulable
// memory across a bare-metal node pool, for macOS the number of
// available host slots (1 VM per Mac mini).
type PoolDemand struct {
	Name string

	// PerPodCost is what one Pod consumes from the shared budget,
	// in the same unit as `fleetCapacity`:
	//   - Linux: per-Pod memory request in bytes (kata microVMs
	//     pin memory per sandbox; CPU is deliberately
	//     oversubscribed, so memory is the only bin-packed
	//     dimension).
	//   - macOS: always 1 (one Mac mini = one slot = one VM,
	//     per Apple's Virtualization.framework SLA).
	PerPodCost int64

	// Floor is `minWarmPoolFloor` — the always-on warm guarantee.
	Floor int32

	// Load is `claimed + queued` — real work running or waiting for a
	// Pod right now.
	Load int32

	// Target is the per-pool `DesiredReplicas` output: the full ask
	// including the speculative p95 warm buffer, already clamped to
	// `maxReplicas`.
	Target int32
}

// AllocateFleet distributes `fleetCapacity` across pools sharing a
// capacity domain, in three tiers:
//
//  1. Floor — every pool's `minWarmPoolFloor` (the warm guarantee).
//  2. Load — `claimed + queued` real work above the floor.
//  3. Headroom — the speculative p95 warm buffer (`Target` above
//     floor+load).
//
// Tiers 1+2 are genuine need and are always granted in full, even when
// their sum exceeds capacity: the excess goes Pending, which is the
// operator's "add a host" signal. The autoscaler must not mask real
// demand by dropping warm guarantees or starving queued work.
//
// Tier 3 is discretionary. It's granted only from the capacity left
// after tiers 1+2, split proportionally to each pool's requested
// headroom when short. That squeeze is the cross-pool reclaim: an idle
// pool's speculative warm Pods are denied before another pool's real
// queued work, so a starved high-demand pool can grow as idle pools
// fall back toward their floor.
//
// Returns desired replicas per pool name, each in `[base_i, Target_i]`
// where `base_i = min(max(floor_i, load_i), target_i)`. The algorithm
// is unit-agnostic: `fleetCapacity` and `PerPodCost` just need to be
// in the same unit (memory bytes for Linux, host slots for macOS).
func AllocateFleet(pools []PoolDemand, fleetCapacity int64) map[string]int32 {
	out := make(map[string]int32, len(pools))

	type headroom struct {
		name string
		want int32 // replicas of speculative buffer requested
		cost int64 // per-Pod cost
	}

	var headrooms []headroom
	var headroomCostTotal int64
	remaining := fleetCapacity

	// Tier 1+2: grant base = real need, always in full.
	for _, p := range pools {
		base := p.Floor
		if p.Load > base {
			base = p.Load
		}
		if base > p.Target {
			base = p.Target
		}
		if base < 0 {
			base = 0
		}

		out[p.Name] = base
		remaining -= int64(base) * p.PerPodCost

		want := p.Target - base
		if want > 0 && p.PerPodCost > 0 {
			headrooms = append(headrooms, headroom{name: p.Name, want: want, cost: p.PerPodCost})
			headroomCostTotal += int64(want) * p.PerPodCost
		}
	}

	// No capacity left for speculative warm, or nobody wants any.
	if remaining <= 0 || headroomCostTotal == 0 {
		return out
	}

	// Uncontended: everything fits, grant all headroom.
	if remaining >= headroomCostTotal {
		for _, h := range headrooms {
			out[h.name] += h.want
		}
		return out
	}

	// Contended: split `remaining` proportionally to requested headroom
	// cost. Each pool's fair grant works out to `ratio * want`
	// replicas, so we scale the replica ask directly — a float ratio
	// avoids the int64 overflow that `remaining * wantCost` hits at
	// GiB scale. Integer floor per pool; leftover from rounding stays
	// unused (conservative — never over-commits).
	ratio := float64(remaining) / float64(headroomCostTotal)
	for _, h := range headrooms {
		grant := int32(float64(h.want) * ratio)
		if grant > h.want {
			grant = h.want
		}
		out[h.name] += grant
	}

	return out
}
