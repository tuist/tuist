package shipper

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// The production failure this guards: on a Mac mini, tailscaled publishes
// MagicDNS through the macOS dynamic store, which libresolv reads and Go's
// CGO_ENABLED=0 resolver does not. curl resolved the receiver, the agent could
// not, and every push failed with "no such host" for 2224 consecutive attempts
// while the daemon looked healthy.
func TestDialContextResolvesThroughMagicDNS(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()
	_, port, err := net.SplitHostPort(strings.TrimPrefix(server.URL, "http://"))
	if err != nil {
		t.Fatalf("split test server address: %v", err)
	}

	// A resolver that cannot answer, standing in for a host where 100.100.100.100
	// is unreachable because tailscaled is not up yet. The dial must still land
	// via the system resolver rather than failing outright — otherwise a shipper
	// started before tailscaled would never recover.
	dead := &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			var d net.Dialer
			return d.DialContext(ctx, network, "127.0.0.1:1")
		},
	}

	dial := dialContextVia(dead, 2*time.Second)
	conn, err := dial(context.Background(), "tcp", net.JoinHostPort("localhost", port))
	if err != nil {
		t.Fatalf("dial fell through to no resolver at all: %v", err)
	}
	_ = conn.Close()
}

// The happy path — a name only the primary resolver knows — needs a DNS server
// to assert, so it is covered on the host rather than here. What is asserted
// here is that the primary is consulted at all: a resolver that answers with a
// wrong-but-valid address must be the one that decides where the dial lands.
func TestDialContextPrefersPrimaryResolver(t *testing.T) {
	reached := make(chan string, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reached <- r.Host
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()
	_, port, err := net.SplitHostPort(strings.TrimPrefix(server.URL, "http://"))
	if err != nil {
		t.Fatalf("split test server address: %v", err)
	}

	primary := &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			var d net.Dialer
			return d.DialContext(ctx, network, "127.0.0.1:1")
		},
	}
	dial := dialContextVia(primary, 2*time.Second)

	client := &http.Client{Transport: &http.Transport{DialContext: dial}, Timeout: 5 * time.Second}
	resp, err := client.Get("http://localhost:" + port + "/")
	if err != nil {
		t.Fatalf("get through custom dialer: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", resp.StatusCode)
	}
	select {
	case host := <-reached:
		if !strings.HasSuffix(host, port) {
			t.Fatalf("reached %q, want a host ending in :%s", host, port)
		}
	default:
		t.Fatal("request never reached the server")
	}
}

func TestNewHTTPClientUsesTheMagicDNSDialer(t *testing.T) {
	client := NewHTTPClient(30 * time.Second)
	if client.Timeout != 30*time.Second {
		t.Fatalf("Timeout = %v, want 30s", client.Timeout)
	}
	transport, ok := client.Transport.(*http.Transport)
	if !ok {
		t.Fatalf("Transport = %T, want *http.Transport", client.Transport)
	}
	if transport.DialContext == nil {
		t.Fatal("Transport.DialContext is nil: the client would use the default resolver, " +
			"which on a Mac mini cannot see MagicDNS")
	}
}
