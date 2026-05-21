// Package runner resolves the per-Machine GitHub Actions runner
// bootstrap config that the Scaleway Apple Silicon CAPI provider
// hands to the host-side bootstrap step.
//
// The CAPI provider's job ends at "Mac mini ordered, SSH-reachable,
// tart-kubelet installed." Whether the host also runs a workload-
// level agent (today: a GitHub Actions self-hosted runner for the
// vm-image-builder fleet) is a separate concern. This package is
// the seam between those two layers: it reads the operator-managed
// credential Secret named on the Machine CR, exchanges those long-
// lived credentials for a short-lived runner registration token,
// and returns a fully-resolved `bootstrap.GHActionsRunnerConfig`
// ready to install.
//
// Encapsulating it here keeps GitHub-specific knowledge — App
// credential shape, JWT-signed installation-token exchange,
// runner-registration-token endpoint — out of the Scaleway CR
// reconciler. The reconciler depends only on the `Resolver`
// interface; the production wiring in `cmd/manager/main.go` picks
// `*GitHubAppResolver`. Adding a PAT-based, GitLab Runner, or
// Forgejo equivalent is a new struct that implements the same
// interface, with no edits to the Machine controller.
package runner

import (
	"context"
	"fmt"
	"strings"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/githubapp"
	"github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// Resolver turns a `*infrav1.GHActionsRunnerConfig` declared on a
// Machine into a fully-populated `*bootstrap.GHActionsRunnerConfig`
// the host-side bootstrap can consume. Returning nil for both the
// pointer and the error means the Machine doesn't request a runner
// (the common case for pure Node fleets).
type Resolver interface {
	Resolve(ctx context.Context, namespace string, spec *infrav1.GHActionsRunnerConfig) (*bootstrap.GHActionsRunnerConfig, error)
}

// GitHubAppMinter is the slice of the public-GitHub-API surface
// GitHubAppResolver needs. Declared as an interface so tests can
// drop in a stub without making real HTTP calls. The concrete
// `*githubapp.Client` satisfies it.
type GitHubAppMinter interface {
	MintRunnerRegistrationToken(ctx context.Context, creds githubapp.Credentials, org string) (string, error)
}

// GitHubAppResolver pulls the App credential triple (App ID,
// installation ID, RSA private key) out of an operator-managed
// K8s Secret in the Machine's namespace and exchanges them for a
// short-lived runner registration token via the public GitHub API.
//
// The Secret shape (`app-id`, `installation-id`, `private-key`) is
// owned by this resolver, not by the CR. The CR carries only the
// Secret name; rotating credentials, switching to a different App,
// or migrating to a different storage backend all happen behind
// this interface without touching the Machine controller.
type GitHubAppResolver struct {
	// Client reads the credential Secret in the Machine's
	// namespace. Same client surface the controller uses for the
	// rest of its work.
	Client client.Reader

	// Minter performs the JWT → installation-token →
	// registration-token exchange against the public GitHub API.
	// Wired to `*githubapp.Client` in production; tests use a
	// stub that returns a canned token.
	Minter GitHubAppMinter
}

// Resolve reads the credential Secret named in `spec.GHAppSecretName`,
// confirms all three fields are present, and mints a fresh
// registration token good for ~1h. A missing-or-empty Secret OR a
// GitHub API hiccup is a transient error: ESO may not have synced
// yet, or GitHub may be having a bad minute. The caller requeues;
// we don't surface a terminal failure here.
func (g *GitHubAppResolver) Resolve(
	ctx context.Context,
	namespace string,
	spec *infrav1.GHActionsRunnerConfig,
) (*bootstrap.GHActionsRunnerConfig, error) {
	if spec == nil {
		return nil, nil
	}
	if spec.GHAppSecretName == "" {
		return nil, fmt.Errorf("ghActionsRunner.ghAppSecretName is required when ghActionsRunner is set")
	}
	if g.Minter == nil {
		return nil, fmt.Errorf("GitHubAppResolver.Minter not wired; the manager binary must set it")
	}

	secret := &corev1.Secret{}
	if err := g.Client.Get(ctx, types.NamespacedName{
		Namespace: namespace,
		Name:      spec.GHAppSecretName,
	}, secret); err != nil {
		return nil, fmt.Errorf("read github-app secret %s/%s: %w",
			namespace, spec.GHAppSecretName, err)
	}
	creds := githubapp.Credentials{
		AppID:          strings.TrimSpace(string(secret.Data["app-id"])),
		InstallationID: strings.TrimSpace(string(secret.Data["installation-id"])),
		PrivateKey:     secret.Data["private-key"],
	}
	var missing []string
	if creds.AppID == "" {
		missing = append(missing, "app-id")
	}
	if creds.InstallationID == "" {
		missing = append(missing, "installation-id")
	}
	if len(creds.PrivateKey) == 0 {
		missing = append(missing, "private-key")
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("github-app secret %s/%s missing field(s): %s",
			namespace, spec.GHAppSecretName, strings.Join(missing, ", "))
	}

	token, err := g.Minter.MintRunnerRegistrationToken(ctx, creds, spec.GHOrg)
	if err != nil {
		return nil, fmt.Errorf("mint runner registration token via github app: %w", err)
	}
	return &bootstrap.GHActionsRunnerConfig{
		GHOrg:                     spec.GHOrg,
		GHRunnerLabels:            spec.GHRunnerLabels,
		GHRunnerVersion:           spec.GHRunnerVersion,
		GHRunnerRegistrationToken: token,
	}, nil
}
