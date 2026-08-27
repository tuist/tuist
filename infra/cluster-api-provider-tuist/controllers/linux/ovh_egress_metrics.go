package linux

import (
	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

// The three numbers behind a node's egress budget, published together so that
// `reported < configured` is a fact about one reconcile rather than a race between
// exporters scraped at different offsets.
//
// `node` is set explicitly — nothing adds it at scrape time, and the operator's own
// `instance`/`pod` labels name the node the operator runs on, not the box. With it
// set, these join against kube_node_status_capacity{resource="tuist_dev_egress_mbps"}.
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

// The source label: "discovery" is a reading from OVH, a held floor an earlier
// reading supports included; "manual" is a pinned machine, so a pin left in place is
// alertable on its age; "held" is a floor with no reading behind it, kept apart from
// "discovery" so a dashboard filtering on OVH-backed budgets does not count it;
// "configured" is spec.egressBudgetMbps.

func init() {
	metrics.Registry.MustRegister(egressReportedGauge, egressConfiguredGauge, egressAdvertisedGauge)
}

// recordEgressReported republishes rather than updates: `tier` and `service` are
// labels, so a box that changes offer — or a machine re-adopted onto another server —
// would otherwise leave its old series alongside the new one, both looking current.
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

// forgetEgressReported drops just the reported series, for when its reading stops
// describing the box the machine holds. The next read would republish it, but that is
// a day away at best and never on a machine discovery is skipping.
func forgetEgressReported(node string) {
	egressReportedGauge.DeletePartialMatch(prometheus.Labels{"node": node})
}

// forgetEgressMetrics drops a machine's series once its CR is gone, so a released
// box stops reporting a budget nothing is advertising any more.
func forgetEgressMetrics(node string) {
	for _, gauge := range []*prometheus.GaugeVec{egressReportedGauge, egressConfiguredGauge, egressAdvertisedGauge} {
		gauge.DeletePartialMatch(prometheus.Labels{"node": node})
	}
}
