package power

import (
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"path"
	"strconv"
	"strings"
	"time"
)

// EatonOutletSettings is one outlet's settings as the card reports them.
type EatonOutletSettings struct {
	Number         int
	StateOnStartup string
	Switchable     bool
	// Settings is the card's settings object, written back whole with
	// changed fields.
	Settings map[string]any
}

// EatonIdentity is the card's identification ("managers/1/identification").
type EatonIdentity struct {
	Product  string
	Model    string
	Serial   string
	Firmware string
	MAC      string
}

// EatonAccount is one local account on the card.
type EatonAccount struct {
	ID      string
	Name    string
	Profile string
	Enabled bool
	Locked  bool
	Licence string
}

// EatonProfile is one of the card's account profiles: administrators, viewers
// or operators.
type EatonProfile struct {
	Ref  string
	ID   string
	Name string
}

type eatonGetter func(ctx context.Context, path string, out any) error

// OutletSettings reads every outlet's settings through the driver's session.
func (e *Eaton) OutletSettings(ctx context.Context, o Outlet) ([]EatonOutletSettings, error) {
	return eatonOutletSettings(ctx, func(ctx context.Context, path string, out any) error {
		return e.call(ctx, o, http.MethodGet, path, out)
	})
}

// Identification reads the card's identification through the driver's session.
func (e *Eaton) Identification(ctx context.Context, o Outlet) (EatonIdentity, error) {
	return eatonIdentification(ctx, func(ctx context.Context, path string, out any) error {
		return e.call(ctx, o, http.MethodGet, path, out)
	})
}

func eatonOutletSettings(ctx context.Context, get eatonGetter) ([]EatonOutletSettings, error) {
	var list struct {
		Members []struct {
			ID string `json:"@id"`
		} `json:"members"`
	}
	if err := get(ctx, "/powerDistributions/"+eatonDistribution+"/outlets", &list); err != nil {
		return nil, err
	}
	outlets := make([]EatonOutletSettings, 0, len(list.Members))
	for _, member := range list.Members {
		n, err := strconv.Atoi(path.Base(member.ID))
		if err != nil || n < 1 {
			return nil, fmt.Errorf("outlet %q is not numbered", member.ID)
		}
		var outlet struct {
			Settings       map[string]any `json:"settings"`
			Specifications struct {
				Switchable bool `json:"switchable"`
			} `json:"specifications"`
		}
		if err := get(ctx, eatonOutletPath(n), &outlet); err != nil {
			return nil, err
		}
		state, _ := outlet.Settings["stateOnStartup"].(string)
		outlets = append(outlets, EatonOutletSettings{Number: n, StateOnStartup: state, Switchable: outlet.Specifications.Switchable, Settings: outlet.Settings})
	}
	return outlets, nil
}

func eatonIdentification(ctx context.Context, get eatonGetter) (EatonIdentity, error) {
	var id struct {
		ProductName     string `json:"productName"`
		ModelNumber     string `json:"modelNumber"`
		SerialNumber    string `json:"serialNumber"`
		FirmwareVersion string `json:"firmwareVersion"`
		MACAddress      string `json:"macAddress"`
	}
	if err := get(ctx, "/managers/1/identification", &id); err != nil {
		return EatonIdentity{}, err
	}
	return EatonIdentity{Product: id.ProductName, Model: id.ModelNumber, Serial: id.SerialNumber, Firmware: id.FirmwareVersion, MAC: strings.ToLower(id.MACAddress)}, nil
}

// EatonSession is one logged-in session on a card, separate from the driver's:
// the administrator's, which adoption runs as.
type EatonSession struct {
	ep *eatonEndpoint
	o  Outlet
}

// OpenEatonSession logs in as o.Username with o.Password. A non-empty
// newPassword is set in the same request, which is how the card's forced
// password change on a factory account is answered.
func OpenEatonSession(ctx context.Context, o Outlet, newPassword string, timeout time.Duration) (*EatonSession, error) {
	e := &Eaton{Timeout: timeout}
	config, _, err := e.config(o)
	if err != nil {
		return nil, err
	}
	config.initialPassword = ""
	ep := &eatonEndpoint{}
	if err := ep.configure(ctx, config, e.timeout()); err != nil {
		return nil, err
	}
	if err := ep.authenticate(ctx, o.Password, newPassword); err != nil {
		return nil, err
	}
	return &EatonSession{ep: ep, o: o}, nil
}

// Close logs the session out.
func (s *EatonSession) Close(ctx context.Context) error {
	return s.ep.logout(ctx)
}

func (s *EatonSession) request(ctx context.Context, method, path string, body any, reauth bool, out any) error {
	var payload []byte
	if body != nil {
		var err error
		if payload, err = json.Marshal(body); err != nil {
			return err
		}
	}
	send := s.ep.do
	if reauth {
		send = s.ep.doReauth
	}
	status, answer, err := send(ctx, method, eatonAPI+path, payload)
	if err != nil {
		return fmt.Errorf("%s %s: %w", method, path, err)
	}
	if status < 200 || status > 299 {
		return fmt.Errorf("%s %s: %d: %s", method, path, status, strings.TrimSpace(string(answer)))
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(answer, out); err != nil {
		return fmt.Errorf("decode %s: %w", path, err)
	}
	return nil
}

func (s *EatonSession) get(ctx context.Context, path string, out any) error {
	return s.request(ctx, http.MethodGet, path, nil, false, out)
}

// OutletSettings reads every outlet's settings.
func (s *EatonSession) OutletSettings(ctx context.Context) ([]EatonOutletSettings, error) {
	return eatonOutletSettings(ctx, s.get)
}

// Identification reads the card's identification.
func (s *EatonSession) Identification(ctx context.Context) (EatonIdentity, error) {
	return eatonIdentification(ctx, s.get)
}

// SetOutletSettings writes an outlet's settings object whole
// ("powerDistributions/1/outlets/1/settings").
func (s *EatonSession) SetOutletSettings(ctx context.Context, n int, settings map[string]any) error {
	return s.request(ctx, http.MethodPut, eatonOutletPath(n)+"/settings", settings, false, nil)
}

// Accounts lists the card's local accounts.
func (s *EatonSession) Accounts(ctx context.Context) ([]EatonAccount, error) {
	var list struct {
		Members []struct {
			ID          string `json:"id"`
			Name        string `json:"name"`
			Profile     string `json:"profile"`
			Enabled     bool   `json:"enabled"`
			Locked      bool   `json:"locked"`
			Preferences struct {
				Licence string `json:"licenceAgreement"`
			} `json:"preferences"`
		} `json:"members"`
	}
	if err := s.get(ctx, "/accountService/userProviders/local/accounts", &list); err != nil {
		return nil, err
	}
	accounts := make([]EatonAccount, 0, len(list.Members))
	for _, m := range list.Members {
		accounts = append(accounts, EatonAccount{ID: m.ID, Name: m.Name, Profile: m.Profile, Enabled: m.Enabled, Locked: m.Locked, Licence: m.Preferences.Licence})
	}
	return accounts, nil
}

// Profiles lists the card's account profiles.
func (s *EatonSession) Profiles(ctx context.Context) ([]EatonProfile, error) {
	var list struct {
		Members []struct {
			Ref  string `json:"@id"`
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"members"`
	}
	if err := s.get(ctx, "/accountService/profiles", &list); err != nil {
		return nil, err
	}
	profiles := make([]EatonProfile, 0, len(list.Members))
	for _, m := range list.Members {
		profiles = append(profiles, EatonProfile{Ref: m.Ref, ID: m.ID, Name: m.Name})
	}
	return profiles, nil
}

// AcceptLicence accepts the licence agreement for an account ("accept eula").
func (s *EatonSession) AcceptLicence(ctx context.Context, accountID string) error {
	return s.request(ctx, http.MethodPut, "/accountService/userProviders/local/accounts/"+accountID+"/preferences/licenceAgreement", "accepted", false, nil)
}

// CreateAccount creates a local account ("new account"), which the card
// requires a reauthentication token for.
func (s *EatonSession) CreateAccount(ctx context.Context, name, profileRef, password, fullName string) (EatonAccount, error) {
	var created struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	err := s.request(ctx, http.MethodPost, "/accountService/userProviders/local/accounts", map[string]any{
		"name":        name,
		"profile":     profileRef,
		"enabled":     true,
		"credentials": map[string]any{"password": password},
		"vcard":       map[string]any{"email": "", "fullName": fullName, "phone": "", "organization": ""},
		"neverBlock":  true,
		"neverExpire": true,
	}, true, &created)
	if err != nil {
		return EatonAccount{}, err
	}
	return EatonAccount{ID: created.ID, Name: created.Name, Profile: profileRef, Enabled: true}, nil
}

// DeleteAccount removes a local account ("remove account").
func (s *EatonSession) DeleteAccount(ctx context.Context, id string) error {
	return s.request(ctx, http.MethodDelete, "/accountService/userProviders/local/accounts/"+id, nil, false, nil)
}

// UnlockAccount unlocks a local account ("unlock account").
func (s *EatonSession) UnlockAccount(ctx context.Context, id string) error {
	return s.request(ctx, http.MethodPost, "/accountService/userProviders/local/accounts/"+id+"/actions/unlock", nil, false, nil)
}

// ProbeTLSFingerprint reads the SHA-256 of the certificate the endpoint
// presents, trusting nothing: what trust on first use records, and what an
// adopted card's pin is compared with.
func ProbeTLSFingerprint(ctx context.Context, o Outlet, timeout time.Duration) (string, error) {
	base, err := o.endpointWithScheme("https", "", nil)
	if err != nil {
		return "", err
	}
	host := strings.TrimPrefix(base, "https://")
	if _, _, err := net.SplitHostPort(host); err != nil {
		host = net.JoinHostPort(host, "443")
	}
	dialer := &tls.Dialer{
		NetDialer: &net.Dialer{Timeout: timeout},
		//nolint:gosec // Only reads the certificate; nothing is sent over this connection.
		Config: &tls.Config{InsecureSkipVerify: true, MinVersion: tls.VersionTLS12},
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	conn, err := dialer.DialContext(ctx, "tcp", host)
	if err != nil {
		return "", fmt.Errorf("read the certificate of %s: %w", o.Host, err)
	}
	defer conn.Close()
	certs := conn.(*tls.Conn).ConnectionState().PeerCertificates
	if len(certs) == 0 {
		return "", fmt.Errorf("%s presented no certificate", o.Host)
	}
	sum := sha256.Sum256(certs[0].Raw)
	return formatFingerprint(sum[:]), nil
}

// SameTLSFingerprint reports whether two fingerprints name the same
// certificate, however each is written.
func SameTLSFingerprint(a, b string) bool {
	x, err := ParseTLSFingerprint(a)
	if err != nil {
		return false
	}
	y, err := ParseTLSFingerprint(b)
	if err != nil {
		return false
	}
	return string(x) == string(y)
}
