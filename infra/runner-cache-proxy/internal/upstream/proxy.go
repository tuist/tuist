// Package upstream routes decrypted requests from a MITM'd cache
// connection. CacheService calls go to the local cache-gateway with the
// guest's cache token swapped in (the guest never holds the secret);
// everything else is forwarded to genuine GitHub with the original
// Authorization header untouched. A missing token or a tripped breaker
// fails open to GitHub.
package upstream

import (
	"context"
	"crypto/tls"
	"net"
	"net/http"
	"net/http/httputil"
	"net/netip"
	"net/url"
	"time"

	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/metrics"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/router"
)

// TokenLookup resolves a guest source IP to its cache token.
type TokenLookup interface {
	Lookup(ip netip.Addr) ([]byte, bool)
}

// BreakerAllow reports whether CacheService may be routed to the gateway.
type BreakerAllow interface {
	Allow() bool
}

// ConnContext is the per-connection identity the router needs.
type ConnContext struct {
	SrcIP       netip.Addr
	SNI         string
	OriginalDst netip.AddrPort
}

// Proxy routes requests for one MITM'd connection.
type Proxy struct {
	gatewayURL *url.URL
	registry   TokenLookup
	breaker    BreakerAllow
	decisions  *router.DecisionCache

	// gatewayTransport is the round-tripper for gateway requests.
	gatewayTransport http.RoundTripper
	// githubTransport, when set, overrides the default TLS transport for
	// genuine-GitHub requests (tests point it at a fake).
	githubTransport http.RoundTripper
	// dial overrides connection dialing (tests point it at fakes).
	dial func(network, addr string) (net.Conn, error)
}

// Options configures a Proxy.
type Options struct {
	GatewayURL       string
	Registry         TokenLookup
	Breaker          BreakerAllow
	Decisions        *router.DecisionCache
	GatewayTransport http.RoundTripper
	// GitHubTransport overrides the genuine-GitHub round-tripper; nil
	// builds a TLS transport dialing the recovered original destination.
	GitHubTransport http.RoundTripper
	// Dial overrides outbound dialing; nil uses net.Dial.
	Dial func(network, addr string) (net.Conn, error)
}

// New builds a Proxy.
func New(opts Options) (*Proxy, error) {
	var gw *url.URL
	if opts.GatewayURL != "" {
		u, err := url.Parse(opts.GatewayURL)
		if err != nil {
			return nil, err
		}
		gw = u
	}
	dial := opts.Dial
	if dial == nil {
		dial = func(network, addr string) (net.Conn, error) {
			return (&net.Dialer{Timeout: 5 * time.Second}).Dial(network, addr)
		}
	}
	gwt := opts.GatewayTransport
	if gwt == nil {
		gwt = http.DefaultTransport
	}
	return &Proxy{
		gatewayURL:       gw,
		registry:         opts.Registry,
		breaker:          opts.Breaker,
		decisions:        opts.Decisions,
		gatewayTransport: gwt,
		githubTransport:  opts.GitHubTransport,
		dial:             dial,
	}, nil
}

// Handler returns an http.Handler that routes requests for one connection.
func (p *Proxy) Handler(cc ConnContext) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		target := p.targetFor(cc, r.URL.Path)
		if target == router.Gateway {
			p.serveGateway(cc, w, r)
			return
		}
		p.serveGitHub(cc, w, r)
	})
}

// targetFor resolves the sticky routing decision for this request.
func (p *Proxy) targetFor(cc ConnContext, path string) router.Target {
	allows := p.gatewayURL != nil && (p.breaker == nil || p.breaker.Allow())
	compute := func() router.Target { return router.Route(path, allows) }
	if p.decisions == nil {
		return compute()
	}
	// Sticky only for the diverted CacheService path; other paths route
	// statelessly so artifact/OIDC traffic is never pinned.
	if !allows {
		return compute()
	}
	key := cc.SrcIP.String() + "|" + cc.SNI
	return p.decisions.Resolve(key, compute)
}

func (p *Proxy) serveGateway(cc ConnContext, w http.ResponseWriter, r *http.Request) {
	token, ok := p.registry.Lookup(cc.SrcIP)
	if !ok {
		// No staged token: fail open to GitHub rather than 401 the job.
		metrics.TokenLookups.WithLabelValues("miss").Inc()
		metrics.FailOpen.WithLabelValues("no_token").Inc()
		p.serveGitHub(cc, w, r)
		return
	}
	metrics.TokenLookups.WithLabelValues("hit").Inc()

	start := time.Now()
	rp := &httputil.ReverseProxy{
		Transport: p.gatewayTransport,
		Director: func(req *http.Request) {
			req.URL.Scheme = p.gatewayURL.Scheme
			req.URL.Host = p.gatewayURL.Host
			req.Host = p.gatewayURL.Host
			req.Header.Set("Authorization", "Bearer "+string(token))
		},
		ErrorHandler: func(rw http.ResponseWriter, req *http.Request, _ error) {
			// Gateway unreachable: fail open to GitHub.
			metrics.FailOpen.WithLabelValues("gateway_error").Inc()
			p.serveGitHub(cc, rw, req)
		},
	}
	metrics.Connections.WithLabelValues("gateway").Inc()
	rp.ServeHTTP(w, r)
	metrics.GatewayRequestDuration.Observe(time.Since(start).Seconds())
}

func (p *Proxy) serveGitHub(cc ConnContext, w http.ResponseWriter, r *http.Request) {
	host := cc.SNI
	transport := p.githubTransport
	if transport == nil {
		transport = &http.Transport{
			DialContext: func(_ context.Context, network, _ string) (net.Conn, error) {
				// Always dial the recovered original destination, not DNS.
				return p.dial(network, cc.OriginalDst.String())
			},
			TLSClientConfig: &tls.Config{ServerName: host},
		}
	}
	rp := &httputil.ReverseProxy{
		Transport: transport,
		Director: func(req *http.Request) {
			req.URL.Scheme = "https"
			req.URL.Host = host
			req.Host = host
			// Original Authorization header is preserved untouched.
		},
	}
	metrics.Connections.WithLabelValues("genuine_github").Inc()
	rp.ServeHTTP(w, r)
}
