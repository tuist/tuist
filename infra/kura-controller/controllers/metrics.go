package controllers

import (
	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

// kuraNotReadyPodDeletionsTotal counts pods the controller proactively deleted
// because they were not Ready and still running a superseded image, so a
// rollout that leaned on the parallel fast path is distinguishable from one
// that walked ordinals through the readiness-gated update.
var kuraNotReadyPodDeletionsTotal = prometheus.NewCounterVec(
	prometheus.CounterOpts{
		Name: "kura_controller_not_ready_pod_deletions_total",
		Help: "Not-Ready Kura pods deleted on an image change so they recreate on the desired image in parallel.",
	},
	[]string{"namespace", "instance"},
)

func init() {
	metrics.Registry.MustRegister(kuraNotReadyPodDeletionsTotal)
}
