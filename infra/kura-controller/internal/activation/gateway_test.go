package activation

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type roundTripper func(*http.Request) (*http.Response, error)

func (f roundTripper) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func request(host string) *http.Request {
	r := httptest.NewRequest(http.MethodPut, "https://"+host+"/api/cache/cas/blob", strings.NewReader("artifact"))
	r.Header.Set("Authorization", "Bearer test-token")
	return r
}

func TestEnvironment(t *testing.T) {
	cases := map[string]string{"acme.cache.tuist.dev": "production", "acme-staging.cache.tuist.dev": "staging", "acme-canary.cache.tuist.dev": "canary", "acme.cache.tuist.dev.evil": "", "a.b.cache.tuist.dev": "", "-a.cache.tuist.dev": "", "a-.cache.tuist.dev": "", "a-canary-staging.cache.tuist.dev": "", "acme.cache.tuist.dev:444": ""}
	for host, want := range cases {
		env, ok := Environment(host)
		if ok != (want != "") || ok && env != want {
			t.Errorf("%s: %s,%v", host, env, ok)
		}
	}
}

func TestColdUploadWaitsWithoutReadingOrReplayingBody(t *testing.T) {
	var resolutions atomic.Int32
	control := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" || r.URL.Query().Get("host") != "acme-staging.cache.tuist.dev" || r.Header.Get("Authorization") != "Bearer test-token" {
			t.Error("lost control scope")
		}
		if resolutions.Add(1) == 1 {
			w.WriteHeader(202)
			return
		}
		fmt.Fprint(w, `{"endpoint":"https://acme-eu.kura.tuist.dev"}`)
	}))
	defer control.Close()
	g := New(Servers{"staging": control.URL}, 2)
	g.Poll = time.Millisecond
	var calls atomic.Int32
	g.Transport = roundTripper(func(r *http.Request) (*http.Response, error) {
		calls.Add(1)
		if resolutions.Load() < 2 {
			t.Error("forwarded before activation")
		}
		if r.URL.Host != "acme-eu.kura.tuist.dev" || r.Host != r.URL.Host || r.URL.Path != "/api/cache/cas/blob" {
			t.Error("wrong backend or path")
		}
		if r.Header.Get("Authorization") != "Bearer test-token" || r.Header.Get("CF-IPCountry") != "" || r.Header.Get("X-Forwarded-For") != "" {
			t.Error("bad forwarded headers")
		}
		body, _ := io.ReadAll(r.Body)
		if string(body) != "artifact" {
			t.Error("lost upload")
		}
		return &http.Response{StatusCode: 201, Header: make(http.Header), Body: io.NopCloser(strings.NewReader("stored"))}, nil
	})
	r := request("acme-staging.cache.tuist.dev")
	r.Header.Set("CF-IPCountry", "US")
	r.Header.Set("X-Forwarded-For", "forged")
	r.Body = &activationBody{Reader: r.Body, ready: func() bool { return resolutions.Load() >= 2 }, t: t}
	w := httptest.NewRecorder()
	g.ServeHTTP(w, r)
	if w.Code != 201 || w.Body.String() != "stored" || calls.Load() != 1 {
		t.Fatalf("%d %s, calls=%d", w.Code, w.Body, calls.Load())
	}
}

type activationBody struct {
	io.Reader
	ready func() bool
	t     *testing.T
}

func (b *activationBody) Read(p []byte) (int, error) {
	if !b.ready() {
		b.t.Error("read upload before activation")
	}
	return b.Reader.Read(p)
}
func (b *activationBody) Close() error { return nil }

func TestRejectsWithoutProvisioning(t *testing.T) {
	g := New(Servers{"production": "https://tuist.dev"}, 1)
	g.Control.Transport = roundTripper(func(*http.Request) (*http.Response, error) { t.Fatal("must not call control plane"); return nil, nil })
	for _, tc := range []struct {
		host, path, auth string
		status           int
	}{
		{"acme.cache.tuist.dev", "/ready", "Bearer valid", 404},
		{"acme.cache.tuist.dev", "/_internal/status", "Bearer valid", 404},
		{"acme.cache.tuist.dev", "/blob", "", 401},
		{"acme.evil", "/blob", "Bearer valid", 404},
		{"acme-canary.cache.tuist.dev", "/blob", "Bearer valid", 404},
	} {
		r := request(tc.host)
		r.URL.Path = tc.path
		r.Header.Set("Authorization", tc.auth)
		w := httptest.NewRecorder()
		g.ServeHTTP(w, r)
		if w.Code != tc.status {
			t.Errorf("%+v: %d", tc, w.Code)
		}
	}
}

func TestControlPlaneRefusalsAndUnsafeTargets(t *testing.T) {
	for _, status := range []int{401, 403, 402, 404, 429, 500, 302} {
		t.Run(fmt.Sprint(status), func(t *testing.T) {
			g := New(Servers{"production": "https://tuist.dev"}, 1)
			g.Control.Transport = roundTripper(func(*http.Request) (*http.Response, error) {
				return &http.Response{StatusCode: status, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(""))}, nil
			})
			w := httptest.NewRecorder()
			g.ServeHTTP(w, request("acme.cache.tuist.dev"))
			want := status
			if status == 500 || status == 302 {
				want = 503
			}
			if w.Code != want {
				t.Fatalf("%d, want %d", w.Code, want)
			}
		})
	}
	for _, target := range []string{"https://acme.cache.tuist.dev", "http://acme.kura.tuist.dev", "https://127.0.0.1", "https://acme.kura.tuist.dev.evil", "https://user@acme.kura.tuist.dev", "https://acme.kura.tuist.dev:443", "https://acme.kura.tuist.dev/path"} {
		g := New(Servers{"production": "https://tuist.dev"}, 1)
		g.Control.Transport = roundTripper(func(*http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(fmt.Sprintf(`{"endpoint":%q}`, target)))}, nil
		})
		w := httptest.NewRecorder()
		g.ServeHTTP(w, request("acme.cache.tuist.dev"))
		if w.Code != 503 {
			t.Errorf("accepted %s", target)
		}
	}
}

func TestTimeoutAndCapacityAreRetryableGRPC(t *testing.T) {
	g := New(Servers{"production": "https://tuist.dev"}, 1)
	g.Wait = 5 * time.Millisecond
	g.Poll = time.Millisecond
	g.Control.Transport = roundTripper(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 202, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(""))}, nil
	})
	r := request("acme.cache.tuist.dev")
	r.Header.Set("Content-Type", "application/grpc")
	w := httptest.NewRecorder()
	g.ServeHTTP(w, r)
	if w.Code != 200 || w.Header().Get("Grpc-Status") != "14" || w.Header().Get("Retry-After") != "2" {
		t.Fatalf("%d %v", w.Code, w.Header())
	}
	g.slots <- struct{}{}
	w = httptest.NewRecorder()
	g.ServeHTTP(w, r)
	if w.Header().Get("Grpc-Status") != "8" {
		t.Fatal(w.Header())
	}
	<-g.slots
}

func TestCancellationStopsActivation(t *testing.T) {
	g := New(Servers{"production": "https://tuist.dev"}, 1)
	g.Control.Transport = roundTripper(func(r *http.Request) (*http.Response, error) { <-r.Context().Done(); return nil, r.Context().Err() })
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	w := httptest.NewRecorder()
	g.ServeHTTP(w, request("acme.cache.tuist.dev").WithContext(ctx))
	if len(g.slots) != 0 {
		t.Fatal("leaked admission slot")
	}
}

func TestGRPCStreamingAndTrailers(t *testing.T) {
	// A real HTTP/2 TLS upstream exercises ReverseProxy's streaming and trailer
	// handling; no gRPC decoding or buffering belongs in the activation gateway.
	payload := bytes.Repeat([]byte("frame"), 10000)
	backend := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.ProtoMajor != 2 {
			t.Error("upstream is not HTTP/2")
		}
		body, _ := io.ReadAll(r.Body)
		if !bytes.Equal(body, payload) {
			t.Error("corrupted gRPC payload")
		}
		w.Header().Set("Content-Type", "application/grpc")
		w.Header().Set("Trailer", "Grpc-Status")
		w.WriteHeader(200)
		_, _ = w.Write(payload)
		w.Header().Set("Grpc-Status", "0")
	}))
	backend.EnableHTTP2 = true
	backend.StartTLS()
	defer backend.Close()
	g := New(Servers{"production": "https://tuist.dev"}, 1)
	g.Control.Transport = roundTripper(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"endpoint":"https://acme-eu.kura.tuist.dev"}`))}, nil
	})
	g.Transport = roundTripper(func(r *http.Request) (*http.Response, error) {
		r.URL.Host = strings.TrimPrefix(backend.URL, "https://")
		return backend.Client().Transport.RoundTrip(r)
	})
	gateway := httptest.NewUnstartedServer(g)
	gateway.Config.Protocols = new(http.Protocols)
	gateway.Config.Protocols.SetUnencryptedHTTP2(true)
	gateway.Start()
	defer gateway.Close()
	protocols := new(http.Protocols)
	protocols.SetUnencryptedHTTP2(true)
	client := &http.Client{Transport: &http.Transport{Protocols: protocols}, Timeout: time.Second}
	r, _ := http.NewRequest("POST", gateway.URL+"/google.bytestream.ByteStream/Write", bytes.NewReader(payload))
	r.Host = "acme.cache.tuist.dev"
	r.Header.Set("Authorization", "Bearer test-token")
	r.Header.Set("Content-Type", "application/grpc")
	resp, err := client.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil || !bytes.Equal(body, payload) || resp.Trailer.Get("Grpc-Status") != "0" {
		t.Fatalf("body=%d trailers=%v err=%v", len(body), resp.Trailer, err)
	}
}

func TestCachedRouteStillForwardsEachRequestsCredential(t *testing.T) {
	g := New(Servers{"production": "https://tuist.dev"}, 1)
	var controls atomic.Int32
	g.Control.Transport = roundTripper(func(*http.Request) (*http.Response, error) {
		controls.Add(1)
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"endpoint":"https://acme-eu.kura.tuist.dev"}`))}, nil
	})
	g.Transport = roundTripper(func(r *http.Request) (*http.Response, error) {
		status := 200
		if r.Header.Get("Authorization") != "Bearer test-token" {
			status = 403
		}
		return &http.Response{StatusCode: status, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(""))}, nil
	})
	for _, token := range []string{"test-token", "another-credential"} {
		r := request("acme.cache.tuist.dev")
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		g.ServeHTTP(w, r)
		want := 200
		if token != "test-token" {
			want = 403
		}
		if w.Code != want {
			t.Fatalf("credential %s: %d", token, w.Code)
		}
	}
	if controls.Load() != 1 {
		t.Fatalf("route not cached: %d", controls.Load())
	}
	g.routesMu.Lock()
	route := g.routes["acme.cache.tuist.dev"]
	route.expires = time.Now().Add(-time.Second)
	g.routes["acme.cache.tuist.dev"] = route
	g.routesMu.Unlock()
	if g.cachedRoute("acme.cache.tuist.dev") != nil {
		t.Fatal("expired route retained")
	}
}

func TestProxyFailureDoesNotReplayUpload(t *testing.T) {
	g := New(Servers{"production": "https://tuist.dev"}, 1)
	g.Control.Transport = roundTripper(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"endpoint":"https://acme-eu.kura.tuist.dev"}`))}, nil
	})
	var calls int
	g.Transport = roundTripper(func(r *http.Request) (*http.Response, error) {
		calls++
		_, _ = io.Copy(io.Discard, r.Body)
		return nil, io.ErrUnexpectedEOF
	})
	w := httptest.NewRecorder()
	g.ServeHTTP(w, request("acme.cache.tuist.dev"))
	if w.Code != 503 || calls != 1 {
		t.Fatalf("%d attempts, status %d", calls, w.Code)
	}
	if g.cachedRoute("acme.cache.tuist.dev") != nil {
		t.Fatal("failed route retained")
	}
}
