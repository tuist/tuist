package runner

import (
	"context"
	"errors"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/githubapp"
)

// TestResolve_NilSpecReturnsNil locks in the most common case:
// pure Node fleets (macosFleet, runnersFleet) don't carry a
// GHActionsRunner spec, and the resolver must short-circuit
// without touching the K8s API or GitHub.
func TestResolve_NilSpecReturnsNil(t *testing.T) {
	r := &GitHubAppResolver{Minter: &stubMinter{}}
	cfg, err := r.Resolve(context.Background(), "tuist", nil)
	if err != nil {
		t.Fatalf("nil spec must not error, got %v", err)
	}
	if cfg != nil {
		t.Fatalf("nil spec must produce nil config, got %+v", cfg)
	}
}

// TestResolve_HappyPath verifies the end-to-end flow: read the
// 3-field Secret, hand the credentials to the minter, return a
// bootstrap config with the minted token + the CR's labels/org
// passed through.
func TestResolve_HappyPath(t *testing.T) {
	secret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Namespace: "tuist", Name: "builders-fleet-gh-app"},
		Data: map[string][]byte{
			"app-id":          []byte("1234567"),
			"installation-id": []byte("98765432"),
			"private-key":     []byte("-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----\n"),
		},
	}
	minter := &stubMinter{token: "AABBCC_token"}
	r := &GitHubAppResolver{Client: fakeClientWith(t, secret), Minter: minter}

	cfg, err := r.Resolve(context.Background(), "tuist", &infrav1.GHActionsRunnerConfig{
		GHOrg:           "tuist",
		GHRunnerLabels:  "self-hosted,macos,bare-metal,vm-image-builder",
		GHRunnerVersion: "2.334.0",
		GHAppSecretName: "builders-fleet-gh-app",
	})
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	if cfg == nil {
		t.Fatal("expected non-nil config")
	}
	if cfg.GHRunnerRegistrationToken != "AABBCC_token" {
		t.Fatalf("token = %q, want AABBCC_token", cfg.GHRunnerRegistrationToken)
	}
	if cfg.GHOrg != "tuist" || cfg.GHRunnerLabels == "" || cfg.GHRunnerVersion != "2.334.0" {
		t.Fatalf("spec fields didn't pass through: %+v", cfg)
	}
	if minter.gotOrg != "tuist" {
		t.Fatalf("minter saw org=%q, want tuist", minter.gotOrg)
	}
	if minter.gotCreds.AppID != "1234567" || minter.gotCreds.InstallationID != "98765432" {
		t.Fatalf("minter saw wrong creds: %+v", minter.gotCreds)
	}
}

// TestResolve_TrimsWhitespaceOnNumericFields covers an operator
// papercut: 1Password's web UI tends to append a trailing newline
// when pasting App ID / installation ID values. Without the trim,
// `"1234567\n"` reaches the GitHub API and gets rejected with an
// opaque 400 the operator has to decode. Trim at the boundary.
func TestResolve_TrimsWhitespaceOnNumericFields(t *testing.T) {
	secret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Namespace: "tuist", Name: "gh-app"},
		Data: map[string][]byte{
			"app-id":          []byte("  1234567\n"),
			"installation-id": []byte("98765432\n"),
			"private-key":     []byte("-----BEGIN RSA PRIVATE KEY-----\n..."),
		},
	}
	minter := &stubMinter{token: "tok"}
	r := &GitHubAppResolver{Client: fakeClientWith(t, secret), Minter: minter}

	if _, err := r.Resolve(context.Background(), "tuist", &infrav1.GHActionsRunnerConfig{
		GHOrg: "tuist", GHAppSecretName: "gh-app",
	}); err != nil {
		t.Fatalf("resolve: %v", err)
	}
	if minter.gotCreds.AppID != "1234567" {
		t.Fatalf("AppID should be trimmed: got %q", minter.gotCreds.AppID)
	}
	if minter.gotCreds.InstallationID != "98765432" {
		t.Fatalf("InstallationID should be trimmed: got %q", minter.gotCreds.InstallationID)
	}
}

// TestResolve_MissingSecretFieldsListed surfaces a specific
// per-field error message rather than a generic "decode failed."
// The operator sees exactly which 1Password field is empty and
// can fix it without spelunking through controller logs.
func TestResolve_MissingSecretFieldsListed(t *testing.T) {
	secret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Namespace: "tuist", Name: "gh-app"},
		Data: map[string][]byte{
			"app-id":          []byte("1234567"),
			"installation-id": []byte(""),
			"private-key":     nil,
		},
	}
	r := &GitHubAppResolver{Client: fakeClientWith(t, secret), Minter: &stubMinter{}}

	_, err := r.Resolve(context.Background(), "tuist", &infrav1.GHActionsRunnerConfig{
		GHAppSecretName: "gh-app",
	})
	if err == nil {
		t.Fatal("expected error from empty fields")
	}
	if !strings.Contains(err.Error(), "installation-id") || !strings.Contains(err.Error(), "private-key") {
		t.Fatalf("error must name the missing fields: %v", err)
	}
}

// TestResolve_MissingSecretNameFailsLoudly: an operator forgetting
// to set ghAppSecretName on the CR shouldn't silently produce a
// config with an empty token. Fail fast with a clear message.
func TestResolve_MissingSecretNameFailsLoudly(t *testing.T) {
	r := &GitHubAppResolver{Client: fakeClientWith(t), Minter: &stubMinter{}}
	_, err := r.Resolve(context.Background(), "tuist", &infrav1.GHActionsRunnerConfig{})
	if err == nil || !strings.Contains(err.Error(), "ghAppSecretName") {
		t.Fatalf("want error mentioning ghAppSecretName, got %v", err)
	}
}

// TestResolve_MinterErrorPropagates verifies that a GitHub API
// failure (network blip, throttle, invalid credentials) bubbles
// up with the original cause attached. The controller relies on
// this to emit a meaningful event + requeue.
func TestResolve_MinterErrorPropagates(t *testing.T) {
	secret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Namespace: "tuist", Name: "gh-app"},
		Data: map[string][]byte{
			"app-id":          []byte("1"),
			"installation-id": []byte("2"),
			"private-key":     []byte("x"),
		},
	}
	minter := &stubMinter{err: errors.New("github 503")}
	r := &GitHubAppResolver{Client: fakeClientWith(t, secret), Minter: minter}

	_, err := r.Resolve(context.Background(), "tuist", &infrav1.GHActionsRunnerConfig{
		GHAppSecretName: "gh-app",
	})
	if err == nil || !strings.Contains(err.Error(), "github 503") {
		t.Fatalf("want minter error to surface, got %v", err)
	}
}

// === helpers ================================================================

type stubMinter struct {
	token    string
	err      error
	gotCreds githubapp.Credentials
	gotOrg   string
}

func (s *stubMinter) MintRunnerRegistrationToken(_ context.Context, creds githubapp.Credentials, org string) (string, error) {
	s.gotCreds = creds
	s.gotOrg = org
	if s.err != nil {
		return "", s.err
	}
	return s.token, nil
}

func fakeClientWith(t *testing.T, objs ...*corev1.Secret) client.Reader {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	builder := fake.NewClientBuilder().WithScheme(scheme)
	for _, s := range objs {
		builder = builder.WithObjects(s)
	}
	return builder.Build()
}
