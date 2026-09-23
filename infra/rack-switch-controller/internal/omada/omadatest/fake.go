// Package omadatest is a fake Omada controller for tests: an httptest TLS
// server that answers the Open API calls package omada makes, with the
// behaviour measured on controller 6.3.0.45 where it matters (token expiry,
// adoption's transitions, the port endpoint's refusals).
package omadatest

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"

	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
)

const (
	OmadacID     = "fake-omadac"
	ClientID     = "client-id"
	ClientSecret = "client-secret"
	SiteName     = "ber1"
	SiteID       = "site-ber1"

	DefaultNetworkID = "net-default"
	ProfileAllID     = "profile-all"
	ProfileDefaultID = "profile-default"
	ProfileDisableID = "profile-disable"
)

// State is a device's status and detailStatus.
type State struct {
	Status int
	Detail int
}

var (
	Pending        = State{omada.StatusPending, 20}
	Adopting       = State{omada.StatusPending, 22}
	AdoptionFailed = State{omada.StatusPending, omada.DetailAdoptionFailed}
	Connected      = State{omada.StatusConnected, 14}
	Disconnected   = State{omada.StatusDisconnected, 0}
)

// Switch is a switch the fake controller knows.
type Switch struct {
	MAC      string
	Model    string
	State    State
	Hostname string
	Ports    []omada.Port
	Loopback *omada.Loopback
	// Logins adoption succeeds with; any other fails.
	Logins []omada.Login
	// The login each start-adopt carried, in order.
	AdoptedWith []omada.Login
	// The last override body written to each port.
	Overrides map[int]map[string]any
	LAGs      map[int][]int
	// The switch's interfaces, as GET switches/{mac}/networks returns them.
	Networks []map[string]any

	queue []State
}

// ManagementInterface is a management interface as the controller returned it
// on the SG3452 and SX3832: mode 0 static, 1 DHCP.
func ManagementInterface(mode int, address, netmask, gateway string) map[string]any {
	return map[string]any{
		"id":    "switch-net-default",
		"vlan":  float64(1),
		"mvlan": true,
		"name":  "Default",
		"ip": map[string]any{
			"mode": float64(mode), "ip": address, "netmask": netmask, "gateway": gateway,
			"fallback": true, "fallbackIp": "192.168.0.1", "fallbackMask": "255.255.255.0",
		},
		"ipv6Enable": false,
		"ipv6":       map[string]any{},
		"mode":       float64(0),
		"status":     float64(1),
	}
}

// Request is one Open API call, with its path under /openapi/v1/{omadacId}
// and without the query.
type Request struct {
	Method string
	Path   string
	Body   map[string]any
}

// Server is the fake controller.
type Server struct {
	*httptest.Server

	mu            sync.Mutex
	tokens        map[string]bool
	issued        int
	TokenLifetime int
	deviceHost    string
	deviceHostOn  bool
	ssh           map[string]any
	account       omada.Login
	lldp          map[string]any
	snmp          map[string]any
	networks      []omada.LANNetwork
	profiles      []omada.LANProfile
	switches      map[string]*Switch
	requests      []Request
}

// New starts a fake controller with one site, the controller's default
// networks and port profiles, and SSH off, as a fresh controller has it.
func New() *Server {
	s := &Server{
		tokens:        map[string]bool{},
		TokenLifetime: 7200,
		ssh:           map[string]any{"sshEnable": false, "sshServerPort": float64(22), "layer3Access": false},
		account:       omada.Login{Username: "admin", Password: "wizard-password"},
		lldp:          map[string]any{"enable": false},
		snmp:          map[string]any{"snmpV1Enable": false, "snmpV2Enable": true, "location": "", "contact": ""},
		networks:      []omada.LANNetwork{{ID: DefaultNetworkID, Name: "Default", VLAN: 1, Purpose: 1, Application: 1}},
		profiles: []omada.LANProfile{
			{ID: ProfileAllID, Name: "All", NativeNetworkID: DefaultNetworkID, UntagNetworkIDs: []string{DefaultNetworkID}, TagNetworkIDs: []string{}, SpanningTreeEnable: true},
			{ID: ProfileDefaultID, Name: "Default", NativeNetworkID: DefaultNetworkID, UntagNetworkIDs: []string{DefaultNetworkID}, TagNetworkIDs: []string{}, SpanningTreeEnable: true},
			{ID: ProfileDisableID, Name: "Disable", SpanningTreeEnable: true},
		},
		switches: map[string]*Switch{},
	}
	s.Server = httptest.NewTLSServer(http.HandlerFunc(s.serve))
	return s
}

// Ports is n ports as the controller lists them on a freshly adopted switch:
// Port<n>, profile "All", no override.
func Ports(n int) []omada.Port {
	ports := make([]omada.Port, n)
	for i := range ports {
		ports[i] = omada.Port{Port: i + 1, Name: fmt.Sprintf("Port%d", i+1), ProfileID: ProfileAllID, ProfileName: "All", Status: 1}
	}
	return ports
}

// AddSwitch adds a switch. Its MAC is normalised to the controller's form.
func (s *Server) AddSwitch(sw Switch) {
	s.mu.Lock()
	defer s.mu.Unlock()
	sw.MAC = omada.ControllerMAC(sw.MAC)
	if sw.Overrides == nil {
		sw.Overrides = map[int]map[string]any{}
	}
	if sw.LAGs == nil {
		sw.LAGs = map[int][]int{}
	}
	s.switches[sw.MAC] = &sw
}

// Switch is a copy of a switch's state.
func (s *Server) Switch(mac string) Switch {
	s.mu.Lock()
	defer s.mu.Unlock()
	sw := *s.switches[omada.ControllerMAC(mac)]
	sw.Ports = append([]omada.Port(nil), sw.Ports...)
	return sw
}

// Update changes a switch under the server's lock.
func (s *Server) Update(mac string, change func(*Switch)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	change(s.switches[omada.ControllerMAC(mac)])
}

// SetAccount sets the site's device account.
func (s *Server) SetAccount(login omada.Login) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.account = login
}

// Account is the site's device account.
func (s *Server) Account() omada.Login {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.account
}

// DeviceHost is the address the controller advertises, "" when none.
func (s *Server) DeviceHost() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.deviceHostOn {
		return ""
	}
	return s.deviceHost
}

// SSH is the site's SSH setting.
func (s *Server) SSH() map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	return copyMap(s.ssh)
}

// LLDP and SNMP are the site's service settings.
func (s *Server) LLDP() map[string]any { s.mu.Lock(); defer s.mu.Unlock(); return copyMap(s.lldp) }
func (s *Server) SNMP() map[string]any { s.mu.Lock(); defer s.mu.Unlock(); return copyMap(s.snmp) }

// Networks is the site's networks.
func (s *Server) Networks() []omada.LANNetwork {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]omada.LANNetwork(nil), s.networks...)
}

// ExpireTokens makes the controller reject every token it has issued.
func (s *Server) ExpireTokens() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.tokens = map[string]bool{}
}

// TokensIssued counts the tokens issued so far.
func (s *Server) TokensIssued() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.issued
}

// Requests is every Open API call so far.
func (s *Server) Requests() []Request {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]Request(nil), s.requests...)
}

// Writes is every call so far other than a GET.
func (s *Server) Writes() []Request {
	var writes []Request
	for _, r := range s.Requests() {
		if r.Method != http.MethodGet {
			writes = append(writes, r)
		}
	}
	return writes
}

// ResetRequests forgets the calls so far.
func (s *Server) ResetRequests() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.requests = nil
}

type fault struct {
	code int
	msg  string
}

func (f *fault) Error() string { return f.msg }

func fail(code int, format string, args ...any) *fault {
	return &fault{code: code, msg: fmt.Sprintf(format, args...)}
}

const generalError = -1001

var (
	macPath      = `([0-9A-F]{2}(?:-[0-9A-F]{2}){5})`
	sitePrefix   = `^/sites/([^/]+)`
	routeSwitch  = regexp.MustCompile(sitePrefix + `/switches/` + macPath + `$`)
	routeGeneral = regexp.MustCompile(sitePrefix + `/switches/` + macPath + `/general-config$`)
	routePort    = regexp.MustCompile(sitePrefix + `/switches/` + macPath + `/ports/(\d+)$`)
	routeLoop    = regexp.MustCompile(sitePrefix + `/switches/` + macPath + `/config/loopback$`)
	routeLAG     = regexp.MustCompile(sitePrefix + `/switches/` + macPath + `/lags/(\d+)$`)
	routeSwNets  = regexp.MustCompile(sitePrefix + `/switches/` + macPath + `/networks$`)
	routeSwNet   = regexp.MustCompile(sitePrefix + `/switches/` + macPath + `/networks/([^/]+)$`)
	routeAdopt   = regexp.MustCompile(sitePrefix + `/devices/` + macPath + `/start-adopt$`)
	routeSite    = regexp.MustCompile(sitePrefix + `(/.*)$`)
)

func (s *Server) serve(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()

	var body map[string]any
	if raw, _ := io.ReadAll(r.Body); len(raw) > 0 {
		if err := json.Unmarshal(raw, &body); err != nil {
			reply(w, nil, fail(generalError, "malformed body"))
			return
		}
	}

	switch {
	case r.URL.Path == "/api/info" && r.Method == http.MethodGet:
		reply(w, map[string]any{"omadacId": OmadacID}, nil)
		return
	case r.URL.Path == "/openapi/authorize/token" && r.Method == http.MethodPost:
		reply(s.token(w, r, body))
		return
	}

	prefix := "/openapi/v1/" + OmadacID
	if !strings.HasPrefix(r.URL.Path, prefix+"/") {
		http.NotFound(w, r)
		return
	}
	path := strings.TrimPrefix(r.URL.Path, prefix)
	if !s.tokens[strings.TrimPrefix(r.Header.Get("Authorization"), "AccessToken=")] {
		reply(w, nil, fail(-44112, "The access token has expired."))
		return
	}
	s.requests = append(s.requests, Request{Method: r.Method, Path: path, Body: body})
	result, err := s.route(r.Method, path, body)
	reply(w, result, err)
}

func (s *Server) token(w http.ResponseWriter, r *http.Request, body map[string]any) (http.ResponseWriter, any, error) {
	if r.URL.Query().Get("grant_type") != "client_credentials" {
		return w, nil, fail(-44111, "The grant type is invalid.")
	}
	if body["omadacId"] != OmadacID || body["client_id"] != ClientID || body["client_secret"] != ClientSecret {
		return w, nil, fail(-44106, "The client id or client secret is invalid.")
	}
	s.issued++
	token := fmt.Sprintf("token-%d", s.issued)
	s.tokens[token] = true
	return w, map[string]any{"accessToken": token, "tokenType": "bearer", "expiresIn": s.TokenLifetime}, nil
}

func reply(w http.ResponseWriter, result any, err error) {
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		code := generalError
		if f, ok := err.(*fault); ok {
			code = f.code
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"errorCode": code, "msg": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]any{"errorCode": 0, "msg": "Success.", "result": result})
}

func paged[T any](items []T) map[string]any {
	if items == nil {
		items = []T{}
	}
	return map[string]any{"totalRows": len(items), "currentPage": 1, "currentSize": len(items), "data": items}
}

func (s *Server) route(method, path string, body map[string]any) (any, error) {
	switch {
	case path == "/sites" && method == http.MethodGet:
		return paged([]map[string]string{{"name": "Default", "siteId": "site-default"}, {"name": SiteName, "siteId": SiteID}}), nil
	case path == "/controller/setting/general" && method == http.MethodGet:
		return map[string]any{"deviceManage": map[string]any{"deviceHostEnable": s.deviceHostOn, "deviceHost": s.deviceHost}}, nil
	case path == "/controller/setting/general" && method == http.MethodPatch:
		manage, _ := body["deviceManage"].(map[string]any)
		s.deviceHostOn, _ = manage["deviceHostEnable"].(bool)
		s.deviceHost, _ = manage["deviceHost"].(string)
		return nil, nil
	}

	if m := routeAdopt.FindStringSubmatch(path); m != nil && method == http.MethodPost {
		return nil, s.startAdopt(m[1], m[2], body)
	}
	if m := routeSwitch.FindStringSubmatch(path); m != nil && method == http.MethodGet {
		sw, err := s.adopted(m[1], m[2])
		if err != nil {
			return nil, err
		}
		return map[string]any{"mac": sw.MAC, "portList": sw.Ports}, nil
	}
	if m := routeGeneral.FindStringSubmatch(path); m != nil {
		sw, err := s.adopted(m[1], m[2])
		if err != nil {
			return nil, err
		}
		if method == http.MethodGet {
			return map[string]any{"name": sw.Hostname}, nil
		}
		sw.Hostname, _ = body["name"].(string)
		return nil, nil
	}
	if m := routePort.FindStringSubmatch(path); m != nil && method == http.MethodPatch {
		sw, err := s.adopted(m[1], m[2])
		if err != nil {
			return nil, err
		}
		n, _ := strconv.Atoi(m[3])
		return nil, s.patchPort(sw, n, body)
	}
	if m := routeLoop.FindStringSubmatch(path); m != nil && method == http.MethodPut {
		sw, err := s.adopted(m[1], m[2])
		if err != nil {
			return nil, err
		}
		raw, _ := json.Marshal(body)
		var loopback omada.Loopback
		_ = json.Unmarshal(raw, &loopback)
		sw.Loopback = &loopback
		return nil, nil
	}
	if m := routeLAG.FindStringSubmatch(path); m != nil && method == http.MethodDelete {
		sw, err := s.adopted(m[1], m[2])
		if err != nil {
			return nil, err
		}
		id, _ := strconv.Atoi(m[3])
		members, ok := sw.LAGs[id]
		if !ok {
			return nil, fail(generalError, "General error.")
		}
		for _, member := range members {
			if p := port(sw, member); p != nil {
				p.LAGPort = false
				p.Name = fmt.Sprintf("Port%d", member)
			}
		}
		delete(sw.LAGs, id)
		return nil, nil
	}
	if m := routeSwNets.FindStringSubmatch(path); m != nil && method == http.MethodGet {
		sw, err := s.adopted(m[1], m[2])
		if err != nil {
			return nil, err
		}
		return paged(sw.Networks), nil
	}
	if m := routeSwNet.FindStringSubmatch(path); m != nil && method == http.MethodPost {
		sw, err := s.adopted(m[1], m[2])
		if err != nil {
			return nil, err
		}
		ip, _ := body["ip"].(map[string]any)
		for _, field := range []string{"mode", "ip", "netmask", "gateway", "fallback", "fallbackIp", "fallbackMask"} {
			if _, present := ip[field]; !present {
				return nil, fail(generalError, "Invalid request parameters.")
			}
		}
		for i, entry := range sw.Networks {
			if entry["id"] == m[3] {
				written := copyMap(body)
				written["status"] = entry["status"]
				sw.Networks[i] = written
				return nil, nil
			}
		}
		return nil, fail(generalError, "General error.")
	}

	m := routeSite.FindStringSubmatch(path)
	if m == nil || m[1] != SiteID {
		return nil, fail(-33000, "This site does not exist.")
	}
	switch rest := m[2]; {
	case rest == "/devices" && method == http.MethodGet:
		return paged(s.deviceList(false)), nil
	case rest == "/grid/devices/pending" && method == http.MethodGet:
		return paged(s.deviceList(true)), nil
	case rest == "/ssh" && method == http.MethodGet:
		return s.ssh, nil
	case rest == "/ssh" && method == http.MethodPut:
		s.ssh = copyMap(body)
		return nil, nil
	case rest == "/device-account" && method == http.MethodGet:
		return s.account, nil
	case rest == "/device-account" && method == http.MethodPut:
		s.account = omada.Login{Username: fmt.Sprint(body["username"]), Password: fmt.Sprint(body["password"])}
		return nil, nil
	case rest == "/lldp" && method == http.MethodGet:
		return s.lldp, nil
	case rest == "/lldp" && method == http.MethodPatch:
		s.lldp = copyMap(body)
		return nil, nil
	case rest == "/setting/service/snmp" && method == http.MethodGet:
		return s.snmp, nil
	case rest == "/setting/service/snmp" && method == http.MethodPatch:
		s.snmp = copyMap(body)
		return nil, nil
	case rest == "/lan-networks" && method == http.MethodGet:
		return paged(s.networks), nil
	case rest == "/lan-networks" && method == http.MethodPost:
		vlan := int(number(body["vlan"]))
		for _, n := range s.networks {
			if n.VLAN == vlan {
				return nil, fail(generalError, "The VLAN ID already exists.")
			}
		}
		id := fmt.Sprintf("net-%d", vlan)
		s.networks = append(s.networks, omada.LANNetwork{ID: id, Name: fmt.Sprint(body["name"]), VLAN: vlan, Purpose: int(number(body["purpose"])), Application: int(number(body["application"]))})
		return map[string]any{"id": id}, nil
	case rest == "/lan-profiles" && method == http.MethodGet:
		return paged(s.profiles), nil
	}
	return nil, fail(generalError, "the fake does not answer %s %s", method, path)
}

func (s *Server) deviceList(pendingOnly bool) []omada.Device {
	macs := make([]string, 0, len(s.switches))
	for mac := range s.switches {
		macs = append(macs, mac)
	}
	sort.Strings(macs)
	var devices []omada.Device
	for _, mac := range macs {
		sw := s.switches[mac]
		if !pendingOnly && len(sw.queue) > 0 {
			sw.State, sw.queue = sw.queue[0], sw.queue[1:]
			if sw.State == Connected {
				s.adopt(sw)
			}
		}
		if pendingOnly && sw.State.Status != omada.StatusPending {
			continue
		}
		detail := sw.State.Detail
		devices = append(devices, omada.Device{MAC: sw.MAC, Model: sw.Model, Name: sw.Hostname, Status: sw.State.Status, DetailStatus: &detail})
	}
	return devices
}

// adopt is what adoption did to ber1-mgmt: its hostname became its MAC, and
// the site's device account replaced its login.
func (s *Server) adopt(sw *Switch) {
	sw.Hostname = sw.MAC
	sw.Logins = []omada.Login{s.account}
}

func (s *Server) startAdopt(siteID, mac string, body map[string]any) error {
	if siteID != SiteID {
		return fail(-33000, "This site does not exist.")
	}
	sw, ok := s.switches[mac]
	if !ok || sw.State.Status != omada.StatusPending {
		return fail(-39003, "The device is not pending.")
	}
	login := omada.Login{Username: fmt.Sprint(body["username"]), Password: fmt.Sprint(body["password"])}
	sw.AdoptedWith = append(sw.AdoptedWith, login)
	outcome := AdoptionFailed
	for _, l := range sw.Logins {
		if l == login {
			outcome = Connected
		}
	}
	sw.queue = nil
	if sw.State == AdoptionFailed {
		// A failure from an earlier attempt shows until the controller picks
		// the new request up.
		sw.queue = append(sw.queue, AdoptionFailed)
	}
	sw.queue = append(sw.queue, Adopting, outcome)
	return nil
}

func (s *Server) adopted(siteID, mac string) (*Switch, error) {
	if siteID != SiteID {
		return nil, fail(-33000, "This site does not exist.")
	}
	sw, ok := s.switches[mac]
	if !ok || sw.State.Status == omada.StatusPending {
		return nil, fail(-39001, "The device does not exist.")
	}
	return sw, nil
}

func (s *Server) patchPort(sw *Switch, n int, body map[string]any) error {
	p := port(sw, n)
	if p == nil {
		return fail(generalError, "General error.")
	}
	if p.LAGPort {
		return fail(generalError, "The ports in a LAG cannot be modified.")
	}
	if body["profileId"] != p.ProfileID {
		return fail(generalError, "Invalid request parameters.")
	}
	if body["operation"] == "aggregating" {
		setting, _ := body["lagSetting"].(map[string]any)
		name, _ := body["name"].(string)
		if number(setting["lagType"]) != 2 || name == "" {
			return fail(generalError, "General error.")
		}
		var members []int
		requested, _ := setting["ports"].([]any)
		for _, m := range requested {
			members = append(members, int(number(m)))
		}
		for _, member := range members {
			mp := port(sw, member)
			if mp == nil || mp.LAGPort {
				return fail(generalError, "General error.")
			}
		}
		for _, member := range members {
			mp := port(sw, member)
			mp.LAGPort = true
			mp.Name = name
		}
		sw.LAGs[int(number(setting["lagId"]))] = members
		return nil
	}
	if enabled, present := body["profileVlanOverrideEnable"]; present && enabled == false && p.ProfileName == "All" {
		return fail(generalError, "When the VLAN configuration in the profile bound to the port is disabled, the VLAN configuration of the port cannot follow the profile.")
	}
	if name, ok := body["name"].(string); ok {
		p.Name = name
	}
	if override, present := body["profileOverrideEnable"].(bool); present {
		p.ProfileOverrideEnable = override
		if override {
			sw.Overrides[n] = copyMap(body)
		} else {
			delete(sw.Overrides, n)
		}
	}
	return nil
}

func port(sw *Switch, n int) *omada.Port {
	for i := range sw.Ports {
		if sw.Ports[i].Port == n {
			return &sw.Ports[i]
		}
	}
	return nil
}

func number(v any) float64 {
	f, _ := v.(float64)
	return f
}

func copyMap(m map[string]any) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}
