package power

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// The fake is written from Eaton's published Rack PDU G4 API (the Postman
// collection "Rack PDU G4" and the GNM user guide), not from captured traffic.

type fakeOutlet struct {
	on         bool
	switchable bool
	// lag is how many reads still report the state before the last switch.
	lag int
}

type fakeG4 struct {
	mu sync.Mutex

	username, password string
	outlets            map[int]*fakeOutlet

	token, session string
	// foreignSession is a session some other client holds on the account.
	foreignSession bool
	logins         int
	logouts        int
	actions        []string
	inFlight       int
	maxInFlight    int
	delay          time.Duration
	// switchLag is how many reads after a switch action still report the old
	// state.
	switchLag int
}

func newFakeG4(outlets map[int]*fakeOutlet) *fakeG4 {
	return &fakeG4{username: "tuist-controller", password: "hunter2", outlets: outlets}
}

func (f *fakeG4) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		f.inFlight++
		if f.inFlight > f.maxInFlight {
			f.maxInFlight = f.inFlight
		}
		delay := f.delay
		f.mu.Unlock()
		defer func() {
			f.mu.Lock()
			f.inFlight--
			f.mu.Unlock()
		}()
		if delay > 0 {
			select {
			case <-time.After(delay):
			case <-r.Context().Done():
				return
			}
		}

		f.mu.Lock()
		defer f.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")

		if r.URL.Path == "/rest/mbdetnrs/2.0/oauth2/token/" && r.Method == http.MethodPost {
			var body map[string]string
			_ = json.NewDecoder(r.Body).Decode(&body)
			if body["username"] != f.username || body["password"] != f.password || body["grant_type"] != "password" {
				w.WriteHeader(http.StatusUnauthorized)
				fmt.Fprint(w, `{"code":"InvalidCredential"}`)
				return
			}
			if f.foreignSession || f.token != "" {
				w.WriteHeader(http.StatusForbidden)
				fmt.Fprint(w, `{"code":"ConcurentSession"}`)
				return
			}
			f.logins++
			f.token = "token-" + strconv.Itoa(f.logins)
			f.session = "/mbdetnrs/2.0/sessionService/sessions/" + strconv.Itoa(f.logins)
			fmt.Fprintf(w, `{"token_type":"Bearer","access_token":%q,"session":%q}`, f.token, f.session)
			return
		}

		if f.token == "" || r.Header.Get("Authorization") != "Bearer "+f.token {
			w.WriteHeader(http.StatusUnauthorized)
			fmt.Fprint(w, `{"code":"InvalidCredential"}`)
			return
		}

		if r.Method == http.MethodDelete && r.URL.Path == "/rest"+f.session {
			f.token, f.session = "", ""
			f.logouts++
			return
		}

		rest, ok := strings.CutPrefix(r.URL.Path, "/rest/mbdetnrs/2.0/powerDistributions/1/outlets/")
		if !ok {
			http.NotFound(w, r)
			return
		}
		id, action, _ := strings.Cut(rest, "/actions/")
		n, _ := strconv.Atoi(id)
		outlet, known := f.outlets[n]
		if !known {
			http.NotFound(w, r)
			return
		}
		switch {
		case r.Method == http.MethodGet && action == "":
			on := outlet.on
			if outlet.lag > 0 {
				outlet.lag--
				on = !on
			}
			fmt.Fprintf(w, `{"id":"%d","status":{"switchedOn":%t,"delayBeforeSwitchOn":-1,"delayBeforeSwitchOff":-1},"specifications":{"switchable":%t}}`, n, on, outlet.switchable)
		case r.Method == http.MethodPost && (action == "switchOn" || action == "switchOff"):
			if !outlet.switchable {
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			f.actions = append(f.actions, fmt.Sprintf("%d/%s", n, action))
			outlet.on = action == "switchOn"
			outlet.lag = f.switchLag
		default:
			http.NotFound(w, r)
		}
	})
}

// expire ends the session on the card, as its lease or inactivity timeout does.
func (f *fakeG4) expire() {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.token, f.session = "", ""
}

func (f *fakeG4) snapshot() (logins, logouts int, actions []string, maxInFlight int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.logins, f.logouts, append([]string(nil), f.actions...), f.maxInFlight
}

func eatonAgainst(t *testing.T, fake *fakeG4) (*Eaton, Outlet) {
	t.Helper()
	srv := httptest.NewTLSServer(fake.handler())
	t.Cleanup(srv.Close)
	sum := sha256.Sum256(srv.Certificate().Raw)
	e := &Eaton{SettleTimeout: 2 * time.Second, PollInterval: time.Millisecond}
	return e, Outlet{
		Driver:         DriverEaton,
		Host:           srv.URL,
		Outlet:         "1",
		Username:       fake.username,
		Password:       fake.password,
		TLSFingerprint: formatFingerprint(sum[:]),
	}
}

func TestEatonReadsAndSwitchesOnOneSession(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	e, outlet := eatonAgainst(t, fake)

	got, err := e.State(context.Background(), outlet)
	if err != nil {
		t.Fatalf("State: %v", err)
	}
	if got != StateOn {
		t.Fatalf("State = %q, want %q", got, StateOn)
	}
	if err := e.Set(context.Background(), outlet, false); err != nil {
		t.Fatalf("Set(off): %v", err)
	}
	got, err = e.State(context.Background(), outlet)
	if err != nil || got != StateOff {
		t.Fatalf("State after Set(off) = %q, %v; want Off", got, err)
	}

	logins, _, actions, _ := fake.snapshot()
	if logins != 1 {
		t.Fatalf("logged in %d times, want 1: the card allows one session per user", logins)
	}
	if strings.Join(actions, ",") != "1/switchOff" {
		t.Fatalf("actions = %v, want [1/switchOff]", actions)
	}
}

func TestEatonSetIsIdempotent(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	e, outlet := eatonAgainst(t, fake)

	if err := e.Set(context.Background(), outlet, true); err != nil {
		t.Fatalf("Set(on) on an outlet already on: %v", err)
	}
	if _, _, actions, _ := fake.snapshot(); len(actions) != 0 {
		t.Fatalf("switched an outlet already in the requested state: %v", actions)
	}
}

func TestEatonSetWaitsForTheOutletToSwitch(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	fake.switchLag = 3
	e, outlet := eatonAgainst(t, fake)
	if err := Cycle(context.Background(), e, outlet, time.Millisecond); err != nil {
		t.Fatalf("Cycle against an outlet that reports its switch late: %v", err)
	}
}

func TestEatonSetFailsWhenTheOutletNeverSwitches(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	e, outlet := eatonAgainst(t, fake)
	e.SettleTimeout = 20 * time.Millisecond
	fake.switchLag = 1 << 20

	err := e.Set(context.Background(), outlet, false)
	if err == nil || !strings.Contains(err.Error(), "still reads") {
		t.Fatalf("Set against an outlet that never switches = %v, want a timeout naming its state", err)
	}
}

func TestEatonLogsInAgainWhenTheCardEndsTheSession(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	e, outlet := eatonAgainst(t, fake)

	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State: %v", err)
	}
	fake.expire()
	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State after the session expired: %v", err)
	}
	if logins, _, _, _ := fake.snapshot(); logins != 2 {
		t.Fatalf("logged in %d times, want 2", logins)
	}
}

func TestEatonNamesAConcurrentSession(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	fake.foreignSession = true
	e, outlet := eatonAgainst(t, fake)

	_, err := e.State(context.Background(), outlet)
	if !errors.Is(err, ErrEatonConcurrentSession) {
		t.Fatalf("State with the account's session held elsewhere = %v, want ErrEatonConcurrentSession", err)
	}
	if !strings.Contains(err.Error(), "web UI") || !strings.Contains(err.Error(), "account of its own") {
		t.Fatalf("error does not say who holds the session or what to do: %v", err)
	}
}

func TestEatonRefusesWrongCredentials(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	e, outlet := eatonAgainst(t, fake)
	outlet.Password = "wrong"

	_, err := e.State(context.Background(), outlet)
	if err == nil || !strings.Contains(err.Error(), "refused the username and password") {
		t.Fatalf("State with a wrong password = %v", err)
	}
}

func TestEatonSerialisesCallsToOneCard(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}, 2: {on: false, switchable: true}})
	fake.delay = 2 * time.Millisecond
	e, outlet := eatonAgainst(t, fake)

	var wg sync.WaitGroup
	errs := make(chan error, 20)
	for i := range 20 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			o := outlet
			o.Outlet = strconv.Itoa(1 + i%2)
			if _, err := e.State(context.Background(), o); err != nil {
				errs <- err
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatalf("concurrent State: %v", err)
	}
	logins, _, _, maxInFlight := fake.snapshot()
	if logins != 1 {
		t.Fatalf("logged in %d times, want 1", logins)
	}
	if maxInFlight != 1 {
		t.Fatalf("%d requests reached the card at once, want 1", maxInFlight)
	}
}

func TestEatonOutletIsAOneBasedNumber(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	e, outlet := eatonAgainst(t, fake)
	for _, id := range []string{"0", "", "-1", "A1", "outlet1"} {
		outlet.Outlet = id
		_, err := e.State(context.Background(), outlet)
		if err == nil || !strings.Contains(err.Error(), "1-based") {
			t.Fatalf("State(outlet %q) = %v, want an error naming 1-based outlet numbers", id, err)
		}
		if err := e.Set(context.Background(), outlet, true); err == nil {
			t.Fatalf("Set(outlet %q) succeeded", id)
		}
	}
	if logins, _, _, _ := fake.snapshot(); logins != 0 {
		t.Fatalf("logged in for an outlet id that cannot exist")
	}
}

func TestEatonRefusesToSwitchANonSwitchableOutlet(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: false}})
	e, outlet := eatonAgainst(t, fake)

	err := e.Set(context.Background(), outlet, false)
	if err == nil || !strings.Contains(err.Error(), "not switchable") {
		t.Fatalf("Set on a non-switchable outlet = %v", err)
	}
	if _, _, actions, _ := fake.snapshot(); len(actions) != 0 {
		t.Fatalf("sent %v to a non-switchable outlet", actions)
	}
}

func TestEatonHTTPSNeedsAFingerprint(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	e, outlet := eatonAgainst(t, fake)
	outlet.TLSFingerprint = ""

	_, err := e.State(context.Background(), outlet)
	if err == nil || !strings.Contains(err.Error(), "openssl s_client -connect 127.0.0.1:443") {
		t.Fatalf("State without a fingerprint = %v, want the command that reads one", err)
	}
}

func TestEatonRefusesACertificateThatIsNotPinned(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	e, outlet := eatonAgainst(t, fake)
	outlet.TLSFingerprint = strings.Repeat("ab", 32)

	_, err := e.State(context.Background(), outlet)
	if err == nil || !strings.Contains(err.Error(), "not the pinned") {
		t.Fatalf("State against an unpinned certificate = %v", err)
	}
	if logins, _, _, _ := fake.snapshot(); logins != 0 {
		t.Fatal("sent credentials to a card whose certificate did not match the pin")
	}
}

func TestEatonDialsThroughDialAndKeepsTheSessionPerCard(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	e, outlet := eatonAgainst(t, fake)
	u, err := url.Parse(outlet.Host)
	if err != nil {
		t.Fatal(err)
	}
	outlet.Host = "https://pdu.rack.invalid:" + u.Port()
	outlet.Dial = "127.0.0.1"

	if got, err := e.State(context.Background(), outlet); err != nil || got != StateOn {
		t.Fatalf("State through Dial = %q, %v", got, err)
	}

	// Moving the dial logs the old session out before opening another, or
	// the card would refuse the new login.
	outlet.Dial = "localhost"
	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State after the dial moved: %v", err)
	}
	logins, logouts, _, _ := fake.snapshot()
	if logins != 2 || logouts != 1 {
		t.Fatalf("logins = %d, logouts = %d; want 2 and 1", logins, logouts)
	}
}

func TestEatonCloseLogsOut(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	e, outlet := eatonAgainst(t, fake)
	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State: %v", err)
	}
	r := NewRegistryWith(map[string]Driver{DriverEaton: e})
	if err := r.Close(context.Background()); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if _, logouts, _, _ := fake.snapshot(); logouts != 1 {
		t.Fatalf("logouts = %d, want 1", logouts)
	}
	// A successor logs in without meeting its predecessor's session.
	if _, err := (&Eaton{}).State(context.Background(), outlet); err != nil {
		t.Fatalf("State from a new driver after Close: %v", err)
	}
}

func TestEatonHonoursTheContext(t *testing.T) {
	fake := newFakeG4(map[int]*fakeOutlet{1: {on: true, switchable: true}})
	fake.delay = time.Second
	e, outlet := eatonAgainst(t, fake)

	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	start := time.Now()
	if _, err := e.State(ctx, outlet); err == nil {
		t.Fatal("State outlived its context")
	}
	if elapsed := time.Since(start); elapsed > 500*time.Millisecond {
		t.Fatalf("State took %s against a 50ms deadline", elapsed)
	}
}

func TestEatonBareHostIsHTTPS(t *testing.T) {
	config, key, err := (&Eaton{}).config(Outlet{
		Host: "192.168.0.16", Outlet: "1", Username: "u", Password: "p",
		TLSFingerprint: strings.Repeat("AB:", 31) + "AB",
	})
	if err != nil {
		t.Fatalf("config: %v", err)
	}
	if config.base != "https://192.168.0.16" || key != "https://192.168.0.16" {
		t.Fatalf("base = %q, key = %q; want https://192.168.0.16", config.base, key)
	}
}

func TestParseTLSFingerprint(t *testing.T) {
	want := strings.Repeat("ab", 32)
	for _, in := range []string{
		want,
		strings.ToUpper(want),
		strings.TrimSuffix(strings.Repeat("AB:", 32), ":"),
		"sha256 Fingerprint=" + strings.TrimSuffix(strings.Repeat("AB:", 32), ":") + "\n",
	} {
		got, err := ParseTLSFingerprint(in)
		if err != nil || hex.EncodeToString(got) != want {
			t.Fatalf("ParseTLSFingerprint(%q) = %x, %v", in, got, err)
		}
	}
	for _, in := range []string{"", "abcd", strings.Repeat("zz", 32), strings.Repeat("ab", 20)} {
		if _, err := ParseTLSFingerprint(in); err == nil {
			t.Fatalf("ParseTLSFingerprint(%q) accepted a value that is not a SHA-256", in)
		}
	}
}

func TestRegistryResolvesEaton(t *testing.T) {
	d, err := NewRegistry().Get(DriverEaton)
	if err != nil {
		t.Fatalf("Get(eaton): %v", err)
	}
	if _, ok := d.(*Eaton); !ok {
		t.Fatalf("Get(eaton) returned %T", d)
	}
}
