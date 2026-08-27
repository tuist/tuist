package linux

import (
	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

// The three numbers behind a node's egress budget, published where all three are
// known at once. Splitting them across sources would mean joining the operator's
// view against kube-state-metrics and the egress-tree agent at different scrape
// offsets; here they move together, so `reported < configured` is a fact about one
// reconcile rather than a race between two exporters.
//
// The `node` label is set explicitly and equals the machine name for the Linux
// kinds. Nothing adds it at scrape time: the operator's series carry `instance`
// and `pod` for the operator's own pod, which runs on a general node, so a
// scrape-added label would name the wrong host. With `node` set, these join
// directly against kube_node_status_capacity{resource="tuist_dev_egress_mbps"}.
var (
	egressReportedGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_ovh_egress_reported_mbps",
		Help: "Public egress limitation OVH reports for the box (bandwidth.OvhToInternet), in Mbps.",
	}, []string{"node", "fleet", "service", "tier"})

	egressConfiguredGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_ovh_egress_configured_mbps",
		Help: "Egress budget configured on the machine (spec.egressBudgetMbps), in Mbps.",
	}, []string{"node", "fleet"})

	egressAdvertisedGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_ovh_egress_advertised_mbps",
		Help: "Egress budget advertised as the node's tuist.dev/egress-mbps capacity, in Mbps.",
	}, []string{"node", "fleet", "source"})
)

// What the source label carries, for the reader of this file rather than the Help
// string: "discovery" is a reading from OVH, including one the ratchet is holding;
// "manual" is a machine pinned by the tuist.dev/egress-mbps-override annotation, so
// a pin left in place is alertable on its age; "configured" is spec.egressBudgetMbps.

func init() {
	metrics.Registry.MustRegister(egressReportedGauge, egressConfiguredGauge, egressAdvertisedGauge)
}

// recordEgressReported republishes the reported series, dropping the machine's
// prior one first: `tier` and `service` are labels, so a box moved to another
// offer — or a machine re-adopted onto a different server — would otherwise leave
// its old series alongside the new one and both would look current.
func recordEgressReported(node, fleet, service, tier string, mbps int32) {
	egressReportedGauge.DeletePartialMatch(prometheus.Labels{"node": node})
	egressReportedGauge.WithLabelValues(node, fleet, service, tier).Set(float64(mbps))
}

func recordEgressBudgets(node, fleet string, configured, advertised int32, source string) {
	egressConfiguredGauge.WithLabelValues(node, fleet).Set(float64(configured))
	// Republished rather than updated: `source` is a label, so a node that moves
	// from a pin back to discovery would otherwise keep both series alive.
	egressAdvertisedGauge.DeletePartialMatch(prometheus.Labels{"node": node})
	egressAdvertisedGauge.WithLabelValues(node, fleet, source).Set(float64(advertised))
}

// forgetEgressMetrics drops a machine's series once its CR is gone, so a released
// box stops reporting a budget nothing is advertising any more.
func forgetEgressMetrics(node string) {
	for _, gauge := range []*prometheus.GaugeVec{egressReportedGauge, egressConfiguredGauge, egressAdvertisedGauge} {
		gauge.DeletePartialMatch(prometheus.Labels{"node": node})
	}
}
