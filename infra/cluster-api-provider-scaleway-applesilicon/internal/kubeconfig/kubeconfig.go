// Package kubeconfig builds the kubeconfig YAML each Mac mini's
// tart-kubelet uses to authenticate to the cluster API server.
//
// We share a single ServiceAccount across the fleet (created by the
// Helm chart). The chart also creates a long-lived
// `kubernetes.io/service-account-token` Secret bound to it; the
// controller reads that Secret + the API server's external URL +
// CA bundle and produces a self-contained kubeconfig.
//
// One shared SA is a deliberate trade-off: simpler to operate, less
// strong tenant isolation than per-Node SAs would give. Acceptable
// while we're the only customer; per-Node SAs (or TLS bootstrap+CSR
// like upstream kubelet) become important when the runners product
// runs customer Pods on these hosts.
package kubeconfig

import (
	"context"
	"encoding/base64"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// Builder produces kubeconfig YAML on demand.
type Builder struct {
	Client       client.Client
	APIServerURL string
	CABundle     []byte // PEM-encoded CA cert (apiserver's signer)

	// TokenSecret is the name + namespace of the Secret holding the
	// shared SA token. Must be type kubernetes.io/service-account-token
	// so k8s populates `data.token` on its own.
	TokenSecretName      string
	TokenSecretNamespace string
}

// Render returns a kubeconfig YAML ready to be dropped on a Mac mini.
// Looks up the token Secret on every call so a kubeconfig built right
// after a token rotation always carries the current value.
func (b *Builder) Render(ctx context.Context, nodeName string) (string, error) {
	if b.APIServerURL == "" {
		return "", fmt.Errorf("kubeconfig: APIServerURL is empty")
	}
	if b.TokenSecretName == "" || b.TokenSecretNamespace == "" {
		return "", fmt.Errorf("kubeconfig: TokenSecret name/namespace required")
	}

	sec := &corev1.Secret{}
	if err := b.Client.Get(ctx, client.ObjectKey{
		Namespace: b.TokenSecretNamespace,
		Name:      b.TokenSecretName,
	}, sec); err != nil {
		return "", fmt.Errorf("kubeconfig: read token secret: %w", err)
	}
	token, ok := sec.Data["token"]
	if !ok || len(token) == 0 {
		return "", fmt.Errorf("kubeconfig: secret %s/%s has no 'token' key (has k8s populated it yet?)",
			b.TokenSecretNamespace, b.TokenSecretName)
	}

	// Prefer the CA from the token secret if it carries one — that's
	// the chain the apiserver actually serves. Fall back to the CA
	// bundle the operator was configured with.
	ca := sec.Data["ca.crt"]
	if len(ca) == 0 {
		ca = b.CABundle
	}
	if len(ca) == 0 {
		return "", fmt.Errorf("kubeconfig: no CA bundle (token secret missing ca.crt and operator has none configured)")
	}

	caB64 := base64.StdEncoding.EncodeToString(ca)
	user := fmt.Sprintf("tart-kubelet-%s", nodeName)
	return fmt.Sprintf(`apiVersion: v1
kind: Config
current-context: tart-kubelet
clusters:
  - name: cluster
    cluster:
      server: %s
      certificate-authority-data: %s
contexts:
  - name: tart-kubelet
    context:
      cluster: cluster
      user: %s
users:
  - name: %s
    user:
      token: %s
`, b.APIServerURL, caB64, user, user, string(token)), nil
}
