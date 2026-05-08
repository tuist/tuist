package podagent

import (
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

func TestForwarder_RelaysHTTPRequest(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, "ok\n")
	}))
	defer upstream.Close()

	upstreamAddr := strings.TrimPrefix(upstream.URL, "http://")

	fw, err := NewForwarder("127.0.0.1:0", func() (string, error) { return upstreamAddr, nil })
	if err != nil {
		t.Fatalf("NewForwarder: %v", err)
	}
	defer fw.Stop()

	resp, err := http.Get("http://" + fw.Addr().String() + "/anything")
	if err != nil {
		t.Fatalf("get through forwarder: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	body, _ := io.ReadAll(resp.Body)
	if string(body) != "ok\n" {
		t.Fatalf("body = %q, want %q", string(body), "ok\n")
	}
}

func TestForwarder_ResolvesEverytime(t *testing.T) {
	// Two upstreams: the resolver flips between them per call, so we
	// can prove the forwarder doesn't cache the first answer.
	a := newProbeServer("A")
	defer a.Close()
	b := newProbeServer("B")
	defer b.Close()

	var n atomic.Int32
	resolve := func() (string, error) {
		if n.Add(1)%2 == 1 {
			return strings.TrimPrefix(a.URL, "http://"), nil
		}
		return strings.TrimPrefix(b.URL, "http://"), nil
	}

	fw, err := NewForwarder("127.0.0.1:0", resolve)
	if err != nil {
		t.Fatalf("NewForwarder: %v", err)
	}
	defer fw.Stop()

	// Each request needs its own client + Connection: close so
	// keep-alive doesn't pin us to the first upstream chosen.
	bodyOf := func() string {
		req, _ := http.NewRequest("GET", "http://"+fw.Addr().String()+"/x", nil)
		req.Close = true
		resp, err := http.DefaultTransport.RoundTrip(req)
		if err != nil {
			t.Fatalf("get: %v", err)
		}
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)
		return string(body)
	}

	first := bodyOf()
	second := bodyOf()
	if first == second {
		t.Fatalf("expected the two requests to land on different upstreams; both returned %q", first)
	}
}

func TestForwarder_ReturnsBadGatewayWhenResolveFails(t *testing.T) {
	fw, err := NewForwarder("127.0.0.1:0", func() (string, error) { return "", errors.New("vm has no IP yet") })
	if err != nil {
		t.Fatalf("NewForwarder: %v", err)
	}
	defer fw.Stop()

	resp, err := http.Get("http://" + fw.Addr().String() + "/metrics")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", resp.StatusCode)
	}
}

func TestForwarder_StopIsIdempotent(t *testing.T) {
	fw, err := NewForwarder("127.0.0.1:0", func() (string, error) { return "127.0.0.1:1", nil })
	if err != nil {
		t.Fatalf("NewForwarder: %v", err)
	}
	fw.Stop()
	fw.Stop()
}

func newProbeServer(body string) *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, body)
	}))
}
