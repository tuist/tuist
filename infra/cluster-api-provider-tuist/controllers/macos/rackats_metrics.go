package macos

import (
	"fmt"

	"github.com/prometheus/client_golang/prometheus"
	corev1 "k8s.io/api/core/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// What the RackATS controller observes of each controller-managed transfer
// switch, on the operator's /metrics. It replaces an SNMP exporter: the same
// reads that fill status fill these. The observation series exist only while
// the last observation succeeded, so an alert on them never fires on a stale
// value; capt_rackats_observed says whether one did.
var (
	rackATSLabels = []string{"ats", "site"}

	rackATSObserved = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackats_observed",
		Help: "1 when the RackATS controller's last read of the transfer switch succeeded, 0 when it failed or was not attempted (unreachable, unsupported card, changed certificate).",
	}, rackATSLabels)
	rackATSLastObserved = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackats_last_observed_timestamp_seconds",
		Help: "Unix time of the last successful read of the transfer switch's sources.",
	}, rackATSLabels)
	rackATSActiveSource = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackats_active_source",
		Help: "The source powering the load: 1 or 2, 0 when neither does.",
	}, rackATSLabels)
	rackATSPreferredSource = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackats_preferred_source",
		Help: "The preferred source the card reports: 1 or 2, 0 when it reports none the controller recognises.",
	}, rackATSLabels)
	rackATSRedundant = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackats_redundant",
		Help: "1 when the source not powering the load is good, so the switch could take the load to it; 0 otherwise.",
	}, rackATSLabels)
	rackATSInputGood = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackats_input_good",
		Help: "1 when the source is in its normal range, 0 when it is derated, out of range, missing or unknown.",
	}, append(rackATSLabels, "source"))
	rackATSInputState = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackats_input_state",
		Help: "The source's state as a 1-valued series: state is good, derated, outOfRange, missing or unknown.",
	}, append(rackATSLabels, "source", "state"))
	rackATSInputVoltage = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackats_input_voltage_volts",
		Help: "The source's voltage, when the card reports it.",
	}, append(rackATSLabels, "source"))
	rackATSTransfers = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "capt_rackats_observed_transfers_total",
		Help: "Changes of the source powering the load that the controller observed between two reads, a minute apart. A transfer and its return within one interval is not seen.",
	}, append(rackATSLabels, "from", "to"))

	// The lifecycle, like the other rack power devices'.
	rackATSReady = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackats_ready",
		Help: "1 when the RackATS is Ready: adopted, its certificate pinned, and its last read succeeded.",
	}, rackATSLabels)
	rackATSAdopted = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackats_adopted",
		Help: "1 when the controller adopted the transfer switch's card.",
	}, rackATSLabels)
	rackATSDrifted = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackats_drifted",
		Help: "1 when the card's configuration no longer matches the spec (reported, not written over until the next generation).",
	}, rackATSLabels)
	rackATSCertificateChanged = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackats_certificate_changed",
		Help: "1 when the card presents a certificate other than the pinned one, which blocks every write and read until accepted.",
	}, rackATSLabels)
)

func init() {
	metrics.Registry.MustRegister(rackATSObserved, rackATSLastObserved, rackATSActiveSource, rackATSPreferredSource,
		rackATSRedundant, rackATSInputGood, rackATSInputState, rackATSInputVoltage, rackATSTransfers,
		rackATSReady, rackATSAdopted, rackATSDrifted, rackATSCertificateChanged)
}

// recordRackATSMetrics publishes a controller-managed RackATS's status.
func recordRackATSMetrics(ats *infrav1.RackATS) {
	labels := prometheus.Labels{"ats": ats.Name, "site": ats.Spec.Site}
	flag := func(ok bool) float64 {
		if ok {
			return 1
		}
		return 0
	}
	rackATSReady.With(labels).Set(flag(conditions.IsTrue(ats, clusterv1.ReadyCondition)))
	rackATSAdopted.With(labels).Set(flag(ats.Status.Adopted))
	rackATSDrifted.With(labels).Set(flag(ats.Status.Drift == infrav1.RackCardDriftDrifted))
	rackATSCertificateChanged.With(labels).Set(flag(conditions.IsTrue(ats, RackCardCertificateChangedCondition)))

	redundant := conditions.Get(ats, RackATSRedundantCondition)
	observed := redundant != nil && redundant.Status != corev1.ConditionUnknown && ats.Status.LastObserved != nil
	rackATSObserved.With(labels).Set(flag(observed))
	forgetRackATSObservation(ats.Name)
	if !observed {
		return
	}
	rackATSLastObserved.With(labels).Set(float64(ats.Status.LastObserved.Unix()))
	rackATSActiveSource.With(labels).Set(float64(ats.Status.ActiveSource))
	rackATSPreferredSource.With(labels).Set(float64(ats.Status.PreferredSource))
	rackATSRedundant.With(labels).Set(flag(redundant.Status == corev1.ConditionTrue))
	for _, in := range ats.Status.Inputs {
		source := fmt.Sprint(in.Source)
		rackATSInputGood.WithLabelValues(ats.Name, ats.Spec.Site, source).Set(flag(in.State == infrav1.RackATSInputGood))
		rackATSInputState.WithLabelValues(ats.Name, ats.Spec.Site, source, string(in.State)).Set(1)
		var volts float64
		if _, err := fmt.Sscan(in.Voltage, &volts); err == nil {
			rackATSInputVoltage.WithLabelValues(ats.Name, ats.Spec.Site, source).Set(volts)
		}
	}
}

// forgetRackATSObservation drops the observation series, so a switch that is
// not being read reports no stale source.
func forgetRackATSObservation(name string) {
	match := prometheus.Labels{"ats": name}
	for _, g := range []*prometheus.GaugeVec{rackATSLastObserved, rackATSActiveSource, rackATSPreferredSource,
		rackATSRedundant, rackATSInputGood, rackATSInputState, rackATSInputVoltage} {
		g.DeletePartialMatch(match)
	}
}

// forgetRackATSMetrics drops every series of a RackATS that is gone or not the
// controller's.
func forgetRackATSMetrics(name string) {
	forgetRackATSObservation(name)
	match := prometheus.Labels{"ats": name}
	for _, g := range []*prometheus.GaugeVec{rackATSObserved, rackATSReady, rackATSAdopted, rackATSDrifted, rackATSCertificateChanged} {
		g.DeletePartialMatch(match)
	}
	rackATSTransfers.DeletePartialMatch(match)
}
