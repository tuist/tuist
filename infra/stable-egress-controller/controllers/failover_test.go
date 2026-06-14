package controllers

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
)

const (
	candKey = "tuist.dev/stable-egress-candidate"
	candVal = "server"
	actKey  = "tuist.dev/stable-egress-gateway"
	actVal  = "server"
)

func TestSelectActive(t *testing.T) {
	tests := []struct {
		name    string
		ready   []string
		current string
		want    string
	}{
		{"sticky to current healthy", []string{"a", "b"}, "b", "b"},
		{"failover when current gone", []string{"b", "c"}, "a", "b"},
		{"lexical pick with no current", []string{"c", "a", "b"}, "", "a"},
		{"none ready", nil, "a", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := selectActive(tt.ready, tt.current); got != tt.want {
				t.Fatalf("selectActive(%v, %q) = %q, want %q", tt.ready, tt.current, got, tt.want)
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
	assignErr error
	assigns   []int64
}

func (f *fakeFIP) CurrentServerID(context.Context, string) (int64, error) { return f.server, nil }
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
