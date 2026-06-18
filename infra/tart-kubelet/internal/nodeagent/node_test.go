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

	m.configureNode(node)

	dp, ok := conditionByType(node.Status.Conditions, corev1.NodeDiskPressure)
	if !ok {
		t.Fatal("expected a DiskPressure condition to be seeded")
	}
	if dp.Status != corev1.ConditionFalse {
		t.Fatalf("DiskPressure = %q, want False", dp.Status)
	}
}

func TestApplyDiskPressureSetsTrueWithDetail(t *testing.T) {
	m := &Maintainer{
		DiskPressure: func(context.Context) (bool, string, error) {
			return true, "vm-x at 100%", nil
		},
	}
	node := &corev1.Node{}
	m.configureNode(node)

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
	m.configureNode(node)

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
	m.configureNode(node)
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
	m.configureNode(node)

	m.applyDiskPressure(context.Background(), node)

	dp, ok := conditionByType(node.Status.Conditions, corev1.NodeDiskPressure)
	if !ok || dp.Status != corev1.ConditionFalse {
		t.Fatalf("expected seeded False to remain, got ok=%v status=%q", ok, dp.Status)
	}
}
