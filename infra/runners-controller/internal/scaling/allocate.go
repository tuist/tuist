package scaling

// PoolDemand is one pool's input to the fleet-capacity allocation.
// All pools in a single AllocateFleet call share one bare-metal node
// pool (the contention domain), so their footprints compete for the
// same allocatable memory.
type PoolDemand struct {
	Name string

	// PodMemBytes is the per-Pod memory request — the binding
	// constraint for kata microVMs, which pin memory per sandbox.
	// CPU is deliberately oversubscribed on the fleet (see the helm
	// values), so the allocator bin-packs on memory only.
	PodMemBytes int64

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

// AllocateFleet distributes `fleetMemBytes` of schedulable memory
// across pools sharing a bare-metal node pool, in three priority tiers:
//
//  1. Load — `claimed + queued`, the real work running or waiting for a
//     Pod. Genuine demand; granted in full even when it exceeds capacity
//     (the excess goes Pending, the operator's "add a host" signal).
//  2. Floor — `minWarmPoolFloor` above load: the speculative warm
//     guarantee that keeps the next spike off cold-start. Idle warm Pods.
//  3. Headroom — the p95 warm buffer (`Target` above floor+load). Also
//     idle, the most speculative.
//
// Only tier 1 is inviolable. Tiers 2 and 3 are idle warm capacity, and
// they yield — headroom first, then floor — to admit another pool's real
// queued work. That is the cross-pool reclaim: when a starved shape has
// queued jobs that don't fit, an idle shape's warm Pods are reaped
// (its desired falls below its floor) to free the memory, rather than
// leaving the queued jobs Pending while idle Pods hold reservations.
//
// The tradeoff is deliberate: under sustained load on one shape, other
// shapes' warm pools shrink toward their real load, so a returning spike
// on a squeezed shape pays cold-start. A job queued now beats a warm Pod
// for a job that might arrive. The per-pool scale-down cooldown damps the
// reap so it doesn't thrash.
//
// Each tier is granted in full when it fits; otherwise it is split
// proportionally to requested memory and all lower tiers get nothing.
// Result per pool is in `[load_i, Target_i]`. Memory is the only
// dimension considered.
func AllocateFleet(pools []PoolDemand, fleetMemBytes int64) map[string]int32 {
	out := make(map[string]int32, len(pools))

	type tierWant struct {
		name string
		want int32
		mem  int64
	}
	var loadWants, floorWants, headWants []tierWant

	// Decompose each pool's Target into the three priority tiers.
	for _, p := range pools {
		target := p.Target
		if target < 0 {
			target = 0
		}

		load := p.Load
		if load < 0 {
			load = 0
		}
		if load > target {
			load = target
		}

		// Top of the floor tier: the warm guarantee, never below load,
		// never above target. This is what the old "base" used to grant
		// unconditionally; it is now squeezable above `load`.
		floorTop := p.Floor
		if floorTop < load {
			floorTop = load
		}
		if floorTop > target {
			floorTop = target
		}

		out[p.Name] = 0

		if load > 0 {
			loadWants = append(loadWants, tierWant{p.Name, load, p.PodMemBytes})
		}
		if floorWant := floorTop - load; floorWant > 0 && p.PodMemBytes > 0 {
			floorWants = append(floorWants, tierWant{p.Name, floorWant, p.PodMemBytes})
		}
		if headWant := target - floorTop; headWant > 0 && p.PodMemBytes > 0 {
			headWants = append(headWants, tierWant{p.Name, headWant, p.PodMemBytes})
		}
	}

	remaining := fleetMemBytes

	// grantTier grants a discretionary tier from `remaining`, returning
	// true only when it was satisfied in full (so the caller knows
	// whether to attempt the next-lower tier). A partially-funded tier
	// is split proportionally to requested memory and exhausts capacity.
	grantTier := func(wants []tierWant) bool {
		var total int64
		for _, w := range wants {
			total += int64(w.want) * w.mem
		}
		if total == 0 {
			return true // nothing wanted; capacity untouched
		}
		if remaining >= total {
			for _, w := range wants {
				out[w.name] += w.want
			}
			remaining -= total
			return true
		}
		if remaining > 0 {
			ratio := float64(remaining) / float64(total)
			for _, w := range wants {
				grant := int32(float64(w.want) * ratio)
				if grant > w.want {
					grant = w.want
				}
				out[w.name] += grant
			}
		}
		remaining = 0
		return false
	}

	// Tier 1: real load — always granted in full, even past capacity.
	// Excess drives `remaining` negative; lower tiers then get nothing.
	for _, w := range loadWants {
		out[w.name] += w.want
		remaining -= int64(w.want) * w.mem
	}
	if remaining < 0 {
		remaining = 0
	}

	// Tier 2: floor (warm guarantee), then tier 3: headroom — only if
	// floors fit in full. Floors yield to tier-1 load above; headroom
	// yields to floors.
	if grantTier(floorWants) {
		grantTier(headWants)
	}

	return out
}
