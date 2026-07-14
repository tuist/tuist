//go:build e2e

// e2e_test verifies the App-credential exchange against the real
// GitHub API. Gated with the `e2e` build tag so unit-test CI skips
// it; opt in with:
//
//	go test -tags e2e -run TestE2E_MintAgainstRealGitHub -v ./internal/githubapp
//
// against env vars exported from 1Password:
//
//	APP_ID="$(op read op://tuist-k8s-staging/BUILDERS_FLEET_GITHUB_APP/app-id)" \
//	INSTALLATION_ID="$(op read op://tuist-k8s-staging/BUILDERS_FLEET_GITHUB_APP/installation-id)" \
//	PRIVATE_KEY="$(op read op://tuist-k8s-staging/BUILDERS_FLEET_GITHUB_APP/private-key)" \
//	GH_ORG=tuist \
//	go test -tags e2e -run TestE2E_MintAgainstRealGitHub -v ./internal/githubapp
//
// Running it against the real API also produces a real ~1h
// registration token visible in `gh api /orgs/<org>/actions/runners`
// — useful as a one-shot operator-side check whenever the App
// credentials in 1P get re-rolled.

package githubapp

import (
	"context"
	"os"
	"testing"
)

func TestE2E_MintAgainstRealGitHub(t *testing.T) {
	creds := Credentials{
		AppID:          os.Getenv("APP_ID"),
		InstallationID: os.Getenv("INSTALLATION_ID"),
		PrivateKey:     []byte(os.Getenv("PRIVATE_KEY")),
	}
	org := os.Getenv("GH_ORG")
	if creds.AppID == "" || creds.InstallationID == "" || len(creds.PrivateKey) == 0 || org == "" {
		t.Skip("set APP_ID, INSTALLATION_ID, PRIVATE_KEY, GH_ORG to run")
	}

	client := &Client{}
	token, err := client.MintRunnerRegistrationToken(context.Background(), creds, org)
	if err != nil {
		t.Fatalf("mint: %v", err)
	}
	if len(token) < 20 {
		t.Fatalf("registration token suspiciously short: %d chars", len(token))
	}
	t.Logf("got registration token (first 8 chars): %s…", token[:8])
}
