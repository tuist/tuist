package shared

import (
	"context"
	"slices"
	"testing"
	"time"

	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

type recordingRevoker struct{ revoked []string }

func (r *recordingRevoker) DeleteNodeIdentity(_ context.Context, machine string) error {
	r.revoked = append(r.revoked, machine)
	return nil
}

func TestNodeIdentitySweepRevokesOnlyIdentitiesNothingCanUse(t *testing.T) {
	now := time.Date(2026, 11, 25, 12, 0, 0, 0, time.UTC)
	old := metav1.NewTime(now.Add(-48 * time.Hour))
	sa := func(name, machine string, created metav1.Time, managed bool) *corev1.ServiceAccount {
		labels := map[string]string{nodeIdentityMachineLabel: machine}
		if managed {
			labels[nodeIdentityManagedByLabel] = nodeIdentityManagedByValue
		}
		return &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{
			Namespace: "tuist", Name: name, Labels: labels, CreationTimestamp: created,
		}}
	}
	objs := []runtimeObject{
		// The CR and the Node are gone (a finalizer bypassed): revoked.
		sa("tart-kubelet-kura-fleet-a", "kura-fleet-a", old, true),
		// Same shape in another namespace: not this operator's.
		&corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: "other", Name: "tart-kubelet-x",
			Labels: map[string]string{nodeIdentityManagedByLabel: nodeIdentityManagedByValue, nodeIdentityMachineLabel: "x"}, CreationTimestamp: old}},
		// Minted moments ago, before its Node registered: kept.
		sa("tart-kubelet-fresh", "fresh", metav1.NewTime(now.Add(-5*time.Minute)), true),
		// Its machine still exists, though it has no Node: kept.
		sa("tart-kubelet-rack-b01", "rack-b01", old, true),
		&infrav1.RackAppleSiliconMachine{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist", Name: "rack-b01"}},
		// A Node without a machine (a joined OVH box mid-rename): kept.
		sa("tart-kubelet-ovh-1", "ovh-1", old, true),
		&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ovh-1"}},
		// A borrowed host's identity is named after its lease's Node: kept.
		sa("tart-kubelet-staging-rack-b02", "staging-rack-b02", old, true),
		&infrav1.RackHostLease{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist", Name: "b02"}},
		// The chart's rack-joining-nodes identity carries no managed-by: kept.
		sa("tart-kubelet-joining", "joining", old, false),
	}

	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	b := fake.NewClientBuilder().WithScheme(scheme)
	for _, o := range objs {
		b = b.WithObjects(o)
	}
	c := b.Build()

	for _, revoke := range []bool{false, true} {
		rev := &recordingRevoker{}
		s := &NodeIdentitySweep{
			Client: c, Revoker: rev, Namespace: "tuist", Grace: time.Hour, Revoke: revoke,
			LeaseNodeName: func(lease string) string { return "staging-rack-" + lease },
			Log:           logr.Discard(), now: func() time.Time { return now },
		}
		orphaned, err := s.SweepOnce(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if !slices.Equal(orphaned, []string{"kura-fleet-a"}) {
			t.Fatalf("revoke=%v: orphaned = %v, want [kura-fleet-a]", revoke, orphaned)
		}
		want := []string(nil)
		if revoke {
			want = []string{"kura-fleet-a"}
		}
		if !slices.Equal(rev.revoked, want) {
			t.Fatalf("revoke=%v: revoked %v, want %v", revoke, rev.revoked, want)
		}
	}
}

type runtimeObject = interface {
	metav1.Object
	runtime.Object
}
