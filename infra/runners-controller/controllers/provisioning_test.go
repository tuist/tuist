package controllers

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
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
	if admission.cap != 2 || admission.available != 2 {
		t.Fatalf("admission = %+v, want sibling minimum cap and availability 2", admission)
	}
}

func TestProvisioningAdmissionIgnoresUnschedulableSiblingPods(t *testing.T) {
	scheme := mustScheme(t)
	poolA := newLinuxKataPool("linux-a", 8, 2)
	poolB := newLinuxKataPool("linux-b", 8, 2)
	node := readyLinuxRunnerNode("runner-node", poolA.Spec.FleetSelector)
	// Sibling Pods the scheduler rejected: no node has memory for their
	// shape. They must not consume poolA's fleet budget.
	stuckB1 := unschedulableRunnerPod("linux-b-runner-1", poolB.Name)
	stuckB2 := unschedulableRunnerPod("linux-b-runner-2", poolB.Name)
	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(poolA, poolB, node, stuckB1, stuckB2).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), poolA)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.blockedReason != "" || admission.available != 2 {
		t.Fatalf("admission = %+v, want unblocked with availability 2", admission)
	}
	if admission.pendingForFleet != 0 {
		t.Fatalf("pendingForFleet = %d, want unschedulable siblings excluded", admission.pendingForFleet)
	}
}

func TestProvisioningAdmissionCountsScheduledSiblingPodsAgainstFleetCap(t *testing.T) {
	scheme := mustScheme(t)
	poolA := newLinuxKataPool("linux-a", 8, 2)
	poolB := newLinuxKataPool("linux-b", 8, 2)
	node := readyLinuxRunnerNode("runner-node", poolA.Spec.FleetSelector)
	bootingB1 := newRunnerPod("linux-b-runner-1", "img", corev1.PodPending, poolB.Name)
	bootingB1.Spec.NodeName = node.Name
	bootingB2 := newRunnerPod("linux-b-runner-2", "img", corev1.PodPending, poolB.Name)
	bootingB2.Spec.NodeName = node.Name
	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(poolA, poolB, node, bootingB1, bootingB2).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), poolA)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.blockedReason != "fleet_cap" || admission.available != 0 {
		t.Fatalf("admission = %+v, want fleet_cap with no availability", admission)
	}
}

func TestProvisioningAdmissionBoundsOwnUnschedulableBacklog(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 8, 2)
	node := readyLinuxRunnerNode("runner-node", pool.Spec.FleetSelector)
	stuck1 := unschedulableRunnerPod("linux-a-runner-1", pool.Name)
	stuck2 := unschedulableRunnerPod("linux-a-runner-2", pool.Name)
	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(pool, node, stuck1, stuck2).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.blockedReason != "pool_unschedulable" || admission.available != 0 {
		t.Fatalf("admission = %+v, want pool_unschedulable with no availability", admission)
	}
}

func unschedulableRunnerPod(name, poolName string) *corev1.Pod {
	pod := newRunnerPod(name, "img", corev1.PodPending, poolName)
	pod.Status.Conditions = []corev1.PodCondition{{
		Type:   corev1.PodScheduled,
		Status: corev1.ConditionFalse,
		Reason: corev1.PodReasonUnschedulable,
	}}
	return pod
}
