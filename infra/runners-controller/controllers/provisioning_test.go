package controllers

import (
	"context"
	"testing"
	"time"

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
