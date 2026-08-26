package scaling

import "sort"

// PoolDemand is one pool's input to the fleet-capacity allocation.
// All pools in a single AllocateFleet call share one capacity budget
// (the contention domain): the schedulable memory across the fleet's
// nodes, for both Linux bare metal and macOS Mac minis.
type PoolDemand struct {
	Name string

	// PerPodCost is what one Pod consumes from the shared budget,
	// in the same unit as `fleetCapacity` — per-Pod memory request
	// in bytes on both platforms, because memory is the only
	// bin-packed dimension on either:
	//   - Linux: kata microVMs pin memory per sandbox; CPU is
	//     deliberately oversubscribed. Includes RuntimeClass
	//     overhead, which is charged at admission.
	//   - macOS: tart-kubelet advertises the host's usable RAM and
	//     the guest is sized from the Pod's request, so the
	//     quotient is how many Tart guests the host admits. Apple's
	//     Virtualization.framework SLA caps that at 2 regardless,
	//     and Tart enforces it.
	PerPodCost int64

	// Floor is `minWarmPoolFloor` — the always-on warm guarantee.
	Floor int32

	// Load is `Signals.Load()` — Pods holding capacity (including
	// post-job cache and teardown work), plus work waiting for a Pod,
	// plus one Pod when the pool has queued work that is real but
	// currently undispatchable (see Signals.BlockedDemand).
	Load int32

	// Target is the per-pool `DesiredReplicas` output: the full ask
	// including the speculative p95 warm buffer, already clamped to
	// `maxReplicas`.
	Target int32

	// ShapeKey groups pools whose Pods place identically on a node, so
	// their grants can be capped against what the fleet's nodes can
	// actually seat for that shape. Empty opts the pool out of the cap.
	// See AllocateFleet's `shapeCaps`.
	ShapeKey string
}

// AllocateFleet distributes `fleetCapacity` across pools sharing a
// capacity domain, in three priority tiers:
//
//  1. Load — the capacity held by live runner Pods, plus work waiting for
//     one, plus one Pod for work that is queued but currently blocked on
//     an account's concurrency limit. Genuine demand; granted in full even
//     when it exceeds capacity (the excess goes Pending, the operator's
//     "add a host" signal). Admitting blocked demand here is what keeps a
//     pool whose work is temporarily unservable from being classified as
//     idle and starved of a Pod forever on a saturated fleet.
//  2. Floor — `minWarmPoolFloor` above load: the speculative warm
//     guarantee that keeps the next spike off cold-start. Idle warm Pods.
//  3. Headroom — the p95 warm buffer (`Target` above floor+load). Also
//     idle, the most speculative.
//
// Only tier 1 is inviolable. Tiers 2 and 3 are idle warm capacity, and
// they yield — headroom first, then floor — to admit another pool's real
// queued work. That is the cross-pool reclaim: when a starved shape has
// queued jobs that don't fit, an idle shape's warm Pods are reaped
// (its desired falls below its floor) to free capacity, rather than
// leaving the queued jobs Pending while idle Pods hold reservations.
//
// The tradeoff is deliberate: under sustained load on one shape, other
// shapes' warm pools shrink toward their real load, so a returning spike
// on a squeezed shape pays cold-start. A job queued now beats a warm Pod
// for a job that might arrive. The per-pool scale-down cooldown damps the
// reap so it doesn't thrash.
//
// Each tier is granted in full when it fits; otherwise it is split
// proportionally to requested cost and all lower tiers get nothing.
// Result per pool is in `[load_i, Target_i]`. The algorithm is
// unit-agnostic: `fleetCapacity` and `PerPodCost` just need to be in
// the same unit (allocatable memory bytes on both platforms today).
//
// `shapeCaps` is an optional per-ShapeKey ceiling on the number of Pods
// the fleet can actually place for that shape, applied before the byte
// budget. A nil or empty map disables it. See capByShape for why the
// byte budget cannot express this on its own.
func AllocateFleet(pools []PoolDemand, fleetCapacity int64, shapeCaps map[string]int32) map[string]int32 {
	pools = capByShape(pools, shapeCaps)

	out := make(map[string]int32, len(pools))

	type tierWant struct {
		name string
		want int32
		cost int64
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
			loadWants = append(loadWants, tierWant{p.Name, load, p.PerPodCost})
		}
		if floorWant := floorTop - load; floorWant > 0 && p.PerPodCost > 0 {
			floorWants = append(floorWants, tierWant{p.Name, floorWant, p.PerPodCost})
		}
		if headWant := target - floorTop; headWant > 0 && p.PerPodCost > 0 {
			headWants = append(headWants, tierWant{p.Name, headWant, p.PerPodCost})
		}
	}

	remaining := fleetCapacity

	// grantTier grants a discretionary tier from `remaining`, returning
	// true only when it was satisfied in full (so the caller knows
	// whether to attempt the next-lower tier). A partially-funded tier
	// is split proportionally to requested cost and exhausts capacity.
	grantTier := func(wants []tierWant) bool {
		var total int64
		for _, w := range wants {
			total += int64(w.want) * w.cost
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
		remaining -= int64(w.want) * w.cost
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

// capByShape clamps each pool's Target so that the pools sharing a
// ShapeKey never sum above what the fleet's nodes can actually seat for
// that shape.
//
// `maxReplicas` cannot do this. It is a PER-POOL ceiling, and the pools
// sharing a shape are siblings: five Xcode pools each capped at the two
// M4 hosts that can seat a 12 vCPU guest compose to ten, not two. Nor
// can the shared byte budget catch it, because that budget pools memory
// across nodes which cannot host the shape at all — a fleet advertising
// 157 GB reads as five 28 GB slots when only two hosts can seat one.
// Everything above the real count is a Pod that no node will ever
// accept, so it is not the transient "add a host" overshoot the load
// tier deliberately allows; it is permanent.
//
// The cap is handed out by the same priority the tiers use — load
// first, then the warm floor, then headroom — one Pod per pool per
// round, so two pools contending for a single slot do not both lose it,
// and in name order so the split is identical on every reconcile.
//
// Clamping Target (rather than the tiers directly) is enough: the tier
// decomposition already clamps load and floor to it.
func capByShape(pools []PoolDemand, shapeCaps map[string]int32) []PoolDemand {
	if len(shapeCaps) == 0 {
		return pools
	}

	groups := map[string][]int{}
	for i, pool := range pools {
		if pool.ShapeKey == "" {
			continue
		}
		if _, capped := shapeCaps[pool.ShapeKey]; !capped {
			continue
		}
		groups[pool.ShapeKey] = append(groups[pool.ShapeKey], i)
	}
	if len(groups) == 0 {
		return pools
	}

	out := make([]PoolDemand, len(pools))
	copy(out, pools)

	for key, members := range groups {
		limit := shapeCaps[key]
		if limit < 0 {
			limit = 0
		}

		var asked int32
		for _, i := range members {
			asked += clampMin(out[i].Target, 0)
		}
		if asked <= limit {
			continue
		}

		sort.Slice(members, func(a, b int) bool { return out[members[a]].Name < out[members[b]].Name })

		granted := make([]int32, len(members))
		remaining := limit
		for _, ceiling := range []func(PoolDemand) int32{loadCeiling, floorCeiling, targetCeiling} {
			for remaining > 0 {
				progressed := false
				for j, i := range members {
					if remaining == 0 {
						break
					}
					if granted[j] < ceiling(out[i]) {
						granted[j]++
						remaining--
						progressed = true
					}
				}
				if !progressed {
					break
				}
			}
		}

		for j, i := range members {
			out[i].Target = granted[j]
			out[i].Load = clampMax(out[i].Load, granted[j])
			out[i].Floor = clampMax(out[i].Floor, granted[j])
		}
	}

	return out
}

// The three ceilings capByShape fills in priority order, each the top of
// one tier and each already bounded by the pool's own Target.
func targetCeiling(p PoolDemand) int32 { return clampMin(p.Target, 0) }

func loadCeiling(p PoolDemand) int32 {
	return clampMax(clampMin(p.Load, 0), targetCeiling(p))
}

func floorCeiling(p PoolDemand) int32 {
	floor := clampMin(p.Floor, 0)
	if load := loadCeiling(p); floor < load {
		floor = load
	}
	return clampMax(floor, targetCeiling(p))
}

func clampMin(v, min int32) int32 {
	if v < min {
		return min
	}
	return v
}

func clampMax(v, max int32) int32 {
	if v > max {
		return max
	}
	return v
}
