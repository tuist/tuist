package linux

import (
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/event"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

func ovhMachineForPredicate() *infrav1.OVHDedicatedMachine {
	return &infrav1.OVHDedicatedMachine{ObjectMeta: metav1.ObjectMeta{
		Name: "m", Namespace: "ns", Generation: 1,
		Labels:          map[string]string{"cluster.x-k8s.io/cluster-name": "c"},
		Annotations:     map[string]string{"a": "1"},
		Finalizers:      []string{OVHDedicatedMachineFinalizer},
		OwnerReferences: []metav1.OwnerReference{{Kind: "Machine", Name: "m", UID: "u"}},
	}}
}

// The reconcilers count a failed bootstrap in status and requeue after 30 s.
// Waking on that status write instead retried at once: a GRA box that refused
// the fleet key took 30,043 SSH logins in about 11 hours on 2026-10-05.
func TestOwnStatusWritesDoNotWakeTheReconciler(t *testing.T) {
	old := ovhMachineForPredicate()
	updated := old.DeepCopy()
	updated.Status.BootstrapAttempts = 1
	updated.Status.Phase = "Bootstrapping"
	updated.ResourceVersion = "2"
	if ignoreOwnStatusWrites().Update(event.UpdateEvent{ObjectOld: old, ObjectNew: updated}) {
		t.Fatal("a status-only update woke the reconciler")
	}
}

func TestEverythingButStatusStillWakesTheReconciler(t *testing.T) {
	for name, change := range map[string]func(*infrav1.OVHDedicatedMachine){
		"spec":             func(m *infrav1.OVHDedicatedMachine) { m.Generation = 2 },
		"label":            func(m *infrav1.OVHDedicatedMachine) { m.Labels["x"] = "y" },
		"annotation":       func(m *infrav1.OVHDedicatedMachine) { m.Annotations["cluster.x-k8s.io/paused"] = "" },
		"finalizer":        func(m *infrav1.OVHDedicatedMachine) { m.Finalizers = nil },
		"owner reference":  func(m *infrav1.OVHDedicatedMachine) { m.OwnerReferences = nil },
		"deletion started": func(m *infrav1.OVHDedicatedMachine) { now := metav1.Now(); m.DeletionTimestamp = &now },
	} {
		t.Run(name, func(t *testing.T) {
			old := ovhMachineForPredicate()
			updated := old.DeepCopy()
			change(updated)
			if !ignoreOwnStatusWrites().Update(event.UpdateEvent{ObjectOld: old, ObjectNew: updated}) {
				t.Fatalf("a %s change did not wake the reconciler", name)
			}
		})
	}
	if !ignoreOwnStatusWrites().Create(event.CreateEvent{Object: ovhMachineForPredicate()}) {
		t.Fatal("a create did not wake the reconciler")
	}
	if !ignoreOwnStatusWrites().Delete(event.DeleteEvent{Object: ovhMachineForPredicate()}) {
		t.Fatal("a delete did not wake the reconciler")
	}
}
