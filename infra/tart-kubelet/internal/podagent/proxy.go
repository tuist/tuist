package podagent

import (
	"context"
	"errors"
	"fmt"
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

// NewForwarder starts listening on listenAddr. Resolve is called on
// every incoming request to compute the upstream `host:port` to
// proxy to — keeping it pluggable lets the caller plug in a Tart IP
// lookup rather than hardcoding an address that goes stale on VM
// restart.
func NewForwarder(listenAddr string, resolve func() (string, error)) (*Forwarder, error) {
	if resolve == nil {
		return nil, errors.New("resolve function is required")
	}
	l, err := net.Listen("tcp", listenAddr)
	if err != nil {
		return nil, fmt.Errorf("listen on %s: %w", listenAddr, err)
	}

	rp := &httputil.ReverseProxy{
		// Director rewrites the outbound request to point at the
		// freshly resolved upstream. Errors here can't be surfaced
		// directly, so we stash them on the request context for the
		// ErrorHandler to translate into a 502.
		Director: func(req *http.Request) {
			target, err := resolve()
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
			if rerr, ok := req.Context().Value(resolveErrKey{}).(error); ok && rerr != nil {
				http.Error(w, "tart-kubelet: upstream resolve failed: "+rerr.Error(), http.StatusBadGateway)
				return
			}
			http.Error(w, "tart-kubelet: upstream proxy error: "+err.Error(), http.StatusBadGateway)
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
		Handler:           rp,
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

// resolveErrKey is the context key tart-kubelet's reverse-proxy
// Director uses to ferry resolution errors over to the
// ErrorHandler.
type resolveErrKey struct{}
