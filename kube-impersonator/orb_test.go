package main

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

const (
	testWorkspace = "8e5f0d8f-a1a5-429d-843d-6096a60fa0a1"
	testAudience  = "https://kube-orb-prod.tuist.dev"
	testThread    = "T-01a1a59e-55fb-744b-9415-b85a337f24d2"
	testProject   = "1e345004-78e8-4e1d-bb72-27bb1a22d450"
)

type orbFixture struct {
	key       *rsa.PrivateKey
	issuer    string
	policyHit chan http.Header
	apiHit    chan http.Header
	jwksHits  atomic.Int32
	server    *httptest.Server
}

func newOrbFixture(t *testing.T) *orbFixture {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	f := &orbFixture{key: key, policyHit: make(chan http.Header, 1), apiHit: make(chan http.Header, 1)}

	jwks := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		f.jwksHits.Add(1)
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []map[string]string{{
			"kty": "RSA", "kid": "k1",
			"n": base64.RawURLEncoding.EncodeToString(key.N.Bytes()),
			"e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes()),
		}}})
	}))
	t.Cleanup(jwks.Close)
	f.issuer = "https://ampcode.example/api/workload-identity"

	policy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := r.Header.Clone()
		h.Set("Host", r.Host)
		f.policyHit <- h
		w.Header().Set("Impersonate-User", "amp-orb:"+r.Header.Get("X-Tuist-Amp-Email")+":"+r.Header.Get("X-Tuist-Amp-Thread-Id"))
		w.Header().Add("Impersonate-Group", "tuist-eng")
	}))
	t.Cleanup(policy.Close)

	api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.apiHit <- r.Header.Clone()
		w.WriteHeader(http.StatusTeapot)
	}))
	t.Cleanup(api.Close)
	apiURL, _ := url.Parse(api.URL)

	tokens := &tokenStore{token: "pod-sa-token"}
	proxy := &httputil.ReverseProxy{Director: rewriteToApiserver(apiURL, tokens)}
	verifier := newOrbVerifier(orbConfig{
		issuer: f.issuer, jwksURL: jwks.URL, audience: testAudience, workspaceID: testWorkspace, projectID: testProject,
	}, http.DefaultClient)

	f.server = httptest.NewServer(orbHandler(verifier, http.DefaultClient, policy.URL, proxy))
	t.Cleanup(f.server.Close)
	return f
}

func (f *orbFixture) claims() map[string]any {
	now := time.Now()
	return map[string]any{
		"iss": f.issuer, "aud": testAudience,
		"sub": "workspace:" + testWorkspace + ":project:p:user:u:thread:" + testThread,
		"iat": now.Unix(), "exp": now.Add(10 * time.Minute).Unix(),
		"email": "marek@tuist.dev", "email_verified": true, "token_use": "exchanged",
		"user_id": "user_01M5Y6GCBK8FBV5R1PD1H36AZ8", "thread_id": testThread,
		"workspace_id": testWorkspace, "project_id": testProject,
	}
}

func sign(t *testing.T, key *rsa.PrivateKey, header, claims map[string]any) string {
	t.Helper()
	enc := func(v any) string {
		b, _ := json.Marshal(v)
		return base64.RawURLEncoding.EncodeToString(b)
	}
	input := enc(header) + "." + enc(claims)
	digest := sha256.Sum256([]byte(input))
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	return input + "." + base64.RawURLEncoding.EncodeToString(sig)
}

func (f *orbFixture) do(t *testing.T, token string, extra http.Header) int {
	t.Helper()
	return f.doHost(t, "kube-orb-prod.tuist.dev", token, extra)
}

func (f *orbFixture) doHost(t *testing.T, host, token string, extra http.Header) int {
	t.Helper()
	req, _ := http.NewRequest(http.MethodGet, f.server.URL+"/api/v1/namespaces/tuist/pods", nil)
	req.Host = host
	for k, v := range extra {
		req.Header[k] = v
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	return resp.StatusCode
}

var rs256 = map[string]any{"alg": "RS256", "kid": "k1", "typ": "JWT"}

func TestOrbValidTokenIsImpersonatedFromVerifiedClaims(t *testing.T) {
	f := newOrbFixture(t)
	spoof := http.Header{
		"X-Pomerium-Claim-Email": {"someone-else@tuist.dev"},
		"X-Tuist-Amp-Email":      {"someone-else@tuist.dev"},
		"Impersonate-Group":      {"system:masters"},
	}

	if got := f.do(t, sign(t, f.key, rs256, f.claims()), spoof); got != http.StatusTeapot {
		t.Fatalf("status = %d, want the apiserver's 418", got)
	}

	policy := <-f.policyHit
	if policy.Get("Host") != "kube-orb-prod.tuist.dev" {
		t.Errorf("policy Host = %q", policy.Get("Host"))
	}
	if policy.Get("X-Tuist-Amp-Email") != "marek@tuist.dev" || policy.Get("X-Tuist-Amp-Thread-Id") != testThread {
		t.Errorf("policy got caller-chosen identity: %v", policy)
	}
	if policy.Get("X-Pomerium-Claim-Email") != "" {
		t.Error("orb listener forwarded a Pomerium identity header to the policy call")
	}

	api := <-f.apiHit
	if api.Get("Authorization") != "Bearer pod-sa-token" {
		t.Errorf("apiserver Authorization = %q; the orb token must not reach the apiserver", api.Get("Authorization"))
	}
	if got := api.Values("Impersonate-Group"); len(got) != 1 || got[0] != "tuist-eng" {
		t.Errorf("Impersonate-Group = %v, want only the policy's groups", got)
	}
	if got := api.Get("Impersonate-User"); got != "amp-orb:marek@tuist.dev:"+testThread {
		t.Errorf("Impersonate-User = %q", got)
	}
}

func TestOrbRejectsTokensWithoutCallingPolicy(t *testing.T) {
	f := newOrbFixture(t)
	other, _ := rsa.GenerateKey(rand.Reader, 2048)

	cases := map[string]func() string{
		"no token": func() string { return "" },
		"other workspace": func() string {
			c := f.claims()
			c["workspace_id"] = "00000000-0000-0000-0000-000000000000"
			return sign(t, f.key, rs256, c)
		},
		"other project": func() string {
			c := f.claims()
			c["project_id"] = "00000000-0000-0000-0000-000000000000"
			return sign(t, f.key, rs256, c)
		},
		"other audience": func() string {
			c := f.claims()
			c["aud"] = "https://kube-orb-canary.tuist.dev"
			return sign(t, f.key, rs256, c)
		},
		"other issuer": func() string {
			c := f.claims()
			c["iss"] = "https://evil.example"
			return sign(t, f.key, rs256, c)
		},
		"expired": func() string {
			c := f.claims()
			c["iat"] = time.Now().Add(-20 * time.Minute).Unix()
			c["exp"] = time.Now().Add(-10 * time.Minute).Unix()
			return sign(t, f.key, rs256, c)
		},
		"lifetime over an hour": func() string {
			c := f.claims()
			c["exp"] = time.Now().Add(30 * time.Minute).Unix()
			return sign(t, f.key, rs256, c)
		},
		"project setup token": func() string {
			c := f.claims()
			for _, k := range []string{"thread_id", "user_id", "email", "email_verified"} {
				delete(c, k)
			}
			return sign(t, f.key, rs256, c)
		},
		"not exchanged": func() string {
			c := f.claims()
			c["token_use"] = "mcp"
			return sign(t, f.key, rs256, c)
		},
		"unverified email": func() string {
			c := f.claims()
			c["email_verified"] = false
			return sign(t, f.key, rs256, c)
		},
		"forged with another key": func() string { return sign(t, other, rs256, f.claims()) },
		"alg none": func() string {
			parts := strings.Split(sign(t, f.key, map[string]any{"alg": "none", "kid": "k1"}, f.claims()), ".")
			return parts[0] + "." + parts[1] + "."
		},
		"HS256 confusion": func() string {
			return sign(t, f.key, map[string]any{"alg": "HS256", "kid": "k1"}, f.claims())
		},
	}

	for name, token := range cases {
		t.Run(name, func(t *testing.T) {
			if got := f.do(t, token(), nil); got != http.StatusUnauthorized {
				t.Fatalf("status = %d, want 401", got)
			}
			select {
			case <-f.policyHit:
				t.Fatal("policy was consulted for a rejected token")
			case <-f.apiHit:
				t.Fatal("apiserver was reached with a rejected token")
			default:
			}
		})
	}
}

func TestPomeriumListenerForwardsOnlyPomeriumIdentity(t *testing.T) {
	got := pomeriumPolicyHeaders(&http.Request{Header: http.Header{
		"X-Pomerium-Claim-Email": {"marek@tuist.dev"},
		"X-Tuist-Amp-Email":      {"someone-else@tuist.dev"},
		"X-Tuist-Amp-Thread-Id":  {testThread},
	}})
	if got.Get("X-Pomerium-Claim-Email") != "marek@tuist.dev" || got.Get("X-Tuist-Amp-Email") != "" || got.Get("X-Tuist-Amp-Thread-Id") != "" {
		t.Fatalf("human policy headers = %v", got)
	}
}

func TestOrbEnvComesFromVerifiedAudienceNotHost(t *testing.T) {
	f := newOrbFixture(t)

	// An in-cluster caller holding a valid prod token picks another Host.
	if got := f.doHost(t, "kube-orb-staging.tuist.dev", sign(t, f.key, rs256, f.claims()), nil); got != http.StatusTeapot {
		t.Fatalf("status = %d", got)
	}
	<-f.apiHit
	if host := (<-f.policyHit).Get("Host"); host != "kube-orb-prod.tuist.dev" {
		t.Fatalf("policy Host = %q, want the verified audience's host", host)
	}
}

func TestOrbUnknownKidFloodFetchesJWKSOnce(t *testing.T) {
	f := newOrbFixture(t)
	forged := sign(t, f.key, map[string]any{"alg": "RS256", "kid": "forged"}, f.claims())

	for range 20 {
		if got := f.do(t, forged, nil); got != http.StatusUnauthorized {
			t.Fatalf("status = %d, want 401", got)
		}
	}
	if hits := f.jwksHits.Load(); hits != 1 {
		t.Fatalf("JWKS fetched %d times for 20 forged kids, want 1", hits)
	}

	// Real tokens still verify from the cache the forged kids filled.
	if got := f.do(t, sign(t, f.key, rs256, f.claims()), nil); got != http.StatusTeapot {
		t.Fatalf("valid token status = %d", got)
	}
	<-f.policyHit
	<-f.apiHit
}
