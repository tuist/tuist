package nodeagent

import (
	"context"
	"errors"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func nodeTaints(t *testing.T, c client.Client, name string) []corev1.Taint {
	t.Helper()
	node := &corev1.Node{}
	if err := c.Get(context.Background(), types.NamespacedName{Name: name}, node); err != nil {
		t.Fatalf("get node: %v", err)
	}
	return node.Spec.Taints
}

// A host joining the cluster is held out of scheduling from the moment its
// Node exists, so no runner Pod lands before its images are pulled.
func TestEnsureNodeTaintsANodeItCreatesUntilReleased(t *testing.T) {
	c := newNodeFakeClient()
	gate := NewPrewarmGate()
	m := &Maintainer{Client: c, NodeName: "mac-1", Heartbeat: time.Second, PrewarmGate: gate}

	if err := m.ensureNode(context.Background()); err != nil {
		t.Fatalf("ensureNode: %v", err)
	}
	if held, err := gate.Wait(context.Background()); err != nil || !held {
		t.Fatalf("Wait = %v, %v; want the gate to hold a Node this process created", held, err)
	}
	if !hasTaint(nodeTaints(t, c, "mac-1"), PrewarmTaintKey) {
		t.Fatal("a freshly created Node does not carry the prewarm taint")
	}

	gate.Release()
	if err := m.refresh(context.Background()); err != nil {
		t.Fatalf("refresh: %v", err)
	}
	taints := nodeTaints(t, c, "mac-1")
	if hasTaint(taints, PrewarmTaintKey) {
		t.Fatal("the prewarm taint survived the gate's release")
	}
	if !hasTaint(taints, "tuist.dev/macos") {
		t.Fatal("removing the prewarm taint dropped the macos taint")
	}
}

// A tart-kubelet restart on a registered host must not take it out of
// service, and must clear a taint a previous process left mid-pull.
func TestEnsureNodeDoesNotHoldAnExistingNode(t *testing.T) {
	existing := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "mac-1"},
		Spec: corev1.NodeSpec{Taints: []corev1.Taint{
			{Key: "tuist.dev/macos", Value: "true", Effect: corev1.TaintEffectNoSchedule},
			{Key: PrewarmTaintKey, Value: "true", Effect: corev1.TaintEffectNoSchedule},
		}},
	}
	c := newNodeFakeClient(existing)
	gate := NewPrewarmGate()
	m := &Maintainer{Client: c, NodeName: "mac-1", Heartbeat: time.Second, PrewarmGate: gate}

	if err := m.ensureNode(context.Background()); err != nil {
		t.Fatalf("ensureNode: %v", err)
	}
	if held, _ := gate.Wait(context.Background()); held {
		t.Fatal("the gate holds a Node that already existed")
	}
	if hasTaint(nodeTaints(t, c, "mac-1"), PrewarmTaintKey) {
		t.Fatal("a leftover prewarm taint was not removed")
	}
}

func TestPrewarmGateReleasedBeforeRegistrationNeverHolds(t *testing.T) {
	gate := NewPrewarmGate()
	gate.Release()
	gate.decide(context.Background(), true)
	if gate.Held() {
		t.Fatal("a gate released before the Node was created holds it, and nothing would release it again")
	}
}

func TestPrewarmGateWaitHonoursCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := NewPrewarmGate().Wait(ctx); err == nil {
		t.Fatal("Wait returned without the Node being registered or the context ending")
	}
}

func TestMaintainerWithoutAGateNeverTaints(t *testing.T) {
	c := newNodeFakeClient()
	m := &Maintainer{Client: c, NodeName: "mac-1", Heartbeat: time.Second}
	if err := m.ensureNode(context.Background()); err != nil {
		t.Fatalf("ensureNode: %v", err)
	}
	if hasTaint(nodeTaints(t, c, "mac-1"), PrewarmTaintKey) {
		t.Fatal("a Maintainer without a gate tainted its Node")
	}
}

// A host reinstalled in place keeps its Node but comes back with no goldens,
// so it is held like a new one instead of taking Pods that wait on every
// image's download.
func TestEnsureNodeHoldsAnExistingNodeOnAnEmptyHost(t *testing.T) {
	existing := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "mac-1"},
		Spec: corev1.NodeSpec{Taints: []corev1.Taint{
			{Key: "tuist.dev/macos", Value: "true", Effect: corev1.TaintEffectNoSchedule},
		}},
	}
	c := newNodeFakeClient(existing)
	gate := NewPrewarmGate()
	gate.HostEmpty = func(context.Context) (bool, error) { return true, nil }
	m := &Maintainer{Client: c, NodeName: "mac-1", Heartbeat: time.Second, PrewarmGate: gate}

	if err := m.ensureNode(context.Background()); err != nil {
		t.Fatalf("ensureNode: %v", err)
	}
	if held, err := gate.Wait(context.Background()); err != nil || !held {
		t.Fatalf("Wait = %v, %v; want the gate to hold an existing Node whose host has no goldens", held, err)
	}
	if !hasTaint(nodeTaints(t, c, "mac-1"), PrewarmTaintKey) {
		t.Fatal("an existing Node on an empty host does not carry the prewarm taint")
	}

	gate.Release()
	if err := m.refresh(context.Background()); err != nil {
		t.Fatalf("refresh: %v", err)
	}
	if hasTaint(nodeTaints(t, c, "mac-1"), PrewarmTaintKey) {
		t.Fatal("the prewarm taint survived the gate's release")
	}
}

// A probe that cannot tell whether the host holds goldens must not take a
// serving host out of scheduling.
func TestEnsureNodeDoesNotHoldAnExistingNodeWhenTheGoldenProbeFails(t *testing.T) {
	c := newNodeFakeClient(&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "mac-1"}})
	gate := NewPrewarmGate()
	gate.HostEmpty = func(context.Context) (bool, error) { return true, errors.New("tart list failed") }
	m := &Maintainer{Client: c, NodeName: "mac-1", Heartbeat: time.Second, PrewarmGate: gate}

	if err := m.ensureNode(context.Background()); err != nil {
		t.Fatalf("ensureNode: %v", err)
	}
	if held, _ := gate.Wait(context.Background()); held {
		t.Fatal("the gate holds an existing Node on a failed golden probe")
	}
	if hasTaint(nodeTaints(t, c, "mac-1"), PrewarmTaintKey) {
		t.Fatal("a failed golden probe tainted an existing Node")
	}
}
