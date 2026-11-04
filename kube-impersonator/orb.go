// Orb access: kubectl from an Amp orb, authenticated by the orb's own
// Amp workload identity token instead of a Pomerium browser session.
//
// The orb runs `amp orb id-token --audience <ORB_AUDIENCE>` (through a
// kubectl exec credential plugin) and presents the token as its bearer.
// This listener verifies it against Amp's published keys, requires our
// Amp workspace and a token minted for a thread (not project setup),
// then asks tuist-ops for the impersonation decision with the verified
// claims. Nothing the client sends besides the bearer reaches the
// policy call, so a caller cannot choose its own identity.
//
// Unlike the Pomerium listener, this one is reachable from the pod
// network: the token, not the bind address, is the authentication.
package main

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	"net/http/httputil"
	"regexp"
	"strings"
	"sync"
	"time"
)

const (
	defaultOrbIssuer = "https://ampcode.com/api/workload-identity"
	// Amp mints tokens for 60 s to 1 h.
	orbMaxTokenLifetime = time.Hour
	orbClockSkew        = 60 * time.Second
	// A token signed with an unknown key triggers a refetch, at most
	// this often, so a flood of forged kids cannot hammer Amp.
	jwksMinRefetch = time.Minute
	jwksMaxAge     = time.Hour
)

var threadIDPattern = regexp.MustCompile(`^T-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

type orbConfig struct {
	listenAddr  string
	issuer      string
	jwksURL     string
	audience    string
	workspaceID string
}

func orbConfigFromEnv() (orbConfig, error) {
	cfg := orbConfig{
		listenAddr:  envOr("ORB_LISTEN_ADDR", ""),
		issuer:      envOr("ORB_ISSUER", defaultOrbIssuer),
		audience:    envOr("ORB_AUDIENCE", ""),
		workspaceID: envOr("ORB_WORKSPACE_ID", ""),
	}
	cfg.jwksURL = envOr("ORB_JWKS_URL", cfg.issuer+"/jwks.json")
	if cfg.listenAddr == "" {
		return cfg, nil
	}
	if cfg.audience == "" || cfg.workspaceID == "" {
		return cfg, errors.New("ORB_LISTEN_ADDR requires ORB_AUDIENCE and ORB_WORKSPACE_ID")
	}
	return cfg, nil
}

// orbIdentity is what a verified token says about its caller.
type orbIdentity struct {
	email    string
	userID   string
	threadID string
}

type orbClaims struct {
	Iss           string          `json:"iss"`
	Aud           json.RawMessage `json:"aud"`
	Exp           int64           `json:"exp"`
	Iat           int64           `json:"iat"`
	Nbf           int64           `json:"nbf"`
	TokenUse      string          `json:"token_use"`
	WorkspaceID   string          `json:"workspace_id"`
	UserID        string          `json:"user_id"`
	ThreadID      string          `json:"thread_id"`
	Email         string          `json:"email"`
	EmailVerified bool            `json:"email_verified"`
}

type orbVerifier struct {
	cfg  orbConfig
	keys *jwksCache
	now  func() time.Time
}

func newOrbVerifier(cfg orbConfig, client *http.Client) *orbVerifier {
	return &orbVerifier{
		cfg:  cfg,
		keys: &jwksCache{url: cfg.jwksURL, client: client, keys: map[string]*rsa.PublicKey{}},
		now:  time.Now,
	}
}

func (v *orbVerifier) verify(ctx context.Context, token string) (orbIdentity, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return orbIdentity{}, errors.New("not a JWT")
	}

	var header struct {
		Alg string `json:"alg"`
		Kid string `json:"kid"`
	}
	if err := decodeSegment(parts[0], &header); err != nil {
		return orbIdentity{}, fmt.Errorf("header: %w", err)
	}
	// Pinned: Amp signs with RS256 only. Never take the algorithm
	// from the token beyond checking it matches.
	if header.Alg != "RS256" || header.Kid == "" {
		return orbIdentity{}, fmt.Errorf("unsupported alg %q or missing kid", header.Alg)
	}

	key, err := v.keys.get(ctx, header.Kid, v.now())
	if err != nil {
		return orbIdentity{}, err
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return orbIdentity{}, fmt.Errorf("signature encoding: %w", err)
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if err := rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], sig); err != nil {
		return orbIdentity{}, errors.New("bad signature")
	}

	var c orbClaims
	if err := decodeSegment(parts[1], &c); err != nil {
		return orbIdentity{}, fmt.Errorf("claims: %w", err)
	}
	return v.checkClaims(c)
}

func (v *orbVerifier) checkClaims(c orbClaims) (orbIdentity, error) {
	now := v.now()
	switch {
	case c.Iss != v.cfg.issuer:
		return orbIdentity{}, fmt.Errorf("issuer %q", c.Iss)
	case !audienceContains(c.Aud, v.cfg.audience):
		return orbIdentity{}, errors.New("audience mismatch")
	case c.Exp == 0 || c.Iat == 0:
		return orbIdentity{}, errors.New("missing exp or iat")
	case now.After(time.Unix(c.Exp, 0).Add(orbClockSkew)):
		return orbIdentity{}, errors.New("expired")
	case time.Unix(c.Iat, 0).After(now.Add(orbClockSkew)):
		return orbIdentity{}, errors.New("issued in the future")
	case c.Nbf != 0 && time.Unix(c.Nbf, 0).After(now.Add(orbClockSkew)):
		return orbIdentity{}, errors.New("not yet valid")
	case time.Unix(c.Exp, 0).Sub(time.Unix(c.Iat, 0)) > orbMaxTokenLifetime:
		return orbIdentity{}, errors.New("lifetime too long")
	// Amp's audience is not a secret: any orb in any workspace can
	// mint a token for it. The workspace is what makes it ours.
	case c.WorkspaceID != v.cfg.workspaceID:
		return orbIdentity{}, fmt.Errorf("workspace %q", c.WorkspaceID)
	case c.TokenUse != "exchanged":
		return orbIdentity{}, fmt.Errorf("token_use %q", c.TokenUse)
	// Project-setup tokens carry no user or thread; they identify a
	// project snapshot, not a person, and get nothing here.
	case !threadIDPattern.MatchString(c.ThreadID) || c.UserID == "":
		return orbIdentity{}, errors.New("not a thread token")
	case c.Email == "" || !c.EmailVerified:
		return orbIdentity{}, errors.New("no verified email")
	}
	return orbIdentity{email: c.Email, userID: c.UserID, threadID: c.ThreadID}, nil
}

func audienceContains(raw json.RawMessage, want string) bool {
	var one string
	if json.Unmarshal(raw, &one) == nil {
		return one == want
	}
	var many []string
	if json.Unmarshal(raw, &many) == nil {
		for _, a := range many {
			if a == want {
				return true
			}
		}
	}
	return false
}

func decodeSegment(seg string, out any) error {
	b, err := base64.RawURLEncoding.DecodeString(seg)
	if err != nil {
		return err
	}
	dec := json.NewDecoder(bytes.NewReader(b))
	return dec.Decode(out)
}

type jwksCache struct {
	url    string
	client *http.Client

	mu          sync.Mutex
	keys        map[string]*rsa.PublicKey
	fetchedAt   time.Time
	lastAttempt time.Time
}

func (c *jwksCache) get(ctx context.Context, kid string, now time.Time) (*rsa.PublicKey, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	key, ok := c.keys[kid]
	stale := now.Sub(c.fetchedAt) > jwksMaxAge
	if ok && !stale {
		return key, nil
	}
	if now.Sub(c.lastAttempt) >= jwksMinRefetch || stale {
		c.lastAttempt = now
		if keys, err := fetchJWKS(ctx, c.client, c.url); err != nil {
			log.Printf("orb: JWKS fetch failed (keeping %d cached keys): %v", len(c.keys), err)
		} else {
			c.keys, c.fetchedAt = keys, now
		}
	}
	if key, ok := c.keys[kid]; ok {
		return key, nil
	}
	return nil, fmt.Errorf("unknown signing key %q", kid)
}

func fetchJWKS(ctx context.Context, client *http.Client, url string) (map[string]*rsa.PublicKey, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status %d", resp.StatusCode)
	}

	var doc struct {
		Keys []struct {
			Kty string `json:"kty"`
			Kid string `json:"kid"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&doc); err != nil {
		return nil, err
	}
	keys := map[string]*rsa.PublicKey{}
	for _, k := range doc.Keys {
		if k.Kty != "RSA" || k.Kid == "" {
			continue
		}
		n, errN := base64.RawURLEncoding.DecodeString(k.N)
		e, errE := base64.RawURLEncoding.DecodeString(k.E)
		if errN != nil || errE != nil || len(e) == 0 || len(e) > 4 {
			continue
		}
		pub := &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: int(new(big.Int).SetBytes(e).Int64())}
		if pub.N.BitLen() < 2048 {
			continue
		}
		keys[k.Kid] = pub
	}
	if len(keys) == 0 {
		return nil, errors.New("no usable RSA keys")
	}
	return keys, nil
}

// orbHandler authenticates the orb, resolves its tier through
// tuist-ops and proxies to the apiserver. It logs one line per
// request: this path does not pass through Pomerium, so these lines
// are the access trail.
func orbHandler(v *orbVerifier, client *http.Client, policyURL string, proxy *httputil.ReverseProxy) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || token == "" {
			// 401 makes client-go rerun the exec credential plugin.
			http.Error(w, "Amp workload identity token required", http.StatusUnauthorized)
			return
		}
		orb, err := v.verify(r.Context(), strings.TrimSpace(token))
		if err != nil {
			log.Printf("orb: rejected token for %s %s: %v", r.Method, r.URL.Path, err)
			http.Error(w, "invalid Amp workload identity token", http.StatusUnauthorized)
			return
		}

		id, err := callPolicy(r.Context(), client, policyURL, r.Host, http.Header{
			"X-Tuist-Amp-Email":     {orb.email},
			"X-Tuist-Amp-User-Id":   {orb.userID},
			"X-Tuist-Amp-Thread-Id": {orb.threadID},
		})
		if err != nil {
			log.Printf("orb: policy lookup failed for %s (%s): %v", orb.email, orb.threadID, err)
			http.Error(w, "impersonation policy unavailable", http.StatusBadGateway)
			return
		}

		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		proxy.ServeHTTP(rec, r.WithContext(context.WithValue(r.Context(), identityKey, id)))
		log.Printf("orb: email=%s thread=%s user=%s groups=%s method=%s path=%s status=%d",
			orb.email, orb.threadID, id.user, strings.Join(id.groups, ","), r.Method, r.URL.Path, rec.status)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

// Flush and Unwrap keep `logs -f`, watches and connection upgrades
// working through the recorder.
func (s *statusRecorder) Flush() {
	if f, ok := s.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

func (s *statusRecorder) Unwrap() http.ResponseWriter { return s.ResponseWriter }
