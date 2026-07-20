package podagent

import (
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

// vmBootDurationSeconds is wall-clock time from `tart clone` start to
// the first non-empty `tart ip` for a freshly-created VM. The clone
// step dominates for fresh OCI images (multi-GB pull from ghcr +
// disk extraction), the boot step dominates afterwards. Buckets
// span 10s (cached image + warm host) to 10min — the cold-pull tail
// of a multi-GB Tart image over a slow link can exceed 5min, and
// keeping 600 in the explicit buckets keeps that population on the
// heatmap instead of binning it into +Inf.
//
// Pool label comes from the Pod's `tuist.dev/runner-pool` label so
// the runner-as-a-service surfaces can break out per-pool boot
// distributions — different pool images carry different OS + Xcode
// versions and boot at different speeds.
//
// Registered once on package init via controller-runtime's
// `metrics.Registry`; it's the same registry the controller-runtime
// manager serves on its --metrics-bind-address endpoint, so the
// histogram lands on the same `:8080/metrics` page Alloy scrapes.
var vmBootDurationSeconds = prometheus.NewHistogramVec(
	prometheus.HistogramOpts{
		Name:    "tart_kubelet_vm_boot_duration_seconds",
		Help:    "Wall-clock time from `tart clone` start to first non-empty `tart ip` for a freshly-created VM.",
		Buckets: []float64{10, 20, 30, 45, 60, 90, 120, 180, 240, 300, 600},
	},
	[]string{"pool"},
)

// goldenBaseMaterializedTotal counts golden base VMs materialized via a
// full `tart pull` + `tart clone` (the multi-GB image download + extract).
// Recycles clone from the host's per-digest golden base — an APFS
// clonefile that touches the network zero times — so in steady state this
// counter is flat. It ticks up only when a host first sees a digest (and
// once per host on a runner-image roll). A rising rate between rolls is the
// "goldens aren't sticking, we're re-pulling per job" regression signal the
// whole golden-base scheme exists to kill.
var goldenBaseMaterializedTotal = prometheus.NewCounterVec(
	prometheus.CounterOpts{
		Name: "tart_kubelet_golden_base_materialized_total",
		Help: "Golden base VMs materialized via full image pull+clone (per pool). Flat in steady state; ticks on first-sight of a digest.",
	},
	[]string{"pool"},
)

// goldenBaseReusedTotal counts provisions that cloned from an existing
// golden base — the APFS clonefile fast path that touches the network
// zero times. It's the counterpart to goldenBaseMaterializedTotal:
// reused/(reused+materialized) is the golden-base hit rate, and a
// materialized rate that climbs while reused stays flat is the
// "goldens aren't sticking, we're re-pulling per job" regression the
// whole golden-base scheme exists to kill. Without this counter that
// regression is invisible — a silent warm-path miss (a `tart get` that
// errors and falls through to a cold re-pull) looks identical to a
// legitimate first-sight materialization.
var goldenBaseReusedTotal = prometheus.NewCounterVec(
	prometheus.CounterOpts{
		Name: "tart_kubelet_golden_base_reused_total",
		Help: "Provisions that cloned from an existing golden base (APFS clonefile, no network), per pool.",
	},
	[]string{"pool"},
)

// guestDiskUsagePercent is the percent-used of each running VM's guest
// root volume, as read by the node maintainer's DiskPressure probe. It's
// the gradient signal behind the binary DiskPressure node condition:
// graphing it shows a leaking workload's slope days before the volume
// hits 100% and writes start failing with ENOSPC, and it lets alert
// thresholds be tuned (warn vs page) without redeploying tart-kubelet.
//
// Labelled by VM name; the scrape adds the per-mini `instance` label.
// Lands on the same `:8080/metrics` page Alloy scrapes via the
// `tuist-macos-tart-kubelet` job.
var guestDiskUsagePercent = prometheus.NewGaugeVec(
	prometheus.GaugeOpts{
		Name: "tart_kubelet_guest_disk_usage_percent",
		Help: "Percent-used of a running VM's guest root volume (0-100).",
	},
	[]string{"vm"},
)

// podProvisionDelaySeconds is wall-clock from a Pod's creation timestamp
// to the moment `tart run` is about to start its VM — so it spans
// scheduling + image pull + clone, the segment the boot histogram (which
// starts at `tart run`) can't see and where a digest-roll pull wave
// shows up. Recorded once per Pod, on the path that reaches Run, so a
// failed-and-retried provisioning doesn't double-count toward retry
// delay. A rising p90 here is the "slow to provision / pull wave" signal.
//
// Pool label from the Pod's `tuist.dev/runner-pool` label, same as the
// boot histogram, for per-pool breakdowns.
//
// Buckets run to an hour: a cold pull of a tens-of-GB image behind the
// single-concurrency reconcile puts real observations well past ten
// minutes, and prod p99 sits on the top bucket through every busy hour.
// Anything censored at the ceiling reads as "10 minutes" no matter how
// much worse it is, which defeats the rising-p90 signal above.
//
// This only measures Pods that eventually run — it is observed on the
// path to Run, so a Pod that never provisions contributes nothing here
// and no quantile will show it. Detection of that case belongs on a
// gauge over live Pods, not on this histogram.
var podProvisionDelaySeconds = prometheus.NewHistogramVec(
	prometheus.HistogramOpts{
		Name:    "tart_kubelet_pod_provision_delay_seconds",
		Help:    "Wall-clock from Pod creation to tart run start (scheduling + image pull + clone).",
		Buckets: []float64{1, 5, 10, 20, 30, 60, 120, 180, 300, 600, 1200, 1800, 3600},
	},
	[]string{"pool"},
)

// vmProvisionWorkSeconds isolates the on-host provisioning work a fresh
// Pod triggers — ensureGolden (warm clonefile or cold pull+clone) plus
// the runner `tart clone` — from podProvisionDelaySeconds, which starts
// at Pod creation and so also folds in scheduling/queue wait (a Pod can
// sit Pending behind the host's previous single-VM job for minutes).
// The `path` label ("warm" = golden reused, "cold" = golden
// materialized) makes the cold-pull tail explicit, so a high
// podProvisionDelaySeconds can be attributed to queue wait vs. a genuine
// re-pull at a glance rather than guessed at.
// Buckets match podProvisionDelaySeconds so the two are comparable at a
// glance; a cold pull is exactly the case that exceeds ten minutes.
var vmProvisionWorkSeconds = prometheus.NewHistogramVec(
	prometheus.HistogramOpts{
		Name:    "tart_kubelet_vm_provision_work_seconds",
		Help:    "Wall-clock for on-host provisioning work (ensureGolden + runner clone), per pool and path (warm=clonefile, cold=pull).",
		Buckets: []float64{1, 5, 10, 20, 30, 60, 120, 180, 300, 600, 1200, 1800, 3600},
	},
	[]string{"pool", "path"},
)

// cacheVolumeOutcomeTotal counts how per-account cache-volume branches end
// their lives: promoted (became the account's new master),
// discarded (read-only/clean/failed/never-dispatched job), or none (no volume
// was attached — feature off or admission declined). promoted/(promoted+
// discarded) is the warmth-capture rate.
var cacheVolumeOutcomeTotal = prometheus.NewCounterVec(
	prometheus.CounterOpts{
		Name: "tart_kubelet_cache_volume_outcome_total",
		Help: "Terminal disposition of per-account cache-volume branches, by outcome.",
	},
	[]string{"outcome"},
)

// cacheVolumeMaterializeTotal counts post-dispatch materializations by whether
// a master existed for the dispatched account on this host: "warm" (the
// account's master was clonefiled into the VM's branch) or "cold" (no master
// yet — a first job for that account here, whose writes seed the master).
// warm/(warm+cold) is the hit rate of the local warm set against dispatched
// demand — the signal for whether affinity is routing jobs to hosts that hold
// their account's master.
var cacheVolumeMaterializeTotal = prometheus.NewCounterVec(
	prometheus.CounterOpts{
		Name: "tart_kubelet_cache_volume_materialize_total",
		Help: "Post-dispatch cache materializations, by warm/cold.",
	},
	[]string{"result"},
)

// cacheVolumeConvergedTotal counts background fast-forwards of this host's
// master to the account's HEAD — a host that was behind pulling the latest
// master after a job started (off the job-start path), so the next job on it
// starts fresher. A high rate relative to materialize means hosts are
// frequently stale (jobs spread thin across hosts, or the cache churns fast).
var cacheVolumeConvergedTotal = prometheus.NewCounter(
	prometheus.CounterOpts{
		Name: "tart_kubelet_cache_volume_converged_total",
		Help: "Materialize-time master fast-forwards to the account's HEAD.",
	},
)

// cacheVolumeResidentCount is the number of resident master images on this
// host (all accounts, all volume names). Divided by the quota, it's the "how
// many accounts does this host keep hot" signal.
var cacheVolumeResidentCount = prometheus.NewGauge(
	prometheus.GaugeOpts{
		Name: "tart_kubelet_cache_volume_resident_count",
		Help: "Resident per-account cache master images on this host.",
	},
)

// cacheVolumeRootFreeBytes is statfs free space on the quota-bounded
// runner-cache volume — the ground truth behind admission and watermark
// eviction. A sustained decline toward the low watermark is the eviction-
// pressure signal.
var cacheVolumeRootFreeBytes = prometheus.NewGauge(
	prometheus.GaugeOpts{
		Name: "tart_kubelet_cache_volume_root_free_bytes",
		Help: "Free bytes on the quota-bounded runner-cache root volume.",
	},
)

// cacheVolumeEnabled is 1 when the feature is active on this host
// (--runner-cache-root set). It exists so root_mounted is never read in
// isolation: every gauge here is registered unconditionally and so reports its
// zero default on a host where the feature is off and Start never runs. Without
// this, a disabled host (enabled 0, mounted 0) is indistinguishable from an
// enabled-but-unmounted one (enabled 1, mounted 0) — the very ambiguity
// root_mounted is meant to remove. Read root_mounted only where enabled == 1.
var cacheVolumeEnabled = prometheus.NewGauge(
	prometheus.GaugeOpts{
		Name: "tart_kubelet_cache_volume_enabled",
		Help: "1 when per-account cache volumes are enabled on this host (--runner-cache-root set); 0 when the feature is off. Gate root_mounted on this.",
	},
)

// cacheVolumeRootMounted is 1 when --runner-cache-root points at an actually-
// mounted volume and 0 when the feature is enabled but the path is not a mount
// (unprovisioned, or the host rebooted and the volume did not auto-remount).
// A 0 here WHILE enabled == 1 is the direct, unambiguous signal that every job
// on this host is silently falling back to the cold path.
var cacheVolumeRootMounted = prometheus.NewGauge(
	prometheus.GaugeOpts{
		Name: "tart_kubelet_cache_volume_root_mounted",
		Help: "1 when the runner-cache root is a mounted volume, 0 when --runner-cache-root is set but the path is not mounted (all jobs run cold until it mounts). Only meaningful when cache_volume_enabled is 1.",
	},
)

// cacheVolumeAdmissionDeclinedTotal counts branches that AllocateBranch declined
// because the runner-cache root had no room even after evicting every master —
// a silent cold-path fallback until now. A nonzero, growing value means the
// quota volume is genuinely full (masters + live-branch reservations), distinct
// from the volume being unmounted (root_mounted=0) or the feature off.
var cacheVolumeAdmissionDeclinedTotal = prometheus.NewCounter(
	prometheus.CounterOpts{
		Name: "tart_kubelet_cache_volume_admission_declined_total",
		Help: "Cache-volume allocations declined for lack of room even after LRU eviction; the VM ran cold.",
	},
)

func init() {
	metrics.Registry.MustRegister(
		vmBootDurationSeconds,
		guestDiskUsagePercent,
		podProvisionDelaySeconds,
		goldenBaseMaterializedTotal,
		goldenBaseReusedTotal,
		vmProvisionWorkSeconds,
		cacheVolumeOutcomeTotal,
		cacheVolumeMaterializeTotal,
		cacheVolumeConvergedTotal,
		cacheVolumeResidentCount,
		cacheVolumeRootFreeBytes,
		cacheVolumeEnabled,
		cacheVolumeRootMounted,
		cacheVolumeAdmissionDeclinedTotal,
	)
}

// RecordVolumeOutcome increments the per-outcome count of finalized cache
// volume branches.
func RecordVolumeOutcome(outcome string) {
	if outcome == "" {
		outcome = string(VolumeOutcomeNone)
	}
	cacheVolumeOutcomeTotal.WithLabelValues(outcome).Inc()
}

// RecordVolumeMaterialized increments the warm/cold count of post-dispatch
// cache materializations.
func RecordVolumeMaterialized(warm bool) {
	result := "cold"
	if warm {
		result = "warm"
	}
	cacheVolumeMaterializeTotal.WithLabelValues(result).Inc()
}

// RecordVolumeConverged increments the count of materialize-time master
// fast-forwards to the account's HEAD.
func RecordVolumeConverged() {
	cacheVolumeConvergedTotal.Inc()
}

// RecordVolumeResident publishes the resident master count and root free
// bytes, sampled on the reconcile tick.
func RecordVolumeResident(count int, freeBytes uint64) {
	cacheVolumeResidentCount.Set(float64(count))
	cacheVolumeRootFreeBytes.Set(float64(freeBytes))
}

// RecordVolumeEnabled marks the cache-volume feature active on this host. Set
// once when an enabled manager starts; a disabled host never calls it, so the
// gauge stays at its 0 default there.
func RecordVolumeEnabled() {
	cacheVolumeEnabled.Set(1)
}

// RecordVolumeRootMounted publishes whether the runner-cache root is a mounted
// volume, sampled at startup and on every reconcile tick.
func RecordVolumeRootMounted(mounted bool) {
	if mounted {
		cacheVolumeRootMounted.Set(1)
		return
	}
	cacheVolumeRootMounted.Set(0)
}

// RecordVolumeAdmissionDeclined increments the count of cache-volume
// allocations declined for lack of room even after eviction.
func RecordVolumeAdmissionDeclined() {
	cacheVolumeAdmissionDeclinedTotal.Inc()
}

// RecordGoldenMaterialized increments the per-pool count of golden base
// VMs materialized via a full image pull+clone. Called once per cold
// `ensureGolden` (first-sight of a digest on this host), not on the
// clonefile recycle path.
func RecordGoldenMaterialized(pool string) {
	if pool == "" {
		pool = "unknown"
	}
	goldenBaseMaterializedTotal.WithLabelValues(pool).Inc()
}

// RecordGoldenReused increments the per-pool count of provisions that
// cloned from an already-present golden base (the warm clonefile path).
func RecordGoldenReused(pool string) {
	if pool == "" {
		pool = "unknown"
	}
	goldenBaseReusedTotal.WithLabelValues(pool).Inc()
}

// RecordVMProvisionWork records the wall-clock of the on-host
// provisioning work for one Pod. path is "warm" (golden reused) or
// "cold" (golden materialized via pull).
func RecordVMProvisionWork(pool, path string, d time.Duration) {
	if pool == "" {
		pool = "unknown"
	}
	vmProvisionWorkSeconds.WithLabelValues(pool, path).Observe(d.Seconds())
}

// RecordGuestDiskUsage publishes a VM's guest root-volume usage percent.
func RecordGuestDiskUsage(vm string, percent int) {
	guestDiskUsagePercent.WithLabelValues(vm).Set(float64(percent))
}

// ResetGuestDiskUsage drops all guest-disk series. Called at the start
// of each probe sweep so a VM that's gone (stopped, deleted, migrated)
// stops reporting a stale last-known capacity.
func ResetGuestDiskUsage() {
	guestDiskUsagePercent.Reset()
}
