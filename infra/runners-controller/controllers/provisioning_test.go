package controllers

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestCreationReservationStoreReleasesObservedPod(t *testing.T) {
	now := time.Unix(1000, 0)
	store := creationReservationStore{}
	store.add("tuist-runners", "runner-a", "linux", "runners-linux", now)

	total, _ := store.reconcile("tuist-runners", "runners-linux", map[string]struct{}{
		"tuist-runners/runner-a": {},
	}, now)
	if total != 0 {
		t.Fatalf("observed reservation count = %d, want 0", total)
	}
	if len(store.byName) != 0 {
		t.Fatalf("observed reservation remained in store: %+v", store.byName)
	}
}

func TestCreationReservationStoreExpiresUnobservedPod(t *testing.T) {
	now := time.Unix(1000, 0)
	store := creationReservationStore{}
	store.add("tuist-runners", "runner-a", "linux", "runners-linux", now)

	total, _ := store.reconcile(
		"tuist-runners",
		"runners-linux",
		map[string]struct{}{},
		now.Add(creationReservationLifetime),
	)
	if total != 0 {
		t.Fatalf("expired reservation count = %d, want 0", total)
	}
	if len(store.byName) != 0 {
		t.Fatalf("expired reservation remained in store: %+v", store.byName)
	}
}

func TestProvisioningAdmissionUsesLowestSiblingCap(t *testing.T) {
	scheme := mustScheme(t)
	poolA := newLinuxKataPool("linux-a", 8, 4)
	poolB := newLinuxKataPool("linux-b", 8, 2)
	node := readyLinuxRunnerNode("runner-node", poolA.Spec.FleetSelector)
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(poolA, poolB, node).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), poolA)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	// The sibling also has a gap and nothing provisioning, so one of the two
	// slots is reserved for it: the ceiling is the sibling minimum, the share
	// is what this pool may take of it.
	if admission.cap != 2 || admission.poolCap != 1 || admission.available != 1 {
		t.Fatalf("admission = %+v, want sibling minimum cap 2 and a share of 1", admission)
	}
}

func TestProvisioningAdmissionCountsUnschedulableSiblingPodsAgainstFleetCap(t *testing.T) {
	scheme := mustScheme(t)
	poolA := newLinuxKataPool("linux-a", 8, 2)
	poolB := newLinuxKataPool("linux-b", 8, 2)
	node := readyLinuxRunnerNode("runner-node", poolA.Spec.FleetSelector)
	// Unschedulable Pods still hold the ceiling: the scheduler may bind
	// them the moment capacity returns, with no admission check between.
	stuckB1 := unschedulableRunnerPod("linux-b-runner-1", poolB.Name, time.Unix(1000, 0))
	stuckB2 := unschedulableRunnerPod("linux-b-runner-2", poolB.Name, time.Unix(1000, 0))
	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(poolA, poolB, node, stuckB1, stuckB2).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), poolA)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.blockedReason != "fleet_cap" || admission.available != 0 {
		t.Fatalf("admission = %+v, want fleet_cap with no availability", admission)
	}
}

// The starvation this guards against: an unschedulable Pod is never reaped by
// the bound-Pod start timeout, because that clock only starts at node binding.
func TestUnschedulableTimedOutReleasesSlotOnlyAfterTimeout(t *testing.T) {
	pool := newLinuxKataPool("linux-a", 8, 2)
	rejectedAt := time.Unix(1000, 0)
	pod := unschedulableRunnerPod("linux-a-runner-1", pool.Name, rejectedAt)
	timeout := time.Duration(pool.Spec.Provisioning.StartTimeoutSecondsOrDefault()) * time.Second

	if startTimedOut(pod, pool, rejectedAt.Add(timeout)) {
		t.Fatal("bound-Pod start timeout fired on a Pod with no node")
	}
	if unschedulableTimedOut(pod, pool, rejectedAt.Add(timeout-time.Second)) {
		t.Fatal("unschedulable reap fired before the timeout elapsed")
	}
	if !unschedulableTimedOut(pod, pool, rejectedAt.Add(timeout)) {
		t.Fatal("unschedulable reap did not fire after the timeout elapsed")
	}
}

// A Pod the scheduler rejected and then placed is booting a sandbox like any
// other, so it must keep its slot rather than be reaped out from under itself.
func TestUnschedulableTimedOutIgnoresPodThatLaterScheduled(t *testing.T) {
	pool := newLinuxKataPool("linux-a", 8, 2)
	rejectedAt := time.Unix(1000, 0)
	pod := unschedulableRunnerPod("linux-a-runner-1", pool.Name, rejectedAt)
	// Capacity returned: the scheduler bound it and cleared the condition.
	pod.Spec.NodeName = "runner-node"
	pod.Status.Conditions = []corev1.PodCondition{{
		Type:               corev1.PodScheduled,
		Status:             corev1.ConditionTrue,
		LastTransitionTime: metav1.NewTime(rejectedAt.Add(time.Hour)),
	}}

	if unschedulableTimedOut(pod, pool, rejectedAt.Add(2*time.Hour)) {
		t.Fatal("reaped a Pod that the scheduler subsequently placed")
	}
}

// Capacity returning must not release a burst larger than the ceiling. The
// Pods that were unschedulable are exactly the ones the scheduler binds first,
// so the count that gates creation has to include them the whole time.
func TestProvisioningAdmissionHoldsCapAsUnschedulablePodsBecomeSchedulable(t *testing.T) {
	scheme := mustScheme(t)
	poolA := newLinuxKataPool("linux-a", 8, 2)
	poolB := newLinuxKataPool("linux-b", 8, 2)
	node := readyLinuxRunnerNode("runner-node", poolB.Spec.FleetSelector)
	bound := unschedulableRunnerPod("linux-b-runner-1", poolB.Name, time.Unix(1000, 0))
	bound.Spec.NodeName = node.Name
	bound.Status.Conditions = []corev1.PodCondition{{
		Type:   corev1.PodScheduled,
		Status: corev1.ConditionTrue,
	}}
	stillStuck := unschedulableRunnerPod("linux-b-runner-2", poolB.Name, time.Unix(1000, 0))
	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(poolA, poolB, node, bound, stillStuck).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), poolA)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.pendingForFleet != 2 {
		t.Fatalf("pendingForFleet = %d, want both the newly bound and the still-stuck Pod", admission.pendingForFleet)
	}
	if admission.blockedReason != "fleet_cap" || admission.available != 0 {
		t.Fatalf("admission = %+v, want the ceiling held across the transition", admission)
	}
}

// The starvation seen on 2026-09-02: one shape holds the entire fleet ceiling
// with Pods no node can seat, and every sibling with a replica gap is refused
// creation for as long as the shortfall lasts. The fleet ceiling still holds
// (burst guarantee), but the hog's own share shrinks by one per sibling that
// has a gap and nothing provisioning, so it may not top the count back up
// after unschedulableTimedOut reaps one of its Pods.
func TestProvisioningAdmissionHogCannotRecreateAfterReapWhileSiblingStarves(t *testing.T) {
	scheme := mustScheme(t)
	hog := newLinuxKataPool("linux-big", 8, 4)
	starved := newLinuxKataPool("linux-small", 8, 4)
	node := readyLinuxRunnerNode("runner-node", hog.Spec.FleetSelector)
	// After the reap: three of the hog's four parked Pods remain, so the fleet
	// count (3) is under the ceiling (4) and the freed slot is up for grabs.
	stuck := []*corev1.Pod{
		unschedulableRunnerPod("linux-big-runner-1", hog.Name, time.Unix(1000, 0)),
		unschedulableRunnerPod("linux-big-runner-2", hog.Name, time.Unix(1000, 0)),
		unschedulableRunnerPod("linux-big-runner-3", hog.Name, time.Unix(1000, 0)),
	}
	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(hog, starved, node, stuck[0], stuck[1], stuck[2]).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	hogAdmission, err := r.provisioningAdmission(context.Background(), hog)
	if err != nil {
		t.Fatalf("provisioningAdmission(hog): %v", err)
	}
	if hogAdmission.poolCap != 3 || hogAdmission.blockedReason != "pool_share" || hogAdmission.available != 0 {
		t.Fatalf("hog admission = %+v, want share 3 (cap 4 minus one starved sibling) and no availability", hogAdmission)
	}

	starvedAdmission, err := r.provisioningAdmission(context.Background(), starved)
	if err != nil {
		t.Fatalf("provisioningAdmission(starved): %v", err)
	}
	if starvedAdmission.blockedReason != "" || starvedAdmission.available != 1 {
		t.Fatalf("starved admission = %+v, want the freed slot", starvedAdmission)
	}
}

// A pool's share only shrinks for siblings that actually need a slot: one with
// no replica gap, or one already provisioning something, takes nothing away.
func TestProvisioningAdmissionShareIgnoresSiblingsWithoutAGap(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 8, 4)
	satisfied := newLinuxKataPool("linux-b", 0, 4)
	provisioning := newLinuxKataPool("linux-c", 8, 4)
	node := readyLinuxRunnerNode("runner-node", pool.Spec.FleetSelector)
	cPending := unschedulableRunnerPod("linux-c-runner-1", provisioning.Name, time.Unix(1000, 0))
	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(pool, satisfied, provisioning, node, cPending).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.poolCap != 4 {
		t.Fatalf("poolCap = %d, want the full cap: no sibling both has a gap and holds nothing", admission.poolCap)
	}
	if admission.available != 3 {
		t.Fatalf("available = %d, want cap 4 minus the one sibling Pod already provisioning", admission.available)
	}
}

// The share never drops below one, so a pool surrounded by starving siblings
// can still make progress rather than deadlocking the fleet.
func TestProvisioningAdmissionShareFloorsAtOne(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 8, 2)
	objs := []client.Object{pool, readyLinuxRunnerNode("runner-node", pool.Spec.FleetSelector)}
	for _, name := range []string{"linux-b", "linux-c", "linux-d"} {
		objs = append(objs, newLinuxKataPool(name, 8, 2))
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.poolCap != 1 || admission.available != 1 {
		t.Fatalf("admission = %+v, want a share floored at one", admission)
	}
}

func unschedulableRunnerPod(name, poolName string, rejectedAt time.Time) *corev1.Pod {
	pod := newRunnerPod(name, "img", corev1.PodPending, poolName)
	pod.Status.Conditions = []corev1.PodCondition{{
		Type:               corev1.PodScheduled,
		Status:             corev1.ConditionFalse,
		Reason:             corev1.PodReasonUnschedulable,
		LastTransitionTime: metav1.NewTime(rejectedAt),
	}}
	return pod
}
