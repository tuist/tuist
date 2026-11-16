package credentials

import (
	"context"
	"reflect"
	"testing"

	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

// A macOS host's identity is a minted token, not a token Secret, and its
// account may mint tokens for itself only and register its Node in its own
// fleet only, with the runner namespace's Role
// bound beside the cluster role. Deleting the identity takes every grant.
func TestTartKubeletIdentityMintsATokenAndScopesItsGrants(t *testing.T) {
	ctx := context.Background()
	c := fake.NewClientBuilder().WithScheme(clientgoscheme.Scheme).Build()
	m := &Manager{
		Client:                  c,
		Namespace:               "tuist",
		NodeIdentityClusterRole: "tuist-tart-kubelet",
		NodeIdentityRoles:       []types.NamespacedName{{Namespace: "tuist-runners", Name: "tuist-tart-kubelet"}},
		ClusterCA:               []byte("the-ca"),
	}

	id, err := m.EnsureTartKubeletIdentity(ctx, "b01", "runners")
	if err != nil {
		t.Fatal(err)
	}
	if string(id.Token) != "fake-token" || string(id.CA) != "the-ca" {
		t.Fatalf("identity = %q / %q", id.Token, id.CA)
	}
	if err := c.Get(ctx, types.NamespacedName{Namespace: "tuist", Name: "tart-kubelet-b01-token"}, &corev1.Secret{}); !apierrors.IsNotFound(err) {
		t.Fatalf("created a long-lived token Secret (err=%v)", err)
	}

	self := &rbacv1.Role{}
	if err := c.Get(ctx, types.NamespacedName{Namespace: "tuist", Name: "tart-kubelet-b01-self"}, self); err != nil {
		t.Fatal(err)
	}
	wantSelf := []rbacv1.PolicyRule{
		{APIGroups: []string{""}, Resources: []string{"serviceaccounts/token"}, ResourceNames: []string{"tart-kubelet-b01"}, Verbs: []string{"create"}},
		{APIGroups: []string{"tuist.dev"}, Resources: []string{"nodefleets"}, ResourceNames: []string{"runners"}, Verbs: []string{"tuist-register"}},
	}
	if !reflect.DeepEqual(self.Rules, wantSelf) {
		t.Fatalf("self rules = %+v", self.Rules)
	}
	runners := &rbacv1.RoleBinding{}
	if err := c.Get(ctx, types.NamespacedName{Namespace: "tuist-runners", Name: "tart-kubelet-b01"}, runners); err != nil {
		t.Fatal(err)
	}
	if runners.RoleRef.Kind != "Role" || runners.RoleRef.Name != "tuist-tart-kubelet" || runners.Subjects[0].Name != "tart-kubelet-b01" || runners.Subjects[0].Namespace != "tuist" {
		t.Fatalf("runner namespace binding = %+v", runners)
	}
	crb := &rbacv1.ClusterRoleBinding{}
	if err := c.Get(ctx, types.NamespacedName{Name: "tart-kubelet-b01"}, crb); err != nil || crb.RoleRef.Name != "tuist-tart-kubelet" {
		t.Fatalf("cluster role binding = %+v, %v", crb.RoleRef, err)
	}

	// A grant the node access controller made for the host.
	podRefs := &rbacv1.RoleBinding{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist-runners", Name: NodePodRefsName("b01"), Labels: NodeAccessLabels("b01", NodeAccessPodRefs)}}
	if err := c.Create(ctx, podRefs); err != nil {
		t.Fatal(err)
	}
	if err := m.DeleteNodeIdentity(ctx, "b01"); err != nil {
		t.Fatal(err)
	}
	for _, obj := range []client.Object{self, runners, crb, podRefs, &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist", Name: "tart-kubelet-b01"}}} {
		if err := c.Get(ctx, client.ObjectKeyFromObject(obj), obj); !apierrors.IsNotFound(err) {
			t.Fatalf("%T %s survived the identity's deletion (err=%v)", obj, obj.GetName(), err)
		}
	}
}
