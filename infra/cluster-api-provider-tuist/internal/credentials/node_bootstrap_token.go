package credentials

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	// kubeadmNodeBootstrapGroup is the group kubeadm's bindings let request
	// and auto-approve a system:node client certificate.
	kubeadmNodeBootstrapGroup = "system:bootstrappers:kubeadm:default-node-token"

	nodeBootstrapTokenTTL = time.Hour

	// NodeBootstrapTokenLabel names the node a bootstrap token was minted for.
	NodeBootstrapTokenLabel = "tuist.dev/bootstrap-node"
)

// MintNodeBootstrapToken creates a one-hour kubeadm bootstrap token for one
// node's kubelet to request its client certificate with. It returns the
// token's Secret name, for the caller to delete once the kubelet holds its
// certificate, and the `<id>.<secret>` token.
func (m *Manager) MintNodeBootstrapToken(ctx context.Context, nodeName string) (string, string, error) {
	id, secret, err := randomTokenParts()
	if err != nil {
		return "", "", err
	}
	tok := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: "kube-system",
			Name:      "bootstrap-token-" + id,
			Labels: map[string]string{
				"tuist.dev/managed-by":  "capi-scaleway-applesilicon",
				NodeBootstrapTokenLabel: nodeName,
			},
		},
		Type: corev1.SecretType("bootstrap.kubernetes.io/token"),
		Data: map[string][]byte{
			"token-id":                       []byte(id),
			"token-secret":                   []byte(secret),
			"description":                    []byte("kubelet bootstrap for " + nodeName),
			"expiration":                     []byte(time.Now().Add(nodeBootstrapTokenTTL).UTC().Format(time.RFC3339)),
			"usage-bootstrap-authentication": []byte("true"),
			"auth-extra-groups":              []byte(kubeadmNodeBootstrapGroup),
		},
	}
	if err := m.Client.Create(ctx, tok); err != nil {
		if apierrors.IsAlreadyExists(err) {
			return m.MintNodeBootstrapToken(ctx, nodeName)
		}
		return "", "", fmt.Errorf("create bootstrap token for %s: %w", nodeName, err)
	}
	return tok.Name, id + "." + secret, nil
}

// DeleteBootstrapToken removes a bootstrap token's Secret.
func (m *Manager) DeleteBootstrapToken(ctx context.Context, secretName string) error {
	tok := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Namespace: "kube-system", Name: secretName}}
	if err := m.Client.Delete(ctx, tok); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete bootstrap token %s: %w", secretName, err)
	}
	return nil
}
