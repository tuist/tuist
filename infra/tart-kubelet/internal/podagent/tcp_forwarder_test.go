package podagent

import (
	"bufio"
	"io"
	"net"
	"strings"
	"testing"
)

func TestTCPForwarderRelaysBytes(t *testing.T) {
	upstream, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer upstream.Close()

	done := make(chan struct{})
	go func() {
		defer close(done)
		conn, err := upstream.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		line, _ := bufio.NewReader(conn).ReadString('\n')
		_, _ = io.WriteString(conn, "echo:"+line)
	}()

	fw, err := NewTCPForwarder("127.0.0.1:0", func() (string, error) {
		return upstream.Addr().String(), nil
	}, TCPForwarderOptions{})
	if err != nil {
		t.Fatalf("NewTCPForwarder: %v", err)
	}
	defer fw.Stop()

	conn, err := net.Dial("tcp", fw.Addr().String())
	if err != nil {
		t.Fatalf("dial forwarder: %v", err)
	}
	defer conn.Close()
	if _, err := io.WriteString(conn, "hello\n"); err != nil {
		t.Fatalf("write: %v", err)
	}
	got, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if got != "echo:hello\n" {
		t.Fatalf("got %q, want echo:hello\\n", got)
	}
	<-done
}

func TestTCPForwarderRejectsSourcesOutsideAllowedCIDR(t *testing.T) {
	upstream, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer upstream.Close()

	accepted := make(chan struct{}, 1)
	go func() {
		conn, err := upstream.Accept()
		if err == nil {
			accepted <- struct{}{}
			_ = conn.Close()
		}
	}()

	_, deny, _ := net.ParseCIDR("198.51.100.0/24")
	fw, err := NewTCPForwarder("127.0.0.1:0", func() (string, error) {
		return upstream.Addr().String(), nil
	}, TCPForwarderOptions{AllowedCIDRs: []*net.IPNet{deny}})
	if err != nil {
		t.Fatalf("NewTCPForwarder: %v", err)
	}
	defer fw.Stop()

	conn, err := net.Dial("tcp", fw.Addr().String())
	if err != nil {
		t.Fatalf("dial forwarder: %v", err)
	}
	_, _ = io.WriteString(conn, "hello\n")
	buf := make([]byte, 1)
	_, readErr := conn.Read(buf)
	_ = conn.Close()
	if readErr == nil || !strings.Contains(readErr.Error(), "reset") && readErr != io.EOF {
		t.Fatalf("readErr = %v, want closed connection", readErr)
	}

	select {
	case <-accepted:
		t.Fatal("upstream accepted a connection despite source CIDR rejection")
	default:
	}
}
