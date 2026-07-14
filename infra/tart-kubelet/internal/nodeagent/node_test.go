package nodeagent

import (
	"context"
	"errors"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func newNodeFakeClient(objs ...client.Object) client.Client {
	scheme := runtime.NewScheme()
	_ = corev1.AddToScheme(scheme)
	return fake.NewClientBuilder().
		WithScheme(scheme).
		WithStatusSubresource(&corev1.Node{}).
		WithObjects(objs...).
		Build()
}

func nodeProviderID(t *testing.T, c client.Client, name string) string {
	t.Helper()
	node := &corev1.Node{}
	if err := c.Get(context.Background(), types.NamespacedName{Name: name}, node); err != nil {
		t.Fatalf("get node: %v", err)
	}
	return node.Spec.ProviderID
}

func TestEnsureNodeSetsProviderIDOnCreate(t *testing.T) {
	c := newNodeFakeClient()
	m := &Maintainer{Client: c, NodeName: "mac-1", ProviderID: "scw-applesilicon://fr-par-1/abc", Heartbeat: time.Second}
	if err := m.ensureNode(context.Background()); err != nil {
		t.Fatalf("ensureNode: %v", err)
	}
	if got := nodeProviderID(t, c, "mac-1"); got != "scw-applesilicon://fr-par-1/abc" {
		t.Fatalf("providerID = %q, want it set on create", got)
	}
}

func TestEnsureNodePatchesEmptyProviderID(t *testing.T) {
	existing := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "mac-1"}}
	c := newNodeFakeClient(existing)
	m := &Maintainer{Client: c, NodeName: "mac-1", ProviderID: "scw-applesilicon://fr-par-1/abc", Heartbeat: time.Second}
	if err := m.ensureNode(context.Background()); err != nil {
		t.Fatalf("ensureNode: %v", err)
	}
	if got := nodeProviderID(t, c, "mac-1"); got != "scw-applesilicon://fr-par-1/abc" {
		t.Fatalf("providerID = %q, want it patched onto a node registered without one", got)
	}
}

func TestEnsureNodeDoesNotOverwriteExistingProviderID(t *testing.T) {
	existing := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "mac-1"},
		Spec:       corev1.NodeSpec{ProviderID: "scw-applesilicon://fr-par-1/original"},
	}
	c := newNodeFakeClient(existing)
	m := &Maintainer{Client: c, NodeName: "mac-1", ProviderID: "scw-applesilicon://fr-par-1/different", Heartbeat: time.Second}
	if err := m.ensureNode(context.Background()); err != nil {
		t.Fatalf("ensureNode: %v", err)
	}
	if got := nodeProviderID(t, c, "mac-1"); got != "scw-applesilicon://fr-par-1/original" {
		t.Fatalf("providerID = %q, want the original left untouched (immutable)", got)
	}
}

// Regression guard for the golden-affinity no-op: refresh() must persist
// dynamic labels to the API server, not just mutate the in-memory Node.
// Status().Update writes only the status subresource (the fake client honors
// that split via WithStatusSubresource), so without the metadata patch the
// `tuist.dev/golden-*` labels never reach etcd and the controller's
// node-affinity matches nothing.
func TestRefreshPersistsDynamicLabels(t *testing.T) {
	const goldenKey = "tuist.dev/golden-9c8af651fdf30b10"
	c := newNodeFakeClient(&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "mac-1"}})
	m := &Maintainer{
		Client:    c,
		NodeName:  "mac-1",
		Heartbeat: time.Second,
		DynamicLabels: func(context.Context) (map[string]string, error) {
			return map[string]string{goldenKey: "true"}, nil
		},
	}

	if err := m.refresh(context.Background()); err != nil {
		t.Fatalf("refresh: %v", err)
	}

	persisted := &corev1.Node{}
	if err := c.Get(context.Background(), types.NamespacedName{Name: "mac-1"}, persisted); err != nil {
		t.Fatalf("get node: %v", err)
	}
	if got := persisted.Labels[goldenKey]; got != "true" {
		t.Fatalf("golden label not persisted to the API server: labels=%v", persisted.Labels)
	}

	// A later heartbeat that no longer advertises the golden must prune it
	// from the persisted Node (merge patch deletes via null), not just in
	// memory.
	m.DynamicLabels = func(context.Context) (map[string]string, error) { return nil, nil }
	if err := m.refresh(context.Background()); err != nil {
		t.Fatalf("refresh (prune): %v", err)
	}
	persisted = &corev1.Node{}
	if err := c.Get(context.Background(), types.NamespacedName{Name: "mac-1"}, persisted); err != nil {
		t.Fatalf("get node: %v", err)
	}
	if _, present := persisted.Labels[goldenKey]; present {
		t.Fatalf("stale golden label not pruned from persisted node: labels=%v", persisted.Labels)
	}
}

// Regression for nodes stranded in Unknown: once the node-lifecycle
// controller flips Ready to Unknown (after a heartbeat gap, e.g. a kubelet
// restart), a heartbeat must lift the node back to Ready=True. The bug:
// client.Patch overwrote the in-memory node.Status (our freshly-set
// Ready=True) with the server's Unknown before Status().Update, so the
// heartbeat only re-posted Unknown and the node never recovered.
func TestRefreshLiftsNodeOutOfUnknown(t *testing.T) {
	existing := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "mac-1"},
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{{
				Type:    corev1.NodeReady,
				Status:  corev1.ConditionUnknown,
				Reason:  "NodeStatusUnknown",
				Message: "Kubelet stopped posting node status.",
			}},
		},
	}
	c := newNodeFakeClient(existing)
	m := &Maintainer{Client: c, NodeName: "mac-1", Heartbeat: time.Second}

	if err := m.refresh(context.Background()); err != nil {
		t.Fatalf("refresh: %v", err)
	}

	persisted := &corev1.Node{}
	if err := c.Get(context.Background(), types.NamespacedName{Name: "mac-1"}, persisted); err != nil {
		t.Fatalf("get node: %v", err)
	}
	cond, ok := conditionByType(persisted.Status.Conditions, corev1.NodeReady)
	if !ok {
		t.Fatal("Ready condition missing after refresh")
	}
	if cond.Status != corev1.ConditionTrue {
		t.Fatalf("Ready = %q after refresh, want True — a heartbeat must recover a node the controller marked Unknown", cond.Status)
	}
}

func conditionByType(conds []corev1.NodeCondition, t corev1.NodeConditionType) (corev1.NodeCondition, bool) {
	for _, c := range conds {
		if c.Type == t {
			return c, true
		}
	}
	return corev1.NodeCondition{}, false
}

func TestConfigureNodeSeedsDiskPressureFalse(t *testing.T) {
	m := &Maintainer{NodeName: "mac-mini-1"}
	node := &corev1.Node{}

	m.configureNode(node, nil)

	dp, ok := conditionByType(node.Status.Conditions, corev1.NodeDiskPressure)
	if !ok {
		t.Fatal("expected a DiskPressure condition to be seeded")
	}
	if dp.Status != corev1.ConditionFalse {
		t.Fatalf("DiskPressure = %q, want False", dp.Status)
	}
}

func TestConfigureNodeMergesDynamicLabels(t *testing.T) {
	m := &Maintainer{
		NodeName:   "mac-mini-1",
		NodeLabels: map[string]string{"tuist.dev/fleet": "runners"},
	}
	node := &corev1.Node{}

	m.configureNode(node, map[string]string{"tuist.dev/golden-deadbeefdeadbeef": "true"})

	if got := node.Labels["tuist.dev/fleet"]; got != "runners" {
		t.Fatalf("operator label dropped: tuist.dev/fleet = %q", got)
	}
	if got := node.Labels["tuist.dev/golden-deadbeefdeadbeef"]; got != "true" {
		t.Fatalf("dynamic golden label missing: got %q", got)
	}
	if got := node.Labels["tuist.dev/runtime"]; got != "tart" {
		t.Fatalf("intrinsic runtime label = %q", got)
	}
}

// A golden label present on the Node but no longer returned by the provider
// (golden GC'd, or a different digest now) must be pruned — same retire path
// as a dropped operator label.
func TestConfigureNodePrunesStaleDynamicLabels(t *testing.T) {
	m := &Maintainer{NodeName: "mac-mini-1"}
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Labels: map[string]string{"tuist.dev/golden-0000000000000000": "true"},
		},
	}

	m.configureNode(node, map[string]string{"tuist.dev/golden-1111111111111111": "true"})

	if _, present := node.Labels["tuist.dev/golden-0000000000000000"]; present {
		t.Fatal("stale golden label was not pruned")
	}
	if got := node.Labels["tuist.dev/golden-1111111111111111"]; got != "true" {
		t.Fatalf("current golden label missing: got %q", got)
	}
}

// When the provider yields nothing (unset, or a probe error that the
// maintainer treats as "no opinion"), any previously-published golden labels
// are pruned. The production provider masks transient errors with its last
// good result, so a real empty means "this host holds no goldens".
func TestConfigureNodePrunesAllDynamicLabelsWhenNone(t *testing.T) {
	m := &Maintainer{NodeName: "mac-mini-1"}
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Labels: map[string]string{"tuist.dev/golden-0000000000000000": "true"},
		},
	}

	m.configureNode(node, nil)

	if _, present := node.Labels["tuist.dev/golden-0000000000000000"]; present {
		t.Fatal("golden label survived an empty provider result")
	}
}

func TestApplyDiskPressureSetsTrueWithDetail(t *testing.T) {
	m := &Maintainer{
		DiskPressure: func(context.Context) (bool, string, error) {
			return true, "vm-x at 100%", nil
		},
	}
	node := &corev1.Node{}
	m.configureNode(node, nil)

	m.applyDiskPressure(context.Background(), node)

	dp, _ := conditionByType(node.Status.Conditions, corev1.NodeDiskPressure)
	if dp.Status != corev1.ConditionTrue {
		t.Fatalf("DiskPressure = %q, want True", dp.Status)
	}
	if dp.Reason != "TartKubeletHasDiskPressure" {
		t.Fatalf("Reason = %q", dp.Reason)
	}
	if dp.Message != "vm-x at 100%" {
		t.Fatalf("Message = %q", dp.Message)
	}
}

func TestApplyDiskPressureSetsFalse(t *testing.T) {
	m := &Maintainer{
		DiskPressure: func(context.Context) (bool, string, error) {
			return false, "", nil
		},
	}
	node := &corev1.Node{}
	m.configureNode(node, nil)

	m.applyDiskPressure(context.Background(), node)

	dp, _ := conditionByType(node.Status.Conditions, corev1.NodeDiskPressure)
	if dp.Status != corev1.ConditionFalse {
		t.Fatalf("DiskPressure = %q, want False", dp.Status)
	}
}

func TestApplyDiskPressureKeepsPriorValueOnProbeError(t *testing.T) {
	m := &Maintainer{
		DiskPressure: func(context.Context) (bool, string, error) {
			return false, "", errors.New("guest agent unreachable")
		},
	}
	node := &corev1.Node{}
	m.configureNode(node, nil)
	// Simulate a prior heartbeat that observed pressure.
	setCondition(&node.Status.Conditions, corev1.NodeDiskPressure, corev1.ConditionTrue, "TartKubeletHasDiskPressure", "vm-x at 100%")

	m.applyDiskPressure(context.Background(), node)

	dp, _ := conditionByType(node.Status.Conditions, corev1.NodeDiskPressure)
	if dp.Status != corev1.ConditionTrue {
		t.Fatalf("DiskPressure = %q, want unchanged True on probe error", dp.Status)
	}
}

func TestApplyDiskPressureNilProbeIsNoop(t *testing.T) {
	m := &Maintainer{} // no probe
	node := &corev1.Node{}
	m.configureNode(node, nil)

	m.applyDiskPressure(context.Background(), node)

	dp, ok := conditionByType(node.Status.Conditions, corev1.NodeDiskPressure)
	if !ok || dp.Status != corev1.ConditionFalse {
		t.Fatalf("expected seeded False to remain, got ok=%v status=%q", ok, dp.Status)
	}
}
