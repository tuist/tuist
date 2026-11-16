package macos

import (
	"context"
	"fmt"
	"sort"

	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/utils/ptr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
)

// podNodeNameField indexes Pods by the Node they are bound to.
const podNodeNameField = "spec.nodeName"

// NodeAccessReconciler scopes what a macOS host may read to its own Pods, as
// the Node authorizer does for a real kubelet. A host authenticates as a
// ServiceAccount, and RBAC cannot express "the Secrets of Pods on my node",
// so for each Node whose identity is bound to the tart-kubelet ClusterRole it
// keeps, in each namespace with Pods bound there, a Role naming exactly the
// Secrets and ConfigMaps those Pods' env reads and the ServiceAccounts
// tart-kubelet mints their tokens for, bound to the host's ServiceAccount.
//
// Only what tart-kubelet reads is granted: env references (`env.valueFrom`,
// `envFrom`) and a token for the Pod's ServiceAccount, which the Node
// authorizer grants a kubelet whatever the Pod's automount setting (the
// macOS sandbox service mints one for its control Pod, which automounts
// none). Pods sharing a ServiceAccount run on many hosts, so each Pod is
// also granted by name the `tuist-bind-token` verb, and the chart's
// admission policy admits a host's token for another account only when it
// is bound to a Pod the host holds that verb on, as NodeRestriction does.
//
// Only Pods that select `kubernetes.io/os=darwin` are granted anything: a
// Pod meant for Linux that lands here was steered onto the Mac, and must
// not hand the host its Secrets. The admission policy keeps a host from
// relabelling or untainting its Node to attract one; this is the backstop.
// Volumes and image pull secrets are not granted, since a Tart VM has
// neither. Terminal Pods grant nothing. The Roles are owned by the Node, so
// they go with it.
//
// A Pod tart-kubelet sees before its grant lands fails to resolve with a 403
// and is retried; see "Node access" in infra/tart-kubelet/AGENTS.md.
type NodeAccessReconciler struct {
	client.Client
	Credentials *credentials.Manager
}

func (r *NodeAccessReconciler) SetupWithManager(mgr ctrl.Manager) error {
	if err := mgr.GetFieldIndexer().IndexField(context.Background(), &corev1.Pod{}, podNodeNameField, func(o client.Object) []string {
		if node := o.(*corev1.Pod).Spec.NodeName; node != "" {
			return []string{node}
		}
		return nil
	}); err != nil {
		return err
	}
	podToNode := handler.EnqueueRequestsFromMapFunc(func(_ context.Context, o client.Object) []reconcile.Request {
		if node := o.(*corev1.Pod).Spec.NodeName; node != "" {
			return []reconcile.Request{{NamespacedName: types.NamespacedName{Name: node}}}
		}
		return nil
	})
	return ctrl.NewControllerManagedBy(mgr).
		Named("node-access").
		For(&corev1.Node{}).
		Watches(&corev1.Pod{}, podToNode).
		Owns(&rbacv1.Role{}).
		Owns(&rbacv1.RoleBinding{}).
		Complete(r)
}

func (r *NodeAccessReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	nodeName := req.Name
	node := &corev1.Node{}
	if err := r.Get(ctx, req.NamespacedName, node); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, r.revoke(ctx, nodeName)
		}
		return ctrl.Result{}, err
	}
	binding := &rbacv1.ClusterRoleBinding{}
	err := r.Get(ctx, types.NamespacedName{Name: credentials.NodeIdentityServiceAccount(nodeName)}, binding)
	if apierrors.IsNotFound(err) || (err == nil && binding.RoleRef.Name != r.Credentials.NodeIdentityClusterRole) {
		// Not a macOS host of this operator (a Linux node binds
		// system:node, which the Node authorizer scopes).
		return ctrl.Result{}, r.revoke(ctx, nodeName)
	}
	if err != nil {
		return ctrl.Result{}, err
	}

	// A host the operator has not pushed since it started writing the
	// identity Roles (EnsureTartKubeletIdentity) still mints its own and the
	// cache-volume agent's tokens, which the chart's ClusterRole no longer
	// grants. Grant them now, with the fleet its Node already joined, rather
	// than wait for the next push.
	has, err := r.Credentials.HasNodeIdentityRoles(ctx, nodeName)
	if err != nil {
		return ctrl.Result{}, err
	}
	if !has {
		if err := r.Credentials.EnsureNodeIdentityRoles(ctx, nodeName, node.Labels["tuist.dev/fleet"]); err != nil {
			return ctrl.Result{}, fmt.Errorf("grant %s its identity roles: %w", nodeName, err)
		}
	}

	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.MatchingFields{podNodeNameField: nodeName}); err != nil {
		return ctrl.Result{}, err
	}
	owner := &metav1.OwnerReference{
		APIVersion: "v1",
		Kind:       "Node",
		Name:       node.Name,
		UID:        node.UID,
		Controller: ptr.To(true),
	}
	name := credentials.NodePodRefsName(nodeName)
	keep := map[string]bool{}
	for namespace, refs := range podReferences(pods.Items) {
		rules := refs.rules()
		if len(rules) == 0 {
			continue
		}
		if err := r.Credentials.EnsureNodeRole(ctx, namespace, name, nodeName, credentials.NodeAccessPodRefs, rules, owner); err != nil {
			return ctrl.Result{}, fmt.Errorf("grant %s its Pods' references in %s: %w", nodeName, namespace, err)
		}
		keep[namespace] = true
	}
	if err := r.Credentials.DeleteNodeRoles(ctx, nodeName, credentials.NodeAccessPodRefs, name, keep); err != nil {
		return ctrl.Result{}, fmt.Errorf("revoke %s's stale grants: %w", nodeName, err)
	}

	// A host running from a rotated token no longer needs the long-lived one
	// older operators minted; deleting its Secret revokes it.
	if node.Labels[credentials.KubeletCredentialLabel] == credentials.KubeletCredentialToken {
		if err := r.Credentials.RetireLegacyNodeToken(ctx, nodeName); err != nil {
			return ctrl.Result{}, fmt.Errorf("retire %s's legacy token: %w", nodeName, err)
		}
	}
	return ctrl.Result{}, nil
}

func (r *NodeAccessReconciler) revoke(ctx context.Context, node string) error {
	return r.Credentials.DeleteNodeRoles(ctx, node, credentials.NodeAccessPodRefs, credentials.NodePodRefsName(node), nil)
}

// namespaceRefs are the objects of one namespace the Pods on a node use.
type namespaceRefs struct {
	secrets, configMaps, serviceAccounts, pods map[string]bool
}

func (n *namespaceRefs) rules() []rbacv1.PolicyRule {
	var rules []rbacv1.PolicyRule
	add := func(resource, verb string, names map[string]bool) {
		if len(names) == 0 {
			// An empty resourceNames would grant every object.
			return
		}
		list := make([]string, 0, len(names))
		for name := range names {
			list = append(list, name)
		}
		sort.Strings(list)
		rules = append(rules, rbacv1.PolicyRule{APIGroups: []string{""}, Resources: []string{resource}, ResourceNames: list, Verbs: []string{verb}})
	}
	add("secrets", "get", n.secrets)
	add("configmaps", "get", n.configMaps)
	add("serviceaccounts/token", "create", n.serviceAccounts)
	add("pods", credentials.PodBindTokenVerb, n.pods)
	return rules
}

// podReferences groups by namespace what tart-kubelet reads for the
// non-terminal macOS Pods: their env's Secrets and ConfigMaps, their
// ServiceAccounts, and the Pods themselves, to bind tokens to.
func podReferences(pods []corev1.Pod) map[string]*namespaceRefs {
	out := map[string]*namespaceRefs{}
	for i := range pods {
		pod := &pods[i]
		if pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed {
			continue
		}
		if pod.Spec.NodeSelector[corev1.LabelOSStable] != "darwin" {
			continue
		}
		refs := out[pod.Namespace]
		if refs == nil {
			refs = &namespaceRefs{secrets: map[string]bool{}, configMaps: map[string]bool{}, serviceAccounts: map[string]bool{}, pods: map[string]bool{}}
			out[pod.Namespace] = refs
		}
		refs.pods[pod.Name] = true
		visit := func(env []corev1.EnvVar, envFrom []corev1.EnvFromSource) {
			for _, e := range env {
				if e.ValueFrom == nil {
					continue
				}
				if ref := e.ValueFrom.SecretKeyRef; ref != nil && ref.Name != "" {
					refs.secrets[ref.Name] = true
				}
				if ref := e.ValueFrom.ConfigMapKeyRef; ref != nil && ref.Name != "" {
					refs.configMaps[ref.Name] = true
				}
			}
			for _, from := range envFrom {
				if ref := from.SecretRef; ref != nil && ref.Name != "" {
					refs.secrets[ref.Name] = true
				}
				if ref := from.ConfigMapRef; ref != nil && ref.Name != "" {
					refs.configMaps[ref.Name] = true
				}
			}
		}
		for _, c := range pod.Spec.InitContainers {
			visit(c.Env, c.EnvFrom)
		}
		for _, c := range pod.Spec.Containers {
			visit(c.Env, c.EnvFrom)
		}
		for _, c := range pod.Spec.EphemeralContainers {
			visit(c.Env, c.EnvFrom)
		}
		sa := pod.Spec.ServiceAccountName
		if sa == "" {
			sa = "default"
		}
		refs.serviceAccounts[sa] = true
	}
	return out
}
