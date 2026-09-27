package macos

import (
	"github.com/prometheus/client_golang/prometheus"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

var (
	rackPDUAdoptedGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackpdu_adopted",
		Help: "1 when the RackPDU controller has adopted the PDU's card, 0 otherwise. Labels: pdu, site.",
	}, []string{"pdu", "site"})

	rackPDUReadyGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackpdu_ready",
		Help: "1 when power goes through the RackPDU (adopted, certificate pinned, the controller's account logs in), 0 otherwise: every host plugged into it has no remote reboot. Labels: pdu, site.",
	}, []string{"pdu", "site"})

	rackPDUDriftedGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackpdu_drifted",
		Help: "1 when the PDU's card no longer matches its spec (an outlet's startup state), which the controller reports and leaves until the spec's next generation. Labels: pdu, site.",
	}, []string{"pdu", "site"})

	rackPDUCertificateChangedGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackpdu_certificate_changed",
		Help: "1 when the PDU's card presents a certificate other than the pinned one, which blocks every write until tuist.dev/accept-certificate names it. Labels: pdu, site.",
	}, []string{"pdu", "site"})
)

func init() {
	metrics.Registry.MustRegister(rackPDUAdoptedGauge, rackPDUReadyGauge, rackPDUDriftedGauge, rackPDUCertificateChangedGauge)
}

func recordRackPDUMetrics(pdu *infrav1.RackPDU) {
	labels := []string{pdu.Name, pdu.Spec.Site}
	for _, g := range []*prometheus.GaugeVec{rackPDUAdoptedGauge, rackPDUReadyGauge, rackPDUDriftedGauge, rackPDUCertificateChangedGauge} {
		g.DeletePartialMatch(prometheus.Labels{"pdu": pdu.Name})
	}
	rackPDUAdoptedGauge.WithLabelValues(labels...).Set(boolGauge(pdu.Status.Adopted))
	rackPDUReadyGauge.WithLabelValues(labels...).Set(boolGauge(conditions.IsTrue(pdu, clusterv1.ReadyCondition)))
	rackPDUDriftedGauge.WithLabelValues(labels...).Set(boolGauge(pdu.Status.Drift == infrav1.RackPDUDriftDrifted))
	rackPDUCertificateChangedGauge.WithLabelValues(labels...).Set(boolGauge(conditions.IsTrue(pdu, RackPDUCertificateChangedCondition)))
}

func forgetRackPDUMetrics(name string) {
	for _, g := range []*prometheus.GaugeVec{rackPDUAdoptedGauge, rackPDUReadyGauge, rackPDUDriftedGauge, rackPDUCertificateChangedGauge} {
		g.DeletePartialMatch(prometheus.Labels{"pdu": name})
	}
}
