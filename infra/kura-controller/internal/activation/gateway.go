// Package activation serves the wildcard cache fallback while an account has no
// regional DNS record. It never owns storage or replays an artifact request.
package activation

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"
)

var handlePattern = regexp.MustCompile(`^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$`)

// Servers is an explicit environment allowlist, never derived from request URLs.
type Servers map[string]string

type Gateway struct {
	Servers   Servers
	Control   *http.Client
	Transport http.RoundTripper
	Wait      time.Duration
	Poll      time.Duration
	Refusals  *Refusals
	slots     chan struct{}
	streams   chan struct{}
}

func New(servers Servers, concurrency int) *Gateway {
	return &Gateway{
		Servers:   servers,
		Control:   &http.Client{Timeout: 3 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }},
		Transport: &http.Transport{Proxy: nil, ForceAttemptHTTP2: true, MaxIdleConns: 128, MaxIdleConnsPerHost: 8, MaxConnsPerHost: 32, IdleConnTimeout: 30 * time.Second, TLSHandshakeTimeout: 5 * time.Second, ResponseHeaderTimeout: 30 * time.Second},
		Wait:      20 * time.Second, Poll: 2 * time.Second, Refusals: NewRefusals(time.Minute, 4096),
		slots: make(chan struct{}, concurrency), streams: make(chan struct{}, concurrency),
	}
}

// Refusals keeps recent 401/403 verdicts per credential digest and host, so a
// client resending a refused credential does not reach the control plane.
type Refusals struct {
	ttl     time.Duration
	limit   int
	now     func() time.Time
	mu      sync.Mutex
	entries map[[sha256.Size]byte]refusal
}

type refusal struct {
	status  int
	expires time.Time
}

func NewRefusals(ttl time.Duration, limit int) *Refusals {
	return &Refusals{ttl: ttl, limit: limit, now: time.Now, entries: make(map[[sha256.Size]byte]refusal)}
}

func refusalKey(server, host, authorization string) [sha256.Size]byte {
	return sha256.Sum256([]byte(server + "\x00" + host + "\x00" + authorization))
}

func (c *Refusals) Lookup(server, host, authorization string) (int, bool) {
	key := refusalKey(server, host, authorization)
	c.mu.Lock()
	defer c.mu.Unlock()
	entry, ok := c.entries[key]
	if !ok {
		return 0, false
	}
	if !c.now().Before(entry.expires) {
		delete(c.entries, key)
		return 0, false
	}
	return entry.status, true
}

// A full table drops the verdict; forgetting one only costs a control-plane call.
func (c *Refusals) Record(server, host, authorization string, status int) {
	if status != http.StatusUnauthorized && status != http.StatusForbidden {
		return
	}
	now := c.now()
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.entries) >= c.limit {
		for key, entry := range c.entries {
			if !now.Before(entry.expires) {
				delete(c.entries, key)
			}
		}
		if len(c.entries) >= c.limit {
			return
		}
	}
	c.entries[refusalKey(server, host, authorization)] = refusal{status: status, expires: now.Add(c.ttl)}
}

func Environment(host string) (string, bool) {
	host = strings.ToLower(host)
	if !strings.HasSuffix(host, ".cache.tuist.dev") {
		return "", false
	}
	handle := strings.TrimSuffix(host, ".cache.tuist.dev")
	env := "production"
	for _, candidate := range []string{"staging", "canary"} {
		if strings.HasSuffix(handle, "-"+candidate) {
			handle = strings.TrimSuffix(handle, "-"+candidate)
			env = candidate
			break
		}
	}
	return env, handlePattern.MatchString(handle) && !strings.HasSuffix(handle, "-staging") && !strings.HasSuffix(handle, "-canary")
}

// The public TLS endpoint may arrive as a gRPC authority with an explicit port.
func canonicalHost(authority string) (string, bool) {
	if strings.Contains(authority, ":") {
		host, port, err := net.SplitHostPort(authority)
		if err != nil || port != "443" {
			return "", false
		}
		authority = host
	}
	return strings.TrimSuffix(strings.ToLower(authority), "."), true
}

func (g *Gateway) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/healthz" {
		w.WriteHeader(http.StatusOK)
		return
	}
	// Health checks, metrics and discovery probes must never provision storage.
	if r.URL.Path == "/ready" || r.URL.Path == "/up" || r.URL.Path == "/metrics" || r.URL.Path == "/" || strings.HasPrefix(r.URL.Path, "/_internal/") {
		unforwardedFailure(w, r, http.StatusNotFound)
		return
	}
	host, validHost := canonicalHost(r.Host)
	env, valid := Environment(host)
	server, configured := g.Servers[env]
	if !validHost || !valid || !configured {
		unforwardedFailure(w, r, http.StatusNotFound)
		return
	}
	authorization := r.Header.Get("Authorization")
	if !strings.HasPrefix(authorization, "Bearer ") || len(authorization) <= 7 {
		unforwardedFailure(w, r, http.StatusUnauthorized)
		return
	}
	if status, refused := g.Refusals.Lookup(server, host, authorization); refused {
		unforwardedFailure(w, r, status)
		return
	}
	admitted := true
	select {
	case g.slots <- struct{}{}:
		defer func() {
			if admitted {
				<-g.slots
			}
		}()
	default:
		unforwardedFailure(w, r, http.StatusTooManyRequests)
		return
	}
	// Bound only activation, not the lifetime of the artifact stream. Leave its
	// body untouched while waiting: HTTP/2 flow control supplies backpressure.
	ctx, cancel := context.WithTimeout(r.Context(), g.Wait)
	defer cancel()
	started := time.Now()
	waited := false
	for {
		target, status := g.resolve(ctx, server, host, authorization)
		if status != http.StatusAccepted && status != http.StatusOK {
			g.Refusals.Record(server, host, authorization, status)
			unforwardedFailure(w, r, status)
			return
		}
		if target != nil {
			if waited {
				slog.Info("cache activation ready", "environment", env, "wait_ms", time.Since(started).Milliseconds())
			}
			<-g.slots
			admitted = false
			g.proxy(w, r, target)
			return
		}
		waited = true
		timer := time.NewTimer(g.Poll)
		select {
		case <-ctx.Done():
			timer.Stop()
			unforwardedFailure(w, r, http.StatusServiceUnavailable)
			return
		case <-timer.C:
		}
	}
}

func (g *Gateway) resolve(ctx context.Context, server, host, authorization string) (*url.URL, int) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, server+"/_internal/kura/activate?host="+url.QueryEscape(host), nil)
	if err != nil {
		return nil, http.StatusServiceUnavailable
	}
	req.Header.Set("Authorization", authorization)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("X-Tuist-Cache-Activation-Billing", "1")
	resp, err := g.Control.Do(req)
	if err != nil {
		return nil, http.StatusServiceUnavailable
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusAccepted:
		return nil, http.StatusAccepted
	case http.StatusUnauthorized, http.StatusForbidden, http.StatusPaymentRequired, http.StatusConflict, http.StatusNotFound, http.StatusTooManyRequests:
		return nil, resp.StatusCode
	case http.StatusOK:
	default:
		return nil, http.StatusServiceUnavailable
	}
	var result struct {
		Endpoint string `json:"endpoint"`
	}
	if json.NewDecoder(io.LimitReader(resp.Body, 8192)).Decode(&result) != nil {
		return nil, http.StatusServiceUnavailable
	}
	target, err := url.Parse(result.Endpoint)
	// Never relay credentials to custom URLs, private addresses, or back to the
	// wildcard (a proxy loop). The authenticated control plane selects the tenant.
	if err != nil || target.Scheme != "https" || target.User != nil || target.Port() != "" || !strings.HasSuffix(target.Hostname(), ".kura.tuist.dev") || target.Path != "" || target.RawQuery != "" || target.Fragment != "" {
		return nil, http.StatusServiceUnavailable
	}
	return target, http.StatusOK
}

func (g *Gateway) proxy(w http.ResponseWriter, r *http.Request, target *url.URL) {
	select {
	case g.streams <- struct{}{}:
		defer func() { <-g.streams }()
	default:
		unforwardedFailure(w, r, http.StatusTooManyRequests)
		return
	}
	proxy := &httputil.ReverseProxy{
		Rewrite: func(p *httputil.ProxyRequest) {
			p.SetURL(target)
			p.Out.Host = target.Host
			// Incoming forwarding/geo headers are not evidence of the original caller.
			for key := range p.Out.Header {
				lower := strings.ToLower(key)
				if strings.HasPrefix(lower, "x-forwarded-") || strings.HasPrefix(lower, "cf-") || lower == "forwarded" || lower == "x-real-ip" {
					p.Out.Header.Del(key)
				}
			}
		},
		Transport: g.Transport, FlushInterval: -1,
		ModifyResponse: func(response *http.Response) error {
			response.Header.Del("X-Tuist-Cache-Activation")
			return nil
		},
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, _ error) {
			failure(w, r, http.StatusServiceUnavailable)
		},
	}
	proxy.ServeHTTP(w, r)
}

// Only pre-forwarding rejections permit a non-idempotent client request to
// retry. A proxy transport failure may have already committed the upload.
func unforwardedFailure(w http.ResponseWriter, r *http.Request, status int) {
	if status == http.StatusServiceUnavailable || status == http.StatusTooManyRequests {
		w.Header().Set("X-Tuist-Cache-Activation", "pending")
	}
	failure(w, r, status)
}

func failure(w http.ResponseWriter, r *http.Request, status int) {
	message := http.StatusText(status)
	if status == http.StatusPaymentRequired {
		message = "Cache access is blocked by billing. Check your plan and payment status in Tuist."
	}
	if status == http.StatusConflict {
		message = "This account uses custom cache endpoints; set TUIST_CACHE_ENDPOINT"
	}
	w.Header().Set("Cache-Control", "no-store")
	if status == http.StatusServiceUnavailable || status == http.StatusTooManyRequests {
		w.Header().Set("Retry-After", "2")
	}
	if strings.HasPrefix(r.Header.Get("Content-Type"), "application/grpc") {
		code := "14"
		switch status {
		case http.StatusUnauthorized:
			code = "16"
		case http.StatusPaymentRequired:
			// Keep the regional cache's terminal status: older clients retry
			// RESOURCE_EXHAUSTED as transient backpressure, including uploads.
			code = "7"
			w.Header().Set("Tuist-Refusal-Reason", "payment_required")
		case http.StatusForbidden:
			code = "7"
		case http.StatusConflict:
			code = "9"
		case http.StatusNotFound:
			code = "5"
		case http.StatusTooManyRequests:
			code = "8"
		}
		w.Header().Set("Content-Type", "application/grpc")
		w.Header().Set("Grpc-Status", code)
		w.Header().Set("Grpc-Message", message)
		w.WriteHeader(http.StatusOK)
		return
	}
	if status == http.StatusPaymentRequired {
		// Match the regional HTTP API so existing generated clients can decode it.
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_ = json.NewEncoder(w).Encode(map[string]string{"message": message})
		return
	}
	http.Error(w, message, status)
}

// Server keeps both the waiting request headers and accepted streams bounded.
// Separate listeners prevent nginx HTTP and gRPC upstream connection pooling
// from mixing protocols on the same address/port.
func Server(addr string, handler http.Handler) *http.Server {
	protocols := new(http.Protocols)
	protocols.SetHTTP1(true)
	protocols.SetUnencryptedHTTP2(true)
	return &http.Server{Addr: addr, Handler: handler, Protocols: protocols, HTTP2: &http.HTTP2Config{MaxConcurrentStreams: 128, MaxReceiveBufferPerConnection: 1 << 20, MaxReceiveBufferPerStream: 64 << 10}, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 5 * time.Minute, WriteTimeout: 5 * time.Minute, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 64 << 10}
}

func Listen(server *http.Server) error {
	err := server.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
