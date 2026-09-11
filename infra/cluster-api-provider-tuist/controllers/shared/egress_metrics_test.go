package shared

import (
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestEgressMetricsRepublishAndForget(t *testing.T) {
	t.Cleanup(func() { ForgetEgressMetrics("n1") })

	RecordEgressReported("ovh", "n1", "fleet", "ns1", "standard", 1000)
	RecordEgressReported("ovh", "n1", "fleet", "ns1", "improved", 5000)
	if n := testutil.CollectAndCount(egressReportedGauge); n != 1 {
		t.Fatalf("reported series = %d, want the old tier's series replaced", n)
	}
	if got := testutil.ToFloat64(egressReportedGauge.WithLabelValues("ovh", "n1", "fleet", "ns1", "improved")); got != 5000 {
		t.Fatalf("reported = %v, want 5000", got)
	}

	RecordEgressBudgets("ovh", "n1", "fleet", 3000, 5000, EgressSourceDiscovery)
	RecordEgressBudgets("ovh", "n1", "fleet", 3000, 1000, EgressSourceManual)
	if n := testutil.CollectAndCount(egressAdvertisedGauge); n != 1 {
		t.Fatalf("advertised series = %d, want the old source's series replaced", n)
	}
	if got := testutil.ToFloat64(egressAdvertisedGauge.WithLabelValues("ovh", "n1", "fleet", EgressSourceManual)); got != 1000 {
		t.Fatalf("advertised = %v, want 1000", got)
	}

	ForgetEgressMetrics("n1")
	for _, gauge := range []*prometheus.GaugeVec{egressReportedGauge, egressConfiguredGauge, egressAdvertisedGauge} {
		if n := testutil.CollectAndCount(gauge); n != 0 {
			t.Fatalf("%d series left after forgetting the node", n)
		}
	}
}
