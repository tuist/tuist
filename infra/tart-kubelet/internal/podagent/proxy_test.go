package podagent

import (
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestForwarder_RelaysMetricsRequest(t *testing.T) {
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

	resp, err := http.Get("http://" + fw.Addr().String() + MetricsPath)
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

func TestForwarder_RejectsNonMetricsPaths(t *testing.T) {
	// Upstream that fails the test if it's ever hit. The path filter
	// must reject before reaching the proxy.
	upstream := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, _ *http.Request) {
		t.Errorf("upstream should not be reached")
	}))
	defer upstream.Close()

	fw, err := NewForwarder("127.0.0.1:0", func() (string, error) {
		return strings.TrimPrefix(upstream.URL, "http://"), nil
	})
	if err != nil {
		t.Fatalf("NewForwarder: %v", err)
	}
	defer fw.Stop()

	for _, path := range []string{"/", "/admin", "/metrics/extra", "/Metrics", "/secret"} {
		resp, err := http.Get("http://" + fw.Addr().String() + path)
		if err != nil {
			t.Fatalf("get %s: %v", path, err)
		}
		_ = resp.Body.Close()
		if resp.StatusCode != http.StatusNotFound {
			t.Fatalf("path %s: status = %d, want 404", path, resp.StatusCode)
		}
	}
}

func TestForwarder_RejectsNonGETMethods(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, _ *http.Request) {
		t.Errorf("upstream should not be reached")
	}))
	defer upstream.Close()

	fw, err := NewForwarder("127.0.0.1:0", func() (string, error) {
		return strings.TrimPrefix(upstream.URL, "http://"), nil
	})
	if err != nil {
		t.Fatalf("NewForwarder: %v", err)
	}
	defer fw.Stop()

	for _, method := range []string{http.MethodPost, http.MethodPut, http.MethodDelete, http.MethodPatch} {
		req, _ := http.NewRequest(method, "http://"+fw.Addr().String()+MetricsPath, nil)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("%s: %v", method, err)
		}
		_ = resp.Body.Close()
		if resp.StatusCode != http.StatusMethodNotAllowed {
			t.Fatalf("method %s: status = %d, want 405", method, resp.StatusCode)
		}
	}
}

func TestForwarder_CachesResolverWithinTTL(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, "ok")
	}))
	defer upstream.Close()
	upstreamAddr := strings.TrimPrefix(upstream.URL, "http://")

	var resolves atomic.Int32
	fw, err := NewForwarder("127.0.0.1:0", func() (string, error) {
		resolves.Add(1)
		return upstreamAddr, nil
	})
	if err != nil {
		t.Fatalf("NewForwarder: %v", err)
	}
	defer fw.Stop()

	for i := 0; i < 5; i++ {
		req, _ := http.NewRequest("GET", "http://"+fw.Addr().String()+MetricsPath, nil)
		req.Close = true
		resp, err := http.DefaultTransport.RoundTrip(req)
		if err != nil {
			t.Fatalf("get %d: %v", i, err)
		}
		_ = resp.Body.Close()
	}

	// Default TTL is 30s, so all 5 requests should share one resolve.
	if got := resolves.Load(); got != 1 {
		t.Fatalf("resolve calls = %d, want 1 (cache should absorb the burst)", got)
	}
}

func TestForwarder_ReturnsBadGatewayWhenResolveFails(t *testing.T) {
	fw, err := NewForwarder("127.0.0.1:0", func() (string, error) { return "", errors.New("vm has no IP yet") })
	if err != nil {
		t.Fatalf("NewForwarder: %v", err)
	}
	defer fw.Stop()

	resp, err := http.Get("http://" + fw.Addr().String() + MetricsPath)
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

func TestCachedResolver_RefreshesAfterTTL(t *testing.T) {
	var n atomic.Int32
	c := newCachedResolver(func() (string, error) {
		return "v" + itoa(int(n.Add(1))), nil
	}, 10*time.Millisecond)

	v1, _ := c.get()
	v2, _ := c.get()
	if v1 != v2 {
		t.Fatalf("expected cached value reused; got %q then %q", v1, v2)
	}

	time.Sleep(15 * time.Millisecond)
	v3, _ := c.get()
	if v3 == v2 {
		t.Fatalf("expected refresh after TTL; still %q", v3)
	}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	digits := []byte{}
	for n > 0 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
		n /= 10
	}
	return string(digits)
}
