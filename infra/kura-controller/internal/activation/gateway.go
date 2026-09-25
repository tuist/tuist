// Package activation serves the wildcard cache fallback while an account has no
// regional DNS record. It never owns storage or replays an artifact request.
package activation

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"
)

var handlePattern = regexp.MustCompile(`^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$`)

type route struct {
	target  *url.URL
	expires time.Time
}

// Servers is an explicit environment allowlist, never derived from request URLs.
type Servers map[string]string

type Gateway struct {
	Servers   Servers
	Control   *http.Client
	Transport http.RoundTripper
	Wait      time.Duration
	Poll      time.Duration
	slots     chan struct{}
	routesMu  sync.Mutex
	routes    map[string]route
}

func New(servers Servers, concurrency int) *Gateway {
	return &Gateway{
		Servers:   servers,
		Control:   &http.Client{Timeout: 3 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }},
		Transport: &http.Transport{Proxy: nil, ForceAttemptHTTP2: true, MaxIdleConns: 128, MaxIdleConnsPerHost: 8, MaxConnsPerHost: 32, IdleConnTimeout: 30 * time.Second, TLSHandshakeTimeout: 5 * time.Second, ResponseHeaderTimeout: 30 * time.Second},
		Wait:      20 * time.Second, Poll: 2 * time.Second, slots: make(chan struct{}, concurrency),
	}
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

func (g *Gateway) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/healthz" {
		w.WriteHeader(http.StatusOK)
		return
	}
	// Health checks, metrics and discovery probes must never provision storage.
	if r.URL.Path == "/ready" || r.URL.Path == "/up" || r.URL.Path == "/metrics" || r.URL.Path == "/" || strings.HasPrefix(r.URL.Path, "/_internal/") {
		failure(w, r, http.StatusNotFound)
		return
	}
	env, valid := Environment(r.Host)
	server, configured := g.Servers[env]
	if !valid || !configured {
		failure(w, r, http.StatusNotFound)
		return
	}
	authorization := r.Header.Get("Authorization")
	if !strings.HasPrefix(authorization, "Bearer ") || len(authorization) <= 7 {
		failure(w, r, http.StatusUnauthorized)
		return
	}
	select {
	case g.slots <- struct{}{}:
		defer func() { <-g.slots }()
	default:
		failure(w, r, http.StatusTooManyRequests)
		return
	}
	if target := g.cachedRoute(r.Host); target != nil {
		g.proxy(w, r, target)
		return
	}
	// Bound only activation, not the lifetime of the artifact stream. Leave its
	// body untouched while waiting: HTTP/2 flow control supplies backpressure.
	ctx, cancel := context.WithTimeout(r.Context(), g.Wait)
	defer cancel()
	started := time.Now()
	for {
		target, status := g.resolve(ctx, server, strings.ToLower(r.Host), authorization)
		if status != http.StatusAccepted && status != http.StatusOK {
			failure(w, r, status)
			return
		}
		if target != nil {
			slog.Info("cache activation ready", "environment", env, "wait_ms", time.Since(started).Milliseconds())
			g.cacheRoute(r.Host, target)
			g.proxy(w, r, target)
			return
		}
		timer := time.NewTimer(g.Poll)
		select {
		case <-ctx.Done():
			timer.Stop()
			failure(w, r, http.StatusServiceUnavailable)
			return
		case <-timer.C:
		}
	}
}

// Routing alone is cached, never authorization. Every forwarded request still
// carries its own credential and is authorized by Kura. This also avoids making
// long-lived clients with a cached wildcard answer query the control plane for
// every blob after their instance has activated.
func (g *Gateway) cachedRoute(host string) *url.URL {
	g.routesMu.Lock()
	defer g.routesMu.Unlock()
	if route, ok := g.routes[host]; ok && time.Now().Before(route.expires) {
		return route.target
	}
	delete(g.routes, host)
	return nil
}

func (g *Gateway) cacheRoute(host string, target *url.URL) {
	g.routesMu.Lock()
	defer g.routesMu.Unlock()
	if g.routes == nil {
		g.routes = make(map[string]route)
	}
	if len(g.routes) >= 1024 {
		for key, route := range g.routes {
			if !time.Now().Before(route.expires) {
				delete(g.routes, key)
			}
		}
	}
	if len(g.routes) < 1024 {
		g.routes[host] = route{target: target, expires: time.Now().Add(30 * time.Second)}
	}
}

func (g *Gateway) forgetRoute(host string) {
	g.routesMu.Lock()
	defer g.routesMu.Unlock()
	delete(g.routes, host)
}

func (g *Gateway) resolve(ctx context.Context, server, host, authorization string) (*url.URL, int) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, server+"/_internal/kura/activate?host="+url.QueryEscape(host), nil)
	if err != nil {
		return nil, http.StatusServiceUnavailable
	}
	req.Header.Set("Authorization", authorization)
	req.Header.Set("Accept", "application/json")
	resp, err := g.Control.Do(req)
	if err != nil {
		return nil, http.StatusServiceUnavailable
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusAccepted:
		return nil, http.StatusAccepted
	case http.StatusUnauthorized, http.StatusForbidden, http.StatusPaymentRequired, http.StatusNotFound, http.StatusTooManyRequests:
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
	host := r.Host
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
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, _ error) {
			g.forgetRoute(host)
			failure(w, r, http.StatusServiceUnavailable)
		},
	}
	proxy.ServeHTTP(w, r)
}

func failure(w http.ResponseWriter, r *http.Request, status int) {
	w.Header().Set("Cache-Control", "no-store")
	if status == http.StatusServiceUnavailable || status == http.StatusTooManyRequests {
		w.Header().Set("Retry-After", "2")
	}
	if strings.HasPrefix(r.Header.Get("Content-Type"), "application/grpc") {
		code := "14"
		switch status {
		case http.StatusUnauthorized:
			code = "16"
		case http.StatusForbidden, http.StatusPaymentRequired:
			code = "7"
		case http.StatusNotFound:
			code = "5"
		case http.StatusTooManyRequests:
			code = "8"
		}
		w.Header().Set("Content-Type", "application/grpc")
		w.Header().Set("Grpc-Status", code)
		w.Header().Set("Grpc-Message", http.StatusText(status))
		w.WriteHeader(http.StatusOK)
		return
	}
	http.Error(w, http.StatusText(status), status)
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
