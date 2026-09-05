package controllers

import (
	"context"
	"errors"
	"reflect"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

type stubMetricsClient struct {
	usage map[string]int64
	err   error
	calls int
}

func (s *stubMetricsClient) PodCPUMilli(_ context.Context, _ string, _ map[string]string) (map[string]int64, error) {
	s.calls++
	if s.err != nil {
		return nil, s.err
	}
	return s.usage, nil
}

func instanceWithPods(names ...string) (*kurav1alpha1.KuraInstance, []corev1.Pod) {
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-acme-us-east-1", Namespace: "kura"},
		Spec:       kurav1alpha1.KuraInstanceSpec{AccountHandle: "acme"},
	}
	pods := make([]corev1.Pod, 0, len(names))
	for _, name := range names {
		pods = append(pods, corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "kura"}})
	}
	return instance, pods
}

// The pod template is shared, so the instance is sized for its busiest pod.
func TestObserveCPUUsageSizesForTheBusiestReplica(t *testing.T) {
	instance, pods := instanceWithPods("kura-acme-us-east-1-0", "kura-acme-us-east-1-1")
	r := &KuraInstanceReconciler{MetricsClient: &stubMetricsClient{usage: map[string]int64{
		"kura-acme-us-east-1-0": 58,
		"kura-acme-us-east-1-1": 631,
	}}}

	r.observeCPUUsage(context.Background(), instance, pods)

	state := instance.Status.CPUAutosize
	if state == nil {
		t.Fatal("expected an observation to be published")
	}
	if state.PeakMilli != 631 {
		t.Fatalf("peak = %dm, want the busiest replica's 631m", state.PeakMilli)
	}
	// 631m + a quarter is 788m, which lands on the 1000m band.
	if state.RequestMilli != 1000 {
		t.Fatalf("request = %dm, want 1000m", state.RequestMilli)
	}
}

// A metrics-server outage must not read as fleet-wide idleness.
func TestObserveCPUUsageIgnoresUnreadableMetrics(t *testing.T) {
	instance, pods := instanceWithPods("kura-acme-us-east-1-0")
	opened := time.Now().UTC().Truncate(cpuBucketDuration).Add(-4 * cpuBucketDuration)
	existing := &kurav1alpha1.KuraInstanceCPUAutosize{
		RequestMilli:     600,
		PeakMilli:        480,
		BucketStartedAt:  &metav1.Time{Time: opened},
		BucketPeaksMilli: []int32{480},
	}

	for name, client := range map[string]*stubMetricsClient{
		"metrics-server unreachable":       {err: errors.New("metrics-server unavailable")},
		"no pod of this instance reported": {usage: map[string]int64{"some-other-pod": 4000}},
	} {
		instance.Status.CPUAutosize = existing.DeepCopy()
		r := &KuraInstanceReconciler{MetricsClient: client}

		r.observeCPUUsage(context.Background(), instance, pods)

		if client.calls != 1 {
			t.Fatalf("%s: expected the metrics client to be consulted once, got %d", name, client.calls)
		}
		got := instance.Status.CPUAutosize
		if !reflect.DeepEqual(got, existing) {
			t.Fatalf("%s: the window moved on an unreadable reading: %+v", name, got)
		}
	}
}

// No metrics client degrades to a flat reservation, not to nothing.
func TestObserveCPUUsageWithoutAMetricsClientLeavesTheColdStart(t *testing.T) {
	instance, pods := instanceWithPods("kura-acme-us-east-1-0")

	(&KuraInstanceReconciler{}).observeCPUUsage(context.Background(), instance, pods)

	if instance.Status.CPUAutosize != nil {
		t.Fatal("expected no observation without a metrics client")
	}
	if got := cpuRequestMilli(instance); got != cpuColdStartMilli {
		t.Fatalf("request = %dm, want the cold-start %dm", got, cpuColdStartMilli)
	}
}

func TestCPURequestGrowsAtOnce(t *testing.T) {
	now := time.Date(2026, 9, 5, 0, 0, 0, 0, time.UTC)

	state := observeCPUPeak(nil, 3, now)
	if state.RequestMilli != cpuColdStartMilli {
		t.Fatalf("a first idle reading moved the request to %dm", state.RequestMilli)
	}

	state = observeCPUPeak(state, 480, now)
	if state.RequestMilli != 600 {
		t.Fatalf("request = %dm, want an immediate rise to 600m", state.RequestMilli)
	}
}

func TestCPURequestHoldsTheColdStartUntilEnoughHistory(t *testing.T) {
	now := time.Date(2026, 9, 5, 0, 0, 0, 0, time.UTC)

	var state *kurav1alpha1.KuraInstanceCPUAutosize
	for i := 0; i < cpuShrinkMinBuckets-1; i++ {
		state = observeCPUPeak(state, 2, now.Add(time.Duration(i)*cpuBucketDuration))
		if state.RequestMilli != cpuColdStartMilli {
			t.Fatalf("request fell to %dm after only %d windows", state.RequestMilli, i+1)
		}
	}

	state = observeCPUPeak(state, 2, now.Add(time.Duration(cpuShrinkMinBuckets-1)*cpuBucketDuration))
	if state.RequestMilli != cpuRequestBands[0] {
		t.Fatalf("request = %dm, want the floor %dm once %d windows were retained",
			state.RequestMilli, cpuRequestBands[0], cpuShrinkMinBuckets)
	}
}

// A quiet weekend must not shrink a weekday tenant into Monday.
func TestCPURequestFallsOnlyOnceThePeakAgesOut(t *testing.T) {
	now := time.Date(2026, 9, 5, 0, 0, 0, 0, time.UTC)

	state := observeCPUPeak(nil, 480, now)
	if state.RequestMilli != 600 {
		t.Fatalf("request = %dm, want 600m", state.RequestMilli)
	}

	for i := 1; i < cpuBucketCount; i++ {
		state = observeCPUPeak(state, 2, now.Add(time.Duration(i)*cpuBucketDuration))
		if state.RequestMilli != 600 {
			t.Fatalf("request fell to %dm while window %d of %d still held the peak",
				state.RequestMilli, i, cpuBucketCount)
		}
	}

	state = observeCPUPeak(state, 2, now.Add(cpuBucketCount*cpuBucketDuration))
	if state.RequestMilli != cpuRequestBands[0] {
		t.Fatalf("request = %dm, want the floor %dm once the peak aged out", state.RequestMilli, cpuRequestBands[0])
	}
}

// An unobserved window is a gap, not idleness.
func TestObserveCPUPeakLeavesUnobservedWindowsEmpty(t *testing.T) {
	now := time.Date(2026, 9, 5, 0, 0, 0, 0, time.UTC)
	state := observeCPUPeak(nil, 631, now)

	state = observeCPUPeak(state, 4, now.Add(4*cpuBucketDuration))

	if len(state.BucketPeaksMilli) != 5 {
		t.Fatalf("retained %d windows, want 5", len(state.BucketPeaksMilli))
	}
	for i, want := range []int32{631, 0, 0, 0, 4} {
		if state.BucketPeaksMilli[i] != want {
			t.Fatalf("window %d = %dm, want %dm", i, state.BucketPeaksMilli[i], want)
		}
	}
	if state.PeakMilli != 631 {
		t.Fatalf("peak = %dm, want the surviving 631m", state.PeakMilli)
	}
}

func TestObserveCPUPeakRetainsAFixedWindow(t *testing.T) {
	now := time.Date(2026, 9, 5, 0, 0, 0, 0, time.UTC)
	var state *kurav1alpha1.KuraInstanceCPUAutosize
	for i := 0; i < cpuBucketCount*3; i++ {
		state = observeCPUPeak(state, int64(10+i), now.Add(time.Duration(i)*cpuBucketDuration))
	}

	if len(state.BucketPeaksMilli) != cpuBucketCount {
		t.Fatalf("retained %d windows, want %d", len(state.BucketPeaksMilli), cpuBucketCount)
	}
	state = observeCPUPeak(state, 5, now.Add(1000*cpuBucketDuration))
	if len(state.BucketPeaksMilli) != cpuBucketCount {
		t.Fatalf("retained %d windows after a long gap, want %d", len(state.BucketPeaksMilli), cpuBucketCount)
	}
}

// The ladder's ends are the floor and the ceiling.
func TestCPUBandIsBounded(t *testing.T) {
	if got := cpuBand(0); got != 50 {
		t.Fatalf("floor = %dm, want 50m", got)
	}
	if got := cpuBand(1 << 40); got != 3000 {
		t.Fatalf("ceiling = %dm, want 3000m", got)
	}
	for i := 1; i < len(cpuRequestBands); i++ {
		if cpuRequestBands[i] <= cpuRequestBands[i-1] {
			t.Fatalf("bands are not ascending at index %d", i)
		}
	}
	for _, milli := range []int64{101, 120, 149, 150} {
		if got := cpuBand(milli); got != 150 {
			t.Fatalf("cpuBand(%d) = %dm, want 150m", milli, got)
		}
	}
}

func TestClampMilliRejectsUnusableReadings(t *testing.T) {
	if got := clampMilli(-5); got != 0 {
		t.Fatalf("negative reading = %dm, want 0m", got)
	}
	if got := clampMilli(1 << 40); got != 12000 {
		t.Fatalf("overflowing reading = %dm, want it clamped to 12000m", got)
	}
}

// Memory and the three extended resources the scheduler bin-packs against
// must not move with CPU.
func TestCPUSizingLeavesTheOtherDimensionsAlone(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{
		Spec: kurav1alpha1.KuraInstanceSpec{
			MemoryFloorMib:       1024,
			MemoryCeilingMib:     4096,
			StorageSize:          "40Gi",
			EgressGuaranteedMbps: 100,
		},
	}
	before := defaultResources(instance, true)

	instance.Status.CPUAutosize = &kurav1alpha1.KuraInstanceCPUAutosize{RequestMilli: 1500}
	after := defaultResources(instance, true)

	if got := after.Requests.Cpu().String(); got != "1500m" {
		t.Fatalf("CPU request = %q, want 1500m", got)
	}
	if _, ok := after.Limits[corev1.ResourceCPU]; ok {
		t.Fatal("CPU is compressible: a limit would cap a burst the box can absorb")
	}
	for _, name := range []corev1.ResourceName{
		corev1.ResourceMemory,
		corev1.ResourceEphemeralStorage,
		memoryCeilingResource,
		egressMbpsResource,
	} {
		if b, a := before.Requests[name], after.Requests[name]; b.Cmp(a) != 0 {
			t.Fatalf("request %q moved from %s to %s", name, b.String(), a.String())
		}
	}
	for _, name := range []corev1.ResourceName{corev1.ResourceMemory, memoryCeilingResource, egressMbpsResource} {
		if b, a := before.Limits[name], after.Limits[name]; b.Cmp(a) != 0 {
			t.Fatalf("limit %q moved from %s to %s", name, b.String(), a.String())
		}
	}
}

// The controller restarts on every deploy, so the decision is persisted.
func TestCPURequestSurvivesAControllerRestart(t *testing.T) {
	now := time.Date(2026, 9, 5, 0, 0, 0, 0, time.UTC)
	var state *kurav1alpha1.KuraInstanceCPUAutosize
	for i := 0; i < cpuShrinkMinBuckets*2; i++ {
		state = observeCPUPeak(state, 480, now.Add(time.Duration(i)*cpuBucketDuration))
	}

	restarted := &kurav1alpha1.KuraInstance{Status: kurav1alpha1.KuraInstanceStatus{CPUAutosize: state.DeepCopy()}}
	if got := cpuRequestMilli(restarted); got != 600 {
		t.Fatalf("request after restart = %dm, want the persisted 600m", got)
	}

	next := observeCPUPeak(restarted.Status.CPUAutosize, 1, now.Add(cpuShrinkMinBuckets*2*cpuBucketDuration))
	if next.RequestMilli != 600 {
		t.Fatalf("request = %dm, want 600m while the ring still holds the peak", next.RequestMilli)
	}
}
