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
		{"use candidate when unhealthy active was filtered out", []corev1.Node{tnode("b", true), tnode("c", true)}, nil, "b"},
		{"NodeReady does not affect an already checked active node", []corev1.Node{tnode("b", true)}, []corev1.Node{tnode("a", false)}, "a"},
		{"elect lexically-lowest candidate when no active", []corev1.Node{tnode("c", true), tnode("a", true), tnode("b", true)}, nil, "a"},
		{"nothing eligible", nil, nil, ""},
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
	onAssign  func()
}

type fakeNodeHealth struct {
	healthy map[string]bool
}

func (f fakeNodeHealth) Healthy(_ context.Context, node *corev1.Node) (bool, error) {
	if healthy, ok := f.healthy[node.Name]; ok {
		return healthy, nil
	}
	return true, nil
}

func (f *fakeFIP) Get(context.Context, string) (string, int64, error) { return f.addr, f.server, nil }
func (f *fakeFIP) Assign(_ context.Context, _ string, serverID int64) error {
	if f.assignErr != nil {
		return f.assignErr
	}
	if f.onAssign != nil {
		f.onAssign()
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

func preparedPod(name, node string, ready bool) *corev1.Pod {
	status := corev1.ConditionFalse
	if ready {
		status = corev1.ConditionTrue
	}
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: "kube-system",
			Labels:    map[string]string{"app.kubernetes.io/name": "host-configurer"},
		},
		Spec: corev1.PodSpec{NodeName: node},
		Status: corev1.PodStatus{
			Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: status}},
		},
	}
}

func newReconciler(fip FloatingIPManager, objs ...client.Object) *FailoverReconciler {
	c := fake.NewClientBuilder().WithObjects(objs...).Build()
	return &FailoverReconciler{
		Client:               c,
		FIP:                  fip,
		FloatingIPName:       "tuist-production-server-egress",
		CandidateLabelKey:    candKey,
		CandidateLabelValue:  candVal,
		ActiveLabelKey:       actKey,
		ActiveLabelValue:     actVal,
		NodeHealthChecker:    fakeNodeHealth{},
		ResyncInterval:       30 * time.Second,
		UnhealthyGracePeriod: 0,
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
	r.NodeHealthChecker = fakeNodeHealth{healthy: map[string]bool{"egress-a": false}}

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

func TestReconcileWaitsForPreparedCandidate(t *testing.T) {
	dead := candidateNode("egress-a", "hcloud://111", false, true)
	unprepared := candidateNode("egress-b", "hcloud://222", true, false)
	prepared := candidateNode("egress-c", "hcloud://333", true, false)
	fip := &fakeFIP{server: 111}
	r := newReconciler(
		fip,
		dead,
		unprepared,
		prepared,
		preparedPod("host-configurer-b", "egress-b", false),
		preparedPod("host-configurer-c", "egress-c", true),
	)
	r.PreparedPodNamespace = "kube-system"
	r.PreparedPodLabelKey = "app.kubernetes.io/name"
	r.PreparedPodLabelValue = "host-configurer"
	r.NodeHealthChecker = fakeNodeHealth{healthy: map[string]bool{"egress-a": false}}

	if _, err := r.Reconcile(context.Background(), reconcile.Request{NamespacedName: types.NamespacedName{Name: reconcileName}}); err != nil {
		t.Fatal(err)
	}

	if fip.server != 333 {
		t.Fatalf("Floating IP on server %d, want prepared server 333", fip.server)
	}
	if got := activeNames(t, r); len(got) != 1 || got[0] != "egress-c" {
		t.Fatalf("active nodes = %v, want [egress-c]", got)
	}
}

func TestReconcileLeavesCurrentAssignmentWhenNoCandidateIsPrepared(t *testing.T) {
	active := candidateNode("egress-a", "hcloud://111", false, true)
	standby := candidateNode("egress-b", "hcloud://222", true, false)
	fip := &fakeFIP{server: 111}
	r := newReconciler(
		fip,
		active,
		standby,
		preparedPod("host-configurer-a", "egress-a", false),
		preparedPod("host-configurer-b", "egress-b", false),
	)
	r.PreparedPodNamespace = "kube-system"
	r.PreparedPodLabelKey = "app.kubernetes.io/name"
	r.PreparedPodLabelValue = "host-configurer"
	r.NodeHealthChecker = fakeNodeHealth{healthy: map[string]bool{"egress-a": false}}

	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}

	if fip.server != 111 {
		t.Fatalf("Floating IP moved to unprepared server %d", fip.server)
	}
	if len(fip.assigns) != 0 {
		t.Fatalf("unexpected Floating IP assignments: %v", fip.assigns)
	}
	if got := activeNames(t, r); len(got) != 1 || got[0] != "egress-a" {
		t.Fatalf("active selectors = %v, want stale provider holder [egress-a]", got)
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
	r.NodeHealthChecker = fakeNodeHealth{healthy: map[string]bool{"general-1": false}}

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

func TestPreparedPodEventPredicate(t *testing.T) {
	r := newReconciler(&fakeFIP{})
	r.PreparedPodNamespace = "kube-system"
	r.PreparedPodLabelKey = "app.kubernetes.io/name"
	r.PreparedPodLabelValue = "host-configurer"
	pred := r.preparedPodEventPredicate()

	matching := preparedPod("host-configurer-a", "egress-a", true)
	unrelated := preparedPod("other", "egress-a", true)
	unrelated.Labels[r.PreparedPodLabelKey] = "other"
	wrongNamespace := preparedPod("host-configurer-b", "egress-b", true)
	wrongNamespace.Namespace = "default"

	if !pred.Create(event.CreateEvent{Object: matching}) {
		t.Fatal("matching Pod create must reconcile")
	}
	if pred.Create(event.CreateEvent{Object: unrelated}) {
		t.Fatal("unrelated Pod create must not reconcile")
	}
	if pred.Create(event.CreateEvent{Object: wrongNamespace}) {
		t.Fatal("matching Pod in another namespace must not reconcile")
	}
	if !pred.Update(event.UpdateEvent{ObjectOld: matching, ObjectNew: unrelated}) {
		t.Fatal("removing the identifying label must reconcile")
	}
}

func TestSetupRequiresPreparedPodSelector(t *testing.T) {
	r := newReconciler(&fakeFIP{})
	if err := r.SetupWithManager(nil); err == nil {
		t.Fatal("expected setup to reject an empty prepared Pod selector")
	}
}

func TestSetupRequiresNodeHealthChecker(t *testing.T) {
	r := newReconciler(&fakeFIP{})
	r.PreparedPodNamespace = "kube-system"
	r.PreparedPodLabelKey = "app.kubernetes.io/name"
	r.NodeHealthChecker = nil
	if err := r.SetupWithManager(nil); err == nil {
		t.Fatal("expected setup to reject a nil node health checker")
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

func TestReconcileIgnoresNodeReadyWhenDirectHealthSucceeds(t *testing.T) {
	active := candidateNode("egress-a", "hcloud://111", false, true)
	standby := candidateNode("egress-b", "hcloud://222", true, false)
	fip := &fakeFIP{server: 111}
	r := newReconciler(fip, active, standby)

	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	if len(fip.assigns) != 0 {
		t.Fatalf("NodeReady alone must not move the Floating IP, got %v", fip.assigns)
	}
	if got := activeNames(t, r); len(got) != 1 || got[0] != "egress-a" {
		t.Fatalf("active nodes = %v, want [egress-a]", got)
	}
}

func TestReconcileRequiresContinuousDirectHealthFailure(t *testing.T) {
	active := candidateNode("egress-a", "hcloud://111", true, true)
	standby := candidateNode("egress-b", "hcloud://222", true, false)
	fip := &fakeFIP{server: 111}
	r := newReconciler(fip, active, standby)
	r.NodeHealthChecker = fakeNodeHealth{healthy: map[string]bool{"egress-a": false}}
	r.UnhealthyGracePeriod = 90 * time.Second
	now := time.Unix(1_000, 0)
	r.Now = func() time.Time { return now }

	for attempt := 1; attempt <= 3; attempt++ {
		if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
			t.Fatal(err)
		}
		if fip.server != 111 {
			t.Fatalf("attempt %d moved the Floating IP before the grace period", attempt)
		}
	}

	now = now.Add(89 * time.Second)
	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	if fip.server != 111 {
		t.Fatal("moved the Floating IP before 90 seconds of continuous failure")
	}

	now = now.Add(time.Second)
	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	if fip.server != 222 {
		t.Fatalf("Floating IP on server %d after the grace period, want 222", fip.server)
	}
}

func TestReconcileDoesNotUndoExternalAssignmentDuringGracePeriod(t *testing.T) {
	active := candidateNode("egress-a", "hcloud://111", true, true)
	standby := candidateNode("egress-b", "hcloud://222", true, false)
	fip := &fakeFIP{server: 111}
	r := newReconciler(fip, active, standby)
	r.NodeHealthChecker = fakeNodeHealth{healthy: map[string]bool{"egress-a": false}}
	r.UnhealthyGracePeriod = 90 * time.Second
	now := time.Unix(1_000, 0)
	r.Now = func() time.Time { return now }

	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	fip.server = 222
	now = now.Add(30 * time.Second)
	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}

	if fip.server != 222 {
		t.Fatalf("controller pulled the Floating IP back to unhealthy server %d during grace", fip.server)
	}
	if len(fip.assigns) != 0 {
		t.Fatalf("grace period must not write provider state, got assignments %v", fip.assigns)
	}
	if got := activeNames(t, r); len(got) != 1 || got[0] != "egress-a" {
		t.Fatalf("grace period changed active selectors to %v", got)
	}
}

func TestReconcileOnlyPromotesReadySchedulableCandidate(t *testing.T) {
	active := candidateNode("egress-a", "hcloud://111", false, true)
	notReady := candidateNode("egress-b", "hcloud://222", false, false)
	unschedulable := candidateNode("egress-c", "hcloud://333", true, false)
	unschedulable.Spec.Unschedulable = true
	deleting := candidateNode("egress-d", "hcloud://444", true, false)
	now := metav1.Now()
	deleting.DeletionTimestamp = &now
	deleting.Finalizers = []string{"test.tuist.dev"}
	ready := candidateNode("egress-e", "hcloud://555", true, false)
	fip := &fakeFIP{server: 111}
	r := newReconciler(fip, active, notReady, unschedulable, deleting, ready)
	r.NodeHealthChecker = fakeNodeHealth{healthy: map[string]bool{"egress-a": false}}

	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	if fip.server != 555 {
		t.Fatalf("Floating IP on server %d, want ready, schedulable, non-deleting server 555", fip.server)
	}
}

func TestReconcileImmediatelyDemotesDeletingActiveNode(t *testing.T) {
	active := candidateNode("egress-a", "hcloud://111", true, true)
	now := metav1.Now()
	active.DeletionTimestamp = &now
	active.Finalizers = []string{"test.tuist.dev"}
	standby := candidateNode("egress-b", "hcloud://222", true, false)
	fip := &fakeFIP{server: 111}
	r := newReconciler(fip, active, standby)
	r.NodeHealthChecker = fakeNodeHealth{healthy: map[string]bool{"egress-a": false}}
	r.UnhealthyGracePeriod = 90 * time.Second

	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	if fip.server != 222 {
		t.Fatalf("Floating IP on server %d, want standby server 222", fip.server)
	}
}

func TestReconcileRemovesOldSelectorBeforeProviderAssignment(t *testing.T) {
	active := candidateNode("egress-a", "hcloud://111", false, true)
	standby := candidateNode("egress-b", "hcloud://222", true, false)
	fip := &fakeFIP{server: 111}
	r := newReconciler(fip, active, standby)
	r.NodeHealthChecker = fakeNodeHealth{healthy: map[string]bool{"egress-a": false}}
	fip.onAssign = func() {
		if got := activeNames(t, r); len(got) != 0 {
			t.Fatalf("active selectors during provider assignment = %v, want none", got)
		}
	}

	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	if got := activeNames(t, r); len(got) != 1 || got[0] != "egress-b" {
		t.Fatalf("active selectors after failover = %v, want [egress-b]", got)
	}
}

func TestReconcileRecoversSelectorAfterProviderAssignmentFailure(t *testing.T) {
	active := candidateNode("egress-a", "hcloud://111", false, true)
	standby := candidateNode("egress-b", "hcloud://222", true, false)
	fip := &fakeFIP{server: 111, assignErr: context.DeadlineExceeded}
	r := newReconciler(fip, active, standby)
	r.NodeHealthChecker = fakeNodeHealth{healthy: map[string]bool{"egress-a": false}}

	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err == nil {
		t.Fatal("expected provider assignment error")
	}
	if got := activeNames(t, r); len(got) != 1 || got[0] != "egress-a" {
		t.Fatalf("active selectors after failed assignment = %v, want provider-observed egress-a", got)
	}
}

func TestReconcileResetsGraceAfterHealthRecovers(t *testing.T) {
	active := candidateNode("egress-a", "hcloud://111", true, true)
	standby := candidateNode("egress-b", "hcloud://222", true, false)
	health := map[string]bool{"egress-a": false}
	fip := &fakeFIP{server: 111}
	r := newReconciler(fip, active, standby)
	r.NodeHealthChecker = fakeNodeHealth{healthy: health}
	r.UnhealthyGracePeriod = 90 * time.Second
	now := time.Unix(1_000, 0)
	r.Now = func() time.Time { return now }

	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	now = now.Add(60 * time.Second)
	health["egress-a"] = true
	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	health["egress-a"] = false
	now = now.Add(time.Second)
	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	now = now.Add(89 * time.Second)
	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	if fip.server != 111 {
		t.Fatal("moved the Floating IP before the reset grace period elapsed")
	}
	now = now.Add(time.Second)
	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	if fip.server != 222 {
		t.Fatalf("Floating IP on server %d after a fresh grace period, want 222", fip.server)
	}
}

func TestReconcileUsesLongerGraceForPreparationLoss(t *testing.T) {
	active := candidateNode("egress-a", "hcloud://111", true, true)
	standby := candidateNode("egress-b", "hcloud://222", true, false)
	fip := &fakeFIP{server: 111}
	r := newReconciler(
		fip,
		active,
		standby,
		preparedPod("host-configurer-a", "egress-a", false),
		preparedPod("host-configurer-b", "egress-b", true),
	)
	r.PreparedPodNamespace = "kube-system"
	r.PreparedPodLabelKey = "app.kubernetes.io/name"
	r.PreparedPodLabelValue = "host-configurer"
	r.UnpreparedGracePeriod = 5 * time.Minute
	now := time.Unix(1_000, 0)
	r.Now = func() time.Time { return now }

	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	now = now.Add(4*time.Minute + 59*time.Second)
	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	if fip.server != 111 {
		t.Fatal("moved the Floating IP during the host-preparation grace period")
	}
	now = now.Add(time.Second)
	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	if fip.server != 222 {
		t.Fatalf("Floating IP on server %d after preparation stayed absent, want 222", fip.server)
	}
}

func TestReconcileNormalizesDuplicateSelectorsWithoutProviderMove(t *testing.T) {
	first := candidateNode("egress-a", "hcloud://111", true, true)
	second := candidateNode("egress-b", "hcloud://222", true, true)
	fip := &fakeFIP{server: 111}
	r := newReconciler(fip, first, second)

	if _, err := r.Reconcile(context.Background(), reconcile.Request{}); err != nil {
		t.Fatal(err)
	}
	if len(fip.assigns) != 0 {
		t.Fatalf("normalizing selectors moved the Floating IP: %v", fip.assigns)
	}
	if got := activeNames(t, r); len(got) != 1 || got[0] != "egress-a" {
		t.Fatalf("active selectors after normalization = %v, want [egress-a]", got)
	}
}
