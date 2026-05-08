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
)

func TestReadyNodeHash_StableAcrossReorderings(t *testing.T) {
	a := []corev1.Node{readyNode("fleet-0"), readyNode("fleet-1")}
	b := []corev1.Node{readyNode("fleet-1"), readyNode("fleet-0")}
	if readyNodeHash(a) != readyNodeHash(b) {
		t.Fatalf("hash should be order-independent: %q vs %q",
			readyNodeHash(a), readyNodeHash(b))
	}
}

func TestReadyNodeHash_ChangesWhenMembershipChanges(t *testing.T) {
	one := []corev1.Node{readyNode("fleet-0")}
	two := []corev1.Node{readyNode("fleet-0"), readyNode("fleet-1")}
	if readyNodeHash(one) == readyNodeHash(two) {
		t.Fatal("hash must distinguish {fleet-0} from {fleet-0, fleet-1}")
	}
}

// TestReadyNodeHash_ExcludesNotReady is the key invariant the P2
// review caught: a Mac mini whose ScalewayAppleSiliconMachine has
// flipped to Phase=Ready can still have a NotReady kube Node (tart-
// kubelet's first heartbeat hasn't landed). Hashing on Phase would
// roll the Deployment too early — Pods can't schedule onto a
// NotReady Node, so they bounce back to the old host and the
// imbalance recurs. Source-of-truth must be Node Ready.
func TestReadyNodeHash_ExcludesNotReady(t *testing.T) {
	mixed := []corev1.Node{
		readyNode("fleet-0"),
		nodeWithReady("fleet-1", corev1.ConditionFalse),
	}
	onlyReady := []corev1.Node{readyNode("fleet-0")}
	if readyNodeHash(mixed) != readyNodeHash(onlyReady) {
		t.Fatal("NotReady Nodes must not contribute to the hash")
	}
}

// TestReadyNodeHash_ExcludesNodesWithoutReadyCondition covers the
// brand-new-Node window before kubelet has reported any conditions
// at all. Same logic as NotReady — Pods can't schedule there.
func TestReadyNodeHash_ExcludesNodesWithoutReadyCondition(t *testing.T) {
	mixed := []corev1.Node{
		readyNode("fleet-0"),
		{ObjectMeta: metav1.ObjectMeta{Name: "fleet-1"}},
	}
	onlyReady := []corev1.Node{readyNode("fleet-0")}
	if readyNodeHash(mixed) != readyNodeHash(onlyReady) {
		t.Fatal("Nodes without a Ready condition must not contribute to the hash")
	}
}

func TestReadyNodeHash_ExcludesNodesPendingDeletion(t *testing.T) {
	now := metav1.Now()
	terminating := readyNode("fleet-1")
	terminating.DeletionTimestamp = &now
	terminating.Finalizers = []string{"hold"}

	withTerminating := []corev1.Node{readyNode("fleet-0"), terminating}
	onlyAlive := []corev1.Node{readyNode("fleet-0")}
	if readyNodeHash(withTerminating) != readyNodeHash(onlyAlive) {
		t.Fatal("terminating Nodes should drop out of the hash immediately")
	}
}

// TestReconcile_StampsAnnotationOnFirstReady locks in the headline
// behaviour: when fleet-0's Node transitions Ready, the Deployment
// gets a fresh fleet-hash annotation. Without it, helm-managed
// workloads like xcresult-processor never rebalance after fleet
// additions.
func TestReconcile_StampsAnnotationOnFirstReady(t *testing.T) {
	node := readyNode("fleet-0")
	dep := emptyDeployment("xcresult-processor", "tuist")

	r, ctx := newFleetSpreadReconciler(t, "tuist", "xcresult-processor", &node, &dep)

	if _, err := r.Reconcile(ctx, ctrl.Request{}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := getAnnotation(t, r, "tuist", "xcresult-processor")
	if got == "" {
		t.Fatal("annotation not stamped on first reconcile with a Ready Node")
	}
}

// TestReconcile_NoOpWhenHashMatches locks in idempotence so we don't
// churn ReplicaSets every reconcile pass in steady state.
func TestReconcile_NoOpWhenHashMatches(t *testing.T) {
	node := readyNode("fleet-0")
	dep := emptyDeployment("xcresult-processor", "tuist")
	dep.Spec.Template.Annotations = map[string]string{
		FleetHashAnnotation: readyNodeHash([]corev1.Node{node}),
	}

	r, ctx := newFleetSpreadReconciler(t, "tuist", "xcresult-processor", &node, &dep)

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
// this PR is for: fleet-1's Node joins as Ready, hash changes,
// deployment annotation changes, k8s rolls a new ReplicaSet,
// topology spread distributes pods across the now-two hosts.
func TestReconcile_RepatchesOnFleetGrowth(t *testing.T) {
	n0 := readyNode("fleet-0")
	n1 := readyNode("fleet-1")
	dep := emptyDeployment("xcresult-processor", "tuist")
	dep.Spec.Template.Annotations = map[string]string{
		FleetHashAnnotation: readyNodeHash([]corev1.Node{n0}),
	}

	r, ctx := newFleetSpreadReconciler(t, "tuist", "xcresult-processor", &n0, &n1, &dep)

	if _, err := r.Reconcile(ctx, ctrl.Request{}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := getAnnotation(t, r, "tuist", "xcresult-processor")
	want := readyNodeHash([]corev1.Node{n0, n1})
	if got != want {
		t.Fatalf("hash not updated on fleet growth: got %q, want %q", got, want)
	}
}

// TestReconcile_DoesNotRollOnPhaseReadyBeforeNodeReady is the P2
// regression test. A new Mac mini whose ScalewayAppleSiliconMachine
// has Phase=Ready but whose kube Node hasn't reported NodeReady yet
// must NOT contribute to the hash — otherwise we roll into a
// scheduling cul-de-sac. Verify by setting up a NotReady Node with
// the right labels and asserting the hash matches "only the Ready
// Node" state.
func TestReconcile_DoesNotRollOnPhaseReadyBeforeNodeReady(t *testing.T) {
	readyOnly := readyNode("fleet-0")
	notYet := nodeWithReady("fleet-1", corev1.ConditionFalse)

	dep := emptyDeployment("xcresult-processor", "tuist")
	dep.Spec.Template.Annotations = map[string]string{
		FleetHashAnnotation: readyNodeHash([]corev1.Node{readyOnly}),
	}

	r, ctx := newFleetSpreadReconciler(t, "tuist", "xcresult-processor", &readyOnly, &notYet, &dep)

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
		t.Fatalf("expected no patch while fleet-1 Node is NotReady, RV %q -> %q",
			before.ResourceVersion, after.ResourceVersion)
	}
}

// TestReconcile_NoOpWhenDeploymentMissing covers the chart-bring-up
// race: the operator can win leadership and reconcile before helm
// has installed the workload Deployment. The reconciler must not
// error in that window — the next Node event will retry.
func TestReconcile_NoOpWhenDeploymentMissing(t *testing.T) {
	node := readyNode("fleet-0")

	r, ctx := newFleetSpreadReconciler(t, "tuist", "xcresult-processor", &node)

	if _, err := r.Reconcile(ctx, ctrl.Request{}); err != nil {
		t.Fatalf("reconcile must tolerate missing deployment, got %v", err)
	}
}

// === helpers ================================================================

func readyNode(name string) corev1.Node {
	return nodeWithReady(name, corev1.ConditionTrue)
}

// nodeWithReady builds a Node carrying the same labels the chart's
// xcresult-processor selects on, so it matches FleetNodeSelector.
func nodeWithReady(name string, ready corev1.ConditionStatus) corev1.Node {
	return corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Name: name,
			Labels: map[string]string{
				"kubernetes.io/os":  "darwin",
				"tuist.dev/runtime": "tart",
			},
		},
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{{
				Type:   corev1.NodeReady,
				Status: ready,
			}},
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
	if err := corev1.AddToScheme(scheme); err != nil {
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
