// Package metrics holds the runners-controller's custom Prometheus
// collectors. They register against controller-runtime's global
// registry, so they're scraped on the manager's existing
// `--metrics-bind-address` endpoint alongside the controller-runtime
// and Go runtime metrics.
//
// These exist because alive/desired replica counts only show the pool
// converging to its target — they can't reveal that the target itself
// was squeezed below the configured warm floor by the fleet allocator.
// That squeeze is the leading indicator for cold boots, so it gets its
// own series.
package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
	ctrlmetrics "sigs.k8s.io/controller-runtime/pkg/metrics"
)

const (
	poolLabel  = "pool"
	phaseLabel = "phase"
)

var podPhaseLabels = []string{"Pending", "Running", "Unknown"}

var (
	// target is the per-pool replica count the autoscaler policy wants
	// BEFORE the fleet allocator apportions shared capacity
	// (scaling.DesiredReplicas). Pair with `allocated` to see how much
	// of the ask the shared-capacity allocator could fund this tick.
	target = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_autoscaler_target_replicas",
		Help: "Per-pool replicas the autoscaler policy wants before fleet-capacity allocation (DesiredReplicas).",
	}, []string{poolLabel})

	// allocated is what the pool got after AllocateFleet split the
	// shared capacity domain across sibling shapes — the value patched
	// to spec.replicas. Equals `target` when the pool isn't contended
	// (or the allocator fell back to the per-pool policy).
	allocated = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_autoscaler_allocated_replicas",
		Help: "Per-pool replicas granted after fleet-capacity allocation (patched to spec.replicas).",
	}, []string{poolLabel})

	// warmDeficitReplicas is the warm-pool capacity the allocator
	// wanted to fund for this pool but couldn't because the shared
	// domain was contended: the part of (load + minWarmPoolFloor),
	// capped at the pool's target, left unfunded. >0 means the shape's
	// warm buffer is being reaped toward its raw load, so the next
	// demand burst on it pays cold-start. This is the leading indicator
	// for cold boots that alive/desired can't surface.
	warmDeficitReplicas = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_autoscaler_warm_deficit_replicas",
		Help: "Warm-pool replicas the fleet allocator could not fund under capacity contention (cold-boot risk).",
	}, []string{poolLabel})

	// minWarmFloor mirrors the configured
	// spec.autoscaling.minWarmPoolFloor so a dashboard can chart
	// configured-vs-funded warm pool from a single source.
	minWarmFloor = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_autoscaler_min_warm_floor_replicas",
		Help: "Configured minWarmPoolFloor per pool (spec.autoscaling.minWarmPoolFloor).",
	}, []string{poolLabel})

	// rollingPods is how many of a pool's Pods are mid-roll right now:
	// drain-eligible stale-image Pods (committed to retire) plus
	// current-image Pods not yet Ready (pulling/booting a replacement).
	// This is the throttled quantity and must stay <= rollCap. Pinned at
	// the cap with stalePods > 0 is a healthy in-progress roll;
	// rollingPods > rollCap means the cap isn't being enforced (a bug).
	rollingPods = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_pool_rolling_pods",
		Help: "Pods mid-roll (drain-eligible stale + current-image not-Ready) per pool.",
	}, []string{poolLabel})

	// stalePods is how many alive Pods are still on a superseded image —
	// the roll backlog. It decreases to 0 as the roll completes. Stuck
	// > 0 (flat, not draining) while rollingPods is pinned is the
	// "roll wedged" signal: a replacement isn't reaching Ready, so the
	// cap never frees and the rollout can't advance.
	stalePods = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_pool_stale_pods",
		Help: "Alive Pods still on a superseded spec.image (image-roll backlog) per pool.",
	}, []string{poolLabel})

	// rollCap is the computed concurrency ceiling:
	// max(1, floor(MaxConcurrentPercent/100 * replicas)). Exported so a
	// dashboard/alert can compare rollingPods against the cap without
	// re-deriving the policy.
	rollCap = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_pool_roll_concurrency_cap",
		Help: "Max Pods allowed mid-roll at once per pool (max(1, floor(pct/100 * replicas))).",
	}, []string{poolLabel})

	phaseReplicas = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_pool_phase_replicas",
		Help: "Alive runner Pods per pool and Kubernetes phase.",
	}, []string{poolLabel, phaseLabel})
)

func init() {
	ctrlmetrics.Registry.MustRegister(target, allocated, warmDeficitReplicas, minWarmFloor, rollingPods, stalePods, rollCap, phaseReplicas)
}

// RecordAllocation publishes one pool's allocation outcome for this
// reconcile tick. `load` is claimed+queued, `floor` is
// minWarmPoolFloor, `targetReplicas` is the pre-allocation
// DesiredReplicas, `allocatedReplicas` is the post-allocation value
// patched to spec.replicas.
func RecordAllocation(pool string, load, floor, targetReplicas, allocatedReplicas int32) {
	target.WithLabelValues(pool).Set(float64(targetReplicas))
	allocated.WithLabelValues(pool).Set(float64(allocatedReplicas))
	minWarmFloor.WithLabelValues(pool).Set(float64(floor))
	warmDeficitReplicas.WithLabelValues(pool).Set(float64(warmDeficit(load, floor, targetReplicas, allocatedReplicas)))
}

// RecordRoll publishes a pool's image-roll progress for this reconcile
// tick: how many Pods are mid-roll, how many remain on the old image,
// and the concurrency cap they're throttled against. Steady state
// (no roll) reports rolling=0, stale=0.
func RecordRoll(pool string, rolling, stale, capacity int) {
	rollingPods.WithLabelValues(pool).Set(float64(rolling))
	stalePods.WithLabelValues(pool).Set(float64(stale))
	rollCap.WithLabelValues(pool).Set(float64(capacity))
}

// RecordPodPhases publishes the pool's alive Pod count by Kubernetes
// phase. Missing phase buckets are explicitly set to 0 so the dashboard
// does not keep stale last_value samples after a pool drains.
func RecordPodPhases(pool string, pending, running, unknown int) {
	phaseReplicas.WithLabelValues(pool, "Pending").Set(float64(pending))
	phaseReplicas.WithLabelValues(pool, "Running").Set(float64(running))
	phaseReplicas.WithLabelValues(pool, "Unknown").Set(float64(unknown))
}

// ClearAutoscaler drops the autoscaler-owned series for a pool. Safe
// to call for an unknown pool.
func ClearAutoscaler(pool string) {
	target.DeleteLabelValues(pool)
	allocated.DeleteLabelValues(pool)
	warmDeficitReplicas.DeleteLabelValues(pool)
	minWarmFloor.DeleteLabelValues(pool)
}

// ClearRunnerPool drops the primary RunnerPool reconciler's series for
// a pool. Safe to call for an unknown pool.
func ClearRunnerPool(pool string) {
	rollingPods.DeleteLabelValues(pool)
	stalePods.DeleteLabelValues(pool)
	rollCap.DeleteLabelValues(pool)
	for _, phase := range podPhaseLabels {
		phaseReplicas.DeleteLabelValues(pool, phase)
	}
}

// Clear drops all pool series when the RunnerPool object is gone. Safe
// to call for an unknown pool.
func Clear(pool string) {
	ClearAutoscaler(pool)
	ClearRunnerPool(pool)
}

// warmDeficit is the warm-pool capacity the fleet allocator wanted to
// fund but couldn't under contention. The allocator funds real load
// (claimed+queued) inviolably, then the warm floor above it; the floor
// is what yields first. So the deficit is the floor portion — (load +
// floor), capped at the pool's target — left unfunded by `allocated`.
// Headroom (the speculative p95 buffer above the floor) is excluded:
// only the warm *guarantee* counts toward cold-boot risk.
func warmDeficit(load, floor, target, allocated int32) int32 {
	if load < 0 {
		load = 0
	}
	if floor < 0 {
		floor = 0
	}
	want := load + floor
	if want > target {
		want = target
	}
	// Measure only the warm-floor shortfall. The allocator funds load
	// inviolably, so clamp `allocated` up to `load` first — a
	// (degenerate) allocated < load is load starvation, a different
	// signal surfaced by Pending/unschedulable Pods, not warm-pool
	// reaping.
	funded := allocated
	if funded < load {
		funded = load
	}
	deficit := want - funded
	if deficit < 0 {
		deficit = 0
	}
	return deficit
}
