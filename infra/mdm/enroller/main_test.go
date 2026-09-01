package main

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"howett.net/plist"
)

func testConfig() config {
	return config{
		publicURL:       "https://mdm-staging.tuist.dev",
		nanomdmAPIKey:   "test-key",
		pushTopic:       "com.apple.mgmt.External.test",
		scepChallenge:   "challenge",
		svcShortName:    "tuist",
		svcFullName:     "Tuist Runner Operator",
		svcPasswordHash: []byte("fake-shadow-hash-data"),
		orgName:         "Tuist",
	}
}

func unmarshalPlist(t *testing.T, raw []byte) map[string]any {
	t.Helper()
	var out map[string]any
	if _, err := plist.Unmarshal(raw, &out); err != nil {
		t.Fatalf("unmarshal plist: %v", err)
	}
	return out
}

func TestEnrollProfile(t *testing.T) {
	raw, err := enrollProfile(testConfig())
	if err != nil {
		t.Fatal(err)
	}
	profile := unmarshalPlist(t, raw)
	content, ok := profile["PayloadContent"].([]any)
	if !ok || len(content) != 2 {
		t.Fatalf("expected 2 payloads, got %#v", profile["PayloadContent"])
	}
	scep := content[0].(map[string]any)
	mdm := content[1].(map[string]any)
	if scep["PayloadType"] != "com.apple.security.scep" {
		t.Errorf("first payload is %v", scep["PayloadType"])
	}
	if mdm["ServerURL"] != "https://mdm-staging.tuist.dev/mdm" {
		t.Errorf("ServerURL = %v", mdm["ServerURL"])
	}
	if mdm["IdentityCertificateUUID"] != scep["PayloadUUID"] {
		t.Error("MDM payload does not reference the SCEP payload identity")
	}
	if mdm["SignMessage"] != true {
		t.Error("SignMessage must be true for Mdm-Signature validation")
	}
	scepContent := scep["PayloadContent"].(map[string]any)
	if scepContent["URL"] != "https://mdm-staging.tuist.dev/scep" {
		t.Errorf("SCEP URL = %v", scepContent["URL"])
	}
}

func TestAccountConfigurationCommand(t *testing.T) {
	raw, err := accountConfigurationCommand(testConfig())
	if err != nil {
		t.Fatal(err)
	}
	envelope := unmarshalPlist(t, raw)
	cmd := envelope["Command"].(map[string]any)
	if cmd["RequestType"] != "AccountConfiguration" {
		t.Fatalf("RequestType = %v", cmd["RequestType"])
	}
	if cmd["SkipPrimarySetupAccountCreation"] != true {
		t.Error("SkipPrimarySetupAccountCreation not set")
	}
	accounts := cmd["AutoSetupAdminAccounts"].([]any)
	account := accounts[0].(map[string]any)
	if account["shortName"] != "tuist" {
		t.Errorf("shortName = %v", account["shortName"])
	}
	if string(account["passwordHash"].([]byte)) != "fake-shadow-hash-data" {
		t.Error("passwordHash did not round-trip as plist data")
	}
}

func TestInstallBootstrapPkgManifest(t *testing.T) {
	pkg := []byte("not-a-real-pkg")
	raw, err := installBootstrapPkgCommand(testConfig(), pkg)
	if err != nil {
		t.Fatal(err)
	}
	envelope := unmarshalPlist(t, raw)
	cmd := envelope["Command"].(map[string]any)
	manifest := cmd["Manifest"].(map[string]any)
	items := manifest["items"].([]any)
	assets := items[0].(map[string]any)["assets"].([]any)
	asset := assets[0].(map[string]any)
	if asset["url"] != "https://mdm-staging.tuist.dev/static/bootstrap.pkg" {
		t.Errorf("asset url = %v", asset["url"])
	}
	if asset["md5-size"].(uint64) != uint64(len(pkg)) {
		t.Errorf("md5-size = %v, want %d", asset["md5-size"], len(pkg))
	}
	md5s := asset["md5s"].([]any)
	if len(md5s) != 1 {
		t.Fatalf("expected a single md5 chunk, got %d", len(md5s))
	}
}

func tokenUpdatePayload(t *testing.T, userID string) []byte {
	t.Helper()
	msg := map[string]any{
		"MessageType": "TokenUpdate",
		"UDID":        "test-udid",
		"Topic":       "com.apple.mgmt.External.test",
	}
	if userID != "" {
		msg["UserID"] = userID
	}
	raw, err := plist.MarshalIndent(msg, plist.XMLFormat, "\t")
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func TestWebhookEnrollSequence(t *testing.T) {
	var mu sync.Mutex
	var enqueued []string
	nano := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, pass, _ := r.BasicAuth()
		if user != "nanomdm" || pass != "test-key" {
			t.Errorf("bad basic auth: %s/%s", user, pass)
		}
		mu.Lock()
		enqueued = append(enqueued, r.URL.Path+"?"+r.URL.RawQuery)
		mu.Unlock()
		w.WriteHeader(http.StatusOK)
	}))
	defer nano.Close()

	cfg := testConfig()
	cfg.nanomdmURL = nano.URL
	profile, _ := enrollProfile(cfg)
	usb, _ := usbProfile(cfg)
	s := &server{
		cfg:           cfg,
		nano:          &nanomdmClient{baseURL: nano.URL, apiKey: cfg.nanomdmAPIKey, client: nano.Client()},
		enrollProfile: profile,
		usbProfile:    usb,
		bootstrapPkg:  []byte("pkg"),
	}

	body, _ := json.Marshal(map[string]any{
		"topic": "mdm.TokenUpdate",
		"checkin_event": map[string]any{
			"udid":               "test-udid",
			"enrollment_id":      "test-udid",
			"ids":                map[string]any{"id": "test-udid", "type": "Device"},
			"token_update_tally": 1,
			"raw_payload":        base64.StdEncoding.EncodeToString(tokenUpdatePayload(t, "")),
		},
	})
	req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(string(body)))
	rec := httptest.NewRecorder()
	s.handleWebhook(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("webhook returned %d", rec.Code)
	}

	deadline := time.After(5 * time.Second)
	for {
		mu.Lock()
		n := len(enqueued)
		mu.Unlock()
		if n == 4 {
			break
		}
		select {
		case <-deadline:
			t.Fatalf("expected 4 enqueues, got %d: %v", n, enqueued)
		case <-time.After(10 * time.Millisecond):
		}
	}
	mu.Lock()
	defer mu.Unlock()
	for i, want := range []string{"no_push=1", "no_push=1", "no_push=1", ""} {
		if !strings.HasPrefix(enqueued[i], "/v1/enqueue/test-udid?") {
			t.Errorf("enqueue %d path = %s", i, enqueued[i])
		}
		if got := strings.SplitN(enqueued[i], "?", 2)[1]; got != want {
			t.Errorf("enqueue %d query = %q, want %q", i, got, want)
		}
	}
}

func TestWebhookIgnoresUserChannelAndOtherMessages(t *testing.T) {
	nano := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Errorf("unexpected enqueue: %s", r.URL.Path)
	}))
	defer nano.Close()

	cfg := testConfig()
	s := &server{
		cfg:  cfg,
		nano: &nanomdmClient{baseURL: nano.URL, apiKey: cfg.nanomdmAPIKey, client: nano.Client()},
	}

	tally1 := 1
	tally2 := 2
	for _, event := range []map[string]any{
		// User-channel TokenUpdate.
		{
			"topic": "mdm.TokenUpdate",
			"checkin_event": map[string]any{
				"udid":               "test-udid",
				"ids":                map[string]any{"id": "test-udid:user", "type": "User"},
				"token_update_tally": tally1,
				"raw_payload":        base64.StdEncoding.EncodeToString(tokenUpdatePayload(t, "some-user-id")),
			},
		},
		// Non-TokenUpdate check-in.
		{
			"topic": "mdm.Authenticate",
			"checkin_event": map[string]any{
				"udid":        "test-udid",
				"raw_payload": base64.StdEncoding.EncodeToString([]byte(`<?xml version="1.0"?><plist version="1.0"><dict><key>MessageType</key><string>Authenticate</string></dict></plist>`)),
			},
		},
		// Push-token rotation on an already-configured device.
		{
			"topic": "mdm.TokenUpdate",
			"checkin_event": map[string]any{
				"udid":               "test-udid",
				"ids":                map[string]any{"id": "test-udid", "type": "Device"},
				"token_update_tally": tally2,
				"raw_payload":        base64.StdEncoding.EncodeToString(tokenUpdatePayload(t, "")),
			},
		},
	} {
		body, _ := json.Marshal(event)
		rec := httptest.NewRecorder()
		s.handleWebhook(rec, httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(string(body))))
		if rec.Code != http.StatusOK {
			t.Fatalf("webhook returned %d", rec.Code)
		}
	}
	time.Sleep(100 * time.Millisecond)
}
