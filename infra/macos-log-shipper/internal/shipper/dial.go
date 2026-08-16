package shipper

import (
	"context"
	"net"
	"net/http"
	"time"
)

// magicDNSAddr is tailscaled's built-in resolver. It is a Tailscale constant,
// the same on every tailnet, and on these hosts it is the only thing that can
// resolve a MagicDNS name.
//
// tailscaled reports DNS as enabled on a Mac mini but installs no resolver
// into macOS: scutil --dns has no entry for this address and /etc/resolv.conf
// carries only the DHCP nameservers. Nothing on the host resolves the receiver
// through the OS — not this binary, not curl, not by FQDN. The MagicDNS server
// itself is listening and answers, so we ask it directly.
const magicDNSAddr = "100.100.100.100:53"

// dialContextVia dials through resolver, falling back to the system resolver
// when it cannot answer.
//
// The fallback is not a nicety. This runs as a launchd daemon with
// RunAtLoad, so it starts while tailscaled may still be coming up and
// 100.100.100.100 is not yet listening; without the fallback a --url given as
// a plain address or a publicly resolvable name would fail for no reason. With
// it, the only case that resolves differently is the one that motivated this:
// a MagicDNS name.
func dialContextVia(resolver *net.Resolver, timeout time.Duration) func(context.Context, string, string) (net.Conn, error) {
	primary := &net.Dialer{Timeout: timeout, Resolver: resolver}
	system := &net.Dialer{Timeout: timeout}
	return func(ctx context.Context, network, addr string) (net.Conn, error) {
		conn, err := primary.DialContext(ctx, network, addr)
		if err == nil {
			return conn, nil
		}
		return system.DialContext(ctx, network, addr)
	}
}

// magicDNSResolver answers from tailscaled rather than from /etc/resolv.conf.
func magicDNSResolver(timeout time.Duration) *net.Resolver {
	return &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			dialer := net.Dialer{Timeout: timeout}
			return dialer.DialContext(ctx, network, magicDNSAddr)
		},
	}
}

// NewHTTPClient returns the client the shipper pushes with. Every dial
// resolves again, so a receiver that moves to a new tailnet address is picked
// up without restarting the agent.
func NewHTTPClient(timeout time.Duration) *http.Client {
	return &http.Client{
		Timeout:   timeout,
		Transport: &http.Transport{DialContext: dialContextVia(magicDNSResolver(5*time.Second), 10*time.Second)},
	}
}
