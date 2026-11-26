package controllers

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const testMiB = 1024 * 1024

// An Enterprise-shaped instance (1024/4096 MiB) allowed to grow to 4096 MiB,
// with two Ready, caught-up replicas each running a 1024 MiB floor.
func memoryAutosizeFixture(t *testing.T) (*KuraInstanceReconciler, *kurav1alpha1.KuraInstance, []corev1.Pod) {
	t.Helper()
	instance, pods := instanceWithPods("kura-acme-us-east-1-0", "kura-acme-us-east-1-1")
	instance.Spec.Replicas = ptr(int32(2))
	instance.Spec.MemoryFloorMib = 1024
	instance.Spec.MemoryCeilingMib = 4096
	instance.Spec.MemoryFloorMaxMib = 4096
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "box"}}
	for i := range pods {
		pods[i].Spec.NodeName = node.Name
		pods[i].Spec.Containers = []corev1.Container{{
			Name:      kuraContainerName,
			Resources: corev1.ResourceRequirements{Requests: corev1.ResourceList{corev1.ResourceMemory: mibQuantity(1024)}},
		}}
		pods[i].Status.Conditions = []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}}
	}
	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(node).Build()}
	return r, instance, pods
}

func floorPoolReport(capacityMib, demandMib, timeouts uint64) runtimeStatus {
	capacity, demand := capacityMib*testMiB, demandMib*testMiB
	return runtimeStatus{
		Ready:                           true,
		BackfillInitialCycle:            backfillCycleComplete,
		FloorPoolCapacityBytes:          &capacity,
		FloorPoolRecentPeakDemandBytes:  &demand,
		FloorPoolAdmissionTimeoutsTotal: &timeouts,
	}
}

// observeBurst feeds a quiet pass that records the pods' counters, then a
// pass whose busiest replica has shed `timeouts` more requests while its
// demand peaked at demandMib.
func observeBurst(r *KuraInstanceReconciler, instance *kurav1alpha1.KuraInstance, pods []corev1.Pod, demandMib, timeouts uint64, now time.Time) {
	r.observeMemoryDemand(context.Background(), instance, pods, map[string]runtimeStatus{
		pods[0].Name: floorPoolReport(704, 40, 0),
		pods[1].Name: floorPoolReport(704, 40, 500),
	}, now)
	r.observeMemoryDemand(context.Background(), instance, pods, map[string]runtimeStatus{
		pods[0].Name: floorPoolReport(704, 40, 0),
		pods[1].Name: floorPoolReport(704, demandMib, 500+timeouts),
	}, now.Add(time.Minute))
}

func renderedMemoryMib(t *testing.T, instance *kurav1alpha1.KuraInstance) (int64, int64) {
	t.Helper()
	r := defaultResources(instance, false)
	return r.Requests.Memory().Value() / testMiB, r.Limits.Memory().Value() / testMiB
}

// The primary's pool (704 MiB of a 1024 MiB floor, so 320 MiB set aside)
// was asked for 1100 MiB. 320 + 1100 x 1.25 = 1695 MiB lands on the 2048
// band, and the ceiling rises by four times the raise so Kura's
// quarter-of-the-ceiling cap does not swallow it.
func TestMemoryFloorGrowsToAdmitTheBusiestReplicasDemand(t *testing.T) {
	r, instance, pods := memoryAutosizeFixture(t)

	observeBurst(r, instance, pods, 1100, memoryGrowthMinTimeouts, time.Now())

	floor, ceiling := renderedMemoryMib(t, instance)
	if floor != 2048 || ceiling != 8192 {
		t.Fatalf("rendered floor/ceiling = %d/%d MiB, want 2048/8192", floor, ceiling)
	}
}

// A pool that filled without anyone queueing is not short: headroom on top of
// a full-but-sufficient pool must not grow the floor.
func TestMemoryFloorHoldsWhenDemandNeverExceededThePool(t *testing.T) {
	r, instance, pods := memoryAutosizeFixture(t)
	samples := map[string]runtimeStatus{
		pods[0].Name: floorPoolReport(704, 704, 0),
		pods[1].Name: floorPoolReport(704, 600, 0),
	}

	r.observeMemoryDemand(context.Background(), instance, pods, samples, time.Now())

	if floor, ceiling := renderedMemoryMib(t, instance); floor != 1024 || ceiling != 4096 {
		t.Fatalf("rendered floor/ceiling = %d/%d MiB, want the plan's 1024/4096", floor, ceiling)
	}
}

func TestMemoryFloorIsBoundedByThePlanMaximum(t *testing.T) {
	r, instance, pods := memoryAutosizeFixture(t)
	instance.Spec.MemoryFloorMaxMib = 1536

	observeBurst(r, instance, pods, 3000, 1000, time.Now())

	if floor, ceiling := renderedMemoryMib(t, instance); floor != 1536 || ceiling != 6144 {
		t.Fatalf("rendered floor/ceiling = %d/%d MiB, want 1536/6144", floor, ceiling)
	}
}

// Without a maximum above the floor the feature is off, whatever status says,
// and turning it off drops the learned state.
func TestMemoryFloorStaysFixedWithoutAMaximum(t *testing.T) {
	r, instance, pods := memoryAutosizeFixture(t)
	instance.Spec.MemoryFloorMaxMib = 0
	instance.Status.MemoryAutosize = &kurav1alpha1.KuraInstanceMemoryAutosize{FloorMib: 4096}

	if floor, ceiling := renderedMemoryMib(t, instance); floor != 1024 || ceiling != 4096 {
		t.Fatalf("rendered floor/ceiling = %d/%d MiB, want the plan's 1024/4096", floor, ceiling)
	}
	samples := map[string]runtimeStatus{pods[0].Name: floorPoolReport(704, 3000, 0), pods[1].Name: floorPoolReport(704, 3000, 0)}
	r.observeMemoryDemand(context.Background(), instance, pods, samples, time.Now())
	if instance.Status.MemoryAutosize != nil {
		t.Fatalf("disabled autosizing kept state %+v", instance.Status.MemoryAutosize)
	}
}

// A release that predates the report is no reading, never zero demand; a
// pod without a published floor sizes its pool from the ceiling, so its
// report says nothing about the floor.
func TestMemoryObservationSkipsPodsThatCannotInformTheFloor(t *testing.T) {
	for _, scenario := range []string{"older release", "no published floor", "joining replica"} {
		t.Run(scenario, func(t *testing.T) {
			r, instance, pods := memoryAutosizeFixture(t)
			samples := map[string]runtimeStatus{}
			for i := range pods {
				switch scenario {
				case "older release":
					samples[pods[i].Name] = runtimeStatus{Ready: true, BackfillInitialCycle: backfillCycleComplete}
				case "no published floor":
					samples[pods[i].Name] = floorPoolReport(1536, 3000, 0)
				case "joining replica":
					samples[pods[i].Name] = floorPoolReport(704, 3000, 0)
				}
			}
			if scenario == "joining replica" {
				report := samples[pods[1].Name]
				report.BackfillInitialCycle = "pending"
				samples[pods[1].Name] = report
			}

			r.observeMemoryDemand(context.Background(), instance, pods, samples, time.Now())

			if state := instance.Status.MemoryAutosize; state != nil && len(state.BucketFloorsMib) > 0 {
				t.Fatalf("expected no observation, got %+v", state)
			}
		})
	}
}

// Growth is immediate; shrinkage waits for eight observed windows, and gaps
// do not count toward them.
func TestMemoryFloorShrinksOnlyAfterEnoughObservedHistory(t *testing.T) {
	start := time.Date(2026, 11, 24, 0, 0, 0, 0, time.UTC)
	quiet := memoryDemandSample{wantedMib: 900, floorMib: 2048}
	state := observeMemoryFloor(nil, memoryDemandSample{wantedMib: 1695, floorMib: 1024, timeouts: memoryGrowthMinTimeouts}, start)
	if state.FloorMib != 2048 {
		t.Fatalf("floor = %d MiB after a burst, want 2048 at once", state.FloorMib)
	}
	// Skip a day: unobserved windows are not evidence of a quiet instance.
	at := start.Add(24 * time.Hour)
	for window := 1; window < cpuShrinkMinBuckets; window++ {
		state = observeMemoryFloor(state, quiet, at)
		if state.FloorMib != 2048 {
			t.Fatalf("floor = %d MiB after %d observed windows, want it held", state.FloorMib, window+1)
		}
		at = at.Add(cpuBucketDuration)
	}
	// Seven quiet windows plus the burst make eight observed windows, but the
	// burst is still in the ring, so the floor holds until it ages out.
	for range cpuBucketCount {
		state = observeMemoryFloor(state, quiet, at)
		at = at.Add(cpuBucketDuration)
	}
	if state.FloorMib != 1024 {
		t.Fatalf("floor = %d MiB once the burst aged out, want the 1024 band", state.FloorMib)
	}
}

// A raise the box cannot fit leaves the replacement Pending, and a Pending pod
// reports nothing, so the cap is what lets the instance recover.
func TestMemoryScheduleCapBacksOffAnUnfittableRaise(t *testing.T) {
	_, instance, pods := memoryAutosizeFixture(t)
	instance.Status.MemoryAutosize = &kurav1alpha1.KuraInstanceMemoryAutosize{FloorMib: 3072}
	pods[1].Spec.NodeName = ""
	pods[1].Spec.Containers[0].Resources.Requests[corev1.ResourceMemory] = resource.MustParse("3Gi")
	pods[1].Status.Phase = corev1.PodPending
	pods[1].Status.Conditions = []corev1.PodCondition{{
		Type:    corev1.PodScheduled,
		Status:  corev1.ConditionFalse,
		Reason:  corev1.PodReasonUnschedulable,
		Message: "0/3 nodes are available: 3 Insufficient tuist.dev/memory-ceiling-mib.",
	}}

	applyMemoryScheduleCap(instance, pods, time.Now())

	// The sibling still runs at 1024 MiB on the box, which proves that fits.
	if floor, _ := renderedMemoryMib(t, instance); floor != 1024 {
		t.Fatalf("rendered floor = %d MiB, want it capped at the scheduled sibling's 1024", floor)
	}
	if instance.Status.MemoryAutosize.FloorMib != 3072 {
		t.Fatal("the observation itself should be untouched; only the cap bounds the template")
	}
}

// A few stray sheds are not a short floor: replayed against production, they
// would have raised three instances a full band for a week.
func TestMemoryFloorIgnoresAWindowWithFewSheds(t *testing.T) {
	r, instance, pods := memoryAutosizeFixture(t)

	observeBurst(r, instance, pods, 1100, memoryGrowthMinTimeouts-1, time.Now())

	if floor, ceiling := renderedMemoryMib(t, instance); floor != 1024 || ceiling != 4096 {
		t.Fatalf("rendered floor/ceiling = %d/%d MiB, want the plan's 1024/4096", floor, ceiling)
	}
}

// The window qualifies, not the pass: demand seen before the window reached
// the threshold still counts once it does, and a restarted pod's counter,
// which went down, counts from zero.
func TestMemoryFloorCountsTheWindowsShedsAcrossPassesAndRestarts(t *testing.T) {
	r, instance, pods := memoryAutosizeFixture(t)
	now := time.Date(2026, 11, 24, 15, 0, 0, 0, time.UTC)

	observeBurst(r, instance, pods, 1100, 4, now)
	if floor, _ := renderedMemoryMib(t, instance); floor != 1024 {
		t.Fatalf("rendered floor = %d MiB after 4 sheds, want the plan's 1024", floor)
	}
	r.observeMemoryDemand(context.Background(), instance, pods, map[string]runtimeStatus{
		pods[0].Name: floorPoolReport(704, 40, 0),
		pods[1].Name: floorPoolReport(704, 40, 6),
	}, now.Add(2*time.Minute))

	if floor, _ := renderedMemoryMib(t, instance); floor != 2048 {
		t.Fatalf("rendered floor = %d MiB once the window shed 10, want 2048", floor)
	}
}
