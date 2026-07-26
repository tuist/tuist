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
	"time"

	"github.com/prometheus/client_golang/prometheus"
	ctrlmetrics "sigs.k8s.io/controller-runtime/pkg/metrics"
)

const (
	poolLabel            = "pool"
	phaseLabel           = "phase"
	reasonLabel          = "reason"
	fleetSelectorLabel   = "fleet_selector"
	operatingSystemLabel = "operating_system"
)

var podPhaseLabels = []string{"Pending", "Running", "Unknown"}
var admissionBlockReasons = []string{"fleet_cap", "no_healthy_node", "fleet_view_error"}
var fleetNodeFilterReasons = []string{"unschedulable", "not_ready", "memory_pressure", "disk_pressure", "pid_pressure"}
var podStartTimeoutReasons = []string{"poller_not_started"}

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

	// oldestPendingPodAge is how long the pool's least-recently-created
	// un-Running Pod has been waiting. **darwin pools only** — see the
	// caller in runnerpool_controller.go. On a Tart pool, Pending means
	// the VM isn't up, so this is the boot path's equivalent of queue
	// age: tens of seconds normally, unbounded when a host stalls mid
	// image-pull. On a Linux pool, Pending is the healthy steady state
	// (the dispatch poller is an init container), so the same reading
	// would peg every idle pool at its warm-pool age.
	//
	// The count in phaseReplicas cannot substitute. A pool that keeps
	// one Pod Pending because it is steadily replacing single-shot
	// runners reads the same as a pool with one Pod wedged for hours —
	// only the age separates them. tart-kubelet's provision histogram
	// cannot either: it is observed when a VM finally starts, so a Pod
	// that never boots is absent from it entirely.
	oldestPendingPodAge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_pool_oldest_pending_pod_age_seconds",
		Help: "Age of a darwin pool's oldest alive Pod that has not reached Running (0 when none).",
	}, []string{poolLabel})

	// claimedJobs and queuedJobs are the server's two demand signals,
	// published separately rather than as the `claimed+queued` sum the
	// allocator consumes. The sum answers "how big should this pool be";
	// only the split answers "is dispatch actually serving this pool",
	// because the two move independently: work draining normally shifts
	// queued -> claimed and leaves the sum flat.
	claimedJobs = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_autoscaler_claimed_jobs",
		Help: "Jobs currently claimed by a runner Pod in this pool (server signal).",
	}, []string{poolLabel})

	queuedJobs = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_autoscaler_queued_jobs",
		Help: "Jobs waiting for a runner Pod in this pool (server signal).",
	}, []string{poolLabel})

	// idleReplicas is how many current-image Pods are alive, unclaimed,
	// and actually able to take work right now. On darwin that means
	// Running: a Pod still waiting for a Mac mini has no VM and is not
	// capacity, however long it has been alive. On Linux it includes
	// Pending, which is where a warm dispatch poller spends its whole
	// idle life. See isWarmCapacity in the RunnerPool reconciler.
	//
	// Pair with queuedJobs to detect dispatch starvation. `queued > 0 AND
	// idle > 0`, sustained, is a contradiction in a healthy fleet: an idle
	// warm Pod polls dispatch continuously, so queued work should reach it
	// within a poll interval. Sustained overlap means dispatch is not
	// serving this pool despite capacity being available, which is the
	// starvation signature that no other series can express — phaseReplicas
	// counts a warm idle Pod and a Pod running a customer job identically,
	// and oldestPendingPodAge only sees Pods that never booted, not booted
	// Pods that never received work.
	idleReplicas = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_pool_idle_replicas",
		Help: "Alive current-image runner Pods with no claim (warm capacity available to take work).",
	}, []string{poolLabel})

	pendingProvisioningPods = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_pool_pending_provisioning_pods",
		Help: "Linux Kata runner Pods waiting for their dispatch poller to start, including local create reservations not yet observed by the cache.",
	}, []string{poolLabel})

	admissionBlockedTotal = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "tuist_runners_pool_admission_blocked_total",
		Help: "Runner reconciliations that left a replica gap because Linux Kata provisioning admission was blocked.",
	}, []string{poolLabel, reasonLabel})

	fleetReadyNodes = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_fleet_ready_nodes",
		Help: "Ready, schedulable, pressure-free nodes contributing capacity to a runner fleet.",
	}, []string{fleetSelectorLabel, operatingSystemLabel})

	fleetFilteredNodes = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tuist_runners_fleet_filtered_nodes",
		Help: "Runner-fleet nodes excluded from capacity or provisioning admission, grouped by reason.",
	}, []string{fleetSelectorLabel, operatingSystemLabel, reasonLabel})

	podStartTimeoutsTotal = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "tuist_runners_pool_pod_start_timeouts_total",
		Help: "Bound Linux runner Pods reaped after failing to start their dispatch poller within the configured timeout.",
	}, []string{poolLabel, reasonLabel})
)

func init() {
	ctrlmetrics.Registry.MustRegister(target, allocated, warmDeficitReplicas, minWarmFloor, rollingPods, stalePods, rollCap, phaseReplicas, oldestPendingPodAge, claimedJobs, queuedJobs, idleReplicas, pendingProvisioningPods, admissionBlockedTotal, fleetReadyNodes, fleetFilteredNodes, podStartTimeoutsTotal)
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

// RecordDemand publishes the server's two demand signals for a pool as
// separate series. Called on every autoscaler tick, including when the
// fleet allocator falls back to the per-pool target, so the signals stay
// live even while allocation is degraded.
func RecordDemand(pool string, claimed, queued int32) {
	claimedJobs.WithLabelValues(pool).Set(float64(claimed))
	queuedJobs.WithLabelValues(pool).Set(float64(queued))
}

// RecordIdleReplicas publishes the pool's unclaimed warm Pod count.
// Callers pass 0 rather than skipping the call so the gauge drains when
// a pool goes fully busy, instead of holding its last sample.
func RecordIdleReplicas(pool string, idle int) {
	if idle < 0 {
		idle = 0
	}
	idleReplicas.WithLabelValues(pool).Set(float64(idle))
}

func RecordPendingProvisioningPods(pool string, pending int) {
	if pending < 0 {
		pending = 0
	}
	pendingProvisioningPods.WithLabelValues(pool).Set(float64(pending))
}

func RecordAdmissionBlocked(pool, reason string) {
	admissionBlockedTotal.WithLabelValues(pool, reason).Inc()
}

func RecordFleetNodes(fleetSelector, operatingSystem string, ready int, filtered map[string]int) {
	if ready < 0 {
		ready = 0
	}
	fleetReadyNodes.WithLabelValues(fleetSelector, operatingSystem).Set(float64(ready))
	for _, reason := range fleetNodeFilterReasons {
		fleetFilteredNodes.WithLabelValues(fleetSelector, operatingSystem, reason).Set(float64(filtered[reason]))
	}
}

func RecordPodStartTimeout(pool, reason string) {
	podStartTimeoutsTotal.WithLabelValues(pool, reason).Inc()
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

// RecordOldestPendingPodAge publishes how long the pool's oldest
// un-Running Pod has been waiting. Callers pass 0 when the pool has
// none, rather than skipping the call, so the gauge drains instead of
// holding its last non-zero sample forever.
func RecordOldestPendingPodAge(pool string, age time.Duration) {
	seconds := age.Seconds()
	if seconds < 0 {
		seconds = 0
	}
	oldestPendingPodAge.WithLabelValues(pool).Set(seconds)
}

// ClearAutoscaler drops the autoscaler-owned series for a pool. Safe
// to call for an unknown pool.
func ClearAutoscaler(pool string) {
	target.DeleteLabelValues(pool)
	allocated.DeleteLabelValues(pool)
	warmDeficitReplicas.DeleteLabelValues(pool)
	minWarmFloor.DeleteLabelValues(pool)
	claimedJobs.DeleteLabelValues(pool)
	queuedJobs.DeleteLabelValues(pool)
}

// ClearRunnerPool drops the primary RunnerPool reconciler's series for
// a pool. Safe to call for an unknown pool.
func ClearRunnerPool(pool string) {
	rollingPods.DeleteLabelValues(pool)
	stalePods.DeleteLabelValues(pool)
	rollCap.DeleteLabelValues(pool)
	oldestPendingPodAge.DeleteLabelValues(pool)
	idleReplicas.DeleteLabelValues(pool)
	pendingProvisioningPods.DeleteLabelValues(pool)
	for _, reason := range admissionBlockReasons {
		admissionBlockedTotal.DeleteLabelValues(pool, reason)
	}
	for _, reason := range podStartTimeoutReasons {
		podStartTimeoutsTotal.DeleteLabelValues(pool, reason)
	}
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
