// Package eatontest fakes an Eaton Rack PDU G4 network card's REST API over
// HTTPS, from Eaton's Postman collection "Rack PDU G4": factory state, forced
// password change, one session per account, accounts with profiles and a
// reauthentication token, outlet settings and switching. NewATS fakes a
// transfer switch behind a Network-M2 card on the same API (see ats.go). It is
// not captured traffic: what a real card answers beyond the collections'
// examples is a guess.
package eatontest

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"time"
)

const api = "/rest/mbdetnrs/2.0"

// Profile ids as the collection lists them.
const (
	ProfileAdministrators = "0"
	ProfileViewers        = "1"
	ProfileOperators      = "2"
)

// Account is one local account on the card.
type Account struct {
	ID              string
	Name            string
	Password        string
	Profile         string
	Enabled         bool
	Locked          bool
	PasswordExpired bool
	Licence         string
}

// Outlet is one outlet's state and settings.
type Outlet struct {
	On         bool
	Switchable bool
	// Lag is how many reads still report the state before the last switch.
	Lag      int
	Settings map[string]any
}

type session struct {
	id      string
	account string
	token   string
}

// Card is a fake G4 card. Its fields are guarded by Mu.
type Card struct {
	Mu sync.Mutex

	Accounts map[string]*Account
	Outlets  map[int]*Outlet
	sessions map[string]*session
	nextID   int

	// ForeignSessions names accounts whose session some other client holds.
	ForeignSessions map[string]bool
	// SwitchLag is how many reads after a switch action report the old state.
	SwitchLag int
	// Delay holds every request this long.
	Delay time.Duration
	// Refusal, when set, answers every login with it: status and body.
	Refusal *Refusal

	Logins []string
	// LoginAttempts counts every login request, answered or refused.
	LoginAttempts int
	// LoginAttemptsBy is the username of every login request, in order.
	LoginAttemptsBy []string
	Logouts         int
	Actions         []string
	Writes          []string
	InFlight        int
	MaxInFlight     int

	Serial   string
	Firmware string
	// Product and ModelNumber are the card's own identification.
	Product     string
	ModelNumber string

	// ATS, when set, is the transfer switch behind the card, served as
	// powerDistributions/1.
	ATS *ATS
	// LegacyWeb answers every request with an HTML 404, as a card that serves
	// no REST API does.
	LegacyWeb bool
	// IgnoreNewPasswordUnlessExpired accepts a login that asks to change the
	// password of an account whose password has not expired without changing
	// it, as a card might whose token endpoint only honours newPassword at the
	// forced first-login change.
	IgnoreNewPasswordUnlessExpired bool

	cert   tls.Certificate
	server *httptest.Server
}

// Refusal is an answer the card gives instead of a token.
type Refusal struct {
	Status int
	Body   string
}

// New starts a factory-fresh card with outlets outlets, every one on and
// switchable, starting in "last known state".
func New(outlets int) *Card {
	c := &Card{
		Accounts: map[string]*Account{
			"0": {ID: "0", Name: "admin", Password: "admin", Profile: ProfileAdministrators, Enabled: true, PasswordExpired: true},
		},
		Outlets:         map[int]*Outlet{},
		sessions:        map[string]*session{},
		nextID:          1,
		ForeignSessions: map[string]bool{},
		Serial:          "421G456777",
		Firmware:        "3.4.3",
		Product:         "Rack PDU Network Management Controller",
		ModelNumber:     "CCME-02-2",
	}
	for n := 1; n <= outlets; n++ {
		c.Outlets[n] = &Outlet{On: true, Switchable: true, Settings: map[string]any{
			"automaticSwitchOnDelay": 1, "lock": false, "rebootPeriod": 10,
			"stateOnStartup": "last known state",
			"current":        map[string]any{"highCriticalThreshold": 10, "highWarningThreshold": 8, "lowWarningThreshold": 0},
		}}
	}
	c.cert = newCertificate()
	c.server = httptest.NewUnstartedServer(http.HandlerFunc(c.serve))
	c.server.TLS = &tls.Config{
		MinVersion: tls.VersionTLS12,
		GetConfigForClient: func(*tls.ClientHelloInfo) (*tls.Config, error) {
			c.Mu.Lock()
			defer c.Mu.Unlock()
			return &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{c.cert}}, nil
		},
	}
	c.server.StartTLS()
	return c
}

// URL is the card's https://host:port.
func (c *Card) URL() string { return c.server.URL }

// Close stops the card.
func (c *Card) Close() { c.server.Close() }

// Fingerprint is the SHA-256 of the certificate the card presents, as openssl
// prints it.
func (c *Card) Fingerprint() string {
	c.Mu.Lock()
	defer c.Mu.Unlock()
	return fingerprint(c.cert.Certificate[0])
}

// RotateCertificate makes the card present a new self-signed certificate, as
// a factory reset or a replaced card does.
func (c *Card) RotateCertificate() {
	cert := newCertificate()
	c.Mu.Lock()
	defer c.Mu.Unlock()
	c.cert = cert
}

// AddAccount adds a ready account: licence accepted, password not expired.
func (c *Card) AddAccount(name, password, profile string) {
	c.Mu.Lock()
	defer c.Mu.Unlock()
	c.nextID++
	id := strconv.Itoa(c.nextID)
	c.Accounts[id] = &Account{ID: id, Name: name, Password: password, Profile: profile, Enabled: true, Licence: "accepted"}
}

// Account returns the account named name, or nil.
func (c *Card) Account(name string) *Account {
	c.Mu.Lock()
	defer c.Mu.Unlock()
	for _, a := range c.Accounts {
		if a.Name == name {
			copied := *a
			return &copied
		}
	}
	return nil
}

// OpenSessions is how many sessions the card holds.
func (c *Card) OpenSessions() int {
	c.Mu.Lock()
	defer c.Mu.Unlock()
	return len(c.sessions)
}

// Expire ends every session, as the card's lease or inactivity timeout does.
func (c *Card) Expire() {
	c.Mu.Lock()
	defer c.Mu.Unlock()
	c.sessions = map[string]*session{}
}

// StateOnStartup reads an outlet's startup state.
func (c *Card) StateOnStartup(n int) string {
	c.Mu.Lock()
	defer c.Mu.Unlock()
	s, _ := c.Outlets[n].Settings["stateOnStartup"].(string)
	return s
}

func (c *Card) serve(w http.ResponseWriter, r *http.Request) {
	c.Mu.Lock()
	c.InFlight++
	if c.InFlight > c.MaxInFlight {
		c.MaxInFlight = c.InFlight
	}
	delay := c.Delay
	c.Mu.Unlock()
	defer func() {
		c.Mu.Lock()
		c.InFlight--
		c.Mu.Unlock()
	}()
	if delay > 0 {
		select {
		case <-time.After(delay):
		case <-r.Context().Done():
			return
		}
	}

	c.Mu.Lock()
	defer c.Mu.Unlock()
	if c.LegacyWeb {
		w.Header().Set("Content-Type", "text/html")
		answer(w, http.StatusNotFound, "<html><body>Not Found</body></html>")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	path := strings.TrimPrefix(r.URL.Path, api)

	if path == "/oauth2/token/" && r.Method == http.MethodPost {
		c.login(w, r)
		return
	}

	s, reauth := c.authorize(r)
	if s == nil {
		answer(w, http.StatusUnauthorized, `{"code":"InvalidCredential"}`)
		return
	}
	account := c.Accounts[s.account]
	admin := account.Profile == ProfileAdministrators

	switch {
	case r.Method == http.MethodDelete && strings.HasPrefix(path, "/sessionService/sessions/"):
		id := strings.TrimPrefix(path, "/sessionService/sessions/")
		for token, other := range c.sessions {
			if other.id == id {
				delete(c.sessions, token)
				c.Logouts++
			}
		}
		answer(w, http.StatusOK, "null")

	case r.Method == http.MethodGet && path == "/accountService/profiles":
		answer(w, http.StatusOK, `{"@id":"/rest/mbdetnrs/2.0/accountService/profiles","members@count":3,"members":[`+
			`{"@id":"/rest/mbdetnrs/2.0/accountService/profiles/0","id":"0","name":"administrators","predefined":true,"roles":["role-user-manager","role-powerdistribution-manager","role-power-manager"]},`+
			`{"@id":"/rest/mbdetnrs/2.0/accountService/profiles/1","id":"1","name":"viewers","predefined":true,"roles":["role-power-viewer"]},`+
			`{"@id":"/rest/mbdetnrs/2.0/accountService/profiles/2","id":"2","name":"operators","predefined":true,"roles":["role-power-manager","role-power-viewer","role-powerdistribution-viewer"]}]}`)

	case path == "/accountService/userProviders/local/accounts" && r.Method == http.MethodGet:
		if !admin {
			answer(w, http.StatusForbidden, `{"code":"NotAuthorized"}`)
			return
		}
		members := make([]map[string]any, 0, len(c.Accounts))
		for id := 0; id < c.nextID+1; id++ {
			a, ok := c.Accounts[strconv.Itoa(id)]
			if !ok {
				continue
			}
			members = append(members, accountJSON(a))
		}
		body, _ := json.Marshal(map[string]any{"members@count": len(members), "members": members})
		answer(w, http.StatusOK, string(body))

	case path == "/accountService/userProviders/local/accounts" && r.Method == http.MethodPost:
		if !admin || !reauth {
			answer(w, http.StatusForbidden, `{"code":"NotAuthorized"}`)
			return
		}
		var request struct {
			Name        string `json:"name"`
			Profile     string `json:"profile"`
			Enabled     bool   `json:"enabled"`
			Credentials struct {
				Password string `json:"password"`
			} `json:"credentials"`
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil || request.Name == "" || !strongPassword(request.Credentials.Password) {
			answer(w, http.StatusBadRequest, `{"code":"InvalidParameter"}`)
			return
		}
		for _, a := range c.Accounts {
			if a.Name == request.Name {
				answer(w, http.StatusConflict, `{"code":"AlreadyExists"}`)
				return
			}
		}
		c.nextID++
		id := strconv.Itoa(c.nextID)
		a := &Account{ID: id, Name: request.Name, Password: request.Credentials.Password,
			Profile: strings.TrimPrefix(request.Profile, api+"/accountService/profiles/"), Enabled: request.Enabled, PasswordExpired: true}
		c.Accounts[id] = a
		c.Writes = append(c.Writes, "create account "+a.Name)
		body, _ := json.Marshal(accountJSON(a))
		answer(w, http.StatusOK, string(body))

	case strings.HasPrefix(path, "/accountService/userProviders/local/accounts/"):
		rest := strings.TrimPrefix(path, "/accountService/userProviders/local/accounts/")
		id, action, _ := strings.Cut(rest, "/")
		a, ok := c.Accounts[id]
		if !ok {
			answer(w, http.StatusNotFound, `{"code":"NotFound"}`)
			return
		}
		switch {
		case r.Method == http.MethodPut && action == "preferences/licenceAgreement":
			if !admin && s.account != id {
				answer(w, http.StatusForbidden, `{"code":"NotAuthorized"}`)
				return
			}
			var value string
			if err := json.NewDecoder(r.Body).Decode(&value); err != nil {
				answer(w, http.StatusBadRequest, `{"code":"InvalidParameter"}`)
				return
			}
			a.Licence = value
			c.Writes = append(c.Writes, "licence "+a.Name)
			answer(w, http.StatusOK, "null")
		case r.Method == http.MethodDelete && action == "" && admin:
			delete(c.Accounts, id)
			for token, other := range c.sessions {
				if other.account == id {
					delete(c.sessions, token)
				}
			}
			c.Writes = append(c.Writes, "delete account "+a.Name)
			answer(w, http.StatusOK, "null")
		case r.Method == http.MethodPost && action == "actions/unlock" && admin:
			a.Locked = false
			c.Writes = append(c.Writes, "unlock "+a.Name)
			answer(w, http.StatusOK, "null")
		default:
			answer(w, http.StatusForbidden, `{"code":"NotAuthorized"}`)
		}

	case r.Method == http.MethodGet && path == "/managers/1/identification":
		fmt.Fprintf(w, `{"physicalName":"Eaton %s","vendor":"Eaton","productName":%q,"serialNumber":%q,"type":"management card","firmwareVersion":%q,"product":"enmc2-fe_0","modelNumber":%q,"partNumber":"755-456-489","macAddress":"00:20:85:D7:00:CA"}`, c.Product, c.Product, c.Serial, c.Firmware, c.ModelNumber)

	case r.Method == http.MethodGet && path == "/powerDistributions/1" && c.ATS == nil:
		// The collection's G3 HD example, which the G4 is taken to share.
		fmt.Fprintf(w, `{"@id":"/rest/mbdetnrs/2.0/powerDistributions/1","id":"1","identification":{"model":"Eaton Rack PDU G4","productName":"Rack PDU G4","serialNumber":%q,"type":"PowerDistribution"},"specifications":{"switchable":true,"type":"pdu"}}`, c.Serial)

	case r.Method == http.MethodGet && path == "/powerDistributions/1/outlets":
		members := []string{}
		for n := 1; n <= len(c.Outlets); n++ {
			members = append(members, fmt.Sprintf(`{"@id":"/rest/mbdetnrs/2.0/powerDistributions/1/outlets/%d"}`, n))
		}
		fmt.Fprintf(w, `{"@id":"/rest/mbdetnrs/2.0/powerDistributions/1/outlets","members@count":%d,"members":[%s]}`, len(c.Outlets), strings.Join(members, ","))

	case strings.HasPrefix(path, "/powerDistributions/1/outlets/"):
		rest := strings.TrimPrefix(path, "/powerDistributions/1/outlets/")
		id, action, _ := strings.Cut(rest, "/")
		n, _ := strconv.Atoi(id)
		outlet, ok := c.Outlets[n]
		if !ok {
			answer(w, http.StatusNotFound, `{"code":"NotFound"}`)
			return
		}
		switch {
		case r.Method == http.MethodGet && action == "":
			on := outlet.On
			if outlet.Lag > 0 {
				outlet.Lag--
				on = !on
			}
			body, _ := json.Marshal(map[string]any{
				"@id":      fmt.Sprintf("/rest/mbdetnrs/2.0/powerDistributions/1/outlets/%d", n),
				"id":       id,
				"settings": outlet.Settings,
				"status": map[string]any{"operating": "in service", "health": "ok", "delayBeforeSwitchOff": -1,
					"delayBeforeSwitchOn": -1, "supply": true, "switchedOn": on},
				"specifications": map[string]any{"feed": "Branches.1", "outletType": "IecC13", "switchable": outlet.Switchable},
			})
			answer(w, http.StatusOK, string(body))
		case r.Method == http.MethodPut && action == "settings":
			if !admin {
				answer(w, http.StatusForbidden, `{"code":"NotAuthorized"}`)
				return
			}
			var settings map[string]any
			if err := json.NewDecoder(r.Body).Decode(&settings); err != nil {
				answer(w, http.StatusBadRequest, `{"code":"InvalidParameter"}`)
				return
			}
			outlet.Settings = settings
			c.Writes = append(c.Writes, fmt.Sprintf("outlet %d settings", n))
			answer(w, http.StatusOK, "null")
		case r.Method == http.MethodPost && (action == "actions/switchOn" || action == "actions/switchOff"):
			if !outlet.Switchable {
				answer(w, http.StatusBadRequest, `{"code":"NotSwitchable"}`)
				return
			}
			c.Actions = append(c.Actions, fmt.Sprintf("%d/%s", n, strings.TrimPrefix(action, "actions/")))
			outlet.On = action == "actions/switchOn"
			outlet.Lag = c.SwitchLag
			answer(w, http.StatusOK, "null")
		default:
			answer(w, http.StatusNotFound, `{"code":"NotFound"}`)
		}

	default:
		if c.ATS != nil && c.serveATS(w, r, path, admin) {
			return
		}
		answer(w, http.StatusNotFound, `{"code":"NotFound"}`)
	}
}

func (c *Card) login(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Username    string `json:"username"`
		Password    string `json:"password"`
		NewPassword string `json:"newPassword"`
	}
	_ = json.NewDecoder(r.Body).Decode(&request)
	c.LoginAttempts++
	c.LoginAttemptsBy = append(c.LoginAttemptsBy, request.Username)
	if c.Refusal != nil {
		answer(w, c.Refusal.Status, c.Refusal.Body)
		return
	}
	var account *Account
	for _, a := range c.Accounts {
		if a.Name == request.Username {
			account = a
		}
	}
	if account == nil || account.Password != request.Password || !account.Enabled {
		answer(w, http.StatusUnauthorized, `{"code":"InvalidCredential"}`)
		return
	}
	if account.Locked {
		answer(w, http.StatusForbidden, `{"code":"AccountBlocked"}`)
		return
	}
	if c.ForeignSessions[account.Name] {
		answer(w, http.StatusForbidden, `{"code":"ConcurentSession"}`)
		return
	}
	for _, s := range c.sessions {
		if s.account == account.ID {
			answer(w, http.StatusForbidden, `{"code":"ConcurentSession"}`)
			return
		}
	}
	if request.NewPassword != "" && !(c.IgnoreNewPasswordUnlessExpired && !account.PasswordExpired) {
		if !strongPassword(request.NewPassword) || request.NewPassword == request.Password {
			answer(w, http.StatusBadRequest, `{"code":"InvalidPassword"}`)
			return
		}
		account.Password = request.NewPassword
		account.PasswordExpired = false
		c.Writes = append(c.Writes, "password "+account.Name)
	} else if request.NewPassword == "" && account.PasswordExpired {
		answer(w, http.StatusForbidden, `{"code":"ExpiredCredentials"}`)
		return
	}
	c.nextID++
	s := &session{id: strconv.Itoa(c.nextID), account: account.ID, token: fmt.Sprintf("token-%d", c.nextID)}
	c.sessions[s.token] = s
	c.Logins = append(c.Logins, account.Name)
	fmt.Fprintf(w, `{"token_type":"Bearer","access_token":%q,"session":"/mbdetnrs/2.0/sessionService/sessions/%s"}`, s.token, s.id)
}

// authorize resolves the request's session, from a bearer token or a
// reauthentication token, base64(access_token:password).
func (c *Card) authorize(r *http.Request) (*session, bool) {
	bearer, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok {
		return nil, false
	}
	if s, ok := c.sessions[bearer]; ok {
		return s, false
	}
	decoded, err := base64.StdEncoding.DecodeString(bearer)
	if err != nil {
		return nil, false
	}
	token, password, ok := strings.Cut(string(decoded), ":")
	if !ok {
		return nil, false
	}
	s, known := c.sessions[token]
	if !known || c.Accounts[s.account].Password != password {
		return nil, false
	}
	return s, true
}

func accountJSON(a *Account) map[string]any {
	return map[string]any{
		"@id":         api + "/accountService/userProviders/local/accounts/" + a.ID,
		"id":          a.ID,
		"name":        a.Name,
		"enabled":     a.Enabled,
		"locked":      a.Locked,
		"profile":     api + "/accountService/profiles/" + a.Profile,
		"preferences": map[string]any{"licenceAgreement": a.Licence},
		"credentials": map[string]any{"password": nil},
	}
}

// strongPassword is the collection's default password policy: 8 to 32
// characters with an upper case letter, a lower case letter, a digit and a
// special character.
func strongPassword(p string) bool {
	if len(p) < 8 || len(p) > 32 {
		return false
	}
	var upper, lower, digit, special bool
	for _, r := range p {
		switch {
		case r >= 'A' && r <= 'Z':
			upper = true
		case r >= 'a' && r <= 'z':
			lower = true
		case r >= '0' && r <= '9':
			digit = true
		default:
			special = true
		}
	}
	return upper && lower && digit && special
}

func answer(w http.ResponseWriter, status int, body string) {
	w.WriteHeader(status)
	fmt.Fprint(w, body)
}

func fingerprint(der []byte) string {
	sum := sha256.Sum256(der)
	parts := make([]string, len(sum))
	for i, b := range sum {
		parts[i] = fmt.Sprintf("%02X", b)
	}
	return strings.Join(parts, ":")
}

func newCertificate() tls.Certificate {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		panic(err)
	}
	serial, _ := rand.Int(rand.Reader, big.NewInt(1<<62))
	template := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: "g3hd-eaton-dev"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(24 * time.Hour),
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		panic(err)
	}
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}
}
