package controllers

import (
	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

var (
	gatewayAvailable = prometheus.NewGauge(prometheus.GaugeOpts{
		Namespace: "tuist",
		Subsystem: "stable_egress",
		Name:      "gateway_available",
		Help:      "Whether a healthy active or prepared standby gateway is available.",
	})
	gatewayPrepared = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Namespace: "tuist",
		Subsystem: "stable_egress",
		Name:      "gateway_prepared",
		Help:      "Whether the outbound address is configured and ready on a candidate gateway node.",
	}, []string{"node"})
	gatewayActive = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Namespace: "tuist",
		Subsystem: "stable_egress",
		Name:      "gateway_active",
		Help:      "The gateway node currently selected for stable outbound traffic.",
	}, []string{"node", "egress_ip"})
	gatewayFailovers = prometheus.NewCounter(prometheus.CounterOpts{
		Namespace: "tuist",
		Subsystem: "stable_egress",
		Name:      "failovers_total",
		Help:      "Total number of stable outbound address assignments performed during failover.",
	})
	gatewayNodeHealthy = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Namespace: "tuist",
		Subsystem: "stable_egress",
		Name:      "gateway_node_healthy",
		Help:      "Whether the controller can directly reach the Cilium listener on a gateway node.",
	}, []string{"node"})
	gatewayHealthCheckFailures = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: "tuist",
		Subsystem: "stable_egress",
		Name:      "health_check_failures_total",
		Help:      "Total number of failed direct gateway node health checks.",
	}, []string{"node"})
)

func init() {
	metrics.Registry.MustRegister(
		gatewayAvailable,
		gatewayPrepared,
		gatewayActive,
		gatewayFailovers,
		gatewayNodeHealthy,
		gatewayHealthCheckFailures,
	)
}
