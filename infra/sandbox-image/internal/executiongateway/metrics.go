package executiongateway

import (
	"github.com/prometheus/client_golang/prometheus"
)

// Labels are fixed sets: never accounts, projects or digests.
type metrics struct {
	executions   *prometheus.CounterVec
	duration     *prometheus.HistogramVec
	streams      prometheus.Gauge
	prefetches   *prometheus.CounterVec
	publications *prometheus.CounterVec
}

func newMetrics(registry prometheus.Registerer) *metrics {
	m := &metrics{
		executions: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "reapi_gateway_executions_total",
			Help: "Execute calls by path (lease or server) and final status: the RPC's error, or the action's status when it completed.",
		}, []string{"path", "code"}),
		duration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "reapi_gateway_execute_seconds",
			Help:    "Execute calls from admission to the final message, by path.",
			Buckets: prometheus.ExponentialBuckets(0.001, 2, 20),
		}, []string{"path"}),
		streams: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "reapi_gateway_streams",
			Help: "Admitted Execute and WaitExecution streams.",
		}),
		prefetches: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "reapi_gateway_prefetches_total",
			Help: "Input prefetches by how the inputs were read (inputs, tree, walk), or why none were (skipped, failed).",
		}, []string{"result"}),
		publications: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "reapi_gateway_publications_total",
			Help: "Background action-cache publications: stored, failed, or dropped while too many were pending.",
		}, []string{"result"}),
	}
	registry.MustRegister(m.executions, m.duration, m.streams, m.prefetches, m.publications)
	return m
}
