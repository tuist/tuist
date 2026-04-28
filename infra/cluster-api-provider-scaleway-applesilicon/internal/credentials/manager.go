// Package credentials manages the per-fleet SSH key and the per-machine
// kubelet bootstrap material so operators don't have to.
//
// The user-facing contract is: drop Scaleway credentials in 1Password
// (which ESO syncs into a Secret), enable the fleet in the chart,
// done. Everything else — SSH keys, bootstrap tokens, CA bundles — is
// derived in-cluster:
//
//   * SSH key: generated on first reconcile, public half registered
//     with Scaleway via the IAM API, private half stashed in a
//     Secret the operator alone reads.
//   * API server URL: read from the in-cluster pod's environment
//     (KUBERNETES_SERVICE_HOST + PORT), which always reflects the
//     cluster the operator is running in.
//   * CA cert: read from the operator pod's mounted service-account
//     token (/var/run/secrets/kubernetes.io/serviceaccount/ca.crt),
//     same CA every kubelet must trust.
//   * Bootstrap token: minted on each Machine reconcile via the
//     standard `bootstrap.kubernetes.io/token` Secret pattern, with
//     a short TTL so leaked tokens expire fast.
package credentials

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/wait"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"golang.org/x/crypto/ssh"

	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/scaleway"
)

const (
	// SSHKeySecretName is the per-fleet Secret holding the private
	// SSH key. Format: ed25519 PEM in `id_ed25519`.
	sshKeySecretSuffix = "-ssh"

	// scalewayKeyAnnotation records the Scaleway-side SSH key ID
	// once registered so we don't re-register on every reconcile.
	scalewayKeyAnnotation = "scaleway.tuist.dev/ssh-key-id"

	bootstrapTokenTTL = 24 * time.Hour
)

// Manager bundles the helpers the controllers need.
type Manager struct {
	Client   client.Client
	Scaleway *scaleway.Client
	// Namespace is where per-fleet Secrets live (typically the
	// release's namespace).
	Namespace string
}

// EnsureFleetSSHKey returns the private SSH key bytes for `fleet`,
// generating + registering a new keypair on first call.
//
// Idempotent across operator restarts: the Secret is the source of
// truth, the Scaleway-side registration the side-effect we converge.
func (m *Manager) EnsureFleetSSHKey(ctx context.Context, fleet string) ([]byte, error) {
	secretName := fleet + sshKeySecretSuffix

	secret := &corev1.Secret{}
	err := m.Client.Get(ctx, types.NamespacedName{Namespace: m.Namespace, Name: secretName}, secret)
	switch {
	case apierrors.IsNotFound(err):
		// Generate + register + persist.
		return m.generateSSHKey(ctx, fleet, secretName)
	case err != nil:
		return nil, fmt.Errorf("get ssh secret: %w", err)
	}

	priv, ok := secret.Data["id_ed25519"]
	if !ok {
		return nil, fmt.Errorf("secret %s/%s missing id_ed25519", m.Namespace, secretName)
	}

	// If the registration with Scaleway has been forgotten (Secret
	// re-imported from a backup, key ID annotation lost), re-register.
	if secret.Annotations[scalewayKeyAnnotation] == "" {
		pub, ok := secret.Data["id_ed25519.pub"]
		if ok {
			id, err := m.Scaleway.EnsureSSHKey(ctx, fleet, string(pub))
			if err != nil {
				return nil, fmt.Errorf("re-register ssh key: %w", err)
			}
			if secret.Annotations == nil {
				secret.Annotations = map[string]string{}
			}
			secret.Annotations[scalewayKeyAnnotation] = id
			if err := m.Client.Update(ctx, secret); err != nil {
				return nil, err
			}
		}
	}

	return priv, nil
}

func (m *Manager) generateSSHKey(ctx context.Context, fleet, secretName string) ([]byte, error) {
	pubKey, privKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate ed25519: %w", err)
	}

	sshPub, err := ssh.NewPublicKey(pubKey)
	if err != nil {
		return nil, fmt.Errorf("ssh public key: %w", err)
	}
	pubBytes := ssh.MarshalAuthorizedKey(sshPub)

	pemBlock, err := ssh.MarshalPrivateKey(privKey, fmt.Sprintf("tuist-capi-%s", fleet))
	if err != nil {
		return nil, fmt.Errorf("marshal private key: %w", err)
	}
	privPEM := pem(pemBlock.Type, pemBlock.Bytes)

	scwID, err := m.Scaleway.EnsureSSHKey(ctx, fleet, string(pubBytes))
	if err != nil {
		return nil, fmt.Errorf("scaleway register ssh key: %w", err)
	}

	secret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: m.Namespace,
			Name:      secretName,
			Annotations: map[string]string{
				scalewayKeyAnnotation: scwID,
			},
			Labels: map[string]string{
				"tuist.dev/managed-by": "capi-scaleway-applesilicon",
				"tuist.dev/fleet":      fleet,
			},
		},
		Type: corev1.SecretTypeOpaque,
		Data: map[string][]byte{
			"id_ed25519":     privPEM,
			"id_ed25519.pub": pubBytes,
		},
	}
	if err := m.Client.Create(ctx, secret); err != nil {
		return nil, fmt.Errorf("create ssh secret: %w", err)
	}
	return privPEM, nil
}

// pem wraps DER bytes with the PEM header SSH expects.
func pem(blockType string, body []byte) []byte {
	const lineWidth = 64
	var b strings.Builder
	b.WriteString("-----BEGIN ")
	b.WriteString(blockType)
	b.WriteString("-----\n")
	encoded := base64.StdEncoding.EncodeToString(body)
	for i := 0; i < len(encoded); i += lineWidth {
		end := i + lineWidth
		if end > len(encoded) {
			end = len(encoded)
		}
		b.WriteString(encoded[i:end])
		b.WriteString("\n")
	}
	b.WriteString("-----END ")
	b.WriteString(blockType)
	b.WriteString("-----\n")
	return []byte(b.String())
}

// BootstrapMaterial captures everything needed to write a kubelet
// bootstrap-kubeconfig on a fresh node.
type BootstrapMaterial struct {
	APIServerURL   string
	CACertData     string // base64-encoded PEM as the kubeconfig expects
	BootstrapToken string
	KubeletVersion string
}

// MintBootstrap returns a fresh bootstrap-token + the cluster's API
// server URL + CA cert, derived from the operator's in-cluster
// service-account context. No 1Password lookup, no manual rotation.
func (m *Manager) MintBootstrap(ctx context.Context, kubeletVersion string) (*BootstrapMaterial, error) {
	apiURL, err := apiServerURL()
	if err != nil {
		return nil, err
	}
	caData, err := caCertB64()
	if err != nil {
		return nil, err
	}
	token, err := m.createBootstrapToken(ctx)
	if err != nil {
		return nil, err
	}
	return &BootstrapMaterial{
		APIServerURL:   apiURL,
		CACertData:     caData,
		BootstrapToken: token,
		KubeletVersion: kubeletVersion,
	}, nil
}

func apiServerURL() (string, error) {
	host := os.Getenv("KUBERNETES_SERVICE_HOST")
	port := os.Getenv("KUBERNETES_SERVICE_PORT")
	if host == "" || port == "" {
		return "", errors.New("KUBERNETES_SERVICE_HOST/PORT not set; not running in-cluster?")
	}
	return fmt.Sprintf("https://%s", net.JoinHostPort(host, port)), nil
}

func caCertB64() (string, error) {
	const path = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read CA cert: %w", err)
	}
	return base64.StdEncoding.EncodeToString(data), nil
}

// createBootstrapToken creates a `bootstrap.kubernetes.io/token`
// Secret in kube-system. The bootstrap-token controller (built into
// kube-controller-manager) honours these by allowing the encoded
// `<id>.<secret>` form to authenticate as
// `system:bootstrappers:tuist-applesilicon`.
func (m *Manager) createBootstrapToken(ctx context.Context) (string, error) {
	id, secret, err := randomTokenParts()
	if err != nil {
		return "", err
	}

	expiration := time.Now().Add(bootstrapTokenTTL).UTC().Format(time.RFC3339)

	tok := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: "kube-system",
			Name:      "bootstrap-token-" + id,
			Labels: map[string]string{
				"tuist.dev/managed-by": "capi-scaleway-applesilicon",
			},
		},
		Type: corev1.SecretType("bootstrap.kubernetes.io/token"),
		Data: map[string][]byte{
			"token-id":                       []byte(id),
			"token-secret":                   []byte(secret),
			"description":                    []byte("CAPI Scaleway Apple Silicon node bootstrap"),
			"expiration":                     []byte(expiration),
			"usage-bootstrap-authentication": []byte("true"),
			"usage-bootstrap-signing":        []byte("true"),
			"auth-extra-groups":              []byte("system:bootstrappers:tuist-applesilicon"),
		},
	}

	// Best-effort: if a token with this id already exists (collision
	// is astronomically unlikely but we Get-then-Create to be polite),
	// generate fresh.
	if err := m.Client.Create(ctx, tok); err != nil {
		if !apierrors.IsAlreadyExists(err) {
			return "", fmt.Errorf("create bootstrap token: %w", err)
		}
		return m.createBootstrapToken(ctx)
	}

	return id + "." + secret, nil
}

// randomTokenParts returns a 6-char id + 16-char secret, both lowercase
// hex (kubeadm token contract).
func randomTokenParts() (string, string, error) {
	const idLen, secretLen = 6, 16
	idBytes := make([]byte, idLen/2)
	secretBytes := make([]byte, secretLen/2)
	if _, err := rand.Read(idBytes); err != nil {
		return "", "", err
	}
	if _, err := rand.Read(secretBytes); err != nil {
		return "", "", err
	}
	return hex(idBytes), hex(secretBytes), nil
}

func hex(b []byte) string {
	const chars = "0123456789abcdef"
	out := make([]byte, len(b)*2)
	for i, c := range b {
		out[i*2] = chars[c>>4]
		out[i*2+1] = chars[c&0x0f]
	}
	return string(out)
}

// WaitFor is a tiny helper for retry loops in tests / debug paths.
var _ = wait.PollUntilContextTimeout
