// Package githubapp mints short-lived GitHub Actions runner
// registration tokens from a long-lived GitHub App credential set.
//
// Sits at the bottom of the credential chain the operator manages
// for builder hosts:
//
//   - The operator installs a GitHub App on the org once at env
//     bring-up. That gives us a (App ID, installation ID, RSA
//     private key) triple, none of which expire.
//   - The triple is stashed in 1Password, synced into the cluster
//     by ExternalSecrets as a Secret with three keys (`app-id`,
//     `installation-id`, `private-key`).
//   - At every Machine reconcile that requests an Actions runner,
//     the controller hands the Secret to a Client.Mint call. Mint
//     signs an RS256 JWT, exchanges it for an installation access
//     token (~1h), and exchanges that for an org-scope runner
//     registration token (~1h). The registration token goes to
//     `installActionsRunner` over SSH and the runner agent stores
//     its own long-lived auth credential locally after that.
//
// Net operator-facing UX: scale up, wait, done. No "rotate the
// registration token before scaling" footgun.
//
// Pure stdlib + crypto: parses both PKCS#1 (`-----BEGIN RSA PRIVATE
// KEY-----`) and PKCS#8 (`-----BEGIN PRIVATE KEY-----`) PEM blocks,
// since the "Generate a private key" button on a GitHub App
// dispenses the former and most other tooling the latter — operators
// shouldn't have to know which.
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
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// defaultAPIBase is github.com's public REST host. Tests inject a
// httptest server URL via Client.BaseURL.
const defaultAPIBase = "https://api.github.com"

// jwtLifetime keeps the App JWT well inside the 10-minute ceiling
// GitHub enforces. The 1-minute headroom absorbs clock skew between
// the controller pod and api.github.com without forcing an extra
// round-trip.
const jwtLifetime = 9 * time.Minute

// Credentials carries the GitHub App identity the controller reads
// from the operator-managed K8s Secret. AppID and InstallationID
// are not secrets in the strict sense — they're printed in the
// App's settings UI — but live in the same Secret so the chart only
// has to wire one ExternalSecret.
type Credentials struct {
	// AppID is the App ID printed at the top of the App's
	// settings page on GitHub. Numeric, ASCII-only.
	AppID string

	// InstallationID identifies the org install of the App. Found
	// on the App's installations list, or via
	//   GET /orgs/{org}/installation
	// with an App JWT.
	InstallationID string

	// PrivateKey is the PEM-encoded RSA private key the App's
	// "Generate a private key" button produces. PKCS#1 or PKCS#8;
	// either parses.
	PrivateKey []byte
}

// Client mints runner-registration tokens. Zero value is usable:
// HTTPClient defaults to http.DefaultClient and BaseURL to
// api.github.com.
type Client struct {
	HTTPClient *http.Client
	BaseURL    string

	// now lets tests pin the JWT iat/exp values for stable
	// signing-output comparisons. Production keeps it nil and gets
	// time.Now.
	now func() time.Time
}

// MintRunnerRegistrationToken returns a fresh org-scope runner
// registration token good for ~1h. Three round-trips: locally sign
// a JWT, POST it for an installation access token, POST that for
// the registration token. Any non-2xx response from GitHub
// surfaces as an error including the API's response body — the
// caller logs it via the reconciler's Recorder + Conditions and
// requeues, so transient hiccups self-heal.
func (c *Client) MintRunnerRegistrationToken(ctx context.Context, creds Credentials, org string) (string, error) {
	if creds.AppID == "" {
		return "", fmt.Errorf("github app credentials: app id is empty")
	}
	if creds.InstallationID == "" {
		return "", fmt.Errorf("github app credentials: installation id is empty")
	}
	if len(creds.PrivateKey) == 0 {
		return "", fmt.Errorf("github app credentials: private key is empty")
	}
	if org == "" {
		return "", fmt.Errorf("github app: org is empty")
	}

	jwt, err := signAppJWT(creds.AppID, creds.PrivateKey, c.timeNow())
	if err != nil {
		return "", fmt.Errorf("sign app jwt: %w", err)
	}
	installationToken, err := c.exchangeInstallationToken(ctx, creds.InstallationID, jwt)
	if err != nil {
		return "", fmt.Errorf("exchange installation token: %w", err)
	}
	regToken, err := c.exchangeRegistrationToken(ctx, org, installationToken)
	if err != nil {
		return "", fmt.Errorf("exchange registration token: %w", err)
	}
	return regToken, nil
}

func (c *Client) httpClient() *http.Client {
	if c.HTTPClient != nil {
		return c.HTTPClient
	}
	return http.DefaultClient
}

func (c *Client) baseURL() string {
	if c.BaseURL != "" {
		return c.BaseURL
	}
	return defaultAPIBase
}

func (c *Client) timeNow() time.Time {
	if c.now != nil {
		return c.now()
	}
	return time.Now()
}

func (c *Client) exchangeInstallationToken(ctx context.Context, installationID, jwt string) (string, error) {
	url := fmt.Sprintf("%s/app/installations/%s/access_tokens", c.baseURL(), installationID)
	return c.postForToken(ctx, url, "Bearer "+jwt)
}

func (c *Client) exchangeRegistrationToken(ctx context.Context, org, installationToken string) (string, error) {
	url := fmt.Sprintf("%s/orgs/%s/actions/runners/registration-token", c.baseURL(), org)
	return c.postForToken(ctx, url, "Bearer "+installationToken)
}

// postForToken handles the shared shape of GitHub's "POST returns
// a JSON body with a `token` field" endpoints. Both the installation-
// token and registration-token endpoints follow it; pulling the
// boilerplate out keeps each call site to a single fmt.Sprintf and
// one helper invocation.
func (c *Client) postForToken(ctx context.Context, url, authHeader string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("Authorization", authHeader)

	resp, err := c.httpClient().Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("github returned %s: %s", resp.Status, strings.TrimSpace(string(body)))
	}
	var payload struct {
		Token string `json:"token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return "", fmt.Errorf("decode response: %w", err)
	}
	if payload.Token == "" {
		return "", fmt.Errorf("github returned an empty token")
	}
	return payload.Token, nil
}

// signAppJWT builds the RS256-signed JWT GitHub's App-auth endpoints
// require. The 30-second iat backdating absorbs clock skew the
// other direction (controller pod ahead of api.github.com) — without
// it, GitHub occasionally rejects with "'iat' claim timestamp is in
// the future".
func signAppJWT(appID string, privateKeyPEM []byte, now time.Time) (string, error) {
	key, err := parseRSAPrivateKey(privateKeyPEM)
	if err != nil {
		return "", err
	}
	header := map[string]string{"alg": "RS256", "typ": "JWT"}
	claims := map[string]any{
		"iat": now.Add(-30 * time.Second).Unix(),
		"exp": now.Add(jwtLifetime).Unix(),
		"iss": appID,
	}
	headerSeg, err := encodeJWTSegment(header)
	if err != nil {
		return "", err
	}
	claimsSeg, err := encodeJWTSegment(claims)
	if err != nil {
		return "", err
	}
	signingInput := headerSeg + "." + claimsSeg
	hashed := sha256.Sum256([]byte(signingInput))
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, hashed[:])
	if err != nil {
		return "", fmt.Errorf("rsa sign: %w", err)
	}
	return signingInput + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}

func parseRSAPrivateKey(pemBytes []byte) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode(pemBytes)
	if block == nil {
		return nil, fmt.Errorf("no PEM block found in private key")
	}
	switch block.Type {
	case "RSA PRIVATE KEY":
		return x509.ParsePKCS1PrivateKey(block.Bytes)
	case "PRIVATE KEY":
		key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("parse pkcs8 private key: %w", err)
		}
		rsaKey, ok := key.(*rsa.PrivateKey)
		if !ok {
			return nil, fmt.Errorf("pkcs8 key is not RSA (got %T)", key)
		}
		return rsaKey, nil
	default:
		return nil, fmt.Errorf("unsupported PEM block type %q (want RSA PRIVATE KEY or PRIVATE KEY)", block.Type)
	}
}

func encodeJWTSegment(v any) (string, error) {
	b, err := json.Marshal(v)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
