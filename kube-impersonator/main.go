// kube-impersonator runs as a sidecar in each env's Pomerium pod.
// Pomerium handles the OIDC dance, authenticates the user, drops
// the X-Pomerium-Claim-Email header, and forwards every kubectl
// request to us on 127.0.0.1:8081. We:
//
//  1. Call tuist-ops's PolicyController over the tailnet egress
//     to resolve the right impersonation tier for (user, env)
//     given the user's tailnet role and any active elevation row.
//  2. Strip the inbound bearer (Pomerium session) and replace it
//     with the pod's ServiceAccount token. The apiserver sees the
//     Pomerium-pod SA as the requester and consumes the
//     Impersonate-User / Impersonate-Group headers for RBAC.
//  3. Strip any client-supplied Impersonate-* headers (we are the
//     sole source of truth) and emit our resolved ones.
//  4. Reverse-proxy the request to https://kubernetes.default.svc:443.
//
// Failure mode: closed. If the policy call to tuist-ops fails, we
// return 502 to kubectl rather than forward to the apiserver
// without the impersonation decision. Better to break kubectl
// briefly than to escalate privileges silently.
package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

const (
	defaultListenAddr      = ":8081"
	defaultApiserverURL    = "https://kubernetes.default.svc:443"
	defaultSATokenFile     = "/var/run/secrets/kubernetes.io/serviceaccount/token"
	defaultCACertFile      = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
	defaultPolicyURL       = "http://tuist-ops-egress/api/v1/policy"
	defaultPolicyTimeoutMS = 5000
	defaultRefreshTTLSec   = 300
)

type config struct {
	listenAddr    string
	apiserverURL  string
	saTokenFile   string
	caCertFile    string
	policyURL     string
	policyTimeout time.Duration
	refreshTTL    time.Duration
}

func configFromEnv() config {
	return config{
		listenAddr:    envOr("LISTEN_ADDR", defaultListenAddr),
		apiserverURL:  envOr("APISERVER_URL", defaultApiserverURL),
		saTokenFile:   envOr("SA_TOKEN_FILE", defaultSATokenFile),
		caCertFile:    envOr("CA_CERT_FILE", defaultCACertFile),
		policyURL:     envOr("POLICY_URL", defaultPolicyURL),
		policyTimeout: time.Duration(envIntOr("POLICY_TIMEOUT_MS", defaultPolicyTimeoutMS)) * time.Millisecond,
		refreshTTL:    time.Duration(envIntOr("REFRESH_TTL_SEC", defaultRefreshTTLSec)) * time.Second,
	}
}

type identity struct {
	user   string
	groups []string
}

type ctxKey int

const identityKey ctxKey = 0

type tokenStore struct {
	mu    sync.RWMutex
	token string
	file  string
}

func (t *tokenStore) reload() error {
	b, err := os.ReadFile(t.file)
	if err != nil {
		return fmt.Errorf("read SA token: %w", err)
	}
	v := strings.TrimSpace(string(b))
	if v == "" {
		return errors.New("SA token file empty")
	}
	t.mu.Lock()
	t.token = v
	t.mu.Unlock()
	return nil
}

func (t *tokenStore) get() string {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.token
}

func main() {
	cfg := configFromEnv()

	tokens := &tokenStore{file: cfg.saTokenFile}
	if err := tokens.reload(); err != nil {
		log.Fatalf("initial SA token load: %v", err)
	}
	go refreshTokenLoop(tokens, cfg.refreshTTL)

	apiURL, err := url.Parse(cfg.apiserverURL)
	if err != nil {
		log.Fatalf("parse apiserver URL %q: %v", cfg.apiserverURL, err)
	}

	apiTransport, err := apiserverTransport(cfg.caCertFile)
	if err != nil {
		log.Fatalf("apiserver transport: %v", err)
	}

	policyClient := &http.Client{Timeout: cfg.policyTimeout}
	proxy := &httputil.ReverseProxy{
		Director:  rewriteToApiserver(apiURL, tokens),
		Transport: apiTransport,
		ErrorLog:  log.New(os.Stderr, "[proxy] ", log.LstdFlags),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.Handle("/", impersonatingHandler(policyClient, cfg.policyURL, proxy))

	log.Printf("kube-impersonator: listen=%s policy=%s apiserver=%s",
		cfg.listenAddr, cfg.policyURL, cfg.apiserverURL)
	srv := &http.Server{
		Addr:              cfg.listenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("listen: %v", err)
	}
}

func refreshTokenLoop(t *tokenStore, ttl time.Duration) {
	tick := time.NewTicker(ttl)
	defer tick.Stop()
	for range tick.C {
		if err := t.reload(); err != nil {
			log.Printf("SA token refresh failed (keeping previous): %v", err)
		}
	}
}

// impersonatingHandler runs the policy lookup first, attaches the
// resolved identity to the request context, then hands off to the
// reverse-proxy. Policy failure → 502 (fail closed).
func impersonatingHandler(client *http.Client, policyURL string, proxy *httputil.ReverseProxy) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id, err := callPolicy(r.Context(), client, policyURL, r)
		if err != nil {
			log.Printf("policy lookup failed for %s: %v", r.URL.Path, err)
			http.Error(w, "impersonation policy unavailable", http.StatusBadGateway)
			return
		}
		r = r.WithContext(context.WithValue(r.Context(), identityKey, id))
		proxy.ServeHTTP(w, r)
	})
}

// callPolicy issues an HTTP GET to tuist-ops's policy endpoint
// with the headers PolicyController reads (Host derives env,
// X-Pomerium-Claim-Email is the user). Response 200 + headers →
// identity. Anything else → error.
func callPolicy(ctx context.Context, c *http.Client, policyURL string, orig *http.Request) (identity, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, policyURL, nil)
	if err != nil {
		return identity{}, err
	}
	// Host is what env derives from. Pomerium leaves it as the
	// public hostname (kube-<env>.tuist.dev) when we ask it to.
	req.Host = orig.Host
	for _, h := range []string{"X-Pomerium-Claim-Email", "X-Tuist-Env"} {
		if v := orig.Header.Get(h); v != "" {
			req.Header.Set(h, v)
		}
	}

	resp, err := c.Do(req)
	if err != nil {
		return identity{}, fmt.Errorf("dial: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return identity{}, fmt.Errorf("status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	user := resp.Header.Get("Impersonate-User")
	if user == "" {
		return identity{}, errors.New("missing Impersonate-User in policy response")
	}
	groups := resp.Header.Values("Impersonate-Group")
	if len(groups) == 0 {
		return identity{}, errors.New("missing Impersonate-Group in policy response")
	}
	return identity{user: user, groups: groups}, nil
}

func rewriteToApiserver(target *url.URL, tokens *tokenStore) func(*http.Request) {
	return func(req *http.Request) {
		id, _ := req.Context().Value(identityKey).(identity)

		req.URL.Scheme = target.Scheme
		req.URL.Host = target.Host
		req.Host = target.Host

		req.Header.Del("Authorization")
		req.Header.Set("Authorization", "Bearer "+tokens.get())

		// We are the sole source of truth for impersonation —
		// any client-supplied Impersonate-* must be stripped
		// before we set our own.
		stripImpersonate(req.Header)
		req.Header.Set("Impersonate-User", id.user)
		for _, g := range id.groups {
			req.Header.Add("Impersonate-Group", g)
		}
	}
}

func stripImpersonate(h http.Header) {
	for k := range h {
		if strings.HasPrefix(strings.ToLower(k), "impersonate-") {
			h.Del(k)
		}
	}
}

// apiserverTransport pins the cluster CA so we get full TLS
// verification on the upstream hop. The cert + token are
// automounted by Kubernetes at the same conventional path
// (`/var/run/secrets/kubernetes.io/serviceaccount/`) that
// every in-cluster client uses; reading from there means we
// trust exactly the CA that signs `kubernetes.default.svc`'s
// serving cert and nothing else. No InsecureSkipVerify.
func apiserverTransport(caCertFile string) (http.RoundTripper, error) {
	caPEM, err := os.ReadFile(caCertFile)
	if err != nil {
		return nil, fmt.Errorf("read cluster CA cert %q: %w", caCertFile, err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(caPEM) {
		return nil, fmt.Errorf("cluster CA cert at %q contains no usable PEM blocks", caCertFile)
	}

	return &http.Transport{
		TLSClientConfig: &tls.Config{
			RootCAs:    pool,
			MinVersion: tls.VersionTLS12,
		},
		// Sane defaults; rely on the standard library otherwise.
		MaxIdleConns:        50,
		MaxIdleConnsPerHost: 10,
		IdleConnTimeout:     90 * time.Second,
	}, nil
}

func envOr(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

func envIntOr(key string, def int) int {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return def
	}
	var out int
	if _, err := fmt.Sscanf(v, "%d", &out); err != nil || out <= 0 {
		return def
	}
	return out
}
