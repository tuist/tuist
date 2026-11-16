// The macOS hosts' kubelet identity.
//
// A Mac mini authenticates as its own ServiceAccount, `tart-kubelet-<node>`,
// with a TokenRequest token the operator mints for each push and the host's
// tart-kubelet replaces before it expires (`internal/nodecred` there). No
// Secret holds it, so no long-lived credential sits in etcd or on a host.
//
// What the identity may read is split three ways, because RBAC cannot say
// "the Secrets of Pods on my node":
//
//   - the chart's ClusterRole, bound per machine: Nodes, Pods, Leases and the
//     other cluster-scoped kubelet needs, with no Secret, ConfigMap or token
//     access;
//   - Roles the chart defines in fixed namespaces (NodeIdentityRoles), bound
//     per machine: the runner namespace's ConfigMaps and the cache-volume
//     agent's token;
//   - per-node Roles naming each Secret, ConfigMap and ServiceAccount the Pods
//     bound to the node reference, kept by the node access controller
//     (controllers/macos/node_access_controller.go), the way the Node
//     authorizer scopes a real kubelet.
//
// The chart's ValidatingAdmissionPolicy keeps a host from creating a Pod that
// would widen its own grants.

package credentials

import (
	"context"
	"errors"
	"fmt"
	"os"
	"time"

	authenticationv1 "k8s.io/api/authentication/v1"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/api/equality"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const (
	// NodeAccessForLabel names the node an RBAC object grants to. Every Role
	// and RoleBinding the operator keeps for a host's identity carries it,
	// and the manager's cache watches only those.
	NodeAccessForLabel = "tuist.dev/node-access-for"
	// NodeAccessKindLabel tells the per-machine identity objects
	// (NodeAccessIdentity) from the node access controller's
	// (NodeAccessPodRefs).
	NodeAccessKindLabel = "tuist.dev/node-access"
	NodeAccessIdentity  = "identity"
	NodeAccessPodRefs   = "pod-refs"

	// KubeletCredentialLabel is the label tart-kubelet puts on its Node once
	// it runs from a kubeconfig whose token it rotates. The node access
	// controller then retires the legacy token Secret. Must match
	// infra/tart-kubelet/internal/nodecred.CredentialLabel.
	KubeletCredentialLabel = "tuist.dev/kubelet-credential"
	KubeletCredentialToken = "token-request"

	// A host's Node may carry the `tuist.dev/fleet` label value only if the
	// host may NodeFleetVerb the NodeFleetGroup NodeFleetResource of that
	// name in the operator's namespace (EnsureNodeIdentityRoles). Must match
	// the chart's tart-kubelet admission policy.
	NodeFleetGroup    = "tuist.dev"
	NodeFleetResource = "nodefleets"
	NodeFleetVerb     = "tuist-register"
	// PodBindTokenVerb on a Pod lets a host mint tokens bound to it. The node
	// access controller grants it for the Pods bound to the host's Node, and
	// the chart's admission policy requires it, as NodeRestriction does for
	// a real kubelet.
	PodBindTokenVerb = "tuist-bind-token"

	// DefaultNodeCredentialTTL is how long a host's token lives. The host
	// replaces it daily, so this is how long a host may be cut off from the
	// API server and still come back on its own.
	DefaultNodeCredentialTTL = 7 * 24 * time.Hour

	// serviceAccountCAPath is the cluster CA the operator's own Pod trusts,
	// the one every host's kubeconfig carries.
	serviceAccountCAPath = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
)

// NodeIdentityServiceAccount is the ServiceAccount a node's kubelet
// authenticates as.
func NodeIdentityServiceAccount(node string) string { return nodeIdentitySAPrefix + "-" + node }

// NodePodRefsName names the per-node Role and RoleBinding the node access
// controller keeps in each namespace with Pods on the node.
func NodePodRefsName(node string) string { return NodeIdentityServiceAccount(node) + "-pod-refs" }

// legacyTokenSecretName is the long-lived service-account-token Secret older
// operators minted for each host.
func legacyTokenSecretName(node string) string { return NodeIdentityServiceAccount(node) + "-token" }

func selfRoleName(node string) string { return NodeIdentityServiceAccount(node) + "-self" }

// NodeAccessLabels are the labels of an RBAC object granting to node.
func NodeAccessLabels(node, kind string) map[string]string {
	return map[string]string{
		"app.kubernetes.io/component": "tart-kubelet",
		"tuist.dev/managed-by":        "capi-scaleway-applesilicon",
		NodeAccessForLabel:            labelValue(node),
		NodeAccessKindLabel:           kind,
	}
}

// EnsureTartKubeletIdentity guarantees a macOS host's ServiceAccount and its
// grants exist and returns a fresh TokenRequest token for the host's
// kubeconfig, with the cluster CA. fleet is the `tuist.dev/fleet` label the
// host's Node may carry ("" for none).
func (m *Manager) EnsureTartKubeletIdentity(ctx context.Context, node, fleet string) (*NodeIdentity, error) {
	if m.NodeIdentityClusterRole == "" {
		return nil, fmt.Errorf("EnsureTartKubeletIdentity: no cluster role configured (chart didn't pass the cluster role name)")
	}
	saName := NodeIdentityServiceAccount(node)
	if err := m.ensureNodeServiceAccount(ctx, saName, node); err != nil {
		return nil, fmt.Errorf("ensure SA: %w", err)
	}
	if err := m.ensureNodeClusterRoleBinding(ctx, saName, saName, node, m.NodeIdentityClusterRole); err != nil {
		return nil, fmt.Errorf("ensure cluster role binding: %w", err)
	}
	if err := m.EnsureNodeIdentityRoles(ctx, node, fleet); err != nil {
		return nil, err
	}

	ttl := m.NodeCredentialTTL
	if ttl <= 0 {
		ttl = DefaultNodeCredentialTTL
	}
	seconds := int64(ttl / time.Second)
	sa := &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: m.Namespace, Name: saName}}
	req := &authenticationv1.TokenRequest{Spec: authenticationv1.TokenRequestSpec{ExpirationSeconds: &seconds}}
	if err := m.Client.SubResource("token").Create(ctx, sa, req); err != nil {
		return nil, fmt.Errorf("mint token for %s: %w", saName, err)
	}
	if req.Status.Token == "" {
		return nil, errors.New("token request returned no token")
	}

	ca := m.ClusterCA
	if len(ca) == 0 {
		data, err := os.ReadFile(serviceAccountCAPath)
		if err != nil {
			return nil, fmt.Errorf("read cluster CA: %w", err)
		}
		ca = data
	}
	return &NodeIdentity{Token: []byte(req.Status.Token), CA: ca}, nil
}

// EnsureNodeIdentityRoles grants node's ServiceAccount what every macOS
// host holds besides the chart's ClusterRole:
//
//   - tokens for its own account, which the host rotates and asks a
//     host-audience one of for the cache prefetch;
//   - the fleet its Node may join. RBAC has no such resource: the chart's
//     admission policy asks the authorizer whether the host may
//     `tuist-register` the `tuist.dev` `nodefleets` named after its Node's
//     `tuist.dev/fleet` label, so a host cannot move its Node into a fleet
//     whose Pods it must not see;
//   - the chart's NodeIdentityRoles.
func (m *Manager) EnsureNodeIdentityRoles(ctx context.Context, node, fleet string) error {
	self := []rbacv1.PolicyRule{{
		APIGroups:     []string{""},
		Resources:     []string{"serviceaccounts/token"},
		ResourceNames: []string{NodeIdentityServiceAccount(node)},
		Verbs:         []string{"create"},
	}}
	if fleet != "" {
		self = append(self, rbacv1.PolicyRule{
			APIGroups:     []string{NodeFleetGroup},
			Resources:     []string{NodeFleetResource},
			ResourceNames: []string{fleet},
			Verbs:         []string{NodeFleetVerb},
		})
	}
	if err := m.EnsureNodeRole(ctx, m.Namespace, selfRoleName(node), node, NodeAccessIdentity, self, nil); err != nil {
		return fmt.Errorf("ensure self role: %w", err)
	}
	saName := NodeIdentityServiceAccount(node)
	for _, role := range m.NodeIdentityRoles {
		ref := rbacv1.RoleRef{APIGroup: rbacv1.GroupName, Kind: "Role", Name: role.Name}
		if err := m.ensureNodeRoleBinding(ctx, role.Namespace, saName, node, NodeAccessIdentity, ref); err != nil {
			return fmt.Errorf("bind role %s: %w", role, err)
		}
	}
	return nil
}

// HasNodeIdentityRoles reports whether node's self Role exists, which
// EnsureNodeIdentityRoles writes.
func (m *Manager) HasNodeIdentityRoles(ctx context.Context, node string) (bool, error) {
	err := m.Client.Get(ctx, client.ObjectKey{Namespace: m.Namespace, Name: selfRoleName(node)}, &rbacv1.Role{})
	if apierrors.IsNotFound(err) {
		return false, nil
	}
	return err == nil, err
}

// RetireLegacyNodeToken deletes the long-lived token Secret of a host that
// no longer uses it. Deleting it revokes the token.
func (m *Manager) RetireLegacyNodeToken(ctx context.Context, node string) error {
	secret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Namespace: m.Namespace, Name: legacyTokenSecretName(node)}}
	if err := m.Client.Delete(ctx, secret); err != nil && !apierrors.IsNotFound(err) {
		return err
	}
	return nil
}

// EnsureNodeRole makes a Role holding exactly rules, and a RoleBinding of it
// to node's ServiceAccount, exist in namespace. A non-nil owner owns both.
func (m *Manager) EnsureNodeRole(ctx context.Context, namespace, name, node, kind string, rules []rbacv1.PolicyRule, owner *metav1.OwnerReference) error {
	for _, rule := range rules {
		// An empty resourceNames grants every object of the resource: a
		// rule must never lose its names.
		if len(rule.ResourceNames) == 0 {
			return fmt.Errorf("role %s/%s: a rule on %v names no objects", namespace, name, rule.Resources)
		}
	}
	role := &rbacv1.Role{ObjectMeta: metav1.ObjectMeta{Namespace: namespace, Name: name}}
	if err := m.upsert(ctx, role, func() {
		role.Labels = NodeAccessLabels(node, kind)
		role.Rules = rules
		setOwner(&role.ObjectMeta, owner)
	}); err != nil {
		return fmt.Errorf("role %s/%s: %w", namespace, name, err)
	}
	ref := rbacv1.RoleRef{APIGroup: rbacv1.GroupName, Kind: "Role", Name: name}
	binding := &rbacv1.RoleBinding{ObjectMeta: metav1.ObjectMeta{Namespace: namespace, Name: name}}
	return m.upsertRoleBinding(ctx, binding, node, kind, ref, owner)
}

func (m *Manager) ensureNodeRoleBinding(ctx context.Context, namespace, name, node, kind string, ref rbacv1.RoleRef) error {
	binding := &rbacv1.RoleBinding{ObjectMeta: metav1.ObjectMeta{Namespace: namespace, Name: name}}
	return m.upsertRoleBinding(ctx, binding, node, kind, ref, nil)
}

func (m *Manager) upsertRoleBinding(ctx context.Context, binding *rbacv1.RoleBinding, node, kind string, ref rbacv1.RoleRef, owner *metav1.OwnerReference) error {
	key := client.ObjectKeyFromObject(binding)
	err := m.Client.Get(ctx, key, binding)
	if err == nil && binding.RoleRef != ref {
		// roleRef is immutable.
		if err := m.Client.Delete(ctx, binding); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("replace role binding %s: %w", key, err)
		}
		binding = &rbacv1.RoleBinding{ObjectMeta: metav1.ObjectMeta{Namespace: key.Namespace, Name: key.Name}}
	}
	if err := m.upsert(ctx, binding, func() {
		binding.Labels = NodeAccessLabels(node, kind)
		binding.RoleRef = ref
		binding.Subjects = []rbacv1.Subject{{Kind: "ServiceAccount", Name: NodeIdentityServiceAccount(node), Namespace: m.Namespace}}
		setOwner(&binding.ObjectMeta, owner)
	}); err != nil {
		return fmt.Errorf("role binding %s: %w", key, err)
	}
	return nil
}

// DeleteNodeRoles removes every Role and RoleBinding of the given kind
// granting to node, except those in keep (namespace → true).
func (m *Manager) DeleteNodeRoles(ctx context.Context, node, kind, name string, keep map[string]bool) error {
	selector := client.MatchingLabels{NodeAccessForLabel: labelValue(node), NodeAccessKindLabel: kind}
	roles := &rbacv1.RoleList{}
	if err := m.Client.List(ctx, roles, selector); err != nil {
		return err
	}
	for i := range roles.Items {
		r := &roles.Items[i]
		if r.Name != name || keep[r.Namespace] {
			continue
		}
		if err := m.Client.Delete(ctx, r); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
	}
	bindings := &rbacv1.RoleBindingList{}
	if err := m.Client.List(ctx, bindings, selector); err != nil {
		return err
	}
	for i := range bindings.Items {
		b := &bindings.Items[i]
		if b.Name != name || keep[b.Namespace] {
			continue
		}
		if err := m.Client.Delete(ctx, b); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
	}
	return nil
}

// deleteTartKubeletRoles removes the Roles and RoleBindings the operator
// keeps for a macOS host's identity. A ServiceAccount recreated under the
// same name must not inherit them.
func (m *Manager) deleteTartKubeletRoles(ctx context.Context, node string) error {
	if err := m.DeleteNodeRoles(ctx, node, NodeAccessPodRefs, NodePodRefsName(node), nil); err != nil {
		return err
	}
	if err := m.DeleteNodeRoles(ctx, node, NodeAccessIdentity, selfRoleName(node), nil); err != nil {
		return err
	}
	return m.DeleteNodeRoles(ctx, node, NodeAccessIdentity, NodeIdentityServiceAccount(node), nil)
}

func (m *Manager) upsert(ctx context.Context, obj client.Object, mutate func()) error {
	err := m.Client.Get(ctx, client.ObjectKeyFromObject(obj), obj)
	switch {
	case apierrors.IsNotFound(err):
		mutate()
		// AlreadyExists means the cache is behind: the caller retries.
		return m.Client.Create(ctx, obj)
	case err != nil:
		return err
	}
	before := obj.DeepCopyObject()
	mutate()
	if equality.Semantic.DeepEqual(before, obj) {
		return nil
	}
	return m.Client.Update(ctx, obj)
}

func setOwner(meta *metav1.ObjectMeta, owner *metav1.OwnerReference) {
	if owner == nil {
		return
	}
	meta.OwnerReferences = []metav1.OwnerReference{*owner}
}
