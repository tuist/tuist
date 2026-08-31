package podagent

import (
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
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

func TestRecordVolumePromote(t *testing.T) {
	acceptedBefore := testutil.ToFloat64(cacheVolumePromoteTotal.WithLabelValues("accepted"))
	rejectedBefore := testutil.ToFloat64(cacheVolumePromoteTotal.WithLabelValues("rejected"))
	errorBefore := testutil.ToFloat64(cacheVolumePromoteTotal.WithLabelValues("error"))

	RecordVolumePromote("accepted")
	RecordVolumePromote("rejected")
	RecordVolumePromote("rejected")
	RecordVolumePromote("error")
	RecordVolumePromote("garbage") // unknown → error, never a false rejection

	if got := testutil.ToFloat64(cacheVolumePromoteTotal.WithLabelValues("accepted")); got != acceptedBefore+1 {
		t.Fatalf("accepted = %v, want %v", got, acceptedBefore+1)
	}
	if got := testutil.ToFloat64(cacheVolumePromoteTotal.WithLabelValues("rejected")); got != rejectedBefore+2 {
		t.Fatalf("rejected = %v, want %v", got, rejectedBefore+2)
	}
	if got := testutil.ToFloat64(cacheVolumePromoteTotal.WithLabelValues("error")); got != errorBefore+2 {
		t.Fatalf("error = %v, want %v", got, errorBefore+2)
	}
}

func TestCacheVolumePromoteSeriesInitialized(t *testing.T) {
	// All three result series must exist from registration so a reject-rate panel
	// reads 0 (not "No data") while promotions happen with zero rejections.
	if got := testutil.CollectAndCount(cacheVolumePromoteTotal); got < 3 {
		t.Fatalf("promote series count = %d, want >= 3 (accepted/rejected/error pre-initialized)", got)
	}
}

// The per-subtree attribution is the point of the whole guest-side walk: without
// these families registered, a full cache image is only ever a fill percentage
// with nothing to blame it on.
func TestCacheVolumeSubtreeMetricsRegistered(t *testing.T) {
	families, err := metrics.Registry.Gather()
	if err != nil {
		t.Fatalf("gather: %v", err)
	}
	registered := map[string]bool{}
	for _, f := range families {
		registered[f.GetName()] = true
	}
	for _, name := range []string{
		"tart_kubelet_cache_volume_subtree_bytes",
		"tart_kubelet_cache_volume_unbudgeted_bytes",
	} {
		if !registered[name] {
			t.Errorf("metric %q is not registered", name)
		}
	}
}
