// Package scaling holds the autoscaler's pure-policy helpers and
// the HTTP client that fetches load signals from the Tuist server.
//
// The split keeps `DesiredReplicas` table-testable without spinning
// up an HTTP server in unit tests; the reconciler composes the
// HTTP client + pure computation.
package scaling

// Signals is the body returned by the Tuist server's
// /api/internal/runners/desired_replicas endpoint. The server is
// the source of these three signals; this package is the policy
// engine that combines them with per-pool knobs.
type Signals struct {
	Fleet                  string `json:"fleet"`
	Claimed                int32  `json:"claimed"`
	Queued                 int32  `json:"queued"`
	P95ConcurrentLastHour  int32  `json:"p95_concurrent_last_hour"`
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
//	floor    = max(MinWarmPoolFloor, P95ConcurrentLastHour)
//	desired  = max(Claimed + Queued, floor) + MinWarmPoolFloor
//	clamped  = min(MaxReplicas, max(0, desired))
//
// Intuition:
//   - `Claimed + Queued` is what's in flight or wanting a Pod right
//     now. The fleet must be at least this big.
//   - `floor` lifts the size to the typical peak observed in the
//     last hour even when current load is below it — that's the
//     "lead the demand" behavior that keeps the next peak from
//     paying cold-start.
//   - `+ MinWarmPoolFloor` adds operator-configured slack on top
//     of whichever (current load OR predicted peak) won, so a
//     fresh arrival lands on a warm Pod instead of waiting for a
//     newly-claimed Pod to start polling.
//   - `MaxReplicas == 0` returns 0, which the caller treats as
//     "autoscaling disabled" — the static spec.Replicas is left
//     alone. This matches the CRD default; a pool that didn't
//     ship MaxReplicas opts out implicitly.
func DesiredReplicas(s Signals, k PolicyKnobs) int32 {
	if k.MaxReplicas <= 0 {
		return 0
	}

	floor := k.MinWarmPoolFloor
	if s.P95ConcurrentLastHour > floor {
		floor = s.P95ConcurrentLastHour
	}

	load := s.Claimed + s.Queued

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
