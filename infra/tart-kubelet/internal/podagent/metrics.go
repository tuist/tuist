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
var podProvisionDelaySeconds = prometheus.NewHistogramVec(
	prometheus.HistogramOpts{
		Name:    "tart_kubelet_pod_provision_delay_seconds",
		Help:    "Wall-clock from Pod creation to tart run start (scheduling + image pull + clone).",
		Buckets: []float64{1, 5, 10, 20, 30, 60, 120, 180, 300, 600},
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
var vmProvisionWorkSeconds = prometheus.NewHistogramVec(
	prometheus.HistogramOpts{
		Name:    "tart_kubelet_vm_provision_work_seconds",
		Help:    "Wall-clock for on-host provisioning work (ensureGolden + runner clone), per pool and path (warm=clonefile, cold=pull).",
		Buckets: []float64{1, 5, 10, 20, 30, 60, 120, 180, 300, 600},
	},
	[]string{"pool", "path"},
)

func init() {
	metrics.Registry.MustRegister(
		vmBootDurationSeconds,
		guestDiskUsagePercent,
		podProvisionDelaySeconds,
		goldenBaseMaterializedTotal,
		goldenBaseReusedTotal,
		vmProvisionWorkSeconds,
	)
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
