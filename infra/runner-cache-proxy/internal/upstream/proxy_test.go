package upstream

import (
	"io"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"net/url"
	"testing"

	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/router"
)

type fakeRegistry struct{ tok map[netip.Addr][]byte }

func (f fakeRegistry) Lookup(ip netip.Addr) ([]byte, bool) { t, ok := f.tok[ip]; return t, ok }

type fakeBreaker struct{ allow bool }

func (f fakeBreaker) Allow() bool { return f.allow }

// redirectRT routes any request to a fixed host (a fake httptest server),
// standing in for the genuine-GitHub TLS transport.
type redirectRT struct{ host, scheme string }

func (rt redirectRT) RoundTrip(r *http.Request) (*http.Response, error) {
	c := r.Clone(r.Context())
	c.URL.Scheme = rt.scheme
	c.URL.Host = rt.host
	return http.DefaultTransport.RoundTrip(c)
}

type capture struct {
	authorization string
	path          string
	hits          int
}

func captureServer(c *capture, body string) *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c.authorization = r.Header.Get("Authorization")
		c.path = r.URL.Path
		c.hits++
		_, _ = io.WriteString(w, body)
	}))
}

const srcIP = "192.168.64.7"

func buildProxy(t *testing.T, gwURL string, github *httptest.Server, tokens map[netip.Addr][]byte, breakerAllow bool) *Proxy {
	t.Helper()
	ghURL, _ := url.Parse(github.URL)
	p, err := New(Options{
		GatewayURL:      gwURL,
		Registry:        fakeRegistry{tok: tokens},
		Breaker:         fakeBreaker{allow: breakerAllow},
		Decisions:       router.NewDecisionCache(0), // no stickiness in these tests
		GitHubTransport: redirectRT{host: ghURL.Host, scheme: ghURL.Scheme},
	})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	return p
}

func do(t *testing.T, p *Proxy, path, auth string) {
	t.Helper()
	ts := httptest.NewServer(p.Handler(ConnContext{
		SrcIP: netip.MustParseAddr(srcIP),
		SNI:   "results-receiver.actions.githubusercontent.com",
	}))
	defer ts.Close()
	req, _ := http.NewRequest(http.MethodPost, ts.URL+path, nil)
	if auth != "" {
		req.Header.Set("Authorization", auth)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	resp.Body.Close()
}

func TestCacheServiceRoutesToGatewayWithTokenSwap(t *testing.T) {
	var gw, gh capture
	gws := captureServer(&gw, "gateway")
	defer gws.Close()
	ghs := captureServer(&gh, "github")
	defer ghs.Close()

	tokens := map[netip.Addr][]byte{netip.MustParseAddr(srcIP): []byte("tenant-cache-token")}
	p := buildProxy(t, gws.URL, ghs, tokens, true)

	do(t, p, router.CacheServicePrefix+"GetCacheEntryDownloadURL", "Bearer runtime-token")

	if gw.hits != 1 {
		t.Fatalf("gateway hits = %d want 1", gw.hits)
	}
	if gw.authorization != "Bearer tenant-cache-token" {
		t.Fatalf("gateway saw auth %q, expected the swapped tenant token", gw.authorization)
	}
	if gh.hits != 0 {
		t.Fatal("github should not have been hit for a CacheService call")
	}
}

func TestArtifactServiceRoutesToGitHubUntouched(t *testing.T) {
	var gw, gh capture
	gws := captureServer(&gw, "gateway")
	defer gws.Close()
	ghs := captureServer(&gh, "github")
	defer ghs.Close()

	tokens := map[netip.Addr][]byte{netip.MustParseAddr(srcIP): []byte("tenant-cache-token")}
	p := buildProxy(t, gws.URL, ghs, tokens, true)

	do(t, p, "/twirp/github.actions.results.api.v1.ArtifactService/CreateArtifact", "Bearer runtime-token")

	if gh.hits != 1 {
		t.Fatalf("github hits = %d want 1", gh.hits)
	}
	if gh.authorization != "Bearer runtime-token" {
		t.Fatalf("github saw auth %q, the original token must be preserved", gh.authorization)
	}
	if gw.hits != 0 {
		t.Fatal("gateway should not have been hit for an ArtifactService call")
	}
}

func TestMissingTokenFailsOpenToGitHub(t *testing.T) {
	var gw, gh capture
	gws := captureServer(&gw, "gateway")
	defer gws.Close()
	ghs := captureServer(&gh, "github")
	defer ghs.Close()

	// No token staged for this source IP.
	p := buildProxy(t, gws.URL, ghs, map[netip.Addr][]byte{}, true)

	do(t, p, router.CacheServicePrefix+"CreateCacheEntry", "Bearer runtime-token")

	if gh.hits != 1 || gw.hits != 0 {
		t.Fatalf("missing token should fail open to github: gw=%d gh=%d", gw.hits, gh.hits)
	}
	if gh.authorization != "Bearer runtime-token" {
		t.Fatalf("github saw auth %q, original must be preserved on fail-open", gh.authorization)
	}
}

func TestBreakerOpenRoutesCacheServiceToGitHub(t *testing.T) {
	var gw, gh capture
	gws := captureServer(&gw, "gateway")
	defer gws.Close()
	ghs := captureServer(&gh, "github")
	defer ghs.Close()

	tokens := map[netip.Addr][]byte{netip.MustParseAddr(srcIP): []byte("tenant-cache-token")}
	p := buildProxy(t, gws.URL, ghs, tokens, false) // breaker open

	do(t, p, router.CacheServicePrefix+"CreateCacheEntry", "Bearer runtime-token")

	if gh.hits != 1 || gw.hits != 0 {
		t.Fatalf("breaker-open CacheService should route to github: gw=%d gh=%d", gw.hits, gh.hits)
	}
}
