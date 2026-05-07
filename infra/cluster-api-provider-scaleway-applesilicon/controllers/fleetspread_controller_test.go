package controllers

import (
	"context"
	"testing"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
)

func TestReadyFleetHash_StableAcrossReorderings(t *testing.T) {
	a := []infrav1.ScalewayAppleSiliconMachine{
		readyMachine("fleet-0"),
		readyMachine("fleet-1"),
	}
	b := []infrav1.ScalewayAppleSiliconMachine{
		readyMachine("fleet-1"),
		readyMachine("fleet-0"),
	}
	if readyFleetHash(a) != readyFleetHash(b) {
		t.Fatalf("hash should be order-independent: %q vs %q",
			readyFleetHash(a), readyFleetHash(b))
	}
}

func TestReadyFleetHash_ChangesWhenMembershipChanges(t *testing.T) {
	one := []infrav1.ScalewayAppleSiliconMachine{readyMachine("fleet-0")}
	two := []infrav1.ScalewayAppleSiliconMachine{readyMachine("fleet-0"), readyMachine("fleet-1")}
	if readyFleetHash(one) == readyFleetHash(two) {
		t.Fatal("hash must distinguish {fleet-0} from {fleet-0, fleet-1}")
	}
}

func TestReadyFleetHash_ExcludesNonReady(t *testing.T) {
	mixed := []infrav1.ScalewayAppleSiliconMachine{
		readyMachine("fleet-0"),
		machineWithPhase("fleet-1", "Provisioning"),
	}
	onlyReady := []infrav1.ScalewayAppleSiliconMachine{readyMachine("fleet-0")}
	if readyFleetHash(mixed) != readyFleetHash(onlyReady) {
		t.Fatal("non-Ready machines must not contribute to the hash")
	}
}

func TestReadyFleetHash_ExcludesMachinesPendingDeletion(t *testing.T) {
	now := metav1.Now()
	terminating := readyMachine("fleet-1")
	terminating.DeletionTimestamp = &now
	terminating.Finalizers = []string{"hold"}

	withTerminating := []infrav1.ScalewayAppleSiliconMachine{
		readyMachine("fleet-0"),
		terminating,
	}
	onlyAlive := []infrav1.ScalewayAppleSiliconMachine{readyMachine("fleet-0")}
	if readyFleetHash(withTerminating) != readyFleetHash(onlyAlive) {
		t.Fatal("terminating machines should drop out of the hash immediately, not after finalizer clears")
	}
}

// TestReconcile_StampsAnnotationOnFirstReady locks in the headline
// behaviour: when fleet-0 transitions Ready, the Deployment gets a
// fresh fleet-hash annotation. Without it, helm-managed workloads
// like xcresult-processor never rebalance after fleet additions.
func TestReconcile_StampsAnnotationOnFirstReady(t *testing.T) {
	ready := readyMachine("fleet-0")
	dep := emptyDeployment("xcresult-processor", "tuist")

	r, ctx := newFleetSpreadReconciler(t, "tuist", "xcresult-processor", &ready, &dep)

	if _, err := r.Reconcile(ctx, ctrl.Request{}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := getAnnotation(t, r, "tuist", "xcresult-processor")
	if got == "" {
		t.Fatal("annotation not stamped on first reconcile with a Ready machine")
	}
}

// TestReconcile_NoOpWhenHashMatches locks in idempotence so we don't
// churn ReplicaSets every reconcile pass in steady state.
func TestReconcile_NoOpWhenHashMatches(t *testing.T) {
	ready := readyMachine("fleet-0")
	dep := emptyDeployment("xcresult-processor", "tuist")
	dep.Spec.Template.Annotations = map[string]string{
		FleetHashAnnotation: readyFleetHash([]infrav1.ScalewayAppleSiliconMachine{ready}),
	}

	r, ctx := newFleetSpreadReconciler(t, "tuist", "xcresult-processor", &ready, &dep)

	// fake client assigns ResourceVersion on store; capture the
	// post-store value as the baseline. Patch would bump it, so RV
	// stability across Reconcile proves we short-circuited.
	var before appsv1.Deployment
	if err := r.Get(ctx, types.NamespacedName{Namespace: "tuist", Name: "xcresult-processor"}, &before); err != nil {
		t.Fatal(err)
	}

	if _, err := r.Reconcile(ctx, ctrl.Request{}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	var after appsv1.Deployment
	if err := r.Get(ctx, types.NamespacedName{Namespace: "tuist", Name: "xcresult-processor"}, &after); err != nil {
		t.Fatal(err)
	}
	if after.ResourceVersion != before.ResourceVersion {
		t.Fatalf("expected no patch on stable hash, RV %q -> %q", before.ResourceVersion, after.ResourceVersion)
	}
}

// TestReconcile_RepatchesOnFleetGrowth covers the production case
// this PR is for: fleet-1 joins, hash changes, deployment annotation
// changes, k8s rolls a new ReplicaSet, topology spread distributes
// pods across the now-two hosts.
func TestReconcile_RepatchesOnFleetGrowth(t *testing.T) {
	m0 := readyMachine("fleet-0")
	m1 := readyMachine("fleet-1")
	dep := emptyDeployment("xcresult-processor", "tuist")
	dep.Spec.Template.Annotations = map[string]string{
		FleetHashAnnotation: readyFleetHash([]infrav1.ScalewayAppleSiliconMachine{m0}),
	}

	r, ctx := newFleetSpreadReconciler(t, "tuist", "xcresult-processor", &m0, &m1, &dep)

	if _, err := r.Reconcile(ctx, ctrl.Request{}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := getAnnotation(t, r, "tuist", "xcresult-processor")
	want := readyFleetHash([]infrav1.ScalewayAppleSiliconMachine{m0, m1})
	if got != want {
		t.Fatalf("hash not updated on fleet growth: got %q, want %q", got, want)
	}
}

// TestReconcile_NoOpWhenDeploymentMissing covers the chart-bring-up
// race: the operator can win leadership and reconcile before helm
// has installed the workload Deployment. The reconciler must not
// error in that window — the next machine event will retry.
func TestReconcile_NoOpWhenDeploymentMissing(t *testing.T) {
	ready := readyMachine("fleet-0")

	r, ctx := newFleetSpreadReconciler(t, "tuist", "xcresult-processor", &ready)

	if _, err := r.Reconcile(ctx, ctrl.Request{}); err != nil {
		t.Fatalf("reconcile must tolerate missing deployment, got %v", err)
	}
}

// === helpers ================================================================

func readyMachine(name string) infrav1.ScalewayAppleSiliconMachine {
	return machineWithPhase(name, "Ready")
}

func machineWithPhase(name, phase string) infrav1.ScalewayAppleSiliconMachine {
	return infrav1.ScalewayAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: "tuist",
		},
		Status: infrav1.ScalewayAppleSiliconMachineStatus{
			Phase: phase,
		},
	}
}

func emptyDeployment(name, namespace string) appsv1.Deployment {
	return appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
		},
		Spec: appsv1.DeploymentSpec{
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{},
			},
		},
	}
}

func newFleetSpreadReconciler(t *testing.T, namespace, deployment string, objs ...client.Object) (*FleetSpreadReconciler, context.Context) {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := appsv1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	cli := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	r := &FleetSpreadReconciler{
		Client:         cli,
		DeploymentName: deployment,
		Namespace:      namespace,
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	return r, ctx
}

func getAnnotation(t *testing.T, r *FleetSpreadReconciler, namespace, name string) string {
	t.Helper()
	var dep appsv1.Deployment
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: namespace, Name: name}, &dep); err != nil {
		t.Fatal(err)
	}
	return dep.Spec.Template.Annotations[FleetHashAnnotation]
}
