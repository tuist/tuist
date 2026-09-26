package power

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// DriverEaton speaks to Eaton Rack PDU G4 network cards.
const DriverEaton = "eaton"

// eatonAPI is the root of the G4 REST API. Older card firmware serves the same
// resources under /rest/mbdetnrs/1.0.
const eatonAPI = "/rest/mbdetnrs/2.0"

// eatonDistribution is the PDU's power distribution: a G4 has one.
const eatonDistribution = "1"

const (
	defaultEatonTimeout       = 15 * time.Second
	defaultEatonSettleTimeout = 10 * time.Second
	defaultEatonPollInterval  = 500 * time.Millisecond
)

// ErrEatonConcurrentSession is returned when the card refuses a login because
// another session holds the account.
var ErrEatonConcurrentSession = errors.New("the PDU account already has a session open (the card allows one per user); another client holds it, such as a person in the web UI signed in with the same account, or an operator that exited without logging out, whose session lapses after an hour idle. Give the controller a PDU account of its own")

// Eaton drives the switched outlets of an Eaton Rack PDU G4 (network card
// GNM) over its REST API, always over HTTPS unless Host names http.
//
// The card allows one session per user. Each endpoint therefore has one bearer
// token that every call reuses, calls to one endpoint are serialised, and the
// token is only replaced when the card rejects it. The controller's account is
// its own: a person signed in to the web UI with it would hold its session.
//
// Outlet ids are 1-based integers, as the card numbers them.
type Eaton struct {
	// Timeout bounds each request. Zero means 15 seconds.
	Timeout time.Duration
	// SettleTimeout bounds how long Set waits for the outlet to read the state
	// it was switched to. Zero means 10 seconds.
	SettleTimeout time.Duration
	// PollInterval is how often Set reads the outlet while it waits. Zero
	// means 500 milliseconds.
	PollInterval time.Duration

	mu        sync.Mutex
	endpoints map[string]*eatonEndpoint
}

// eatonEndpoint is one card: its session and the client that reaches it.
type eatonEndpoint struct {
	mu sync.Mutex
	// config is what the session and client were made for; a change drops
	// both.
	config  eatonConfig
	client  *http.Client
	token   string
	session string
}

type eatonConfig struct {
	base        string
	fingerprint string
	username    string
	password    string
}

type eatonOutlet struct {
	Status struct {
		SwitchedOn           *bool    `json:"switchedOn"`
		DelayBeforeSwitchOn  *float64 `json:"delayBeforeSwitchOn"`
		DelayBeforeSwitchOff *float64 `json:"delayBeforeSwitchOff"`
	} `json:"status"`
	Specifications struct {
		Switchable *bool `json:"switchable"`
	} `json:"specifications"`
}

func (s eatonOutlet) pending() bool {
	for _, d := range []*float64{s.Status.DelayBeforeSwitchOn, s.Status.DelayBeforeSwitchOff} {
		if d != nil && *d >= 0 {
			return true
		}
	}
	return false
}

// State implements Driver.
func (e *Eaton) State(ctx context.Context, o Outlet) (State, error) {
	outlet, err := e.read(ctx, o)
	if err != nil {
		return StateUnknown, err
	}
	return stateOf(*outlet.Status.SwitchedOn), nil
}

// Set implements Driver. It returns once the outlet reads the requested state.
func (e *Eaton) Set(ctx context.Context, o Outlet, on bool) error {
	number, err := eatonOutletNumber(o)
	if err != nil {
		return err
	}
	outlet, err := e.read(ctx, o)
	if err != nil {
		return err
	}
	if s := outlet.Specifications.Switchable; s != nil && !*s {
		return fmt.Errorf("%s is not switchable", o)
	}
	if *outlet.Status.SwitchedOn == on && !outlet.pending() {
		return nil
	}

	action := "switchOff"
	if on {
		action = "switchOn"
	}
	path := fmt.Sprintf("%s/actions/%s", eatonOutletPath(number), action)
	if err := e.call(ctx, o, http.MethodPost, path, nil); err != nil {
		return err
	}

	settle := e.SettleTimeout
	if settle <= 0 {
		settle = defaultEatonSettleTimeout
	}
	interval := e.PollInterval
	if interval <= 0 {
		interval = defaultEatonPollInterval
	}
	deadline := time.Now().Add(settle)
	for {
		outlet, err := e.read(ctx, o)
		if err != nil {
			return err
		}
		if *outlet.Status.SwitchedOn == on {
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("%s accepted %s but still reads %s after %s", o, action, stateOf(*outlet.Status.SwitchedOn), settle)
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("wait for %s to %s: %w", o, action, ctx.Err())
		case <-time.After(interval):
		}
	}
}

// Close logs out of every open session, so a restarted operator is not
// refused a login by its predecessor's session.
func (e *Eaton) Close(ctx context.Context) error {
	e.mu.Lock()
	endpoints := make([]*eatonEndpoint, 0, len(e.endpoints))
	for _, ep := range e.endpoints {
		endpoints = append(endpoints, ep)
	}
	e.mu.Unlock()

	var errs []error
	for _, ep := range endpoints {
		ep.mu.Lock()
		errs = append(errs, ep.logout(ctx))
		ep.mu.Unlock()
	}
	return errors.Join(errs...)
}

func (e *Eaton) read(ctx context.Context, o Outlet) (eatonOutlet, error) {
	var outlet eatonOutlet
	number, err := eatonOutletNumber(o)
	if err != nil {
		return outlet, err
	}
	if err := e.call(ctx, o, http.MethodGet, eatonOutletPath(number), &outlet); err != nil {
		return outlet, err
	}
	if outlet.Status.SwitchedOn == nil {
		return outlet, fmt.Errorf("%s: the card's answer has no status.switchedOn", o)
	}
	return outlet, nil
}

// call sends one authenticated request to the outlet's card, logging in when
// there is no session and once more when the card rejects the token.
func (e *Eaton) call(ctx context.Context, o Outlet, method, path string, out any) error {
	config, key, err := e.config(o)
	if err != nil {
		return err
	}
	ep := e.endpoint(key)
	ep.mu.Lock()
	defer ep.mu.Unlock()

	if err := ep.configure(ctx, config, e.timeout()); err != nil {
		return err
	}

	for attempt := 0; ; attempt++ {
		if ep.token == "" {
			if err := ep.login(ctx); err != nil {
				return fmt.Errorf("%s: %w", o, err)
			}
		}
		status, body, err := ep.do(ctx, method, eatonAPI+path, nil)
		if err != nil {
			return fmt.Errorf("%s: %w", o, err)
		}
		if attempt == 0 && eatonSessionRejected(status, body) {
			ep.token, ep.session = "", ""
			continue
		}
		if status < 200 || status > 299 {
			return fmt.Errorf("%s: %s %s: %d: %s", o, method, path, status, strings.TrimSpace(string(body)))
		}
		if out == nil {
			return nil
		}
		if err := json.Unmarshal(body, out); err != nil {
			return fmt.Errorf("%s: decode %s: %w", o, path, err)
		}
		return nil
	}
}

func (e *Eaton) timeout() time.Duration {
	if e.Timeout > 0 {
		return e.Timeout
	}
	return defaultEatonTimeout
}

func (e *Eaton) endpoint(key string) *eatonEndpoint {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.endpoints == nil {
		e.endpoints = map[string]*eatonEndpoint{}
	}
	ep, ok := e.endpoints[key]
	if !ok {
		ep = &eatonEndpoint{}
		e.endpoints[key] = ep
	}
	return ep
}

// config resolves what an outlet's card is reached with, and the key its
// session is held under: the card's own origin, whatever it is dialled through.
func (e *Eaton) config(o Outlet) (eatonConfig, string, error) {
	origin, err := o.origin("https")
	if err != nil {
		return eatonConfig{}, "", err
	}
	base, err := o.endpointWithScheme("https", "", nil)
	if err != nil {
		return eatonConfig{}, "", err
	}
	config := eatonConfig{base: base, username: o.Username, password: o.Password}
	switch origin.Scheme {
	case "https":
		if strings.TrimSpace(o.TLSFingerprint) == "" {
			return eatonConfig{}, "", fmt.Errorf("%s: HTTPS to the card needs its certificate's SHA-256 fingerprint in the credentials Secret's tlsFingerprint key; read it with: openssl s_client -connect %s:443 </dev/null | openssl x509 -noout -fingerprint -sha256", o, origin.Hostname())
		}
		fingerprint, err := ParseTLSFingerprint(o.TLSFingerprint)
		if err != nil {
			return eatonConfig{}, "", fmt.Errorf("%s: %w", o, err)
		}
		config.fingerprint = hex.EncodeToString(fingerprint)
	case "http":
	default:
		return eatonConfig{}, "", fmt.Errorf("%s: unsupported scheme %q", o, origin.Scheme)
	}
	if o.Username == "" || o.Password == "" {
		return eatonConfig{}, "", fmt.Errorf("%s: the card needs a username and password in the credentials Secret", o)
	}
	return config, origin.String(), nil
}

// configure makes the client for config, logging out of a session made for a
// different one first.
func (ep *eatonEndpoint) configure(ctx context.Context, config eatonConfig, timeout time.Duration) error {
	if ep.client != nil && ep.config == config {
		return nil
	}
	if ep.client != nil {
		_ = ep.logout(ctx)
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	if config.fingerprint != "" {
		want, err := hex.DecodeString(config.fingerprint)
		if err != nil {
			return err
		}
		transport.TLSClientConfig = &tls.Config{
			MinVersion: tls.VersionTLS12,
			// The card's certificate is self-signed and names no address it is
			// dialled by, so it is verified by its pinned fingerprint instead.
			InsecureSkipVerify: true, //nolint:gosec // VerifyConnection pins the leaf certificate.
			VerifyConnection: func(cs tls.ConnectionState) error {
				if len(cs.PeerCertificates) == 0 {
					return fmt.Errorf("the card presented no certificate")
				}
				got := sha256.Sum256(cs.PeerCertificates[0].Raw)
				if !bytes.Equal(got[:], want) {
					return fmt.Errorf("the card's certificate has SHA-256 fingerprint %s, not the pinned %s", formatFingerprint(got[:]), formatFingerprint(want))
				}
				return nil
			},
		}
	}
	ep.config = config
	ep.client = &http.Client{Timeout: timeout, Transport: transport}
	ep.token, ep.session = "", ""
	return nil
}

func (ep *eatonEndpoint) login(ctx context.Context) error {
	body, err := json.Marshal(map[string]string{
		"username":   ep.config.username,
		"password":   ep.config.password,
		"grant_type": "password",
		"scope":      "GUIAccess",
	})
	if err != nil {
		return err
	}
	status, answer, err := ep.do(ctx, http.MethodPost, eatonAPI+"/oauth2/token/", body)
	if err != nil {
		return fmt.Errorf("log in: %w", err)
	}
	switch {
	case status == http.StatusForbidden && eatonCode(answer, "ConcurentSession", "ConcurrentSession"):
		return ErrEatonConcurrentSession
	case status == http.StatusForbidden && eatonCode(answer, "ExpiredCredentials"):
		return fmt.Errorf("log in: the PDU account's password has expired; set a new one on the card and in the credentials Secret")
	case status == http.StatusForbidden && eatonCode(answer, "AccountBlocked"):
		return fmt.Errorf("log in: the PDU account is blocked; unblock it on the card")
	case status == http.StatusUnauthorized:
		return fmt.Errorf("log in: the card refused the username and password: %s", strings.TrimSpace(string(answer)))
	case status < 200 || status > 299:
		return fmt.Errorf("log in: %d: %s", status, strings.TrimSpace(string(answer)))
	}
	var token struct {
		AccessToken string `json:"access_token"`
		Session     string `json:"session"`
	}
	if err := json.Unmarshal(answer, &token); err != nil {
		return fmt.Errorf("log in: decode token: %w", err)
	}
	if token.AccessToken == "" {
		return fmt.Errorf("log in: the card answered without an access token")
	}
	ep.token, ep.session = token.AccessToken, token.Session
	return nil
}

func (ep *eatonEndpoint) logout(ctx context.Context) error {
	if ep.token == "" || ep.client == nil {
		return nil
	}
	session := ep.session
	defer func() { ep.token, ep.session = "", "" }()
	if session == "" {
		return nil
	}
	if !strings.HasPrefix(session, "/rest/") {
		session = "/rest" + session
	}
	status, body, err := ep.do(ctx, http.MethodDelete, session, nil)
	if err != nil {
		return fmt.Errorf("log out of %s: %w", ep.config.base, err)
	}
	if status < 200 || status > 299 {
		return fmt.Errorf("log out of %s: %d: %s", ep.config.base, status, strings.TrimSpace(string(body)))
	}
	return nil
}

// do sends one request with the session's token, when there is one.
func (ep *eatonEndpoint) do(ctx context.Context, method, path string, body []byte) (int, []byte, error) {
	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, ep.config.base+path, reader)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if ep.token != "" {
		req.Header.Set("Authorization", "Bearer "+ep.token)
	}
	resp, err := ep.client.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	answer, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return 0, nil, fmt.Errorf("read %s %s: %w", method, path, err)
	}
	return resp.StatusCode, answer, nil
}

// eatonSessionRejected reports a token the card no longer accepts.
func eatonSessionRejected(status int, body []byte) bool {
	return status == http.StatusUnauthorized ||
		(status == http.StatusForbidden && eatonCode(body, "ExpiredCredentials", "InvalidToken", "ExpiredToken"))
}

func eatonCode(body []byte, codes ...string) bool {
	for _, code := range codes {
		if bytes.Contains(body, []byte(code)) {
			return true
		}
	}
	return false
}

func eatonOutletNumber(o Outlet) (int, error) {
	n, err := strconv.Atoi(strings.TrimSpace(o.Outlet))
	if err != nil || n < 1 {
		return 0, fmt.Errorf("%s: an Eaton outlet is its 1-based number on the PDU, not %q", o, o.Outlet)
	}
	return n, nil
}

func eatonOutletPath(n int) string {
	return fmt.Sprintf("/powerDistributions/%s/outlets/%d", eatonDistribution, n)
}

// ParseTLSFingerprint reads a SHA-256 certificate fingerprint written as hex,
// with or without colons, in either case, optionally as openssl prints it
// (`sha256 Fingerprint=AB:CD:...`).
func ParseTLSFingerprint(s string) ([]byte, error) {
	s = strings.TrimSpace(s)
	if i := strings.LastIndexByte(s, '='); i >= 0 {
		s = s[i+1:]
	}
	s = strings.NewReplacer(":", "", " ", "", "\n", "", "\t", "").Replace(s)
	b, err := hex.DecodeString(strings.ToLower(s))
	if err != nil || len(b) != sha256.Size {
		return nil, fmt.Errorf("tlsFingerprint is not a SHA-256 fingerprint (64 hex digits, colons allowed)")
	}
	return b, nil
}

func formatFingerprint(b []byte) string {
	parts := make([]string, len(b))
	for i, c := range b {
		parts[i] = fmt.Sprintf("%02X", c)
	}
	return strings.Join(parts, ":")
}
