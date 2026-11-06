package power

import (
	"context"
	"encoding/hex"
	"errors"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power/eatontest"
)

const (
	testUser     = "tuist-controller"
	testPassword = "Hunter2-hunter2"
)

// eatonAgainst starts a card on which the controller's account exists and is
// ready, and returns a driver and an outlet on it.
func eatonAgainst(t *testing.T, outlets int) (*eatontest.Card, *Eaton, Outlet) {
	t.Helper()
	card := eatontest.New(outlets)
	t.Cleanup(card.Close)
	card.AddAccount(testUser, testPassword, eatontest.ProfileOperators)
	e := &Eaton{SettleTimeout: 2 * time.Second, PollInterval: time.Millisecond}
	return card, e, Outlet{
		Driver:         DriverEaton,
		Host:           card.URL(),
		Outlet:         "1",
		Username:       testUser,
		Password:       testPassword,
		TLSFingerprint: card.Fingerprint(),
	}
}

func logins(card *eatontest.Card) int {
	card.Mu.Lock()
	defer card.Mu.Unlock()
	return len(card.Logins)
}

func actions(card *eatontest.Card) []string {
	card.Mu.Lock()
	defer card.Mu.Unlock()
	return append([]string(nil), card.Actions...)
}

func TestEatonReadsAndSwitchesOnOneSession(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 2)

	got, err := e.State(context.Background(), outlet)
	if err != nil || got != StateOn {
		t.Fatalf("State = %q, %v; want On", got, err)
	}
	if err := e.Set(context.Background(), outlet, false); err != nil {
		t.Fatalf("Set(off): %v", err)
	}
	got, err = e.State(context.Background(), outlet)
	if err != nil || got != StateOff {
		t.Fatalf("State after Set(off) = %q, %v; want Off", got, err)
	}
	if n := logins(card); n != 1 {
		t.Fatalf("logged in %d times, want 1: the card allows one session per user", n)
	}
	if got := strings.Join(actions(card), ","); got != "1/switchOff" {
		t.Fatalf("actions = %s, want 1/switchOff", got)
	}
}

func TestEatonSetIsIdempotent(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	if err := e.Set(context.Background(), outlet, true); err != nil {
		t.Fatalf("Set(on) on an outlet already on: %v", err)
	}
	if got := actions(card); len(got) != 0 {
		t.Fatalf("switched an outlet already in the requested state: %v", got)
	}
}

func TestEatonSetWaitsForTheOutletToSwitch(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	card.SwitchLag = 3
	if err := Cycle(context.Background(), e, outlet, time.Millisecond); err != nil {
		t.Fatalf("Cycle against an outlet that reports its switch late: %v", err)
	}
}

func TestEatonSetFailsWhenTheOutletNeverSwitches(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	e.SettleTimeout = 20 * time.Millisecond
	card.SwitchLag = 1 << 20
	err := e.Set(context.Background(), outlet, false)
	if err == nil || !strings.Contains(err.Error(), "still reads") {
		t.Fatalf("Set against an outlet that never switches = %v", err)
	}
}

func TestEatonLogsInAgainWhenTheCardEndsTheSession(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State: %v", err)
	}
	card.Expire()
	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State after the session expired: %v", err)
	}
	if n := logins(card); n != 2 {
		t.Fatalf("logged in %d times, want 2", n)
	}
}

func TestEatonNamesAConcurrentSession(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	card.ForeignSessions[testUser] = true
	_, err := e.State(context.Background(), outlet)
	if !errors.Is(err, ErrEatonConcurrentSession) {
		t.Fatalf("State with the account's session held elsewhere = %v, want ErrEatonConcurrentSession", err)
	}
	if !strings.Contains(err.Error(), "web UI") || !strings.Contains(err.Error(), "account of its own") {
		t.Fatalf("error does not say who holds the session or what to do: %v", err)
	}
}

func TestEatonRefusesWrongCredentials(t *testing.T) {
	_, e, outlet := eatonAgainst(t, 1)
	outlet.Password = "Wrong-password1"
	_, err := e.State(context.Background(), outlet)
	var refused *EatonLoginError
	if !errors.As(err, &refused) || !refused.Refused() || !strings.Contains(err.Error(), "InvalidCredential") {
		t.Fatalf("State with a wrong password = %v", err)
	}
}

// A new account must change its password at its first login, so a driver
// given the password it was created with changes it to the one it keeps.
func TestEatonChangesAnAccountsInitialPassword(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	card.Mu.Lock()
	a := card.Accounts["2"]
	a.Password, a.PasswordExpired = "Initial-pass1", true
	card.Mu.Unlock()
	outlet.InitialPassword = "Initial-pass1"

	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State with an account at its first login: %v", err)
	}
	if got := card.Account(testUser); got.Password != testPassword || got.PasswordExpired {
		t.Fatalf("account = %+v, want its password changed to the driver's", got)
	}
}

func TestEatonSerialisesCallsToOneCard(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 2)
	card.Delay = 2 * time.Millisecond
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
	if n := logins(card); n != 1 {
		t.Fatalf("logged in %d times, want 1", n)
	}
	card.Mu.Lock()
	defer card.Mu.Unlock()
	if card.MaxInFlight != 1 {
		t.Fatalf("%d requests reached the card at once, want 1", card.MaxInFlight)
	}
}

func TestEatonOutletIsAOneBasedNumber(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
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
	if n := logins(card); n != 0 {
		t.Fatal("logged in for an outlet id that cannot exist")
	}
}

func TestEatonRefusesToSwitchANonSwitchableOutlet(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	card.Outlets[1].Switchable = false
	err := e.Set(context.Background(), outlet, false)
	if err == nil || !strings.Contains(err.Error(), "not switchable") {
		t.Fatalf("Set on a non-switchable outlet = %v", err)
	}
	if got := actions(card); len(got) != 0 {
		t.Fatalf("sent %v to a non-switchable outlet", got)
	}
}

func TestEatonHTTPSNeedsAFingerprint(t *testing.T) {
	_, e, outlet := eatonAgainst(t, 1)
	outlet.TLSFingerprint = ""
	_, err := e.State(context.Background(), outlet)
	if err == nil || !strings.Contains(err.Error(), "openssl s_client -connect 127.0.0.1:443") {
		t.Fatalf("State without a fingerprint = %v, want the command that reads one", err)
	}
}

func TestEatonRefusesACertificateThatIsNotPinned(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	outlet.TLSFingerprint = strings.Repeat("ab", 32)
	_, err := e.State(context.Background(), outlet)
	if err == nil || !strings.Contains(err.Error(), "not the pinned") {
		t.Fatalf("State against an unpinned certificate = %v", err)
	}
	if n := logins(card); n != 0 {
		t.Fatal("sent credentials to a card whose certificate did not match the pin")
	}
}

func TestEatonDialsThroughDialAndKeepsTheSessionPerCard(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
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
	card.Mu.Lock()
	defer card.Mu.Unlock()
	if len(card.Logins) != 2 || card.Logouts != 1 {
		t.Fatalf("logins = %d, logouts = %d; want 2 and 1", len(card.Logins), card.Logouts)
	}
}

func TestEatonCloseLogsOut(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State: %v", err)
	}
	if err := NewRegistryWith(map[string]Driver{DriverEaton: e}).Close(context.Background()); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if n := card.OpenSessions(); n != 0 {
		t.Fatalf("%d sessions left open", n)
	}
	// A successor logs in without meeting its predecessor's session.
	if _, err := (&Eaton{}).State(context.Background(), outlet); err != nil {
		t.Fatalf("State from a new driver after Close: %v", err)
	}
}

func TestEatonHonoursTheContext(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 1)
	card.Delay = time.Second
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

func TestEatonReadsOutletSettingsAndIdentification(t *testing.T) {
	_, e, outlet := eatonAgainst(t, 3)
	outlets, err := e.OutletSettings(context.Background(), outlet)
	if err != nil {
		t.Fatalf("OutletSettings: %v", err)
	}
	if len(outlets) != 3 || outlets[2].Number != 3 || outlets[0].StateOnStartup != "last known state" {
		t.Fatalf("outlets = %+v", outlets)
	}
	id, err := e.Identification(context.Background(), outlet)
	if err != nil || id.Serial != "421G456777" || id.Firmware != "3.4.3" {
		t.Fatalf("Identification = %+v, %v", id, err)
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

func TestProbeTLSFingerprint(t *testing.T) {
	card, _, outlet := eatonAgainst(t, 1)
	got, err := ProbeTLSFingerprint(context.Background(), outlet, time.Second)
	if err != nil || got != card.Fingerprint() {
		t.Fatalf("ProbeTLSFingerprint = %q, %v; want %q", got, err, card.Fingerprint())
	}
	card.RotateCertificate()
	got, err = ProbeTLSFingerprint(context.Background(), outlet, time.Second)
	if err != nil || got != card.Fingerprint() || got == outlet.TLSFingerprint {
		t.Fatalf("after a new certificate ProbeTLSFingerprint = %q, %v", got, err)
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
