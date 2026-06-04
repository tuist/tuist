package sni

import (
	"bytes"
	"crypto/tls"
	"io"
	"net"
	"testing"
	"time"
)

// captureClientHello drives a real tls.Client over an unbuffered pipe and
// returns the raw ClientHello bytes it emits.
func captureClientHello(t *testing.T, serverName string, max uint16) []byte {
	t.Helper()
	cli, srv := net.Pipe()
	go func() {
		c := tls.Client(cli, &tls.Config{ServerName: serverName, InsecureSkipVerify: true, MaxVersion: max})
		_ = c.Handshake() // never completes; we only need the first flight
		_ = cli.Close()
	}()
	_ = srv.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 8192)
	n, err := srv.Read(buf)
	_ = srv.Close()
	if err != nil && n == 0 {
		t.Fatalf("capture client hello: %v", err)
	}
	return append([]byte(nil), buf[:n]...)
}

func TestPeekExtractsSNI(t *testing.T) {
	for _, ver := range []struct {
		name string
		max  uint16
	}{
		{"tls1.2", tls.VersionTLS12},
		{"tls1.3", tls.VersionTLS13},
	} {
		t.Run(ver.name, func(t *testing.T) {
			hello := captureClientHello(t, "results-receiver.actions.githubusercontent.com", ver.max)
			name, peeked, err := Peek(bytes.NewReader(hello))
			if err != nil {
				t.Fatalf("Peek: %v", err)
			}
			if name != "results-receiver.actions.githubusercontent.com" {
				t.Fatalf("sni = %q", name)
			}
			if !bytes.Equal(peeked, hello) {
				t.Fatalf("peeked bytes (%d) differ from input (%d) — replay would corrupt the stream", len(peeked), len(hello))
			}
		})
	}
}

func TestPeekReplayAcrossFragmentedReads(t *testing.T) {
	hello := captureClientHello(t, "example.blob.core.windows.net", tls.VersionTLS13)
	// Feed the hello one byte at a time to simulate fragmented TCP reads.
	name, peeked, err := Peek(iotest1byte{r: bytes.NewReader(hello)})
	if err != nil {
		t.Fatalf("Peek: %v", err)
	}
	if name != "example.blob.core.windows.net" {
		t.Fatalf("sni = %q", name)
	}
	if !bytes.Equal(peeked, hello) {
		t.Fatal("peeked bytes differ under fragmented reads")
	}
}

func TestPeekNonTLS(t *testing.T) {
	_, peeked, err := Peek(bytes.NewReader([]byte("GET / HTTP/1.1\r\n\r\n")))
	if err != ErrNotTLS {
		t.Fatalf("err = %v want ErrNotTLS", err)
	}
	if len(peeked) == 0 {
		t.Fatal("expected the read bytes to be returned for replay")
	}
}

func TestPeekTruncated(t *testing.T) {
	hello := captureClientHello(t, "host.example", tls.VersionTLS13)
	_, _, err := Peek(bytes.NewReader(hello[:20])) // cut mid-hello
	if err == nil {
		t.Fatal("expected error on truncated hello")
	}
}

// iotest1byte returns at most one byte per Read.
type iotest1byte struct{ r io.Reader }

func (o iotest1byte) Read(p []byte) (int, error) {
	if len(p) == 0 {
		return 0, nil
	}
	return o.r.Read(p[:1])
}
