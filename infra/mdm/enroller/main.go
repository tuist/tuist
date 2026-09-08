// mdm-enroller is the enrollment brain sitting next to NanoMDM. NanoMDM
// speaks the raw MDM protocol but takes no actions of its own; this
// service supplies the three pieces our zero-touch flow needs:
//
//   - GET /enroll: serves the ADE enrollment profile (SCEP + MDM payloads)
//     that the DEP profile's `url` points at.
//   - GET /static/bootstrap.pkg: serves the signed bootstrap package
//     referenced by the InstallEnterpriseApplication manifest.
//   - POST /webhook: receives NanoMDM's check-in webhook and, on a
//     device-channel TokenUpdate, enqueues the fixed on-enroll command
//     sequence: AccountConfiguration, InstallProfile (USB accessories),
//     InstallEnterpriseApplication (bootstrap pkg), DeviceConfigured.
//
// The device holds in "awaiting configuration" (await_device_configured
// in the DEP profile) until DeviceConfigured lands, so the sequence runs
// before anyone could interact with the machine. The webhook's
// token_update_tally distinguishes the enrollment TokenUpdate (tally 1)
// from later push-token rotations, which are ignored.
package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/md5"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"howett.net/plist"
)

type config struct {
	listen          string
	publicURL       string
	nanomdmURL      string
	nanomdmAPIKey   string
	pushTopic       string
	scepChallenge   string
	enrollToken     string
	webhookHMACKey  string
	svcShortName    string
	svcFullName     string
	svcPasswordHash []byte
	assetsDir       string
	orgName         string
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func loadConfig() (config, error) {
	c := config{
		listen:         envOr("ENROLLER_LISTEN", ":9004"),
		publicURL:      strings.TrimRight(os.Getenv("ENROLLER_PUBLIC_URL"), "/"),
		nanomdmURL:     strings.TrimRight(envOr("ENROLLER_NANOMDM_URL", "http://localhost:9000"), "/"),
		nanomdmAPIKey:  os.Getenv("ENROLLER_NANOMDM_API_KEY"),
		pushTopic:      os.Getenv("ENROLLER_PUSH_TOPIC"),
		scepChallenge:  os.Getenv("ENROLLER_SCEP_CHALLENGE"),
		enrollToken:    os.Getenv("ENROLLER_ENROLL_TOKEN"),
		webhookHMACKey: os.Getenv("ENROLLER_WEBHOOK_HMAC_KEY"),
		svcShortName:   envOr("ENROLLER_SVC_ACCOUNT_SHORTNAME", "tuist"),
		svcFullName:    envOr("ENROLLER_SVC_ACCOUNT_FULLNAME", "Tuist Runner Operator"),
		assetsDir:      envOr("ENROLLER_ASSETS_DIR", "/assets"),
		orgName:        envOr("ENROLLER_ORG_NAME", "Tuist"),
	}
	if c.publicURL == "" {
		return c, fmt.Errorf("ENROLLER_PUBLIC_URL is required")
	}
	if c.nanomdmAPIKey == "" {
		return c, fmt.Errorf("ENROLLER_NANOMDM_API_KEY is required")
	}
	if h := os.Getenv("ENROLLER_SVC_ACCOUNT_PASSWORD_HASH_B64"); h != "" {
		decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(h))
		if err != nil {
			return c, fmt.Errorf("decoding ENROLLER_SVC_ACCOUNT_PASSWORD_HASH_B64: %w", err)
		}
		c.svcPasswordHash = decoded
	}
	return c, nil
}

// loadBootstrapPkg returns the signed bootstrap package bytes, or nil if
// the asset has not been provided yet. The package reaches the cluster
// as a base64 1Password field synced by ESO, so the .b64 form is the
// normal one; a raw file is accepted for local runs.
func loadBootstrapPkg(assetsDir string) []byte {
	if b, err := os.ReadFile(filepath.Join(assetsDir, "bootstrap.pkg.b64")); err == nil {
		decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(b)))
		if err != nil {
			log.Printf("bootstrap.pkg.b64 present but not valid base64: %v", err)
			return nil
		}
		return decoded
	}
	if b, err := os.ReadFile(filepath.Join(assetsDir, "bootstrap.pkg")); err == nil {
		return b
	}
	return nil
}

// Static payload UUIDs: the enrollment profile is regenerated per
// request and macOS treats a changed PayloadUUID as a different
// profile, so these must not vary between requests or restarts.
const (
	scepPayloadUUID   = "5A1C74F8-0000-4000-8000-746973740001"
	mdmPayloadUUID    = "5A1C74F8-0000-4000-8000-746973740002"
	enrollProfileUUID = "5A1C74F8-0000-4000-8000-746973740003"
	usbPayloadUUID    = "5A1C74F8-0000-4000-8000-746973740004"
	usbProfileUUID    = "5A1C74F8-0000-4000-8000-746973740005"
)

func enrollProfile(c config) ([]byte, error) {
	scep := map[string]any{
		"PayloadType":        "com.apple.security.scep",
		"PayloadVersion":     1,
		"PayloadIdentifier":  "dev.tuist.mdm.scep",
		"PayloadUUID":        scepPayloadUUID,
		"PayloadDisplayName": "MDM identity (SCEP)",
		"PayloadContent": map[string]any{
			"URL":       c.publicURL + "/scep",
			"Name":      "tuist-mdm-ca",
			"Challenge": c.scepChallenge,
			"Key Type":  "RSA",
			"Key Usage": 5,
			"Keysize":   2048,
			// %HardwareUUID% is substituted by the device as it installs the
			// profile, so every Mac requests a distinct subject. A shared
			// subject is rejected outright by the SCEP CA for every device
			// after the first ("DN ... already exists"), because its renewal
			// policy treats a duplicate DN as a renewal and refuses one until
			// the existing certificate is nearly expired.
			"Subject": [][][]string{
				{{"CN", "tuist-fleet-%HardwareUUID%"}},
			},
		},
	}
	mdm := map[string]any{
		"PayloadType":             "com.apple.mdm",
		"PayloadVersion":          1,
		"PayloadIdentifier":       "dev.tuist.mdm.mdm",
		"PayloadUUID":             mdmPayloadUUID,
		"PayloadDisplayName":      "Tuist MDM",
		"ServerURL":               c.publicURL + "/mdm",
		"CheckInURL":              c.publicURL + "/mdm",
		"Topic":                   c.pushTopic,
		"IdentityCertificateUUID": scepPayloadUUID,
		"AccessRights":            8191,
		// per-user-connections is required to manage macOS at all, and
		// bootstraptoken is what lets the device escrow a bootstrap token on
		// the service account's first GUI login. Neither can be added to an
		// enrolled device later: Apple rejects a payload update that changes
		// per-user-connections, so a device enrolled without it has to be
		// re-enrolled.
		"ServerCapabilities": []string{
			"com.apple.mdm.per-user-connections",
			"com.apple.mdm.bootstraptoken",
		},
		"SignMessage":         true,
		"CheckOutWhenRemoved": true,
	}
	profile := map[string]any{
		"PayloadType":         "Configuration",
		"PayloadVersion":      1,
		"PayloadIdentifier":   "dev.tuist.mdm.enroll",
		"PayloadUUID":         enrollProfileUUID,
		"PayloadDisplayName":  "Tuist MDM enrollment",
		"PayloadOrganization": c.orgName,
		"PayloadScope":        "System",
		"PayloadContent":      []any{scep, mdm},
	}
	return plist.MarshalIndent(profile, plist.XMLFormat, "\t")
}

// usbProfile auto-allows new USB accessories. Mac desktops (the minis)
// do not prompt for accessories today, but Mac laptops do and macOS 26
// extends previously-approved-accessory handling into Recovery; the
// payload is harmless where it does not apply and load-bearing for the
// KVM/DFU cabling where it does. allowUSBRestrictedMode=false disables
// restricted mode, i.e. always allow. Requires a supervised device;
// ADE enrollment qualifies.
func usbProfile(c config) ([]byte, error) {
	restrictions := map[string]any{
		"PayloadType":            "com.apple.applicationaccess",
		"PayloadVersion":         1,
		"PayloadIdentifier":      "dev.tuist.mdm.usb.restrictions",
		"PayloadUUID":            usbPayloadUUID,
		"PayloadDisplayName":     "Allow USB accessories",
		"allowUSBRestrictedMode": false,
	}
	profile := map[string]any{
		"PayloadType":         "Configuration",
		"PayloadVersion":      1,
		"PayloadIdentifier":   "dev.tuist.mdm.usb",
		"PayloadUUID":         usbProfileUUID,
		"PayloadDisplayName":  "Tuist fleet: allow USB accessories",
		"PayloadOrganization": c.orgName,
		"PayloadScope":        "System",
		"PayloadContent":      []any{restrictions},
	}
	return plist.MarshalIndent(profile, plist.XMLFormat, "\t")
}

func newCommandUUID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func commandPlist(requestType string, fields map[string]any) ([]byte, error) {
	command := map[string]any{"RequestType": requestType}
	for k, v := range fields {
		command[k] = v
	}
	envelope := map[string]any{
		"CommandUUID": newCommandUUID(),
		"Command":     command,
	}
	return plist.MarshalIndent(envelope, plist.XMLFormat, "\t")
}

func accountConfigurationCommand(c config) ([]byte, error) {
	return commandPlist("AccountConfiguration", map[string]any{
		"SkipPrimarySetupAccountCreation": true,
		"AutoSetupAdminAccounts": []map[string]any{{
			"shortName":    c.svcShortName,
			"fullName":     c.svcFullName,
			"passwordHash": c.svcPasswordHash,
			"hidden":       false,
		}},
	})
}

func installProfileCommand(profile []byte) ([]byte, error) {
	return commandPlist("InstallProfile", map[string]any{
		"Payload": profile,
	})
}

// installBootstrapPkgCommand uses an inline Manifest (macOS 10.13.6+)
// so no separate manifest plist has to be hosted; the whole package is
// one MD5 chunk. The asset URL must be reachable by the device over
// public HTTPS.
func installBootstrapPkgCommand(c config, pkg []byte) ([]byte, error) {
	sum := md5.Sum(pkg)
	return commandPlist("InstallEnterpriseApplication", map[string]any{
		"Manifest": map[string]any{
			"items": []map[string]any{{
				"assets": []map[string]any{{
					"kind":     "software-package",
					"url":      c.publicURL + "/static/bootstrap.pkg",
					"md5-size": len(pkg),
					"md5s":     []string{hex.EncodeToString(sum[:])},
				}},
			}},
		},
	})
}

type nanomdmClient struct {
	baseURL string
	apiKey  string
	client  *http.Client
}

func (n *nanomdmClient) enqueue(id string, cmd []byte, noPush bool) error {
	u := n.baseURL + "/v1/enqueue/" + id
	if noPush {
		// NanoMDM reads "nopush"; "no_push" is silently ignored and every
		// command sends a push. An APNs failure on an intermediate command
		// then aborts the sequence before DeviceConfigured, stranding the
		// device in Setup Assistant.
		u += "?nopush=1"
	}
	req, err := http.NewRequest(http.MethodPut, u, bytes.NewReader(cmd))
	if err != nil {
		return err
	}
	req.SetBasicAuth("nanomdm", n.apiKey)
	resp, err := n.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode >= 300 {
		return fmt.Errorf("enqueue to %s: HTTP %d: %s", u, resp.StatusCode, body)
	}
	return nil
}

type server struct {
	cfg           config
	nano          *nanomdmClient
	enrollProfile []byte
	usbProfile    []byte
	bootstrapPkg  []byte

	// Enroll sequences run outside the request, because NanoMDM's webhook
	// is fire-and-forget and holding it open buys nothing. Shutdown waits
	// on this so a rollout mid-sequence does not strand a device at
	// "awaiting configuration", which NanoMDM will never retry.
	inFlight sync.WaitGroup
}

func skipIf(cond bool, reason string) string {
	if cond {
		return reason
	}
	return ""
}

// webhookEvent is the subset of NanoMDM's webhook body we care about
// (schema: service/webhook/event.json in the nanomdm repo).
type webhookEvent struct {
	Topic        string `json:"topic"`
	CheckinEvent *struct {
		UDID         string `json:"udid"`
		EnrollmentID string `json:"enrollment_id"`
		IDs          *struct {
			ID   string `json:"id"`
			Type string `json:"type"`
		} `json:"ids"`
		TokenUpdateTally *int   `json:"token_update_tally"`
		RawPayload       []byte `json:"raw_payload"`
	} `json:"checkin_event"`
}

type checkinMessage struct {
	MessageType string `plist:"MessageType"`
	UserID      string `plist:"UserID"`
}

func (s *server) handleWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		http.Error(w, "read error", http.StatusBadRequest)
		return
	}
	if s.cfg.webhookHMACKey != "" {
		mac := hmac.New(sha256.New, []byte(s.cfg.webhookHMACKey))
		mac.Write(body)
		want := base64.StdEncoding.EncodeToString(mac.Sum(nil))
		got := r.Header.Get("X-Hmac-Signature")
		if got == "" || !hmac.Equal([]byte(want), []byte(got)) {
			http.Error(w, "bad signature", http.StatusUnauthorized)
			return
		}
	}
	var event webhookEvent
	if err := json.Unmarshal(body, &event); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	// Always ack; NanoMDM does not retry webhooks and a non-2xx only
	// makes noise in its logs.
	w.WriteHeader(http.StatusOK)

	ce := event.CheckinEvent
	if event.Topic != "mdm.TokenUpdate" || ce == nil {
		return
	}
	// Only the device channel's TokenUpdate starts the sequence. The
	// ids block carries the channel; fall back to sniffing UserID out
	// of the raw check-in for webhook formats without it.
	if ce.IDs != nil {
		if ce.IDs.Type != "Device" {
			return
		}
	} else {
		var msg checkinMessage
		if _, err := plist.Unmarshal(ce.RawPayload, &msg); err != nil {
			log.Printf("webhook: cannot parse check-in payload: %v", err)
			return
		}
		if msg.MessageType != "TokenUpdate" || msg.UserID != "" {
			return
		}
	}
	id := ce.EnrollmentID
	if id == "" && ce.IDs != nil {
		id = ce.IDs.ID
	}
	if id == "" {
		id = ce.UDID
	}
	if id == "" {
		log.Printf("webhook: TokenUpdate without an enrollment id")
		return
	}
	// Only tally 1 is the enrollment TokenUpdate. A missing tally is
	// treated as "not an enrollment" rather than "probably one": replaying
	// the sequence re-runs AccountConfiguration and the bootstrap
	// postinstall against a machine already in service, so the failure
	// mode of guessing wrong is worse in that direction than in the other,
	// where the remedy is re-enrolling a device that never finished.
	if ce.TokenUpdateTally == nil {
		log.Printf("webhook: TokenUpdate for %s carries no tally; refusing to assume this is an enrollment", id)
		return
	}
	if *ce.TokenUpdateTally != 1 {
		log.Printf("webhook: TokenUpdate tally %d for %s, not an enrollment; skipping", *ce.TokenUpdateTally, id)
		return
	}

	s.inFlight.Add(1)
	go func() {
		defer s.inFlight.Done()
		s.runEnrollSequence(id)
	}()
}

func (s *server) runEnrollSequence(id string) {
	log.Printf("enroll sequence for %s: starting", id)
	type step struct {
		name  string
		build func() ([]byte, error)
		skip  string
	}
	// Each step carries its own precondition. Binding them positionally
	// meant a reorder could silently suppress AccountConfiguration or aim
	// the package guard at the wrong command.
	steps := []step{
		{
			name:  "AccountConfiguration",
			build: func() ([]byte, error) { return accountConfigurationCommand(s.cfg) },
			skip:  skipIf(len(s.cfg.svcPasswordHash) == 0, "no service-account password hash configured"),
		},
		{
			name:  "InstallProfile(usb)",
			build: func() ([]byte, error) { return installProfileCommand(s.usbProfile) },
		},
		{
			name:  "InstallEnterpriseApplication(bootstrap)",
			build: func() ([]byte, error) { return installBootstrapPkgCommand(s.cfg, s.bootstrapPkg) },
			skip:  skipIf(len(s.bootstrapPkg) == 0, "no bootstrap package present in the assets secret"),
		},
		{
			name:  "DeviceConfigured",
			build: func() ([]byte, error) { return commandPlist("DeviceConfigured", nil) },
		},
	}
	for i, st := range steps {
		if st.skip != "" {
			log.Printf("enroll sequence for %s: SKIPPING %s: %s", id, st.name, st.skip)
			continue
		}
		cmd, err := st.build()
		if err != nil {
			log.Printf("enroll sequence for %s: building %s: %v", id, st.name, err)
			return
		}
		// The device is polling while it awaits configuration, so only
		// the final command carries a push (which covers the
		// re-enrollment case where it is not).
		noPush := i < len(steps)-1
		if err := s.nano.enqueue(id, cmd, noPush); err != nil {
			log.Printf("enroll sequence for %s: enqueue %s: %v", id, st.name, err)
			return
		}
		log.Printf("enroll sequence for %s: enqueued %s", id, st.name)
	}
}

func (s *server) handleEnroll(w http.ResponseWriter, r *http.Request) {
	// Constant time: this endpoint is internet-facing and the profile it
	// returns carries the SCEP challenge, so a timing oracle on the token
	// would hand over the ability to enrol.
	if s.cfg.enrollToken != "" {
		got := []byte(r.URL.Query().Get("token"))
		want := []byte(s.cfg.enrollToken)
		if subtle.ConstantTimeCompare(got, want) != 1 {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
	}
	w.Header().Set("Content-Type", "application/x-apple-aspen-config")
	w.Header().Set("Content-Disposition", `attachment; filename="tuist-enroll.mobileconfig"`)
	w.Write(s.enrollProfile)
}

func (s *server) handlePkg(w http.ResponseWriter, r *http.Request) {
	if len(s.bootstrapPkg) == 0 {
		http.Error(w, "bootstrap package not provisioned", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Write(s.bootstrapPkg)
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatal(err)
	}
	if cfg.pushTopic == "" {
		log.Printf("WARNING: ENROLLER_PUSH_TOPIC is empty; the enrollment profile is not usable until the APNs ceremony has run")
	}
	profile, err := enrollProfile(cfg)
	if err != nil {
		log.Fatal(err)
	}
	usb, err := usbProfile(cfg)
	if err != nil {
		log.Fatal(err)
	}
	pkg := loadBootstrapPkg(cfg.assetsDir)
	if pkg == nil {
		log.Printf("WARNING: no bootstrap package in %s; InstallEnterpriseApplication will be skipped", cfg.assetsDir)
	}

	s := &server{
		cfg:           cfg,
		nano:          &nanomdmClient{baseURL: cfg.nanomdmURL, apiKey: cfg.nanomdmAPIKey, client: &http.Client{Timeout: 30 * time.Second}},
		enrollProfile: profile,
		usbProfile:    usb,
		bootstrapPkg:  pkg,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("ok")) })
	mux.HandleFunc("/enroll", s.handleEnroll)
	mux.HandleFunc("/static/bootstrap.pkg", s.handlePkg)
	mux.HandleFunc("/webhook", s.handleWebhook)

	srv := &http.Server{Addr: cfg.listen, Handler: mux}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)

	go func() {
		log.Printf("mdm-enroller listening on %s", cfg.listen)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()

	<-stop
	log.Printf("shutting down; waiting for in-flight enroll sequences")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("http shutdown: %v", err)
	}

	// A device held at "awaiting configuration" is only released by
	// DeviceConfigured, and NanoMDM does not retry a webhook it has
	// already delivered, so exiting mid-sequence strands that machine
	// until a human notices. Wait, bounded by the pod's grace period.
	done := make(chan struct{})
	go func() {
		s.inFlight.Wait()
		close(done)
	}()
	select {
	case <-done:
		log.Printf("in-flight enroll sequences finished")
	case <-time.After(25 * time.Second):
		log.Printf("WARNING: gave up waiting on in-flight enroll sequences; a device may be stranded at awaiting-configuration")
	}
}
