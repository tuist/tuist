package power

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// The Shelly plug for the BER1 prototype has not been delivered, so nothing
// here has been run against real firmware. These fakes are therefore written
// from the published API shapes and from RFC 7616 rather than from captured
// traffic, and the digest server below is a conformant SERVER: it recomputes
// the expected response itself and rejects a wrong one, so the client is
// checked against the specification rather than against my own assumption of
// what it should send. What that cannot catch is a firmware quirk; the first
// live cycle is still the real test.

// gen2Plug fakes Shelly Gen2+ firmware: JSON-RPC under /rpc, no /relay.
type gen2Plug struct {
	mu       sync.Mutex
	on       map[string]bool
	requests []string
}

func newGen2Plug(channels map[string]bool) *gen2Plug {
	return &gen2Plug{on: channels}
}

func (p *gen2Plug) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p.mu.Lock()
		defer p.mu.Unlock()
		p.requests = append(p.requests, r.URL.Path)

		id := r.URL.Query().Get("id")
		state, known := p.on[id]
		if !known {
			http.NotFound(w, r)
			return
		}

		switch r.URL.Path {
		case "/rpc/Switch.GetStatus":
			fmt.Fprintf(w, `{"id":%s,"source":"HTTP","output":%t,"apower":11.4}`, id, state)
		case "/rpc/Switch.Set":
			was := state
			p.on[id] = r.URL.Query().Get("on") == "true"
			fmt.Fprintf(w, `{"was_on":%t}`, was)
		default:
			http.NotFound(w, r)
		}
	})
}

func (p *gen2Plug) state(channel string) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.on[channel]
}

// gen1Plug fakes Shelly Gen1 firmware: /relay/<id>, and a 404 on everything
// under /rpc, which is exactly the signal the generation probe keys on.
type gen1Plug struct {
	mu   sync.Mutex
	on   map[string]bool
	seen []string
}

func (p *gen1Plug) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p.mu.Lock()
		defer p.mu.Unlock()
		p.seen = append(p.seen, r.URL.Path)

		channel := strings.TrimPrefix(r.URL.Path, "/relay/")
		state, known := p.on[channel]
		if !strings.HasPrefix(r.URL.Path, "/relay/") || !known {
			http.NotFound(w, r)
			return
		}
		if turn := r.URL.Query().Get("turn"); turn != "" {
			state = turn == "on"
			p.on[channel] = state
		}
		fmt.Fprintf(w, `{"ison":%t,"has_timer":false,"source":"http"}`, state)
	})
}

func shellyAgainst(t *testing.T, h http.Handler) (*Shelly, Outlet) {
	t.Helper()
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return &Shelly{HTTP: srv.Client()}, Outlet{Driver: DriverShelly, Host: srv.URL, Outlet: "0"}
}

func TestShellyGen2ReadsAndSwitches(t *testing.T) {
	plug := newGen2Plug(map[string]bool{"0": true})
	s, outlet := shellyAgainst(t, plug.handler())

	got, err := s.State(context.Background(), outlet)
	if err != nil {
		t.Fatalf("State: %v", err)
	}
	if got != StateOn {
		t.Fatalf("State = %q, want %q", got, StateOn)
	}

	if err := s.Set(context.Background(), outlet, false); err != nil {
		t.Fatalf("Set(off): %v", err)
	}
	if plug.state("0") {
		t.Fatal("Set(off) left the outlet on")
	}

	// Gen2 must never have been probed for the Gen1 endpoint: a fallback that
	// fires on a working device would double every call against the whole rack.
	for _, path := range plug.requests {
		if strings.HasPrefix(path, "/relay/") {
			t.Fatalf("Gen2 device was probed for the Gen1 endpoint %q", path)
		}
	}
}

func TestShellyFallsBackToGen1(t *testing.T) {
	plug := &gen1Plug{on: map[string]bool{"0": false}}
	s, outlet := shellyAgainst(t, plug.handler())

	got, err := s.State(context.Background(), outlet)
	if err != nil {
		t.Fatalf("State: %v", err)
	}
	if got != StateOff {
		t.Fatalf("State = %q, want %q", got, StateOff)
	}

	if err := s.Set(context.Background(), outlet, true); err != nil {
		t.Fatalf("Set(on): %v", err)
	}
	plug.mu.Lock()
	on := plug.on["0"]
	plug.mu.Unlock()
	if !on {
		t.Fatal("Set(on) did not switch the Gen1 relay on")
	}
}

// A 404 means "this firmware does not have this endpoint" and drives the
// generation probe. Every other non-2xx has to surface: read as a
// wrong-generation guess, a 500 from a faulted device would be retried against
// the other endpoint and reported as "not a switch", pointing whoever reads the
// condition at the wrong problem entirely.
func TestShellyNon404ErrorsAreNotTreatedAsWrongGeneration(t *testing.T) {
	var paths []string
	s, outlet := shellyAgainst(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		paths = append(paths, r.URL.Path)
		http.Error(w, "overtemperature", http.StatusInternalServerError)
	}))

	_, err := s.State(context.Background(), outlet)
	if err == nil {
		t.Fatal("State succeeded against a device returning 500")
	}
	if !strings.Contains(err.Error(), "overtemperature") {
		t.Fatalf("error lost the device's own message: %v", err)
	}
	if len(paths) != 1 {
		t.Fatalf("a 500 was retried against the other generation's endpoint: %v", paths)
	}
}

func TestShellyUnknownOutletIsAnError(t *testing.T) {
	plug := newGen2Plug(map[string]bool{"0": true})
	s, outlet := shellyAgainst(t, plug.handler())
	outlet.Outlet = "3"

	if _, err := s.State(context.Background(), outlet); err == nil {
		t.Fatal("State succeeded for a channel the device does not have")
	}
}

func TestShellyEmptyOutletMeansChannelZero(t *testing.T) {
	plug := newGen2Plug(map[string]bool{"0": true})
	s, outlet := shellyAgainst(t, plug.handler())
	outlet.Outlet = ""

	got, err := s.State(context.Background(), outlet)
	if err != nil {
		t.Fatalf("State: %v", err)
	}
	if got != StateOn {
		t.Fatalf("State = %q, want %q", got, StateOn)
	}
}

func TestOutletEndpointDefaultsToHTTPAndDropsPaths(t *testing.T) {
	for _, tc := range []struct {
		name, host, want string
	}{
		{"bare host", "192.168.0.50", "http://192.168.0.50/rpc/Switch.Set?id=0"},
		{"host and port", "192.168.0.50:8080", "http://192.168.0.50:8080/rpc/Switch.Set?id=0"},
		{"explicit https", "https://plug.rack.lan", "https://plug.rack.lan/rpc/Switch.Set?id=0"},
		// A path in the host field would otherwise build /foo/rpc/Switch.Set,
		// which 404s straight into the Gen1 fallback and reports the device as
		// "not a switch".
		{"path is discarded", "http://192.168.0.50/foo", "http://192.168.0.50/rpc/Switch.Set?id=0"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			o := Outlet{Host: tc.host}
			got, err := o.endpoint("/rpc/Switch.Set", map[string][]string{"id": {"0"}})
			if err != nil {
				t.Fatalf("endpoint: %v", err)
			}
			if got != tc.want {
				t.Fatalf("endpoint = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestOutletEndpointRejectsEmptyHost(t *testing.T) {
	if _, err := (Outlet{}).endpoint("/rpc/Switch.Set", nil); err == nil {
		t.Fatal("endpoint succeeded with no host")
	}
}

// digestServer is a conformant RFC 7616 server: it challenges, then recomputes
// the expected response from the credentials it holds and rejects anything
// else. That makes the assertion "our Authorization header is correct by the
// spec" rather than "our header matches what we thought we'd send".
type digestServer struct {
	realm, nonce, user, pass, algorithm string
	handler                             http.Handler
	challenges                          int
}

func (d *digestServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	auth := r.Header.Get("Authorization")
	if !strings.HasPrefix(auth, "Digest ") {
		d.challenges++
		w.Header().Set("WWW-Authenticate", fmt.Sprintf(
			`Digest qop="auth", realm="%s", nonce="%s", algorithm=%s`,
			d.realm, d.nonce, d.algorithm))
		w.WriteHeader(http.StatusUnauthorized)
		return
	}

	_, params := parseChallenge(auth)
	hash := func(s string) string {
		sum := sha256.Sum256([]byte(s))
		return hex.EncodeToString(sum[:])
	}
	ha1 := hash(d.user + ":" + d.realm + ":" + d.pass)
	ha2 := hash(r.Method + ":" + r.URL.RequestURI())
	want := hash(strings.Join([]string{
		ha1, d.nonce, params["nc"], params["cnonce"], params["qop"], ha2,
	}, ":"))

	if params["username"] != d.user || params["nonce"] != d.nonce || params["response"] != want {
		http.Error(w, "bad digest", http.StatusUnauthorized)
		return
	}
	d.handler.ServeHTTP(w, r)
}

func TestShellyAnswersDigestChallenge(t *testing.T) {
	plug := newGen2Plug(map[string]bool{"0": true})
	server := &digestServer{
		realm: "shellyplus1-a8032ab1", nonce: "6f1cbe0d",
		user: "admin", pass: "hunter2", algorithm: "SHA-256",
		handler: plug.handler(),
	}
	s, outlet := shellyAgainst(t, server)
	// Only a password, no username: Shelly Gen2 fixes the account at `admin`
	// and its UI never asks for one, so this is the shape a 1Password item
	// naturally has.
	outlet.Password = "hunter2"

	got, err := s.State(context.Background(), outlet)
	if err != nil {
		t.Fatalf("State against a digest-protected plug: %v", err)
	}
	if got != StateOn {
		t.Fatalf("State = %q, want %q", got, StateOn)
	}
	if server.challenges != 1 {
		t.Fatalf("expected exactly one challenge round trip, got %d", server.challenges)
	}
}

func TestShellyAnswersBasicChallenge(t *testing.T) {
	plug := newGen2Plug(map[string]bool{"0": true})
	s, outlet := shellyAgainst(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, pass, ok := r.BasicAuth()
		if !ok || user != "admin" || pass != "hunter2" {
			w.Header().Set("WWW-Authenticate", `Basic realm="shelly"`)
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		plug.handler().ServeHTTP(w, r)
	}))
	outlet.Username = "admin"
	outlet.Password = "hunter2"

	if _, err := s.State(context.Background(), outlet); err != nil {
		t.Fatalf("State against a basic-auth plug: %v", err)
	}
}

// A 401 with no credentials configured must surface as an authentication
// error, not as a wrong-generation probe. Otherwise the operator's condition
// says "not a switch" when the truth is "someone set a password on the plug".
func TestShellyUnauthenticatedAgainstProtectedPlugErrors(t *testing.T) {
	s, outlet := shellyAgainst(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("WWW-Authenticate", `Digest qop="auth", realm="shelly", nonce="abc", algorithm=SHA-256`)
		http.Error(w, "unauthorized", http.StatusUnauthorized)
	}))

	_, err := s.State(context.Background(), outlet)
	if err == nil {
		t.Fatal("State succeeded against a plug that demanded credentials")
	}
	if strings.Contains(err.Error(), "not a switch") {
		t.Fatalf("401 was misreported as a missing endpoint: %v", err)
	}
}

func TestParseChallengeKeepsCommasInsideQuotedValues(t *testing.T) {
	scheme, params := parseChallenge(`Digest realm="rack, row 3", nonce="abc,def", algorithm=SHA-256, qop="auth"`)
	if scheme != "Digest" {
		t.Fatalf("scheme = %q", scheme)
	}
	for key, want := range map[string]string{
		"realm":     "rack, row 3",
		"nonce":     "abc,def",
		"algorithm": "SHA-256",
		"qop":       "auth",
	} {
		if params[key] != want {
			t.Errorf("params[%q] = %q, want %q", key, params[key], want)
		}
	}
}

func TestDigestRejectsUnsupportedAlgorithm(t *testing.T) {
	_, err := digestAuthorization(http.MethodGet, "/rpc/Switch.GetStatus", "admin", "pw",
		map[string]string{"nonce": "abc", "algorithm": "SHA-512-256"})
	if err == nil {
		t.Fatal("built a digest response for an algorithm we cannot compute; it would fail auth a round trip later with a worse error")
	}
}

func TestDigestRequiresNonce(t *testing.T) {
	_, err := digestAuthorization(http.MethodGet, "/x", "admin", "pw", map[string]string{"algorithm": "SHA-256"})
	if err == nil {
		t.Fatal("built a digest response with no nonce")
	}
}

func TestCyclePowersOffThenOn(t *testing.T) {
	plug := newGen2Plug(map[string]bool{"0": true})
	s, outlet := shellyAgainst(t, plug.handler())

	if err := Cycle(context.Background(), s, outlet, time.Millisecond); err != nil {
		t.Fatalf("Cycle: %v", err)
	}
	if !plug.state("0") {
		t.Fatal("Cycle left the outlet off")
	}

	var sets []string
	plug.mu.Lock()
	for _, p := range plug.requests {
		if p == "/rpc/Switch.Set" {
			sets = append(sets, p)
		}
	}
	plug.mu.Unlock()
	if len(sets) != 2 {
		t.Fatalf("Cycle issued %d Switch.Set calls, want 2 (off then on)", len(sets))
	}
}

// A cycle that could not actually cut power must fail loudly. Reporting success
// would have the caller wait out a boot that never happened and record the
// recovery as attempted, so the escalation ladder advances a rung on a host
// nothing was done to.
func TestCycleFailsWhenTheOutletDoesNotGoOff(t *testing.T) {
	stuck := &stuckOnDriver{}
	err := Cycle(context.Background(), stuck, Outlet{Host: "plug", Outlet: "0"}, time.Millisecond)
	if err == nil {
		t.Fatal("Cycle reported success against an outlet that never powered off")
	}
	if !strings.Contains(err.Error(), "did not power off") {
		t.Fatalf("error does not name the cause: %v", err)
	}
	if stuck.poweredOn {
		t.Fatal("Cycle powered the outlet back on after failing to cut it; the failure would be invisible")
	}
}

// stuckOnDriver accepts a Set but never changes state: a relay welded shut, or
// an outlet whose Set silently targets the wrong channel.
type stuckOnDriver struct{ poweredOn bool }

func (d *stuckOnDriver) State(context.Context, Outlet) (State, error) { return StateOn, nil }
func (d *stuckOnDriver) Set(_ context.Context, _ Outlet, on bool) error {
	if on {
		d.poweredOn = true
	}
	return nil
}

func TestRegistryResolvesShellyAndDefaultsToIt(t *testing.T) {
	r := NewRegistry()
	for _, name := range []string{DriverShelly, ""} {
		d, err := r.Get(name)
		if err != nil {
			t.Fatalf("Get(%q): %v", name, err)
		}
		if _, ok := d.(*Shelly); !ok {
			t.Fatalf("Get(%q) returned %T, want *Shelly", name, d)
		}
	}
	if _, err := r.Get("apc-snmp"); err == nil {
		t.Fatal("Get resolved a driver this build does not have")
	}
}
