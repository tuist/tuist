package credentials

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"fmt"
	"strings"

	"golang.org/x/crypto/ssh"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
)

// EnsureLeaseKey returns the private key and the public authorized_keys line
// of the key this cluster dials a rack host it borrows with, generating the
// pair on first call. Unlike a fleet key, nothing registers it anywhere: the
// operator that lends the host authorizes the public half on the host itself,
// and the private half never leaves this Secret.
func (m *Manager) EnsureLeaseKey(ctx context.Context, secretName, comment string) ([]byte, string, error) {
	secret := &corev1.Secret{}
	err := m.Client.Get(ctx, types.NamespacedName{Namespace: m.Namespace, Name: secretName}, secret)
	switch {
	case err == nil:
		priv, pub := secret.Data["id_ed25519"], strings.TrimSpace(string(secret.Data["id_ed25519.pub"]))
		if len(priv) == 0 || pub == "" {
			return nil, "", fmt.Errorf("secret %s/%s has no key pair", m.Namespace, secretName)
		}
		return priv, pub, nil
	case !apierrors.IsNotFound(err):
		return nil, "", fmt.Errorf("get lease key %s/%s: %w", m.Namespace, secretName, err)
	}

	pubKey, privKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, "", fmt.Errorf("generate ed25519: %w", err)
	}
	sshPub, err := ssh.NewPublicKey(pubKey)
	if err != nil {
		return nil, "", fmt.Errorf("ssh public key: %w", err)
	}
	pub := strings.TrimSpace(string(ssh.MarshalAuthorizedKey(sshPub))) + " " + comment
	block, err := ssh.MarshalPrivateKey(privKey, comment)
	if err != nil {
		return nil, "", fmt.Errorf("marshal private key: %w", err)
	}
	priv := pem(block.Type, block.Bytes)
	secret = &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: m.Namespace,
			Name:      secretName,
			Labels:    map[string]string{"tuist.dev/managed-by": "capi-scaleway-applesilicon"},
		},
		Type: corev1.SecretTypeOpaque,
		Data: map[string][]byte{"id_ed25519": priv, "id_ed25519.pub": []byte(pub)},
	}
	if err := m.Client.Create(ctx, secret); err != nil {
		return nil, "", fmt.Errorf("create lease key %s/%s: %w", m.Namespace, secretName, err)
	}
	return priv, pub, nil
}

// DeleteLeaseKey drops a lease key. The lender revokes it on the host.
func (m *Manager) DeleteLeaseKey(ctx context.Context, secretName string) error {
	secret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Namespace: m.Namespace, Name: secretName}}
	if err := m.Client.Delete(ctx, secret); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete lease key %s/%s: %w", m.Namespace, secretName, err)
	}
	return nil
}
