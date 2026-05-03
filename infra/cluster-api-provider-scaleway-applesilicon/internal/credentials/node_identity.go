// Per-machine kubelet identity. One ServiceAccount + one
// long-lived service-account-token Secret + one ClusterRoleBinding
// per Mac mini, all in the operator's namespace.
//
// The previous shape was one shared SA + token Secret across the
// entire fleet, which meant a compromised host could impersonate
// any other host (the same bearer token unlocked the same set of
// resources from anywhere). For BYOC (PR #10499 description's
// "Path to BYOC" section) that's a non-starter — customer A's Mac
// mini can't be allowed to authenticate as customer B's. Per-Node
// identity is the minimum viable separation.
//
// We stop short of upstream kubelet's TLS bootstrap + NodeAuthorizer
// flow (CSRs, Node-bound certs, NodeRestriction admission) — that's
// the right end state but a substantially larger change. Per-machine
// SAs at least give us a per-machine *identity*; tightening the
// per-machine RBAC to a Node-graph-restricted role is the natural
// follow-up.

package credentials

import (
	"context"
	"errors"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/wait"
)

const (
	// nodeIdentitySAPrefix prefixes every per-machine ServiceAccount
	// the operator manages. The SA's full name is
	// `<prefix>-<machine-name>`. Stable so the chart's RBAC pattern
	// (component label + selector) still finds the SAs for ops.
	nodeIdentitySAPrefix = "tart-kubelet"

	// nodeIdentityTokenWaitTimeout caps the polling we do after we
	// create the Secret. The k8s service-account-token controller
	// usually populates the Secret within milliseconds; if it takes
	// longer than this the cluster has a control-plane issue we
	// can't paper over.
	nodeIdentityTokenWaitTimeout = 30 * time.Second
)

// NodeIdentity is the read shape Render() needs.
type NodeIdentity struct {
	Token []byte
	CA    []byte
}

// EnsureNodeIdentity guarantees a per-machine SA, Secret, and
// ClusterRoleBinding exist, then waits for k8s to populate the
// Secret with `token` + `ca.crt` and returns those bytes. Idempotent
// across restarts: re-running on a Machine that already has identity
// resources just reads them back.
func (m *Manager) EnsureNodeIdentity(ctx context.Context, machineName string) (*NodeIdentity, error) {
	saName := nodeIdentitySAPrefix + "-" + machineName
	tokenSecretName := saName + "-token"
	bindingName := saName

	if m.NodeIdentityClusterRole == "" {
		return nil, fmt.Errorf("EnsureNodeIdentity: NodeIdentityClusterRole not configured (chart didn't pass the cluster role name)")
	}
	if err := m.ensureNodeServiceAccount(ctx, saName, machineName); err != nil {
		return nil, fmt.Errorf("ensure SA: %w", err)
	}
	if err := m.ensureNodeTokenSecret(ctx, saName, tokenSecretName, machineName); err != nil {
		return nil, fmt.Errorf("ensure token secret: %w", err)
	}
	if err := m.ensureNodeClusterRoleBinding(ctx, bindingName, saName, machineName); err != nil {
		return nil, fmt.Errorf("ensure cluster role binding: %w", err)
	}

	token, ca, err := m.waitForTokenSecretPopulated(ctx, tokenSecretName)
	if err != nil {
		return nil, fmt.Errorf("wait for token secret populated: %w", err)
	}
	return &NodeIdentity{Token: token, CA: ca}, nil
}

func (m *Manager) ensureNodeServiceAccount(ctx context.Context, saName, machineName string) error {
	sa := &corev1.ServiceAccount{}
	err := m.Client.Get(ctx, types.NamespacedName{Namespace: m.Namespace, Name: saName}, sa)
	switch {
	case apierrors.IsNotFound(err):
		sa = &corev1.ServiceAccount{
			ObjectMeta: metav1.ObjectMeta{
				Namespace: m.Namespace,
				Name:      saName,
				Labels: map[string]string{
					"app.kubernetes.io/component": "tart-kubelet",
					"tuist.dev/managed-by":        "capi-scaleway-applesilicon",
					"tuist.dev/machine":           machineName,
				},
			},
		}
		if err := m.Client.Create(ctx, sa); err != nil && !apierrors.IsAlreadyExists(err) {
			return err
		}
		return nil
	case err != nil:
		return err
	}
	return nil
}

func (m *Manager) ensureNodeTokenSecret(ctx context.Context, saName, tokenSecretName, machineName string) error {
	secret := &corev1.Secret{}
	err := m.Client.Get(ctx, types.NamespacedName{Namespace: m.Namespace, Name: tokenSecretName}, secret)
	switch {
	case apierrors.IsNotFound(err):
		secret = &corev1.Secret{
			ObjectMeta: metav1.ObjectMeta{
				Namespace: m.Namespace,
				Name:      tokenSecretName,
				Labels: map[string]string{
					"app.kubernetes.io/component": "tart-kubelet",
					"tuist.dev/managed-by":        "capi-scaleway-applesilicon",
					"tuist.dev/machine":           machineName,
				},
				Annotations: map[string]string{
					// k8s populates `data.token` + `data.ca.crt` once
					// it sees this annotation. The pattern is
					// deprecated upstream in favor of the TokenRequest
					// API, but it's the only way to get a long-lived
					// token and tart-kubelet boots from disk without a
					// downward API to refresh.
					"kubernetes.io/service-account.name": saName,
				},
			},
			Type: corev1.SecretTypeServiceAccountToken,
		}
		if err := m.Client.Create(ctx, secret); err != nil && !apierrors.IsAlreadyExists(err) {
			return err
		}
		return nil
	case err != nil:
		return err
	}
	return nil
}

func (m *Manager) ensureNodeClusterRoleBinding(ctx context.Context, bindingName, saName, machineName string) error {
	binding := &rbacv1.ClusterRoleBinding{}
	err := m.Client.Get(ctx, types.NamespacedName{Name: bindingName}, binding)
	switch {
	case apierrors.IsNotFound(err):
		binding = &rbacv1.ClusterRoleBinding{
			ObjectMeta: metav1.ObjectMeta{
				Name: bindingName,
				Labels: map[string]string{
					"app.kubernetes.io/component": "tart-kubelet",
					"tuist.dev/managed-by":        "capi-scaleway-applesilicon",
					"tuist.dev/machine":           machineName,
				},
			},
			RoleRef: rbacv1.RoleRef{
				APIGroup: rbacv1.GroupName,
				Kind:     "ClusterRole",
				Name:     m.NodeIdentityClusterRole,
			},
			Subjects: []rbacv1.Subject{{
				Kind:      "ServiceAccount",
				Name:      saName,
				Namespace: m.Namespace,
			}},
		}
		if err := m.Client.Create(ctx, binding); err != nil && !apierrors.IsAlreadyExists(err) {
			return err
		}
		return nil
	case err != nil:
		return err
	}
	return nil
}

// waitForTokenSecretPopulated polls the Secret until k8s fills in
// `data.token` + `data.ca.crt`. Both are populated by the
// service-account-token controller once it sees the
// kubernetes.io/service-account.name annotation; in practice this
// happens within a few hundred ms.
func (m *Manager) waitForTokenSecretPopulated(ctx context.Context, secretName string) (token, ca []byte, err error) {
	pollCtx, cancel := context.WithTimeout(ctx, nodeIdentityTokenWaitTimeout)
	defer cancel()

	pollErr := wait.PollUntilContextCancel(pollCtx, 500*time.Millisecond, true, func(ctx context.Context) (bool, error) {
		secret := &corev1.Secret{}
		if err := m.Client.Get(ctx, types.NamespacedName{Namespace: m.Namespace, Name: secretName}, secret); err != nil {
			return false, err
		}
		token = secret.Data["token"]
		ca = secret.Data["ca.crt"]
		return len(token) > 0 && len(ca) > 0, nil
	})
	if pollErr != nil {
		if errors.Is(pollErr, context.DeadlineExceeded) {
			return nil, nil, fmt.Errorf("token secret %s/%s not populated within %s", m.Namespace, secretName, nodeIdentityTokenWaitTimeout)
		}
		return nil, nil, pollErr
	}
	return token, ca, nil
}
