package controllers

import (
	"context"
	"net/netip"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
)

const (
	candKey = "tuist.dev/stable-egress-candidate"
	candVal = "server"
	actKey  = "tuist.dev/stable-egress-gateway"
	actVal  = "server"
)

func tnode(name string, ready bool) corev1.Node {
	st := corev1.ConditionFalse
	if ready {
		st = corev1.ConditionTrue
	}
	return corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: name},
		Status:     corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: st}}},
	}
}

func TestSelectGateway(t *testing.T) {
	tests := []struct {
		name       string
		candidates []corev1.Node
		labeled    []corev1.Node
		want       string // "" => nil
	}{
		{"adopt healthy active even if non-candidate", []corev1.Node{tnode("c1", true), tnode("c2", true)}, []corev1.Node{tnode("general-1", true)}, "general-1"},
		{"sticky to active candidate", []corev1.Node{tnode("a", true), tnode("b", true)}, []corev1.Node{tnode("a", true)}, "a"},
		{"failover to candidate when active NotReady", []corev1.Node{tnode("b", true), tnode("c", true)}, []corev1.Node{tnode("a", false)}, "b"},
		{"elect lexically-lowest candidate when no active", []corev1.Node{tnode("c", true), tnode("a", true), tnode("b", true)}, nil, "a"},
		{"nothing eligible", nil, nil, ""},
		{"active NotReady and no Ready candidate", []corev1.Node{tnode("b", false)}, []corev1.Node{tnode("a", false)}, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := selectGateway(tt.candidates, tt.labeled)
			name := ""
			if got != nil {
				name = got.Name
			}
			if name != tt.want {
				t.Fatalf("selectGateway = %q, want %q", name, tt.want)
			}
		})
	}
}

func TestParseHCloudServerID(t *testing.T) {
	id, err := parseHCloudServerID("hcloud://141082942")
	if err != nil || id != 141082942 {
		t.Fatalf("got (%d, %v), want (141082942, nil)", id, err)
	}
	if _, err := parseHCloudServerID("scaleway://x"); err == nil {
		t.Fatal("expected error for non-hcloud providerID")
	}
}

type fakeFIP struct {
	server    int64
	addr      string
	assignErr error
	assigns   []int64
}

func (f *fakeFIP) Get(context.Context, string) (string, int64, error) { return f.addr, f.server, nil }
func (f *fakeFIP) Assign(_ context.Context, _ string, serverID int64) error {
	if f.assignErr != nil {
		return f.assignErr
	}
	f.assigns = append(f.assigns, serverID)
	f.server = serverID
	return nil
}

func candidateNode(name, providerID string, ready bool, active bool) *corev1.Node {
	labels := map[string]string{candKey: candVal}
	if active {
		labels[actKey] = actVal
	}
	status := corev1.ConditionFalse
	if ready {
		status = corev1.ConditionTrue
	}
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: name, Labels: labels},
		Spec:       corev1.NodeSpec{ProviderID: providerID},
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: status}},
		},
	}
}

func newReconciler(fip FloatingIPManager, objs ...client.Object) *FailoverReconciler {
	c := fake.NewClientBuilder().WithObjects(objs...).Build()
	return &FailoverReconciler{
		Client:              c,
		FIP:                 fip,
		FloatingIPName:      "tuist-production-server-egress",
		CandidateLabelKey:   candKey,
		CandidateLabelValue: candVal,
		ActiveLabelKey:      actKey,
		ActiveLabelValue:    actVal,
		ResyncInterval:      30 * time.Second,
	}
}

func activeNames(t *testing.T, r *FailoverReconciler) []string {
	t.Helper()
	var nodes corev1.NodeList
	if err := r.List(context.Background(), &nodes); err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, n := range nodes.Items {
		if n.Labels[actKey] == actVal {
			out = append(out, n.Name)
		}
	}
	return out
}

// Active node dies; the IP + active label move to the surviving Ready candidate.
func TestReconcileFailover(t *testing.T) {
	dead := candidateNode("egress-a", "hcloud://111", false, true) // was active, now NotReady
	alive := candidateNode("egress-b", "hcloud://222", true, false)
	fip := &fakeFIP{server: 111} // IP still on the dead node
	r := newReconciler(fip, dead, alive)

	if _, err := r.Reconcile(context.Background(), reconcile.Request{NamespacedName: types.NamespacedName{Name: reconcileName}}); err != nil {
		t.Fatal(err)
	}

	if fip.server != 222 {
		t.Fatalf("Floating IP on server %d, want 222", fip.server)
	}
	got := activeNames(t, r)
	if len(got) != 1 || got[0] != "egress-b" {
		t.Fatalf("active nodes = %v, want [egress-b]", got)
	}
}

func TestIPInAllowlist(t *testing.T) {
	allow := []netip.Prefix{netip.MustParsePrefix("116.202.0.10/32"), netip.MustParsePrefix("203.0.113.0/29")}
	for _, tc := range []struct {
		addr string
		want bool
	}{
		{"116.202.0.10", true},
		{"203.0.113.4", true},
		{"116.202.0.11", false},
	} {
		got, err := ipInAllowlist(tc.addr, allow)
		if err != nil || got != tc.want {
			t.Fatalf("ipInAllowlist(%q) = (%v, %v), want %v", tc.addr, got, err, tc.want)
		}
	}
}

// An out-of-allowlist Floating IP must not be activated: no assign, no relabel.
func TestReconcileRejectsOutOfAllowlistIP(t *testing.T) {
	node := candidateNode("egress-a", "hcloud://111", true, false)
	fip := &fakeFIP{server: 0, addr: "198.51.100.7"} // not in the allowlist
	r := newReconciler(fip, node)
	r.EgressIPAllowlist = []netip.Prefix{netip.MustParsePrefix("116.202.0.10/32")}

	if _, err := r.Reconcile(context.Background(), reconcile.Request{NamespacedName: types.NamespacedName{Name: reconcileName}}); err != nil {
		t.Fatal(err)
	}
	if len(fip.assigns) != 0 {
		t.Fatalf("must not assign an out-of-allowlist IP, got %v", fip.assigns)
	}
	if got := activeNames(t, r); len(got) != 0 {
		t.Fatalf("must not set the active label, got %v", got)
	}
}

// Enabling over an existing gateway: a healthy non-candidate node already holds
// the active label + FIP. The controller ADOPTS it — no FIP reassign, no relabel
// (the zero-blip enable) — rather than migrating to the candidate.
func TestReconcileAdoptsHealthyNonCandidateActive(t *testing.T) {
	candidate := candidateNode("egress-a", "hcloud://222", true, false)
	active := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "general-1", Labels: map[string]string{actKey: actVal}}, // active, NOT a candidate
		Spec:       corev1.NodeSpec{ProviderID: "hcloud://111"},
		Status:     corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}},
	}
	fip := &fakeFIP{server: 111} // FIP already on the active node
	r := newReconciler(fip, candidate, active)

	if _, err := r.Reconcile(context.Background(), reconcile.Request{NamespacedName: types.NamespacedName{Name: reconcileName}}); err != nil {
		t.Fatal(err)
	}
	if len(fip.assigns) != 0 {
		t.Fatalf("must not reassign the FIP when adopting, got %v", fip.assigns)
	}
	if got := activeNames(t, r); len(got) != 1 || got[0] != "general-1" {
		t.Fatalf("active nodes = %v, want [general-1] (adopted, not migrated)", got)
	}
}

// Failover off a dead non-candidate active node: when the hand-labelled gateway
// is NotReady, the controller migrates to a Ready candidate AND strips the dead
// node's active label cluster-wide so two nodes don't both match Cilium.
func TestReconcileStripsDeadNonCandidateLabelOnFailover(t *testing.T) {
	candidate := candidateNode("egress-a", "hcloud://222", true, false)
	dead := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Name:   "general-1",
			Labels: map[string]string{actKey: actVal}, // active label, NOT a candidate
		},
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionFalse}}, // NotReady
		},
	}
	fip := &fakeFIP{server: 111}
	r := newReconciler(fip, candidate, dead)

	if _, err := r.Reconcile(context.Background(), reconcile.Request{NamespacedName: types.NamespacedName{Name: reconcileName}}); err != nil {
		t.Fatal(err)
	}
	if got := activeNames(t, r); len(got) != 1 || got[0] != "egress-a" {
		t.Fatalf("active nodes = %v, want [egress-a] (dead non-candidate label must be stripped)", got)
	}
	if fip.server != 222 {
		t.Fatalf("Floating IP on server %d, want 222", fip.server)
	}
}

// The Node watch predicate must let through only the changes that affect
// gateway selection, and drop the kubelet status heartbeats that otherwise
// reconcile (and hit the Hetzner API) every few seconds per node.
func TestNodeEventPredicate(t *testing.T) {
	r := newReconciler(&fakeFIP{})
	pred := r.nodeEventPredicate()

	withHeartbeat := func(n *corev1.Node, beat string) *corev1.Node {
		n = n.DeepCopy()
		n.ResourceVersion = beat
		for i := range n.Status.Conditions {
			if n.Status.Conditions[i].Type == corev1.NodeReady {
				n.Status.Conditions[i].LastHeartbeatTime = metav1.Now()
			}
		}
		return n
	}
	withReady := func(n *corev1.Node, ready bool) *corev1.Node {
		n = n.DeepCopy()
		st := corev1.ConditionFalse
		if ready {
			st = corev1.ConditionTrue
		}
		n.Status.Conditions = []corev1.NodeCondition{{Type: corev1.NodeReady, Status: st}}
		return n
	}
	withLabel := func(n *corev1.Node, k, v string) *corev1.Node {
		n = n.DeepCopy()
		if n.Labels == nil {
			n.Labels = map[string]string{}
		}
		n.Labels[k] = v
		return n
	}
	withDeletion := func(n *corev1.Node) *corev1.Node {
		n = n.DeepCopy()
		now := metav1.Now()
		n.DeletionTimestamp = &now
		return n
	}

	base := candidateNode("egress-a", "hcloud://111", true, false)

	tests := []struct {
		name     string
		old, new *corev1.Node
		want     bool
	}{
		{"heartbeat-only update is dropped", base, withHeartbeat(base, "2"), false},
		{"ready transition reconciles", base, withReady(base, false), true},
		{"candidate label change reconciles", base, withLabel(base, candKey, "other"), true},
		{"active label added reconciles", base, withLabel(base, actKey, actVal), true},
		{"deletion timestamp reconciles", base, withDeletion(base), true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := pred.Update(event.UpdateEvent{ObjectOld: tt.old, ObjectNew: tt.new})
			if got != tt.want {
				t.Fatalf("predicate.Update = %v, want %v", got, tt.want)
			}
		})
	}

	if !pred.Create(event.CreateEvent{Object: base}) {
		t.Fatal("Create events must reconcile")
	}
	if !pred.Delete(event.DeleteEvent{Object: base}) {
		t.Fatal("Delete events must reconcile")
	}
}

// Steady state: active node healthy — no IP churn, label unchanged.
func TestReconcileStickyNoChurn(t *testing.T) {
	a := candidateNode("egress-a", "hcloud://111", true, true)
	b := candidateNode("egress-b", "hcloud://222", true, false)
	fip := &fakeFIP{server: 111}
	r := newReconciler(fip, a, b)

	if _, err := r.Reconcile(context.Background(), reconcile.Request{NamespacedName: types.NamespacedName{Name: reconcileName}}); err != nil {
		t.Fatal(err)
	}
	if len(fip.assigns) != 0 {
		t.Fatalf("unexpected Floating IP reassignment: %v", fip.assigns)
	}
	if got := activeNames(t, r); len(got) != 1 || got[0] != "egress-a" {
		t.Fatalf("active nodes = %v, want [egress-a]", got)
	}
}
