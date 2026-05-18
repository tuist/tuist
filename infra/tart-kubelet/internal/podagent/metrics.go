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

func init() {
	metrics.Registry.MustRegister(vmBootDurationSeconds)
}
