package splice

import (
	"io"
	"net"
	"testing"
	"time"
)

// echoServer accepts one connection and echoes everything back.
func echoServer(t *testing.T) net.Listener {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		_, _ = io.Copy(c, c)
		_ = c.Close()
	}()
	return ln
}

func TestSpliceBidirectional(t *testing.T) {
	echo := echoServer(t)
	defer echo.Close()

	// up: the "upstream" side Splice copies to/from.
	up, err := net.Dial("tcp", echo.Addr().String())
	if err != nil {
		t.Fatal(err)
	}

	// client side: a connected TCP pair so we can drive bytes in/out.
	clientLn, _ := net.Listen("tcp", "127.0.0.1:0")
	defer clientLn.Close()
	clientLocal, err := net.Dial("tcp", clientLn.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	clientRemote, err := clientLn.Accept()
	if err != nil {
		t.Fatal(err)
	}

	go Splice(clientRemote, up)

	if _, err := clientLocal.Write([]byte("hello world")); err != nil {
		t.Fatal(err)
	}
	_ = clientLocal.(*net.TCPConn).CloseWrite()

	_ = clientLocal.SetReadDeadline(time.Now().Add(2 * time.Second))
	got, err := io.ReadAll(clientLocal)
	if err != nil {
		t.Fatalf("read echoed bytes: %v", err)
	}
	if string(got) != "hello world" {
		t.Fatalf("got %q want hello world", got)
	}
}
