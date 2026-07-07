package podagent

import (
	"bytes"
	"encoding/binary"
	"io"
	"net"
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
	}, "secret", TCPForwarderOptions{})
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
