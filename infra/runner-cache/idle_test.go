package cachevolumes

import (
	"bufio"
	"context"
	"io"
	"net"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"testing/synctest"
	"time"
)

const bandit15sIdle = 15 * time.Second

// serveClosingIdle closes a connection idle for idle, like Bandit; a request arriving then is never answered.
func serveClosingIdle(conn net.Conn, idle time.Duration) {
	defer conn.Close()
	reader := bufio.NewReader(conn)
	var answered time.Time
	for {
		request, err := http.ReadRequest(reader)
		if err != nil {
			return
		}
		_, _ = io.Copy(io.Discard, request.Body)
		if !answered.IsZero() && time.Since(answered) >= idle {
			return
		}
		if _, err := io.WriteString(conn, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok"); err != nil {
			return
		}
		answered = time.Now()
	}
}

func pipeServerClient(t *testing.T, client *http.Client, dials *atomic.Int32) *http.Client {
	t.Helper()
	transport, ok := client.Transport.(*http.Transport)
	if !ok {
		t.Fatalf("server client transport is %T", client.Transport)
	}
	transport = transport.Clone()
	transport.Proxy = nil
	transport.DialContext = func(context.Context, string, string) (net.Conn, error) {
		dials.Add(1)
		clientEnd, serverEnd := net.Pipe()
		go serveClosingIdle(serverEnd, bandit15sIdle)
		return clientEnd, nil
	}
	t.Cleanup(transport.CloseIdleConnections)
	pipeClient := *client
	pipeClient.Transport = transport
	return &pipeClient
}

func postReport(t *testing.T, client *http.Client) error {
	t.Helper()
	request, err := http.NewRequest(http.MethodPost, "http://tuist.test/api/internal/runners/cache-volumes/authorize", strings.NewReader(`{"pod":"p"}`))
	if err != nil {
		t.Fatal(err)
	}
	response, err := client.Do(request)
	if err != nil {
		return err
	}
	_, _ = io.Copy(io.Discard, response.Body)
	return response.Body.Close()
}

func TestServerClientNeverReusesAConnectionTheServerIsClosingForIdleness(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		var dials atomic.Int32
		client := pipeServerClient(t, NewServerClient(time.Minute), &dials)

		if err := postReport(t, client); err != nil {
			t.Fatal(err)
		}
		time.Sleep(bandit15sIdle)
		if err := postReport(t, client); err != nil {
			t.Fatalf("request after the server's idle timeout: %v", err)
		}
		if got := dials.Load(); got != 2 {
			t.Fatalf("dials = %d, want a new connection after the idle timeout", got)
		}
		client.Transport.(*http.Transport).CloseIdleConnections()
	})
}

func TestServerClientReusesAConnectionWithinItsIdleTimeout(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		var dials atomic.Int32
		client := pipeServerClient(t, NewServerClient(time.Minute), &dials)

		for range 3 {
			if err := postReport(t, client); err != nil {
				t.Fatal(err)
			}
			time.Sleep(ServerIdleTimeout - time.Second)
		}
		if got := dials.Load(); got != 1 {
			t.Fatalf("dials = %d, want one kept-alive connection", got)
		}
		client.Transport.(*http.Transport).CloseIdleConnections()
	})
}
