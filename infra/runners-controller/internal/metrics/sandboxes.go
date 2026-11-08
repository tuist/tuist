package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
	ctrlmetrics "sigs.k8s.io/controller-runtime/pkg/metrics"
)

var sandboxMemory = prometheus.NewGaugeVec(prometheus.GaugeOpts{
	Name: "tuist_runners_sandbox_memory_bytes",
	Help: "Sandbox memory by node and kind: charged (max requested/allocated/applied), grant (admission ceiling, not a reservation), or free (unrequested host memory).",
}, []string{"node", "kind"})
var sandboxGrantTime = prometheus.NewGaugeVec(prometheus.GaugeOpts{
	Name: "tuist_runners_sandbox_grant_timestamp_seconds",
	Help: "Unix timestamp of the last successfully published sandbox allocation; grants expire after 15 seconds.",
}, []string{"node"})
var sandboxRetirements = prometheus.NewCounterVec(prometheus.CounterOpts{
	Name: "tuist_runners_sandbox_retired_pods_total",
	Help: "Idle runner Pods marked for retirement to admit sandbox growth, separate from CI sibling preemption.",
}, []string{"pool"})

func init() { ctrlmetrics.Registry.MustRegister(sandboxMemory, sandboxGrantTime, sandboxRetirements) }

func RecordSandboxAllocation(node string, charged, grant, free int64, timestamp float64) {
	sandboxMemory.WithLabelValues(node, "charged").Set(float64(charged))
	sandboxMemory.WithLabelValues(node, "grant").Set(float64(grant))
	sandboxMemory.WithLabelValues(node, "free").Set(float64(free))
	sandboxGrantTime.WithLabelValues(node).Set(timestamp)
}

func RecordSandboxRetirement(pool string) { sandboxRetirements.WithLabelValues(pool).Inc() }
