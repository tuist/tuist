package scaling

import (
	"sort"
	"time"
)

// PoolDemand is one pool's input to the compute allocation.
// All pools in a single AllocateCompute call share one capacity budget
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

	// Floor is `WarmFloor`: `minWarmPoolFloor`, or load plus the learned
	// spare when that is higher.
	Floor int32

	// MinWarmPoolFloor is the explicit baseline, before learned spare.
	MinWarmPoolFloor int32

	// Active excludes the single contender for withheld-only work: only
	// occupied runners or dispatchable jobs earn priority burst spare.
	Active bool

	// InUse is `Signals.InUse`: dispatchable/occupied work now or a job
	// in the last hour. It earns a baseline before learned bursts.
	InUse bool

	// ColdJobs is `Signals.ColdJobs`: the pool's jobs of the last two weeks
	// that a single warm runner would not have covered. Each warm tier is
	// funded most cold jobs first.
	ColdJobs int32

	// HoursWithJobs is `Signals.HoursWithJobs`: how many hours of the last
	// two weeks had one of the pool's jobs. Breaks ColdJobs ties.
	HoursWithJobs int32

	// LastDemandAt is the pool's `status.lastDemandAt`: when it last had
	// real work, to within ten minutes. Zero when it never had any. It
	// breaks usage ties, most recently used first, then by pool name.
	LastDemandAt time.Time

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
	// See AllocateCompute's `shapeCaps`.
	ShapeKey string
}

// AllocateCompute distributes `fleetCapacity` across pools sharing a
// capacity domain, in three priority tiers:
//
//  1. Load — the capacity held by live runner Pods, plus work waiting for
//     one, plus one Pod for work that is queued but currently blocked on
//     an account's concurrency limit. Genuine demand; granted in full even
//     when it exceeds capacity (the excess goes Pending, the operator's
//     "add a host" signal). Admitting blocked demand here is what keeps a
//     pool whose work is temporarily unservable from being classified as
//     idle and starved of a Pod forever on a saturated fleet.
//  2. Warm stock — a baseline (the explicit minimum, or one above load
//     for pools in use), then one above load for every pool with a learned
//     floor, then remaining learned spare for active pools, recently used
//     quiet pools, and finally idle pools. Each sub-tier
//     funds pools whole in cold-job, usage, recency and name order, concentrating
//     useful bursts rather than splitting capacity proportionally.
//     Withheld-only work does not earn active burst priority.
//  3. Headroom — the p95 warm buffer (`Target` above warm stock). Also
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
// reap so it doesn't thrash, except while a sibling's queued Pods are
// refused for capacity (see controllers/preemption.go).
//
// Headroom is split proportionally to requested cost when it cannot fit;
// whole Pods left by rounding go to the largest Target (grantRemainder).
// A partially funded warm sub-tier leaves lower tiers unfunded.
// Result per pool is in `[load_i, Target_i]`. The algorithm is
// unit-agnostic: `fleetCapacity` and `PerPodCost` just need to be in
// the same unit (allocatable memory bytes on both platforms today).
//
// `shapeCaps` is an optional per-ShapeKey ceiling on the number of Pods
// the fleet can actually place for that shape, applied before the byte
// budget. A nil or empty map disables it. See capByShape for why the
// byte budget cannot express this on its own.
func AllocateCompute(pools []PoolDemand, fleetCapacity int64, shapeCaps map[string]int32) map[string]int32 {
	pools = capByShape(pools, shapeCaps)

	out := make(map[string]int32, len(pools))

	var loadWants, headWants []tierWant
	warmCeilings := []func(PoolDemand) int32{baselineCeiling, learnedBaselineCeiling, activeFloorCeiling, inUseFloorCeiling, floorCeiling}
	warmWants := make([][]tierWant, len(warmCeilings))
	byName := make(map[string]PoolDemand, len(pools))

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

		out[p.Name] = 0
		byName[p.Name] = p

		if load > 0 {
			loadWants = append(loadWants, tierWant{p.Name, load, p.PerPodCost, target})
		}
		previous := load
		for phase, ceiling := range warmCeilings {
			top := ceiling(p)
			if want := top - previous; want > 0 && p.PerPodCost > 0 {
				warmWants[phase] = append(warmWants[phase], tierWant{p.Name, want, p.PerPodCost, target})
			}
			previous = top
		}
		if headWant := target - previous; headWant > 0 && p.PerPodCost > 0 {
			headWants = append(headWants, tierWant{p.Name, headWant, p.PerPodCost, target})
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
			granted := make([]int32, len(wants))
			for i, w := range wants {
				grant := int32(float64(w.want) * ratio)
				if grant > w.want {
					grant = w.want
				}
				granted[i] = grant
				remaining -= int64(grant) * w.cost
			}
			grantRemainder(wants, granted, remaining)
			for i, w := range wants {
				out[w.name] += granted[i]
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

	// Fund whole bursts, most used first. A proportional split leaves
	// several pools warm but none able to absorb its next fan-out.
	grantByUse := func(wants []tierWant) bool {
		sort.SliceStable(wants, func(a, b int) bool {
			pa, pb := byName[wants[a].name], byName[wants[b].name]
			if moreUsed(pa, pb) || moreUsed(pb, pa) {
				return moreUsed(pa, pb)
			}
			return wants[a].name < wants[b].name
		})
		full := true
		for _, w := range wants {
			grant := w.want
			if fits := remaining / w.cost; fits < int64(grant) {
				grant = int32(fits)
				full = false
			}
			out[w.name] += grant
			remaining -= int64(grant) * w.cost
		}
		return full
	}

	// Baselines, active bursts, recent bursts, idle bursts, then headroom.
	for _, wants := range warmWants {
		if !grantByUse(wants) {
			return out
		}
	}
	grantTier(headWants)

	return out
}

// moreUsed ranks warm stock: the pool whose warm seats would have saved the
// most cold boots in the last two weeks first, then the one with jobs in more
// hours, then the one used more recently.
//
// Hours with jobs alone measured how often a pool sees work, not how many of
// its jobs a warm floor serves. On 2026-11-18 the 26.6 pool (jobs in 270
// hours, 360 jobs past the first of their burst) and the internal-only 27.0
// pool (261 hours) were funded before 27.1 (231 hours, 2159 such jobs, all
// customers'), and 27.1's 7 to 12 job fan-outs booted cold. Recency alone let
// a nightly-only pool that finished its last job minutes after a pool used
// every working hour hold the rack's seats until the next job of either
// (2026-11-13: 26.3 took all of 27.1's).
func moreUsed(a, b PoolDemand) bool {
	if a.ColdJobs != b.ColdJobs {
		return a.ColdJobs > b.ColdJobs
	}
	if a.HoursWithJobs != b.HoursWithJobs {
		return a.HoursWithJobs > b.HoursWithJobs
	}
	return a.LastDemandAt.After(b.LastDemandAt)
}

// tierWant is one pool's ask from one tier. `target` is the pool's whole
// Target, which ranks pools for the Pods a partial grant rounds away.
type tierWant struct {
	name   string
	want   int32
	cost   int64
	target int32
}

// grantRemainder hands the capacity a proportional split rounded away to
// whole Pods, one per pool per round, so a partially funded tier still
// spends what it can. Without it a tier of many 1-Pod asks, the shape of
// one warm floor per rack image, rounds every ask to zero the moment the
// tier is one Pod short: every image's warm runner was reaped to make
// room for one queued job, and the slots it freed sat empty.
//
// Pools with the largest Target go first. Target includes the hourly peak,
// so a pool used recently keeps its warm runner before an idle one; ties
// break on name so every reconcile computes the same split.
func grantRemainder(wants []tierWant, granted []int32, remaining int64) {
	order := make([]int, len(wants))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(a, b int) bool {
		wa, wb := wants[order[a]], wants[order[b]]
		if wa.target != wb.target {
			return wa.target > wb.target
		}
		return wa.name < wb.name
	})

	for progressed := true; progressed; {
		progressed = false
		for _, i := range order {
			w := wants[i]
			if granted[i] < w.want && w.cost <= remaining {
				granted[i]++
				remaining -= w.cost
				progressed = true
			}
		}
	}
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
// The cap uses the byte allocator's baseline and burst priorities, with
// warm stock funded whole in usage, recency and name order. Load and
// headroom use one Pod per pool per round, in name order, so contenders
// do not both lose a seat and the split is stable across reconciles.
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
		ceilings := []func(PoolDemand) int32{loadCeiling, baselineCeiling, learnedBaselineCeiling, activeFloorCeiling, inUseFloorCeiling, floorCeiling, targetCeiling}
		for phase, ceiling := range ceilings {
			// Every warm tier uses the byte allocator's ordering. Load and
			// headroom retain round-robin placement inside the shape cap.
			if phase > 0 && phase < len(ceilings)-1 {
				order := make([]int, len(members))
				for j := range order {
					order[j] = j
				}
				sort.SliceStable(order, func(a, b int) bool {
					return moreUsed(out[members[order[a]]], out[members[order[b]]])
				})
				for _, j := range order {
					grant := clampMax(ceiling(out[members[j]])-granted[j], remaining)
					if grant > 0 {
						granted[j] += grant
						remaining -= grant
					}
				}
				continue
			}
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

// The ceilings capByShape fills in priority order, each the top of one tier
// and each already bounded by the pool's own Target.
func targetCeiling(p PoolDemand) int32 { return clampMin(p.Target, 0) }

func baselineCeiling(p PoolDemand) int32 {
	baseline := p.MinWarmPoolFloor
	if p.InUse && baseline < p.Load+1 {
		baseline = p.Load + 1
	}
	return clampMax(clampMin(baseline, loadCeiling(p)), targetCeiling(p))
}

// learnedBaselineCeiling adds the first warm runner of every pool with a
// learned floor, which the server learns only for a pool with a job in the
// last day. It is funded before any pool's further warm runners: a pool's
// first warm runner saves its next job a cold start, a burst's eighth only
// a job of an eight-job burst. Without it a pool with a job every few hours
// drops into the idle tier an hour after each job and, on a full rack, has
// no warm runner when the next one comes (27.2's 16 vCPU pool, 2026-11-23).
func learnedBaselineCeiling(p PoolDemand) int32 {
	baseline := baselineCeiling(p)
	if p.Floor > p.Load && baseline < p.Load+1 {
		baseline = p.Load + 1
	}
	return clampMax(baseline, targetCeiling(p))
}

func activeFloorCeiling(p PoolDemand) int32 {
	if p.Active {
		return floorCeiling(p)
	}
	return learnedBaselineCeiling(p)
}

func inUseFloorCeiling(p PoolDemand) int32 {
	if p.InUse || p.Active {
		return floorCeiling(p)
	}
	return learnedBaselineCeiling(p)
}

func loadCeiling(p PoolDemand) int32 {
	return clampMax(clampMin(p.Load, 0), targetCeiling(p))
}

func floorCeiling(p PoolDemand) int32 {
	floor := clampMin(p.Floor, 0)
	if baseline := learnedBaselineCeiling(p); floor < baseline {
		floor = baseline
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
