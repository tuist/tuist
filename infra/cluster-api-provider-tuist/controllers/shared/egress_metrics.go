package shared

import (
	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

// The `node` label is set explicitly so these join against
// kube_node_status_capacity{resource="tuist_dev_egress_mbps"}; the operator's own
// instance/pod labels name the node the operator runs on, not the box.
var (
	egressReportedGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_egress_reported_mbps",
		Help: "Public egress limitation the provider reports for the box, in Mbps.",
	}, []string{"provider", "node", "fleet", "service", "tier"})

	egressConfiguredGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_egress_configured_mbps",
		Help: "Egress budget configured on the machine (spec.egressBudgetMbps), in Mbps.",
	}, []string{"provider", "node", "fleet"})

	egressAdvertisedGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_egress_advertised_mbps",
		Help: "Egress budget advertised as the node's tuist.dev/egress-mbps capacity, in Mbps.",
	}, []string{"provider", "node", "fleet", "source"})
)

func init() {
	metrics.Registry.MustRegister(egressReportedGauge, egressConfiguredGauge, egressAdvertisedGauge)
}

// RecordEgressReported republishes the node's series rather than updating it:
// service and tier are labels, so a box that changes offer would otherwise leave
// its old series alongside the new one.
func RecordEgressReported(provider, node, fleet, service, tier string, mbps int32) {
	egressReportedGauge.DeletePartialMatch(prometheus.Labels{"node": node})
	egressReportedGauge.WithLabelValues(provider, node, fleet, service, tier).Set(float64(mbps))
}

func RecordEgressBudgets(provider, node, fleet string, configured, advertised int32, source string) {
	egressConfiguredGauge.WithLabelValues(provider, node, fleet).Set(float64(configured))
	egressAdvertisedGauge.DeletePartialMatch(prometheus.Labels{"node": node})
	egressAdvertisedGauge.WithLabelValues(provider, node, fleet, source).Set(float64(advertised))
}

// ForgetEgressReported drops the reported series when its reading no longer
// describes the box the machine holds.
func ForgetEgressReported(node string) {
	egressReportedGauge.DeletePartialMatch(prometheus.Labels{"node": node})
}

// ForgetEgressMetrics drops every series for a node that is no longer governed or
// no longer exists.
func ForgetEgressMetrics(node string) {
	for _, gauge := range []*prometheus.GaugeVec{egressReportedGauge, egressConfiguredGauge, egressAdvertisedGauge} {
		gauge.DeletePartialMatch(prometheus.Labels{"node": node})
	}
}
