// Package connectivity provides a fixed, unauthenticated diagnostic profile.
// It has no listener, shell, caller-supplied destinations, or Kubernetes client.
package connectivity

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptrace"
	"os"
	"sync"
	"time"
)

const (
	Interval       = time.Minute
	requestTimeout = 5 * time.Second
	bodyLimit      = 4096
)

// Result contains only locally generated metadata; response content and error
// strings (which can contain remote input) never enter logs.
type Result struct {
	Time            time.Time `json:"time"`
	Target          string    `json:"target"`
	ConnectBudgetMS int64     `json:"connect_budget_ms"`
	DNSMS           *float64  `json:"dns_ms,omitempty"`
	ConnectMS       *float64  `json:"connect_ms,omitempty"`
	FirstByteMS     *float64  `json:"first_byte_ms,omitempty"`
	TotalMS         float64   `json:"total_ms"`
	Status          int       `json:"status,omitempty"`
	Outcome         string    `json:"outcome"`
}

type lookupFunc func(context.Context, string) ([]net.IPAddr, error)
type dialFunc func(context.Context, string, string) (net.Conn, error)

// ProfileHost selects a reviewed destination, never an arbitrary caller URL.
func ProfileHost(environment string) (string, error) {
	switch environment {
	case "production":
		return "tuist-tuist-server.tuist.svc.cluster.local", nil
	case "staging":
		return "tuist-tuist-server.tuist-staging.svc.cluster.local", nil
	case "canary":
		return "tuist-tuist-server.tuist-canary.svc.cluster.local", nil
	default:
		return "", errors.New("unknown connectivity profile")
	}
}

// Run compares search-list and absolute names with fixed DNS+TCP budgets.
func Run(ctx context.Context, environment string, emit func(Result)) error {
	host, err := ProfileHost(environment)
	if err != nil {
		return err
	}
	resolver := &net.Resolver{PreferGo: true}
	dialer := &net.Dialer{}
	runProfile(ctx, host, emit, func(ctx context.Context, host string, budget time.Duration) Result {
		return probe(ctx, host, budget, requestTimeout, resolver.LookupIPAddr, dialer.DialContext)
	})
	return nil
}

func runProfile(ctx context.Context, host string, emit func(Result), sample func(context.Context, string, time.Duration) Result) {
	for _, name := range []string{host, host + "."} {
		for _, budget := range []time.Duration{time.Second, 3 * time.Second} {
			if ctx.Err() != nil {
				return
			}
			emit(sample(ctx, name, budget))
		}
	}
}

func probe(ctx context.Context, host string, budget, overallTimeout time.Duration, lookup lookupFunc, dial dialFunc) Result {
	start := time.Now()
	result := Result{Time: start.UTC(), Target: host, ConnectBudgetMS: budget.Milliseconds()}
	ctx, cancel := context.WithTimeout(ctx, overallTimeout)
	defer cancel()
	// Transport callbacks can outlive Do on cancellation. Guard both recording
	// and the final snapshot so timeout samples remain race-free.
	var mu sync.Mutex
	stage := "dns"
	elapsed := func() *float64 { v := float64(time.Since(start)) / float64(time.Millisecond); return &v }
	transport := &http.Transport{
		Proxy:                  nil,
		DisableKeepAlives:      true,
		DisableCompression:     true,
		MaxResponseHeaderBytes: 8192,
		DialContext: func(_ context.Context, network, _ string) (net.Conn, error) {
			// Use the request context, not Transport's detached dial context.
			connectCtx, stop := context.WithTimeout(ctx, budget)
			defer stop()
			addresses, err := lookup(connectCtx, host)
			mu.Lock()
			if err == nil {
				result.DNSMS = elapsed()
				stage = "address"
			}
			mu.Unlock()
			if err != nil {
				return nil, err
			}
			// The approved destination is an internal Service. Reject metadata,
			// loopback, public, multicast, and unspecified answers even if DNS
			// is misconfigured. Never resolve again between validation and dial.
			if len(addresses) == 0 || len(addresses) > 16 {
				return nil, errors.New("invalid answers")
			}
			for _, address := range addresses {
				if address.Zone != "" || !address.IP.IsPrivate() {
					return nil, errors.New("disallowed address")
				}
			}
			mu.Lock()
			stage = "connect"
			mu.Unlock()
			// One connection attempt, to the first resolver answer. This keeps
			// the traffic cap independent of answer count; no automatic retries.
			conn, err := dial(connectCtx, network, net.JoinHostPort(addresses[0].IP.String(), "80"))
			mu.Lock()
			if err == nil {
				result.ConnectMS = elapsed()
				stage = "http"
			}
			mu.Unlock()
			return conn, err
		},
	}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	trace := &httptrace.ClientTrace{GotFirstResponseByte: func() { mu.Lock(); result.FirstByteMS = elapsed(); mu.Unlock() }}
	req, requestErr := http.NewRequestWithContext(httptrace.WithClientTrace(ctx, trace), http.MethodGet, "http://"+host+"/ready", nil)
	if requestErr != nil {
		result.Outcome = "request_error"
		result.TotalMS = *elapsed()
		return result
	}
	req.Header.Set("User-Agent", "tuist-connectivity-probe/1")
	response, err := client.Do(req)
	outcome := "ok"
	status := 0
	if err == nil {
		status = response.StatusCode
		n, readErr := io.Copy(io.Discard, io.LimitReader(response.Body, bodyLimit+1))
		_ = response.Body.Close()
		if readErr != nil {
			outcome = "body_error"
		} else if n > bodyLimit {
			outcome = "body_limit"
		}
	}
	mu.Lock()
	defer mu.Unlock()
	if err != nil {
		outcome = stage + "_error"
	}
	result.Status = status
	result.Outcome = outcome
	result.TotalMS = *elapsed()
	return result
}

// ResolverConfig reads exactly one fixed, non-secret file, with a size cap.
func ResolverConfig() (string, error) {
	f, err := os.Open("/etc/resolv.conf")
	if err != nil {
		return "", err
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, 4096))
	return string(data), err
}
