package githubapp

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// TestMint_HappyPath wires a fake GitHub API and verifies the two
// exchanges happen in order with the expected headers and that the
// final registration token is what reaches the caller. Locks in the
// contract operators care about: "App credentials in, registration
// token out."
func TestMint_HappyPath(t *testing.T) {
	keyPEM, _ := newRSAKey(t)

	var seenInstallationAuth, seenRegistrationAuth string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/app/installations/98765432/access_tokens":
			seenInstallationAuth = r.Header.Get("Authorization")
			w.WriteHeader(http.StatusCreated)
			_ = json.NewEncoder(w).Encode(map[string]string{"token": "ghs_installation_token"})
		case "/orgs/tuist/actions/runners/registration-token":
			seenRegistrationAuth = r.Header.Get("Authorization")
			w.WriteHeader(http.StatusCreated)
			_ = json.NewEncoder(w).Encode(map[string]string{"token": "AABBCC_runner_registration_token"})
		default:
			t.Fatalf("unexpected request to %s", r.URL.Path)
		}
	}))
	t.Cleanup(server.Close)

	client := &Client{BaseURL: server.URL}
	token, err := client.MintRunnerRegistrationToken(context.Background(), Credentials{
		AppID:          "1234567",
		InstallationID: "98765432",
		PrivateKey:     keyPEM,
	}, "tuist")
	if err != nil {
		t.Fatalf("mint: %v", err)
	}
	if token != "AABBCC_runner_registration_token" {
		t.Fatalf("unexpected registration token: %q", token)
	}
	if !strings.HasPrefix(seenInstallationAuth, "Bearer ") {
		t.Fatalf("installation exchange missing Bearer prefix, got %q", seenInstallationAuth)
	}
	if seenRegistrationAuth != "Bearer ghs_installation_token" {
		t.Fatalf("registration exchange auth header = %q, want Bearer ghs_installation_token", seenRegistrationAuth)
	}
}

// TestMint_PropagatesGitHubError verifies a 4xx from GitHub surfaces
// with the response body intact so an operator looking at K8s events
// sees the actual reason ("Bad credentials", "Installation not
// found", etc.) instead of a bare status code.
func TestMint_PropagatesGitHubError(t *testing.T) {
	keyPEM, _ := newRSAKey(t)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"message":"Bad credentials"}`))
	}))
	t.Cleanup(server.Close)

	client := &Client{BaseURL: server.URL}
	_, err := client.MintRunnerRegistrationToken(context.Background(), Credentials{
		AppID:          "1234567",
		InstallationID: "98765432",
		PrivateKey:     keyPEM,
	}, "tuist")
	if err == nil {
		t.Fatal("expected error from 401, got nil")
	}
	if !strings.Contains(err.Error(), "401") || !strings.Contains(err.Error(), "Bad credentials") {
		t.Fatalf("error must carry status + body: %v", err)
	}
}

// TestMint_RejectsEmptyCredentials guards against an ESO-not-yet-
// synced Secret silently producing a malformed JWT that GitHub
// rejects with a generic message. We fail fast at the boundary with
// a field-specific error so the event tells the operator exactly
// which 1Password field is empty.
func TestMint_RejectsEmptyCredentials(t *testing.T) {
	keyPEM, _ := newRSAKey(t)
	cases := []struct {
		name  string
		creds Credentials
		want  string
	}{
		{"missing AppID", Credentials{InstallationID: "i", PrivateKey: keyPEM}, "app id is empty"},
		{"missing InstallationID", Credentials{AppID: "a", PrivateKey: keyPEM}, "installation id is empty"},
		{"missing PrivateKey", Credentials{AppID: "a", InstallationID: "i"}, "private key is empty"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := (&Client{}).MintRunnerRegistrationToken(context.Background(), tc.creds, "tuist")
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("got %v, want error containing %q", err, tc.want)
			}
		})
	}
}

// TestSignAppJWT_VerifiesWithPublicKey: roundtrip the JWT through
// the App's public key to lock in that we're producing a valid RS256
// signature, not just a well-formed three-segment string.
func TestSignAppJWT_VerifiesWithPublicKey(t *testing.T) {
	keyPEM, key := newRSAKey(t)
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)

	jwt, err := signAppJWT("1234567", keyPEM, now)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	parts := strings.Split(jwt, ".")
	if len(parts) != 3 {
		t.Fatalf("jwt should have 3 segments, got %d", len(parts))
	}

	// Header + claims sanity.
	claimsJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatalf("decode claims: %v", err)
	}
	var claims map[string]any
	if err := json.Unmarshal(claimsJSON, &claims); err != nil {
		t.Fatalf("unmarshal claims: %v", err)
	}
	if claims["iss"] != "1234567" {
		t.Fatalf("iss = %v, want 1234567", claims["iss"])
	}
	if int64(claims["iat"].(float64)) != now.Add(-30*time.Second).Unix() {
		t.Fatalf("iat backdating wrong: %v", claims["iat"])
	}

	// Verify the signature against the matching public key.
	signingInput := parts[0] + "." + parts[1]
	hashed := sha256.Sum256([]byte(signingInput))
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		t.Fatalf("decode sig: %v", err)
	}
	if err := rsa.VerifyPKCS1v15(&key.PublicKey, crypto.SHA256, hashed[:], sig); err != nil {
		t.Fatalf("signature didn't verify: %v", err)
	}
}

// TestParseRSAPrivateKey_AcceptsPKCS8 covers the case where the
// operator runs the private key through `openssl pkcs8` (or pastes
// one from a tool that emits PKCS#8). GitHub's "Generate a private
// key" button produces PKCS#1, but we accept either.
func TestParseRSAPrivateKey_AcceptsPKCS8(t *testing.T) {
	_, key := newRSAKey(t)
	pkcs8, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	pemBytes := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: pkcs8})

	parsed, err := parseRSAPrivateKey(pemBytes)
	if err != nil {
		t.Fatalf("parse pkcs8: %v", err)
	}
	if parsed.N.Cmp(key.N) != 0 {
		t.Fatal("parsed key modulus mismatch")
	}
}

// newRSAKey returns a freshly-generated RSA key as both PEM bytes
// (PKCS#1) and the parsed struct.
func newRSAKey(t *testing.T) ([]byte, *rsa.PrivateKey) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	pemBytes := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(key),
	})
	return pemBytes, key
}
