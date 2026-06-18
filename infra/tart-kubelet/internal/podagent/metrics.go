package podagent

import (
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

// podProvisionDelaySeconds is wall-clock from a Pod's creation
// timestamp to the moment this node begins provisioning its VM (the
// first reconcile that runs `tart pull`/`clone` for it). It isolates
// the gap that was previously invisible: a scheduled Pod can sit
// Pending for minutes before tart-kubelet even starts its VM, and
// nothing measured it — vmBootDurationSeconds starts at clone, and no
// event was emitted before Running. A rising p90 here is the
// "pods stranded before boot" signal that the boot histogram can't see.
//
// Pool label from the Pod's `tuist.dev/runner-pool` label, same as the
// boot histogram, for per-pool breakdowns.
var podProvisionDelaySeconds = prometheus.NewHistogramVec(
	prometheus.HistogramOpts{
		Name:    "tart_kubelet_pod_provision_delay_seconds",
		Help:    "Wall-clock from Pod creation to the start of its VM provisioning (first tart pull/clone).",
		Buckets: []float64{1, 5, 10, 20, 30, 60, 120, 180, 300, 600},
	},
	[]string{"pool"},
)

func init() {
	metrics.Registry.MustRegister(vmBootDurationSeconds, guestDiskUsagePercent, podProvisionDelaySeconds)
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
