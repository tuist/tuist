// Package kubeconfig builds the kubeconfig YAML each Mac mini's
// tart-kubelet uses to authenticate to the cluster API server.
//
// Per-Node identity. The operator's credentials.Manager mints a
// per-machine ServiceAccount + service-account-token Secret +
// ClusterRoleBinding before this package renders. The Builder takes
// the resulting (token, ca) bytes — it doesn't know how the SA was
// created. The split keeps kubeconfig rendering independent of the
// identity model so a future BYOC provider that uses (say) CSR-based
// kubelet TLS bootstrap can reuse this Builder unchanged.
//
// We deliberately don't share a token across the fleet: a compromised
// Mac mini can only impersonate its own Node identity, not every
// other host's.
package kubeconfig

import (
	"context"
	"encoding/base64"
	"fmt"
)

// Builder produces kubeconfig YAML on demand.
type Builder struct {
	APIServerURL string
}

// Render returns a kubeconfig YAML ready to be dropped on a Mac mini,
// authenticating as the per-machine ServiceAccount whose token + CA
// the caller supplies. Caller is responsible for getting (token, ca)
// from credentials.Manager.EnsureNodeIdentity.
func (b *Builder) Render(ctx context.Context, machineName string, token, ca []byte) (string, error) {
	return b.render(machineName, token, ca, "")
}

// TartKubeletTokenFile is where a macOS host keeps the token it rotates.
// The kubeconfig names it as `tokenFile`, which client-go re-reads and
// prefers over the inline token once it exists; tart-kubelet seeds it from
// the inline token whenever the operator pushed a newer one.
const TartKubeletTokenFile = "/etc/tart-kubelet/token"

// RenderTartKubelet renders a macOS host's kubeconfig: the operator's fresh
// token inline, and the file tart-kubelet keeps the token it rotates in.
func (b *Builder) RenderTartKubelet(_ context.Context, machineName string, token, ca []byte) (string, error) {
	return b.render(machineName, token, ca, TartKubeletTokenFile)
}

func (b *Builder) render(machineName string, token, ca []byte, tokenFile string) (string, error) {
	if b.APIServerURL == "" {
		return "", fmt.Errorf("kubeconfig: APIServerURL is empty")
	}
	if len(token) == 0 {
		return "", fmt.Errorf("kubeconfig: token is empty")
	}
	if len(ca) == 0 {
		return "", fmt.Errorf("kubeconfig: ca bundle is empty")
	}
	caB64 := base64.StdEncoding.EncodeToString(ca)
	user := "tart-kubelet-" + machineName
	tokenFileLine := ""
	if tokenFile != "" {
		tokenFileLine = "      tokenFile: " + tokenFile + "\n"
	}
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
%s`, b.APIServerURL, caB64, user, user, string(token), tokenFileLine), nil
}
