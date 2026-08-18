// Package scaling holds the autoscaler's pure-policy helpers and
// the HTTP client that fetches load signals from the Tuist server.
//
// The split keeps `DesiredReplicas` table-testable without spinning
// up an HTTP server in unit tests; the reconciler composes the
// HTTP client + pure computation.
package scaling

// Signals is the body returned by the Tuist server's
// /api/internal/runners/desired_replicas endpoint. The server is
// the source of these signals; this package is the policy
// engine that combines them with per-pool knobs.
type Signals struct {
	Fleet                 string `json:"fleet"`
	Claimed               int32  `json:"claimed"`
	Occupied              int32  `json:"occupied"`
	Queued                int32  `json:"queued"`
	Withheld              int32  `json:"withheld"`
	P95ConcurrentLastHour int32  `json:"p95_concurrent_last_hour"`
}

// CurrentOccupancy returns the server's complete capacity-held signal.
// During a rolling deployment, an older server omits Occupied and it
// decodes as zero, so Claimed remains the safe fallback. The max also
// protects against a read racing between the server's two source queries.
func (s Signals) CurrentOccupancy() int32 {
	if s.Occupied > s.Claimed {
		return s.Occupied
	}
	return s.Claimed
}

// BlockedDemand is the single warm Pod a pool is owed when it has queued
// work the server withheld from `Queued` because the owning account is at
// its concurrency limit.
//
// The server withholds that work on purpose: sizing on raw queue depth
// provisions Pods for jobs dispatch will refuse, and those Pods then idle
// on hosts that pools with claimable work cannot get. But withholding all
// of it reports `Load == 0`, so a pool whose only work is blocked looks
// idle and competes solely in the discretionary tiers. On a saturated
// fleet those tiers are empty, so it never gets a Pod — and without a Pod
// polling dispatch it cannot claim the instant headroom frees, while
// siblings with warm Pods take it within seconds. That is a livelock, and
// it does not self-heal.
//
// One Pod is the whole fix: it is enough to enter the race for freed
// headroom, and it enters tier 1 of AllocateFleet, which is granted even
// past capacity. Sizing for the full withheld count instead would recreate
// exactly the idle-Pod squatting the withholding exists to prevent, which
// is why this saturates at 1 rather than scaling with `Withheld`.
//
// During a rolling deployment an older server omits Withheld, it decodes
// as zero, and this returns zero — Load is then byte-for-byte today's.
func (s Signals) BlockedDemand() int32 {
	if s.Withheld > 0 {
		return 1
	}
	return 0
}

// Load is capacity currently held, plus work that can be dispatched now,
// plus one Pod for work that is real but currently unservable.
func (s Signals) Load() int32 {
	return s.CurrentOccupancy() + s.Queued + s.BlockedDemand()
}

// PolicyKnobs are the per-pool autoscaling parameters from the
// RunnerPool CRD's `spec.autoscaling` block.
type PolicyKnobs struct {
	MinWarmPoolFloor int32
	MaxReplicas      int32
}

// DesiredReplicas computes the autoscaler's target replica count
// from server signals and CRD knobs:
//
//	desired  = max(Load, P95ConcurrentLastHour) + MinWarmPoolFloor
//	clamped  = min(MaxReplicas, max(0, desired))
//
// Intuition:
//   - `Load` is what's holding a Pod (including post-job cache and
//     teardown work) or wanting one right now, plus one Pod for queued
//     work the server withheld as currently undispatchable. The fleet
//     must be at least this big.
//   - `P95ConcurrentLastHour` lifts the size to the typical peak
//     observed in the last hour even when current load is below it —
//     that's the "lead the demand" behavior that keeps the next peak
//     from paying cold-start.
//   - `+ MinWarmPoolFloor` adds operator-configured slack on top
//     of whichever (current load OR predicted peak) won, so a
//     fresh arrival lands on a warm Pod instead of waiting for a
//     newly-claimed Pod to start polling. It is additive only:
//     `desired >= MinWarmPoolFloor` already holds, so clamping the
//     floor as a lower bound as well would double-count it and size
//     an idle pool to twice its configured floor.
//   - `MaxReplicas == 0` returns 0, which the caller treats as
//     "autoscaling disabled" — the static spec.Replicas is left
//     alone. This matches the CRD default; a pool that didn't
//     ship MaxReplicas opts out implicitly.
func DesiredReplicas(s Signals, k PolicyKnobs) int32 {
	if k.MaxReplicas <= 0 {
		return 0
	}

	floor := s.P95ConcurrentLastHour

	load := s.Load()

	target := load
	if floor > target {
		target = floor
	}

	desired := target + k.MinWarmPoolFloor

	if desired > k.MaxReplicas {
		desired = k.MaxReplicas
	}
	if desired < 0 {
		desired = 0
	}
	return desired
}
