package controllers

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	apitypes "k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	k8sfake "k8s.io/client-go/kubernetes/fake"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

// makeHostForProviderFill builds a managed HBM CR with the
// labels + spec.status the reconciler reads (server-number
// label, provisioningState, consumerRef).
func makeHostForProviderFill(name, serverNumber, state, consumer string) *unstructured.Unstructured {
	obj := &unstructured.Unstructured{}
	obj.SetGroupVersionKind(hetznerBareMetalHostGVK)
	obj.SetName(name)
	obj.SetNamespace("org-tuist")
	labels := map[string]string{ManagedByLabel: ManagedByValue}
	if serverNumber != "" {
		labels[ServerNumberLabel] = serverNumber
	}
	obj.SetLabels(labels)
	if state != "" {
		_ = unstructured.SetNestedField(obj.Object, state, "spec", "status", "provisioningState")
	}
	if consumer != "" {
		_ = unstructured.SetNestedField(obj.Object, consumer, "spec", "consumerRef", "name")
	}
	return obj
}

// makeHBMM builds an HBMM CR with the cluster-name label the
// reconciler reads to find the workload kubeconfig.
func makeHBMM(name, clusterName string) *unstructured.Unstructured {
	obj := &unstructured.Unstructured{}
	obj.SetGroupVersionKind(hetznerBareMetalMachineGVK)
	obj.SetName(name)
	obj.SetNamespace("org-tuist")
	obj.SetLabels(map[string]string{
		"cluster.x-k8s.io/cluster-name": clusterName,
	})
	return obj
}

func makeKubeconfigSecret(clusterName string) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name:      clusterName + "-kubeconfig",
			Namespace: "org-tuist",
		},
		Data: map[string][]byte{"value": []byte("fake-kubeconfig-bytes")},
	}
}

func runReconciler(
	t *testing.T,
	hbm *unstructured.Unstructured,
	hbmm *unstructured.Unstructured,
	secret *corev1.Secret,
	workloadObjs ...runtime.Object,
) (kubernetes.Interface, ctrl.Result, error) {
	t.Helper()
	builder := fake.NewClientBuilder().WithObjects(hbm)
	if hbmm != nil {
		builder = builder.WithObjects(hbmm)
	}
	if secret != nil {
		builder = builder.WithObjects(secret)
	}
	cli := builder.Build()
	cs := k8sfake.NewSimpleClientset(workloadObjs...)
	r := &NodeProviderIDFillReconciler{
		Client: cli, Scheme: cli.Scheme(),
		workloadClientFor: func(_ []byte) (kubernetes.Interface, error) { return cs, nil },
	}
	res, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: apitypes.NamespacedName{Namespace: "org-tuist", Name: hbm.GetName()},
	})
	return cs, res, err
}

// nodeGotProviderID reads the Node back from the workload fake
// client and returns its providerID (empty string if missing).
func nodeGotProviderID(t *testing.T, cs kubernetes.Interface, name string) string {
	t.Helper()
	n, err := cs.CoreV1().Nodes().Get(context.Background(), name, metav1.GetOptions{})
	if err != nil {
		return ""
	}
	return n.Spec.ProviderID
}

func TestNodeProviderFill_PatchesEmptyProviderID(t *testing.T) {
	hbm := makeHostForProviderFill("bm-2986829", "2986829", "provisioned", "tuist-staging-runners-linux-v5bcr-gwn8x-7mhgg")
	hbmm := makeHBMM("tuist-staging-runners-linux-v5bcr-gwn8x-7mhgg", "tuist-staging")
	secret := makeKubeconfigSecret("tuist-staging")
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "bm-tuist-staging-runners-linux-v5bcr-gwn8x-7mhgg"},
		Spec:       corev1.NodeSpec{}, // empty providerID
	}

	cs, _, err := runReconciler(t, hbm, hbmm, secret, node)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if got := nodeGotProviderID(t, cs, node.Name); got != "hcloud://bm-2986829" {
		t.Errorf("providerID = %q, want %q", got, "hcloud://bm-2986829")
	}
}

func TestNodeProviderFill_LeavesExistingProviderIDAlone(t *testing.T) {
	hbm := makeHostForProviderFill("bm-1", "1", "provisioned", "tuist-staging-runners-linux-v5bcr-gwn8x-7mhgg")
	hbmm := makeHBMM("tuist-staging-runners-linux-v5bcr-gwn8x-7mhgg", "tuist-staging")
	secret := makeKubeconfigSecret("tuist-staging")
	// Different (or stale) value — reconciler must NOT overwrite.
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "bm-tuist-staging-runners-linux-v5bcr-gwn8x-7mhgg"},
		Spec:       corev1.NodeSpec{ProviderID: "hcloud://bm-9999"},
	}

	cs, _, err := runReconciler(t, hbm, hbmm, secret, node)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if got := nodeGotProviderID(t, cs, node.Name); got != "hcloud://bm-9999" {
		t.Errorf("providerID changed unexpectedly: got %q, want %q", got, "hcloud://bm-9999")
	}
}

func TestNodeProviderFill_FallsBackToBareHBMMNameIfPrefixedNotFound(t *testing.T) {
	hbm := makeHostForProviderFill("bm-1", "1", "provisioned", "consumer-x")
	hbmm := makeHBMM("consumer-x", "tuist-canary")
	secret := makeKubeconfigSecret("tuist-canary")
	// Node registered WITHOUT the `bm-` prefix — e.g. a future
	// caph release that drops the convention.
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "consumer-x"},
	}

	cs, _, err := runReconciler(t, hbm, hbmm, secret, node)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if got := nodeGotProviderID(t, cs, node.Name); got != "hcloud://bm-1" {
		t.Errorf("providerID = %q, want %q", got, "hcloud://bm-1")
	}
}

func TestNodeProviderFill_RequeuesWhenNodeNotYetJoined(t *testing.T) {
	hbm := makeHostForProviderFill("bm-1", "1", "provisioned", "consumer-x")
	hbmm := makeHBMM("consumer-x", "tuist-canary")
	secret := makeKubeconfigSecret("tuist-canary")
	// No workload Nodes — kubelet hasn't registered yet.

	_, res, err := runReconciler(t, hbm, hbmm, secret)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if res.RequeueAfter == 0 {
		t.Errorf("expected RequeueAfter > 0 when Node not joined, got %v", res.RequeueAfter)
	}
}

func TestNodeProviderFill_SkipsUntilProvisioned(t *testing.T) {
	// `image-installing` is mid-state — reconciler should no-op.
	hbm := makeHostForProviderFill("bm-1", "1", "image-installing", "consumer-x")
	hbmm := makeHBMM("consumer-x", "tuist-canary")
	secret := makeKubeconfigSecret("tuist-canary")
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "bm-consumer-x"},
	}

	cs, _, err := runReconciler(t, hbm, hbmm, secret, node)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if got := nodeGotProviderID(t, cs, "bm-consumer-x"); got != "" {
		t.Errorf("reconciler patched Node before HBM reached provisioned state: providerID=%q", got)
	}
}

func TestNodeProviderFill_SkipsWithoutConsumerRef(t *testing.T) {
	hbm := makeHostForProviderFill("bm-1", "1", "provisioned", "")
	// No HBMM, no Secret, no workload Node — reconciler shouldn't try.

	_, _, err := runReconciler(t, hbm, nil, nil)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
}

func TestNodeProviderFill_IgnoresHandAuthoredHBMs(t *testing.T) {
	// Same as the WWN reconciler — managed-by gate keeps us from
	// touching CRs an operator wrote by hand.
	obj := &unstructured.Unstructured{}
	obj.SetGroupVersionKind(hetznerBareMetalHostGVK)
	obj.SetName("hand-authored")
	obj.SetNamespace("org-tuist")
	// NO managed-by label.
	_ = unstructured.SetNestedField(obj.Object, "provisioned", "spec", "status", "provisioningState")
	_ = unstructured.SetNestedField(obj.Object, "consumer-x", "spec", "consumerRef", "name")

	hbmm := makeHBMM("consumer-x", "tuist-canary")
	secret := makeKubeconfigSecret("tuist-canary")
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "bm-consumer-x"}}

	cs, _, err := runReconciler(t, obj, hbmm, secret, node)
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if got := nodeGotProviderID(t, cs, "bm-consumer-x"); got != "" {
		t.Errorf("reconciler touched a hand-authored HBM's Node: providerID=%q", got)
	}
}
