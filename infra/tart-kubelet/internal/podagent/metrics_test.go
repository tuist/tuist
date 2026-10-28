package podagent

import (
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestGuestDiskUsageGauge(t *testing.T) {
	t.Cleanup(ResetGuestDiskUsage)

	RecordGuestDiskUsage("vm-a", 92)
	RecordGuestDiskUsage("vm-b", 30)

	if got := testutil.ToFloat64(guestDiskUsagePercent.WithLabelValues("vm-a")); got != 92 {
		t.Fatalf("vm-a gauge = %v, want 92", got)
	}
	if got := testutil.ToFloat64(guestDiskUsagePercent.WithLabelValues("vm-b")); got != 30 {
		t.Fatalf("vm-b gauge = %v, want 30", got)
	}

	// A sweep that no longer sees vm-b must not leave its last value behind.
	ResetGuestDiskUsage()
	RecordGuestDiskUsage("vm-a", 95)

	if got := testutil.CollectAndCount(guestDiskUsagePercent); got != 1 {
		t.Fatalf("series count after reset = %d, want 1", got)
	}
	if got := testutil.ToFloat64(guestDiskUsagePercent.WithLabelValues("vm-a")); got != 95 {
		t.Fatalf("vm-a gauge after reset = %v, want 95", got)
	}
}
