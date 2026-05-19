package podagent

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"net/http/httputil"
	"sync"
	"time"
)

// MetricsForwarder is a host-side HTTP reverse proxy that forwards
// scrape requests to a Tart VM's metrics endpoint. tart-kubelet
// runs one per Pod that opts in via `prometheus.io/scrape`, so an
// in-cluster scraper that can reach the Mac mini's Node IP can
// scrape the Tart VM's /metrics endpoint without needing a route to
// the VM's NAT-private address.
//
// We use an HTTP reverse proxy rather than a raw TCP relay because
// scrapers like Prometheus reuse connections via HTTP keep-alive: a
// raw TCP relay can't tell when one HTTP request finishes and would
// block both copy goroutines waiting for bytes that never come on
// an idle keep-alive connection. The reverse proxy handles each
// HTTP request as an independent operation.
//
// The upstream address is resolved on every request rather than
// captured at construction time so the forwarder survives a Tart VM
// restart (the new VM gets a new IP from configd's DHCP) without
// the caller needing to tear down + re-create the forwarder.
type Forwarder struct {
	listener net.Listener
	server   *http.Server
	stopOnce sync.Once
	doneOnce sync.Once
	done     chan struct{}
}

// ForwarderOptions controls request-side restrictions on the proxy.
// A zero ForwarderOptions allows traffic from anywhere — callers
// should always set AllowedCIDRs in production deployments because
// the bind address can in practice be a public IP (eg. Scaleway
// Apple Silicon Mac minis only expose a public address; the
// WireGuard / overlay interface a cluster CNI later layers on top
// is what other Nodes actually reach the Mac mini on, and clamping
// to RFC1918 is the simplest portable way to reject the WAN-facing
// path).
type ForwarderOptions struct {
	// AllowedCIDRs is the set of source ranges the proxy accepts.
	// Empty = allow all (only used in tests). RemoteAddr is parsed
	// against each CIDR in order; the first match accepts.
	AllowedCIDRs []*net.IPNet

	// Logger receives the detailed errors that the proxy
	// deliberately suppresses from HTTP responses (a 502 body must
	// not leak VM IPs / names / Tart subprocess output to the
	// allowlisted-but-still-untrusted scraper). Nil falls back to
	// slog.Default().
	Logger *slog.Logger
}

// MetricsPath is the only request path the forwarder will proxy.
// Prometheus exporters serve metrics at /metrics by convention; any
// other path is rejected with 404 to keep the surface area minimal
// (defense in depth — the Tart VM only exposes /metrics on this
// port today, but a future PromEx config or a sibling endpoint on
// the same listener would otherwise become reachable through here).
const MetricsPath = "/metrics"

// NewForwarder starts listening on listenAddr. Resolve is called to
// compute the upstream `host:port` the proxy targets — pluggable so
// the caller can hand in a Tart-IP lookup that surface VM restarts
// (the new VM gets a new IP from configd's DHCP). The forwarder
// caches the resolution for ~30s so a burst of scrapes doesn't
// hammer `tart ip` (which exec's a subprocess on every call) — a
// stale entry self-heals on the first scrape after the cache window
// expires; longer than that and a recently-restarted VM would just
// see one failed scrape before recovering, which the scraper's own
// retry handles.
func NewForwarder(listenAddr string, resolve func() (string, error), opts ForwarderOptions) (*Forwarder, error) {
	if resolve == nil {
		return nil, errors.New("resolve function is required")
	}
	l, err := net.Listen("tcp", listenAddr)
	if err != nil {
		return nil, fmt.Errorf("listen on %s: %w", listenAddr, err)
	}

	logger := opts.Logger
	if logger == nil {
		logger = slog.Default()
	}

	cached := newCachedResolver(resolve, 30*time.Second)

	rp := &httputil.ReverseProxy{
		// Director rewrites the outbound request to point at the
		// freshly resolved upstream. Errors here can't be surfaced
		// directly, so we stash them on the request context for the
		// ErrorHandler to translate into a 502.
		Director: func(req *http.Request) {
			target, err := cached.get()
			if err != nil || target == "" {
				ctx := context.WithValue(req.Context(), resolveErrKey{}, err)
				*req = *req.WithContext(ctx)
				return
			}
			req.URL.Scheme = "http"
			req.URL.Host = target
			req.Host = target
		},
		ErrorHandler: func(w http.ResponseWriter, req *http.Request, err error) {
			// Log the detail server-side, return a generic body to
			// the client. The detailed error can include VM names,
			// IPs, or Tart subprocess output, none of which the
			// scraper has any business seeing — even though it sits
			// inside the allowed CIDR, that's a network boundary,
			// not a trust boundary.
			if rerr, ok := req.Context().Value(resolveErrKey{}).(error); ok && rerr != nil {
				logger.Warn("metrics forwarder: upstream resolve failed",
					"listen", listenAddr, "remote", req.RemoteAddr, "err", rerr)
				http.Error(w, "bad gateway", http.StatusBadGateway)
				return
			}
			logger.Warn("metrics forwarder: upstream proxy error",
				"listen", listenAddr, "remote", req.RemoteAddr, "err", err)
			http.Error(w, "bad gateway", http.StatusBadGateway)
		},
		Transport: &http.Transport{
			DialContext: (&net.Dialer{
				Timeout:   5 * time.Second,
				KeepAlive: 30 * time.Second,
			}).DialContext,
			ResponseHeaderTimeout: 10 * time.Second,
			IdleConnTimeout:       60 * time.Second,
		},
	}

	srv := &http.Server{
		Handler:           sourceCIDRFilter(opts.AllowedCIDRs, pathFilter(MetricsPath, rp)),
		ReadHeaderTimeout: 10 * time.Second,
	}

	f := &Forwarder{
		listener: l,
		server:   srv,
		done:     make(chan struct{}),
	}

	go func() {
		defer f.doneOnce.Do(func() { close(f.done) })
		_ = srv.Serve(l)
	}()

	return f, nil
}

// Addr returns the address the forwarder is bound to.
func (f *Forwarder) Addr() net.Addr { return f.listener.Addr() }

// Stop closes the listener and waits for in-flight requests to
// drain (capped by Shutdown's context). Safe to call multiple times.
func (f *Forwarder) Stop() {
	f.stopOnce.Do(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = f.server.Shutdown(ctx)
	})
	<-f.done
}

// pathFilter returns a handler that forwards GET / HEAD requests
// for `path` to `next` and rejects everything else with 404. Keeps
// the proxy single-purpose: it exists to serve scrapes, not as a
// general HTTP relay into the VM.
func pathFilter(path string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if req.URL.Path != path {
			http.NotFound(w, req)
			return
		}
		if req.Method != http.MethodGet && req.Method != http.MethodHead {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		next.ServeHTTP(w, req)
	})
}

// sourceCIDRFilter returns a handler that rejects requests whose
// RemoteAddr falls outside `allowed`. With `allowed` empty the
// filter is a no-op (used in tests). The bind address can in
// practice be a public IP — Scaleway Apple Silicon Mac minis
// don't expose a private interface that's still routable to
// Linux Alloy DaemonSet Pods elsewhere in the cluster — so this
// is the load-bearing network boundary, not the listen address.
func sourceCIDRFilter(allowed []*net.IPNet, next http.Handler) http.Handler {
	if len(allowed) == 0 {
		return next
	}
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		host, _, err := net.SplitHostPort(req.RemoteAddr)
		if err != nil {
			host = req.RemoteAddr
		}
		ip := net.ParseIP(host)
		if ip == nil {
			http.Error(w, "forbidden: unparseable client address", http.StatusForbidden)
			return
		}
		for _, c := range allowed {
			if c.Contains(ip) {
				next.ServeHTTP(w, req)
				return
			}
		}
		http.Error(w, "forbidden: source address not in allowlist", http.StatusForbidden)
	})
}

// DefaultScrapeAllowedCIDRs is the safe baseline allowlist for the
// metrics proxy: RFC1918 IPv4 ranges, the Tailscale CGNAT range
// (100.64/10 — what tailnet clients dial in on when the cluster
// reaches the Mac mini via Tailscale's subnet router), IPv4 link-
// local, IPv4 loopback, IPv6 unique-local, IPv6 link-local, and
// IPv6 loopback. Covers every realistic cluster Pod / Node CIDR and
// the tailnet-traversing scraper path while clamping out the
// public WAN. Operators on clusters that route Pod traffic through
// public IPs (rare) need to override via --scrape-allowed-cidr.
func DefaultScrapeAllowedCIDRs() []*net.IPNet {
	defaults := []string{
		"10.0.0.0/8",
		"172.16.0.0/12",
		"192.168.0.0/16",
		"100.64.0.0/10",
		"169.254.0.0/16",
		"127.0.0.0/8",
		"fc00::/7",
		"fe80::/10",
		"::1/128",
	}
	out := make([]*net.IPNet, 0, len(defaults))
	for _, c := range defaults {
		_, n, err := net.ParseCIDR(c)
		if err == nil {
			out = append(out, n)
		}
	}
	return out
}

// cachedResolver memoises the upstream lookup for `ttl` so a burst
// of scrapes (or anyone hammering the proxy) doesn't translate 1:1
// into `tart ip` subprocess invocations on the host.
//
// Only successful results are cached. Errors are returned as-is and
// the next call retries the underlying resolver — without that, a
// single transient `tart ip` failure during a VM restart would
// poison every scrape for the full TTL even after the VM came back
// healthy with a new DHCP lease.
type cachedResolver struct {
	fn  func() (string, error)
	ttl time.Duration

	mu       sync.Mutex
	cachedAt time.Time
	target   string
}

func newCachedResolver(fn func() (string, error), ttl time.Duration) *cachedResolver {
	return &cachedResolver{fn: fn, ttl: ttl}
}

func (c *cachedResolver) get() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.target != "" && time.Since(c.cachedAt) < c.ttl {
		return c.target, nil
	}

	target, err := c.fn()
	if err != nil {
		// Don't poison the cache; next call retries the resolver.
		// Keep the previously-cached target untouched so a transient
		// failure doesn't blow it away either.
		return "", err
	}
	c.target = target
	c.cachedAt = time.Now()
	return target, nil
}

// resolveErrKey is the context key tart-kubelet's reverse-proxy
// Director uses to ferry resolution errors over to the
// ErrorHandler.
type resolveErrKey struct{}
