package podagent

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"io"
	"net"
	"strings"
	"testing"
)

func TestVNCForwarderAuthenticatesUpstreamAndPresentsNoAuth(t *testing.T) {
	upstream, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer upstream.Close()

	challenge := []byte("0123456789abcdef")
	expectedResponse, err := vncAuthResponse("secret", challenge)
	if err != nil {
		t.Fatal(err)
	}

	upstreamDone := make(chan struct{})
	go func() {
		defer close(upstreamDone)
		conn, err := upstream.Accept()
		if err != nil {
			return
		}
		defer conn.Close()

		_, _ = conn.Write([]byte("RFB 003.008\n"))
		version := make([]byte, 12)
		_, _ = io.ReadFull(conn, version)
		_, _ = conn.Write([]byte{1, rfbSecurityVNCAuth})

		selected := make([]byte, 1)
		_, _ = io.ReadFull(conn, selected)
		if selected[0] != rfbSecurityVNCAuth {
			t.Errorf("upstream selected security = %d, want %d", selected[0], rfbSecurityVNCAuth)
			return
		}
		_, _ = conn.Write(challenge)

		response := make([]byte, 16)
		_, _ = io.ReadFull(conn, response)
		if !bytes.Equal(response, expectedResponse) {
			t.Errorf("unexpected VNC auth response")
			return
		}

		var ok [4]byte
		_, _ = conn.Write(ok[:])

		clientInit := make([]byte, 1)
		_, _ = io.ReadFull(conn, clientInit)
		_, _ = conn.Write([]byte("ready"))
	}()

	fw, err := NewVNCForwarder("127.0.0.1:0", func() (string, error) {
		return upstream.Addr().String(), nil
	}, "secret", "", TCPForwarderOptions{})
	if err != nil {
		t.Fatalf("NewVNCForwarder: %v", err)
	}
	defer fw.Stop()

	client, err := net.Dial("tcp", fw.Addr().String())
	if err != nil {
		t.Fatalf("dial VNC forwarder: %v", err)
	}
	defer client.Close()

	version := make([]byte, 12)
	if _, err := io.ReadFull(client, version); err != nil {
		t.Fatalf("read version: %v", err)
	}
	if !bytes.Equal(version, []byte("RFB 003.008\n")) {
		t.Fatalf("version = %q", string(version))
	}
	if _, err := client.Write(version); err != nil {
		t.Fatalf("write version: %v", err)
	}

	securityTypes := make([]byte, 2)
	if _, err := io.ReadFull(client, securityTypes); err != nil {
		t.Fatalf("read security types: %v", err)
	}
	if !bytes.Equal(securityTypes, []byte{1, rfbSecurityNone}) {
		t.Fatalf("security types = %v, want no-auth only", securityTypes)
	}
	if _, err := client.Write([]byte{rfbSecurityNone}); err != nil {
		t.Fatalf("select no-auth: %v", err)
	}

	var securityResult [4]byte
	if _, err := io.ReadFull(client, securityResult[:]); err != nil {
		t.Fatalf("read security result: %v", err)
	}
	if got := binary.BigEndian.Uint32(securityResult[:]); got != 0 {
		t.Fatalf("security result = %d, want 0", got)
	}

	if _, err := client.Write([]byte{1}); err != nil {
		t.Fatalf("write client init: %v", err)
	}
	body := make([]byte, 5)
	if _, err := io.ReadFull(client, body); err != nil {
		t.Fatalf("read body: %v", err)
	}
	if !bytes.Equal(body, []byte("ready")) {
		t.Fatalf("body = %q, want ready", string(body))
	}

	<-upstreamDone
}

func TestAuthenticateRelayClientAcceptsExpectedTokenAndPreservesBufferedRFB(t *testing.T) {
	reader := bufio.NewReader(strings.NewReader(relayAuthPrefix + "dashboard-token\nRFB 003.008\n"))

	if err := authenticateRelayClient(reader, relayTokenHash("dashboard-token")); err != nil {
		t.Fatalf("authenticateRelayClient: %v", err)
	}

	remaining := make([]byte, 12)
	if _, err := io.ReadFull(reader, remaining); err != nil {
		t.Fatalf("read buffered RFB version: %v", err)
	}
	if !bytes.Equal(remaining, []byte("RFB 003.008\n")) {
		t.Fatalf("remaining = %q, want RFB version", remaining)
	}
}

func TestAuthenticateRelayClientRejectsMissingOrWrongToken(t *testing.T) {
	for name, input := range map[string]string{
		"missing preface": "RFB 003.008\n",
		"wrong token":     relayAuthPrefix + "wrong-token\n",
	} {
		t.Run(name, func(t *testing.T) {
			reader := bufio.NewReader(strings.NewReader(input))

			if err := authenticateRelayClient(reader, relayTokenHash("dashboard-token")); err == nil {
				t.Fatal("authenticateRelayClient unexpectedly succeeded")
			}
		})
	}
}

// freeLoopbackPort returns a port that was free a moment ago on loopback.
// Good enough to seed a range in tests, where nothing else is racing for it.
func freeLoopbackPort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := l.Addr().(*net.TCPAddr).Port
	_ = l.Close()
	return port
}

func resolveNothing() (string, error) { return "127.0.0.1:1", nil }

// A pinned relay port is a per-host resource while a relay is per-Pod, so a
// second guest on the same mini must land on the next port in the range
// rather than failing to bind. Before the range existed the second guest's
// relay errored out and interactive sessions were dead on half the fleet.
func TestBindVNCForwarder_WalksTheRangeWhenTheBasePortIsTaken(t *testing.T) {
	base := freeLoopbackPort(t)
	r := &Reconciler{NodeIP: "127.0.0.1", VNCRelayPort: base, VNCRelayPortCount: 2}

	first, addr, err := r.bindVNCForwarder(resolveNothing, "pw", "", DefaultScrapeAllowedCIDRs())
	if err != nil {
		t.Fatalf("first relay failed to bind on %s: %v", addr, err)
	}
	defer first.Stop()
	if got := first.Addr().(*net.TCPAddr).Port; got != base {
		t.Fatalf("first relay bound %d, want the base port %d", got, base)
	}

	second, addr, err := r.bindVNCForwarder(resolveNothing, "pw", "", DefaultScrapeAllowedCIDRs())
	if err != nil {
		t.Fatalf("second relay failed to bind on %s: %v; a dual-guest host cannot open both sessions", addr, err)
	}
	defer second.Stop()
	if got := second.Addr().(*net.TCPAddr).Port; got != base+1 {
		t.Fatalf("second relay bound %d, want base+1 = %d", got, base+1)
	}
}

// Exhausting the range is an error, not a silent fallback to an ephemeral
// port: the pinned range is exactly the set of ports the per-Mac egress
// Service forwards, so an ephemeral relay would be unreachable and the
// dashboard would hang instead of reporting a failure.
func TestBindVNCForwarder_FailsWhenTheWholeRangeIsTaken(t *testing.T) {
	base := freeLoopbackPort(t)
	r := &Reconciler{NodeIP: "127.0.0.1", VNCRelayPort: base, VNCRelayPortCount: 1}

	held, _, err := r.bindVNCForwarder(resolveNothing, "pw", "", DefaultScrapeAllowedCIDRs())
	if err != nil {
		t.Fatalf("seed relay failed to bind: %v", err)
	}
	defer held.Stop()

	if fw, _, err := r.bindVNCForwarder(resolveNothing, "pw", "", DefaultScrapeAllowedCIDRs()); err == nil {
		fw.Stop()
		t.Fatal("expected an error once the pinned range is exhausted, got a forwarder on some other port")
	}
}

// No pinned base port means the operator never declared a range, so the relay
// takes an ephemeral port exactly as it did before — the OSS/self-hosted shape.
func TestBindVNCForwarder_UsesEphemeralPortWithoutAPinnedBase(t *testing.T) {
	r := &Reconciler{NodeIP: "127.0.0.1", VNCRelayPortCount: 2}

	fw, _, err := r.bindVNCForwarder(resolveNothing, "pw", "", DefaultScrapeAllowedCIDRs())
	if err != nil {
		t.Fatalf("ephemeral relay failed to bind: %v", err)
	}
	defer fw.Stop()
	if fw.Addr().(*net.TCPAddr).Port == 0 {
		t.Fatal("expected a real ephemeral port")
	}
}
