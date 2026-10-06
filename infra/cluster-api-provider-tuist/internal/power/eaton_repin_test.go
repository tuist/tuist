package power

import (
	"context"
	"io"
	"net"
	"net/url"
	"strings"
	"sync"
	"testing"
)

// tcpProxy forwards to a card and can drop every connection it carries, as a
// keep-alive connection lapses after idling.
type tcpProxy struct {
	mu    sync.Mutex
	conns []net.Conn
	addr  string
}

func newTCPProxy(t *testing.T, target string) *tcpProxy {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = ln.Close() })
	p := &tcpProxy{addr: ln.Addr().String()}
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			b, err := net.Dial("tcp", target)
			if err != nil {
				_ = c.Close()
				continue
			}
			p.mu.Lock()
			p.conns = append(p.conns, c, b)
			p.mu.Unlock()
			go func() { _, _ = io.Copy(b, c) }()
			go func() { _, _ = io.Copy(c, b) }()
		}
	}()
	return p
}

func (p *tcpProxy) dropAll() {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, c := range p.conns {
		_ = c.Close()
	}
	p.conns = nil
}

// Pinning a card's new certificate logs the old session out over a connection
// that verifies the new one: through the old client, pinned to the old
// certificate, the logout never reaches the card once the idle connection has
// gone, and the card refuses the next login while the stranded session lives.
func TestEatonRepinLogsTheOldSessionOut(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	u, err := url.Parse(card.URL())
	if err != nil {
		t.Fatal(err)
	}
	proxy := newTCPProxy(t, u.Host)
	outlet.Host = "https://" + proxy.addr
	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State: %v", err)
	}

	card.RotateCertificate()
	proxy.dropAll()
	outlet.TLSFingerprint = card.Fingerprint()

	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State after pinning the new certificate: %v", err)
	}
	card.Mu.Lock()
	defer card.Mu.Unlock()
	if card.Logouts != 1 {
		t.Fatalf("logouts = %d, want the old session logged out", card.Logouts)
	}
}

// A card that no longer knows the session, one reset to its factory state or
// presenting a new certificate after a reset, answers its logout 401: nothing
// holds the account, so changing the card's settings goes on.
func TestEatonLogoutOfASessionTheCardForgotIsNotAnError(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State: %v", err)
	}
	card.Expire()
	card.RotateCertificate()
	outlet.TLSFingerprint = card.Fingerprint()

	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State after the card forgot the session: %v", err)
	}
}

// A logout that does not reach the card is an error, not a silent stranded
// session.
func TestEatonFailedLogoutIsReported(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State: %v", err)
	}
	card.Close()
	outlet.Password = "Another-password1"
	_, err := e.State(context.Background(), outlet)
	if err == nil || !strings.Contains(err.Error(), "log out") {
		t.Fatalf("State after a logout that could not reach the card = %v, want it named", err)
	}
}
