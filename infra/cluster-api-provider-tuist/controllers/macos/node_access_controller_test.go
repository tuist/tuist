package macos

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
	"k8s.io/utils/ptr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
)

const accessNode = "ber1-runner-b01"

func newNodeAccess(t *testing.T, objs ...client.Object) *NodeAccessReconciler {
	t.Helper()
	c := fake.NewClientBuilder().
		WithScheme(clientgoscheme.Scheme).
		WithObjects(objs...).
		WithIndex(&corev1.Pod{}, podNodeNameField, func(o client.Object) []string {
			return []string{o.(*corev1.Pod).Spec.NodeName}
		}).
		Build()
	return &NodeAccessReconciler{Client: c, Credentials: &credentials.Manager{
		Client:                  c,
		Namespace:               testNamespace,
		NodeIdentityClusterRole: "tart-kubelet",
	}}
}

func accessNodeObjects(node, clusterRole string) []client.Object {
	return []client.Object{
		&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: node, UID: types.UID(node + "-uid")}},
		&rbacv1.ClusterRoleBinding{
			ObjectMeta: metav1.ObjectMeta{Name: "tart-kubelet-" + node},
			RoleRef:    rbacv1.RoleRef{APIGroup: rbacv1.GroupName, Kind: "ClusterRole", Name: clusterRole},
		},
	}
}

func accessPod(name, node string, mutate func(*corev1.Pod)) *corev1.Pod {
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist-runners"},
		Spec: corev1.PodSpec{
			NodeName:           node,
			NodeSelector:       map[string]string{"kubernetes.io/os": "darwin"},
			ServiceAccountName: "runner",
			Containers:         []corev1.Container{{Name: "runner"}},
		},
	}
	if mutate != nil {
		mutate(pod)
	}
	return pod
}

func secretEnv(secret string) corev1.EnvVar {
	return corev1.EnvVar{Name: "S", ValueFrom: &corev1.EnvVarSource{SecretKeyRef: &corev1.SecretKeySelector{
		LocalObjectReference: corev1.LocalObjectReference{Name: secret}, Key: "k",
	}}}
}

func reconcileNodeAccess(t *testing.T, r *NodeAccessReconciler, node string) {
	t.Helper()
	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: node}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
}

func getRole(t *testing.T, r *NodeAccessReconciler, namespace, name string) (*rbacv1.Role, bool) {
	t.Helper()
	role := &rbacv1.Role{}
	err := r.Get(context.Background(), types.NamespacedName{Namespace: namespace, Name: name}, role)
	if apierrors.IsNotFound(err) {
		return nil, false
	}
	if err != nil {
		t.Fatal(err)
	}
	return role, true
}

// A host is granted exactly what its own live macOS Pods' env and token
// minting need: not another node's Pod's Secret, nor a finished Pod's, nor
// a Linux Pod's that landed on the Mac.
func TestNodeAccessGrantsOnlyThisNodesLivePodsReferences(t *testing.T) {
	objs := accessNodeObjects(accessNode, "tart-kubelet")
	objs = append(objs,
		accessPod("a", accessNode, func(p *corev1.Pod) {
			p.Spec.Containers[0].Env = []corev1.EnvVar{secretEnv("runner-env"), {Name: "PLAIN", Value: "x"}}
			p.Spec.Containers[0].EnvFrom = []corev1.EnvFromSource{{ConfigMapRef: &corev1.ConfigMapEnvSource{LocalObjectReference: corev1.LocalObjectReference{Name: "runner-config"}}}}
			p.Spec.InitContainers = []corev1.Container{{Name: "init", EnvFrom: []corev1.EnvFromSource{{SecretRef: &corev1.SecretEnvSource{LocalObjectReference: corev1.LocalObjectReference{Name: "init-secret"}}}}}}
		}),
		// The sandbox control Pod automounts nothing, yet the host mints
		// its token.
		accessPod("control", accessNode, func(p *corev1.Pod) {
			p.Spec.ServiceAccountName = "sandboxd"
			p.Spec.AutomountServiceAccountToken = ptr.To(false)
		}),
		accessPod("done", accessNode, func(p *corev1.Pod) {
			p.Spec.ServiceAccountName = "finished"
			p.Spec.Containers[0].Env = []corev1.EnvVar{secretEnv("finished-job")}
			p.Status.Phase = corev1.PodSucceeded
		}),
		accessPod("elsewhere", "ber1-runner-b02", func(p *corev1.Pod) {
			p.Spec.Containers[0].Env = []corev1.EnvVar{secretEnv("other-host")}
		}),
		// A Linux Pod steered onto the Mac (say, by relabelling its Node).
		accessPod("server", accessNode, func(p *corev1.Pod) {
			p.Spec.NodeSelector = map[string]string{"node.cluster.x-k8s.io/pool": "general"}
			p.Spec.ServiceAccountName = "server"
			p.Spec.Containers[0].Env = []corev1.EnvVar{secretEnv("server-secrets")}
		}),
	)
	r := newNodeAccess(t, objs...)
	reconcileNodeAccess(t, r, accessNode)

	name := credentials.NodePodRefsName(accessNode)
	role, ok := getRole(t, r, "tuist-runners", name)
	if !ok {
		t.Fatal("no Role granting the node's Pods' references")
	}
	want := []rbacv1.PolicyRule{
		{APIGroups: []string{""}, Resources: []string{"secrets"}, ResourceNames: []string{"init-secret", "runner-env"}, Verbs: []string{"get"}},
		{APIGroups: []string{""}, Resources: []string{"configmaps"}, ResourceNames: []string{"runner-config"}, Verbs: []string{"get"}},
		{APIGroups: []string{""}, Resources: []string{"serviceaccounts/token"}, ResourceNames: []string{"runner", "sandboxd"}, Verbs: []string{"create"}},
		{APIGroups: []string{""}, Resources: []string{"pods"}, ResourceNames: []string{"a", "control"}, Verbs: []string{"tuist-bind-token"}},
	}
	if !reflect.DeepEqual(role.Rules, want) {
		t.Fatalf("rules = %+v\nwant  %+v", role.Rules, want)
	}
	if len(role.OwnerReferences) != 1 || role.OwnerReferences[0].Kind != "Node" || role.OwnerReferences[0].UID != types.UID(accessNode+"-uid") {
		t.Fatalf("owner = %+v, want the Node", role.OwnerReferences)
	}
	binding := &rbacv1.RoleBinding{}
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: "tuist-runners", Name: name}, binding); err != nil {
		t.Fatal(err)
	}
	wantSubject := rbacv1.Subject{Kind: "ServiceAccount", Name: "tart-kubelet-" + accessNode, Namespace: testNamespace}
	if binding.RoleRef.Name != name || len(binding.Subjects) != 1 || binding.Subjects[0] != wantSubject {
		t.Fatalf("binding = %+v, want %s bound to %+v", binding, name, wantSubject)
	}
}

// A Pod that references no Secret or ConfigMap gets no rule for them. A
// rule with no resourceNames would grant every object of its resource, so
// EnsureNodeRole refuses one outright.
func TestNodeAccessNeverWritesARuleWithoutNames(t *testing.T) {
	objs := accessNodeObjects(accessNode, "tart-kubelet")
	objs = append(objs, &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: "macos-sbx-1", Namespace: "tuist-sandboxes"},
		Spec: corev1.PodSpec{
			NodeName: accessNode, NodeSelector: map[string]string{"kubernetes.io/os": "darwin"},
			AutomountServiceAccountToken: ptr.To(false), Containers: []corev1.Container{{Name: "sandbox"}},
		},
	})
	r := newNodeAccess(t, objs...)
	reconcileNodeAccess(t, r, accessNode)
	role, ok := getRole(t, r, "tuist-sandboxes", credentials.NodePodRefsName(accessNode))
	if !ok {
		t.Fatal("no Role for the Pod's ServiceAccount")
	}
	for _, rule := range role.Rules {
		if len(rule.ResourceNames) == 0 || (rule.Resources[0] != "serviceaccounts/token" && rule.Resources[0] != "pods") {
			t.Fatalf("unexpected rule %+v", rule)
		}
	}
	if err := r.Credentials.EnsureNodeRole(context.Background(), "x", "y", accessNode, credentials.NodeAccessPodRefs,
		[]rbacv1.PolicyRule{{APIGroups: []string{""}, Resources: []string{"secrets"}, Verbs: []string{"get"}}}, nil); err == nil {
		t.Fatal("EnsureNodeRole accepted a rule naming no objects")
	}
}

// Grants follow the Pods: a namespace whose last Pod left loses its Role,
// and the host's own identity Roles are left alone.
func TestNodeAccessRevokesWhatNoPodReferencesAnyMore(t *testing.T) {
	name := credentials.NodePodRefsName(accessNode)
	stale := &rbacv1.Role{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist", Name: name, Labels: credentials.NodeAccessLabels(accessNode, credentials.NodeAccessPodRefs)}}
	staleBinding := &rbacv1.RoleBinding{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist", Name: name, Labels: credentials.NodeAccessLabels(accessNode, credentials.NodeAccessPodRefs)}}
	self := &rbacv1.Role{ObjectMeta: metav1.ObjectMeta{Namespace: testNamespace, Name: "tart-kubelet-" + accessNode + "-self", Labels: credentials.NodeAccessLabels(accessNode, credentials.NodeAccessIdentity)}}
	objs := append(accessNodeObjects(accessNode, "tart-kubelet"), stale, staleBinding, self,
		accessPod("a", accessNode, func(p *corev1.Pod) { p.Spec.Containers[0].Env = []corev1.EnvVar{secretEnv("runner-env")} }))
	r := newNodeAccess(t, objs...)
	reconcileNodeAccess(t, r, accessNode)

	if _, ok := getRole(t, r, "tuist", name); ok {
		t.Fatal("kept the grant of a namespace with no Pods on the node")
	}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(staleBinding), &rbacv1.RoleBinding{}); !apierrors.IsNotFound(err) {
		t.Fatalf("kept the stale RoleBinding (err=%v)", err)
	}
	if _, ok := getRole(t, r, "tuist-runners", name); !ok {
		t.Fatal("dropped the grant the live Pod needs")
	}
	if _, ok := getRole(t, r, testNamespace, self.Name); !ok {
		t.Fatal("deleted the host's identity Role")
	}
}

// Only hosts bound to the tart-kubelet role get grants; a Linux node's
// system:node identity is scoped by the Node authorizer instead.
func TestNodeAccessIgnoresNodesNotRunningTartKubelet(t *testing.T) {
	objs := append(accessNodeObjects("kura-1", "system:node"),
		accessPod("a", "kura-1", func(p *corev1.Pod) { p.Spec.Containers[0].Env = []corev1.EnvVar{secretEnv("runner-env")} }))
	r := newNodeAccess(t, objs...)
	reconcileNodeAccess(t, r, "kura-1")
	if _, ok := getRole(t, r, "tuist-runners", credentials.NodePodRefsName("kura-1")); ok {
		t.Fatal("granted a non-tart-kubelet node")
	}
}

// The legacy long-lived token is revoked only once the host says it runs from
// a token it rotates.
func TestNodeAccessRetiresTheLegacyTokenOnlyAfterTheHostMovedOff(t *testing.T) {
	legacy := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Namespace: testNamespace, Name: "tart-kubelet-" + accessNode + "-token"}}
	r := newNodeAccess(t, append(accessNodeObjects(accessNode, "tart-kubelet"), legacy)...)
	reconcileNodeAccess(t, r, accessNode)
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(legacy), &corev1.Secret{}); err != nil {
		t.Fatalf("retired the token of a host still using it: %v", err)
	}

	node := &corev1.Node{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: accessNode}, node); err != nil {
		t.Fatal(err)
	}
	node.Labels = map[string]string{credentials.KubeletCredentialLabel: credentials.KubeletCredentialToken}
	if err := r.Update(context.Background(), node); err != nil {
		t.Fatal(err)
	}
	reconcileNodeAccess(t, r, accessNode)
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(legacy), &corev1.Secret{}); !apierrors.IsNotFound(err) {
		t.Fatalf("legacy token survived the host's move to a rotated one (err=%v)", err)
	}
}

// A host the operator has not pushed since the identity Roles existed gets
// them from the controller, pinned to the fleet its Node already joined; a
// host that has them keeps the operator's.
func TestNodeAccessGrantsAnUnpushedHostItsIdentityRoles(t *testing.T) {
	objs := accessNodeObjects(accessNode, "tart-kubelet")
	objs[0].SetLabels(map[string]string{"tuist.dev/fleet": "runners"})
	objs = append(objs, accessNodeObjects("ber1-runner-b02", "tart-kubelet")...)
	pinned := &rbacv1.Role{
		ObjectMeta: metav1.ObjectMeta{Namespace: testNamespace, Name: "tart-kubelet-ber1-runner-b02-self", Labels: credentials.NodeAccessLabels("ber1-runner-b02", credentials.NodeAccessIdentity)},
		Rules:      []rbacv1.PolicyRule{{APIGroups: []string{"tuist.dev"}, Resources: []string{"nodefleets"}, ResourceNames: []string{"rack"}, Verbs: []string{"tuist-register"}}},
	}
	r := newNodeAccess(t, append(objs, pinned)...)
	r.Credentials.NodeIdentityRoles = []types.NamespacedName{{Namespace: "tuist-runners", Name: "tart-kubelet"}}
	reconcileNodeAccess(t, r, accessNode)
	reconcileNodeAccess(t, r, "ber1-runner-b02")

	self, ok := getRole(t, r, testNamespace, "tart-kubelet-"+accessNode+"-self")
	if !ok {
		t.Fatal("no identity Role for the unpushed host")
	}
	want := []rbacv1.PolicyRule{
		{APIGroups: []string{""}, Resources: []string{"serviceaccounts/token"}, ResourceNames: []string{"tart-kubelet-" + accessNode}, Verbs: []string{"create"}},
		{APIGroups: []string{"tuist.dev"}, Resources: []string{"nodefleets"}, ResourceNames: []string{"runners"}, Verbs: []string{"tuist-register"}},
	}
	if !reflect.DeepEqual(self.Rules, want) {
		t.Fatalf("rules = %+v\nwant  %+v", self.Rules, want)
	}
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: "tuist-runners", Name: "tart-kubelet-" + accessNode}, &rbacv1.RoleBinding{}); err != nil {
		t.Fatalf("runner namespace Role not bound: %v", err)
	}
	if got, _ := getRole(t, r, testNamespace, pinned.Name); !reflect.DeepEqual(got.Rules, pinned.Rules) {
		t.Fatalf("rewrote the operator's identity Role: %+v", got.Rules)
	}
}
