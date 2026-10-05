package power

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
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
	// sessionPassword is the password the session was opened with, which the
	// reauthentication token is made from.
	sessionPassword string
}

type eatonConfig struct {
	base            string
	fingerprint     string
	username        string
	password        string
	initialPassword string
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
		return fmt.Errorf("%s: %w", o, err)
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
			return fmt.Errorf("%s: %w", o, &EatonHTTPError{Method: method, Path: path, Status: status, Body: strings.TrimSpace(string(body))})
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

// EatonHTTPError is a card answering a request with a status that is not a
// success, with the body it answered, verbatim.
type EatonHTTPError struct {
	Method string
	Path   string
	Status int
	Body   string
}

func (e *EatonHTTPError) Error() string {
	return fmt.Sprintf("%s %s: %d: %s", e.Method, e.Path, e.Status, e.Body)
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
	config := eatonConfig{base: base, username: o.Username, password: o.Password, initialPassword: o.InitialPassword}
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
	client, err := newEatonClient(config, timeout)
	if err != nil {
		return err
	}
	// The session opened under the old settings is logged out first, or the
	// card, which allows one session per account, refuses the next login. When
	// the card is the same and only the pin moved, the old client, pinned to
	// the certificate the card no longer presents, cannot open a connection,
	// so the new one ends it.
	var logoutErr error
	if ep.client != nil && ep.token != "" {
		logoutErr = ep.endSession(ctx, ep.client)
		if logoutErr != nil && config.base == ep.config.base {
			if err := ep.endSession(ctx, client); err == nil {
				logoutErr = nil
			}
		}
	}
	ep.config = config
	ep.client = client
	ep.token, ep.session = "", ""
	if logoutErr != nil {
		return fmt.Errorf("the session opened before the card's settings changed may still hold the account: %w", logoutErr)
	}
	return nil
}

func newEatonClient(config eatonConfig, timeout time.Duration) (*http.Client, error) {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	if config.fingerprint != "" {
		want, err := hex.DecodeString(config.fingerprint)
		if err != nil {
			return nil, err
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
	return &http.Client{Timeout: timeout, Transport: transport}, nil
}

// EatonLoginError is the card refusing a login, with its code (InvalidCredential,
// ExpiredCredentials, NotAuthorized, AccountBlocked, ConcurentSession) and the
// body it answered with, verbatim.
type EatonLoginError struct {
	Status int
	Code   string
	Body   string
}

func (e *EatonLoginError) Error() string {
	switch e.Code {
	case "ConcurentSession":
		return "log in: " + ErrEatonConcurrentSession.Error()
	case "ExpiredCredentials":
		return "log in: the account's password has expired: " + e.Body
	case "AccountBlocked":
		return "log in: the account is blocked: " + e.Body
	case "InvalidCredential":
		return "log in: the card refused the username and password: " + e.Body
	}
	return fmt.Sprintf("log in: %d: %s", e.Status, e.Body)
}

func (e *EatonLoginError) Is(target error) bool {
	return target == ErrEatonConcurrentSession && e.Code == "ConcurentSession"
}

// Refused reports a login the card refused for its password: a wrong one, or
// one it makes the account change first.
func (e *EatonLoginError) Refused() bool {
	return e.Status == http.StatusUnauthorized || e.Code == "ExpiredCredentials"
}

// NotServed reports an endpoint that does not serve the API's login at all,
// answering it as missing or with a page rather than JSON: a card of another
// kind, or one on firmware that serves another version of the API.
func (e *EatonLoginError) NotServed() bool {
	return e.Status == http.StatusNotFound || e.Status == http.StatusMethodNotAllowed ||
		(e.Code == "" && e.Body != "" && !json.Valid([]byte(e.Body)))
}

var eatonLoginCodes = []string{"ConcurentSession", "ExpiredCredentials", "AccountBlocked", "NotAuthorized", "InvalidCredential"}

// login opens the session with the account's password, or, when the card
// refuses it and the account has an initial password, with that one, changing
// it to the password as the card requires at an account's first login.
func (ep *eatonEndpoint) login(ctx context.Context) error {
	err := ep.authenticate(ctx, ep.config.password, "")
	var refused *EatonLoginError
	if err == nil || ep.config.initialPassword == "" || !errors.As(err, &refused) || !refused.Refused() {
		return err
	}
	if second := ep.authenticate(ctx, ep.config.initialPassword, ep.config.password); second != nil {
		return fmt.Errorf("%w; with the initial password: %v", err, second)
	}
	return nil
}

// authenticate asks the card for a token ("OAuth2/token"), setting a new
// password in the same request when newPassword is not empty ("OAuth2/change
// password"), which is how the card's forced password change is answered.
func (ep *eatonEndpoint) authenticate(ctx context.Context, password, newPassword string) error {
	request := map[string]string{"username": ep.config.username, "password": password}
	if newPassword != "" {
		request["newPassword"] = newPassword
	}
	body, err := json.Marshal(request)
	if err != nil {
		return err
	}
	status, answer, err := ep.doAuth(ctx, http.MethodPost, eatonAPI+"/oauth2/token/", body, "")
	if err != nil {
		return fmt.Errorf("log in: %w", err)
	}
	if status < 200 || status > 299 {
		refusal := &EatonLoginError{Status: status, Body: strings.TrimSpace(string(answer))}
		for _, code := range eatonLoginCodes {
			if eatonCode(answer, code) {
				refusal.Code = code
				break
			}
		}
		if refusal.Code == "" && eatonCode(answer, "ConcurrentSession") {
			refusal.Code = "ConcurentSession"
		}
		return refusal
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
	ep.token, ep.session, ep.sessionPassword = token.AccessToken, token.Session, password
	if newPassword != "" {
		ep.sessionPassword = newPassword
	}
	return nil
}

func (ep *eatonEndpoint) logout(ctx context.Context) error {
	if ep.token == "" || ep.client == nil {
		return nil
	}
	defer func() { ep.token, ep.session = "", "" }()
	return ep.endSession(ctx, ep.client)
}

// endSession deletes the session through client, keeping its token.
func (ep *eatonEndpoint) endSession(ctx context.Context, client *http.Client) error {
	session := ep.session
	if session == "" {
		return nil
	}
	if !strings.HasPrefix(session, "/rest/") {
		session = "/rest" + session
	}
	status, body, err := ep.send(ctx, client, http.MethodDelete, session, nil, ep.token)
	if err != nil {
		return fmt.Errorf("log out of %s: %w", ep.config.base, err)
	}
	// The card does not know the token: the session is already gone, as on a
	// card reset to its factory state, and holds nothing.
	if status == http.StatusUnauthorized {
		return nil
	}
	if status < 200 || status > 299 {
		return fmt.Errorf("log out of %s: %d: %s", ep.config.base, status, strings.TrimSpace(string(body)))
	}
	return nil
}

// do sends one request with the session's token, when there is one.
func (ep *eatonEndpoint) do(ctx context.Context, method, path string, body []byte) (int, []byte, error) {
	return ep.doAuth(ctx, method, path, body, ep.token)
}

// doReauth sends one request with the reauthentication token the card
// requires for account changes: base64(access_token:password).
func (ep *eatonEndpoint) doReauth(ctx context.Context, method, path string, body []byte) (int, []byte, error) {
	token := base64.StdEncoding.EncodeToString([]byte(ep.token + ":" + ep.sessionPassword))
	return ep.doAuth(ctx, method, path, body, token)
}

func (ep *eatonEndpoint) doAuth(ctx context.Context, method, path string, body []byte, bearer string) (int, []byte, error) {
	return ep.send(ctx, ep.client, method, path, body, bearer)
}

func (ep *eatonEndpoint) send(ctx context.Context, client *http.Client, method, path string, body []byte, bearer string) (int, []byte, error) {
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
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	resp, err := client.Do(req)
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
