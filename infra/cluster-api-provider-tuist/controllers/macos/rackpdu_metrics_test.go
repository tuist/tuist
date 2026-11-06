package macos

import (
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestRackPDUMetricsFollowItsStatus(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.reconcile()

	for name, gauge := range map[string]float64{
		"adopted":             testutil.ToFloat64(rackPDUAdoptedGauge.WithLabelValues("ber1-pdu-b", "ber1")),
		"ready":               testutil.ToFloat64(rackPDUReadyGauge.WithLabelValues("ber1-pdu-b", "ber1")),
		"drifted":             testutil.ToFloat64(rackPDUDriftedGauge.WithLabelValues("ber1-pdu-b", "ber1")),
		"certificate changed": testutil.ToFloat64(rackPDUCertificateChangedGauge.WithLabelValues("ber1-pdu-b", "ber1")),
	} {
		want := map[string]float64{"adopted": 1, "ready": 1, "drifted": 0, "certificate changed": 0}[name]
		if gauge != want {
			t.Errorf("%s = %v, want %v", name, gauge, want)
		}
	}

	h.card.RotateCertificate()
	h.reconcile()
	if got := testutil.ToFloat64(rackPDUCertificateChangedGauge.WithLabelValues("ber1-pdu-b", "ber1")); got != 1 {
		t.Fatalf("certificate changed = %v after the card's certificate changed", got)
	}
	if got := testutil.ToFloat64(rackPDUReadyGauge.WithLabelValues("ber1-pdu-b", "ber1")); got != 0 {
		t.Fatalf("ready = %v while the certificate is not pinned", got)
	}

	forgetRackPDUMetrics("ber1-pdu-b")
	if n := testutil.CollectAndCount(rackPDUReadyGauge); n != 0 {
		t.Fatalf("%d ready series left for a deleted RackPDU", n)
	}
}
