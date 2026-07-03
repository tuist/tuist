package shared

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// fakeMover routes by node name, so a test can assert which box won.
type fakeMover struct {
	current string
	moves   []string
}

func (m *fakeMover) CurrentTarget(_ context.Context, _ string) (string, error) { return m.current, nil }
func (m *fakeMover) TargetForNode(node *corev1.Node) (string, error)           { return node.Name, nil }
func (m *fakeMover) Move(_ context.Context, _, target string) error {
	m.moves = append(m.moves, target)
	m.current = target
	return nil
}

func poolNode(name string, ready bool) *corev1.Node {
	status := corev1.ConditionFalse
	if ready {
		status = corev1.ConditionTrue
	}
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: name, Labels: map[string]string{"node.cluster.x-k8s.io/pool": "kura-dedibox"}},
		Spec:       corev1.NodeSpec{ProviderID: "dedibox://fr-par-1/100"},
		Status:     corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: status}}},
	}
}

func demuxPod(name, node string, ready bool) *corev1.Pod {
	status := corev1.ConditionFalse
	if ready {
		status = corev1.ConditionTrue
	}
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "kura", Labels: map[string]string{"app.kubernetes.io/component": "peer-demux"}},
		Spec:       corev1.PodSpec{NodeName: node},
		Status:     corev1.PodStatus{Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: status}}},
	}
}

func failoverIPCR(demux bool) *infrav1.FailoverIP {
	spec := infrav1.FailoverIPSpec{
		IP:               "203.0.113.10",
		Vendor:           "fake",
		Region:           "eu-central",
		NodePoolSelector: map[string]string{"node.cluster.x-k8s.io/pool": "kura-dedibox"},
	}
	if demux {
		spec.DemuxSelector = map[string]string{"app.kubernetes.io/component": "peer-demux"}
		spec.DemuxNamespace = "kura"
	}
	return &infrav1.FailoverIP{ObjectMeta: metav1.ObjectMeta{Name: "eu-central-peer"}, Spec: spec}
}

func newFailoverReconciler(t *testing.T, mover FailoverIPMover, objs ...client.Object) (*FailoverIPReconciler, client.Client) {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).WithStatusSubresource(&infrav1.FailoverIP{}).Build()
	movers := map[string]FailoverIPMover{}
	if mover != nil {
		movers["fake"] = mover
	}
	return &FailoverIPReconciler{Client: c, Scheme: scheme, Movers: movers}, c
}

func reconcileFailover(t *testing.T, r *FailoverIPReconciler) {
	t.Helper()
	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: "eu-central-peer"}}); err != nil {
		t.Fatal(err)
	}
}

func TestFailoverIPRoutesToLowestHealthyBoxWhenUnassigned(t *testing.T) {
	mover := &fakeMover{current: ""}
	r, _ := newFailoverReconciler(t, mover, failoverIPCR(false), poolNode("node-a", true), poolNode("node-b", true))
	reconcileFailover(t, r)
	if len(mover.moves) != 1 || mover.moves[0] != "node-a" {
		t.Fatalf("expected a move to node-a, got %v", mover.moves)
	}
}

func TestFailoverIPAdoptsCurrentHealthyHolder(t *testing.T) {
	mover := &fakeMover{current: "node-b"}
	r, _ := newFailoverReconciler(t, mover, failoverIPCR(false), poolNode("node-a", true), poolNode("node-b", true))
	reconcileFailover(t, r)
	if len(mover.moves) != 0 {
		t.Fatalf("expected no move (adopt healthy holder), got %v", mover.moves)
	}
}

func TestFailoverIPFailsOverWhenHolderUnready(t *testing.T) {
	mover := &fakeMover{current: "node-b"}
	r, _ := newFailoverReconciler(t, mover, failoverIPCR(false), poolNode("node-a", true), poolNode("node-b", false))
	reconcileFailover(t, r)
	if len(mover.moves) != 1 || mover.moves[0] != "node-a" {
		t.Fatalf("expected failover to node-a, got %v", mover.moves)
	}
}

func TestFailoverIPDrainsOffBoxWithUnreadyDemux(t *testing.T) {
	mover := &fakeMover{current: "node-b"}
	// Both nodes Ready, but node-b's demux pod is rolling (not Ready), so the IP
	// must drain to node-a whose demux is Ready.
	r, _ := newFailoverReconciler(t, mover, failoverIPCR(true),
		poolNode("node-a", true), poolNode("node-b", true),
		demuxPod("demux-a", "node-a", true), demuxPod("demux-b", "node-b", false))
	reconcileFailover(t, r)
	if len(mover.moves) != 1 || mover.moves[0] != "node-a" {
		t.Fatalf("expected drain to node-a, got %v", mover.moves)
	}
}

func TestFailoverIPNoMoverIsNoop(t *testing.T) {
	r, c := newFailoverReconciler(t, nil, failoverIPCR(false), poolNode("node-a", true))
	reconcileFailover(t, r)
	got := &infrav1.FailoverIP{}
	if err := c.Get(context.Background(), types.NamespacedName{Name: "eu-central-peer"}, got); err != nil {
		t.Fatal(err)
	}
	if got.Status.Message == "" {
		t.Fatal("expected a surfaced status message when no mover is configured")
	}
}

func TestOVHServiceNameFromProviderID(t *testing.T) {
	got, err := ovhServiceNameFromProviderID("ovh://vin/ns1234.ip-1-2-3.eu")
	if err != nil || got != "ns1234.ip-1-2-3.eu" {
		t.Fatalf("got %q err %v", got, err)
	}
	if _, err := ovhServiceNameFromProviderID("hcloud://5"); err == nil {
		t.Fatal("expected error for non-OVH providerID")
	}
}

func TestParseDediboxTarget(t *testing.T) {
	zone, id, err := parseDediboxTarget("fr-par-1/75839")
	if err != nil || zone != "fr-par-1" || id != 75839 {
		t.Fatalf("got zone=%q id=%d err=%v", zone, id, err)
	}
	if _, _, err := parseDediboxTarget("nonsense"); err == nil {
		t.Fatal("expected error for malformed target")
	}
}
