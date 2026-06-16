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

const poolLabel = "pool"

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
)

func init() {
	ctrlmetrics.Registry.MustRegister(target, allocated, warmDeficitReplicas, minWarmFloor)
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

// Clear drops a pool's series so a deleted (or opted-out) pool stops
// reporting stale gauges. Safe to call for an unknown pool.
func Clear(pool string) {
	target.DeleteLabelValues(pool)
	allocated.DeleteLabelValues(pool)
	warmDeficitReplicas.DeleteLabelValues(pool)
	minWarmFloor.DeleteLabelValues(pool)
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
