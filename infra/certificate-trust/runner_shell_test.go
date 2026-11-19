package main

import (
	"bytes"
	"encoding/json"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

func TestRunnerShellEmbeddedPolicyAndFactories(t *testing.T) {
	var policy struct {
		Hashes []string `json:"distrusted_spki_sha256"`
	}
	if err := json.Unmarshal(policyJSON, &policy); err != nil || len(policy.Hashes) != 12 {
		t.Fatal("invalid canonical policy", err)
	}
	for i, hash := range policy.Hashes {
		policy.Hashes[i] = `"` + hash + `"`
	}
	slices.Sort(policy.Hashes)
	mac, linux := "../runner-image/cmd/runner-shell-agent", "../linux-runner-image/cmd/runner-shell-agent"
	for _, root := range []string{mac, linux} {
		embedded := regexp.MustCompile(`"[0-9a-f]{64}"`).FindAllString(string(read(t, filepath.Join(root, "certificate_trust.go"))), -1)
		slices.Sort(embedded)
		if !slices.Equal(embedded, policy.Hashes) {
			t.Fatalf("embedded runner policy differs from canonical policy: %s", root)
		}
		for _, fixture := range []string{"issuer-roots.pem", "distrusted-intermediates.pem"} {
			if !bytes.Equal(read(t, filepath.Join(root, "testdata/certificate-trust", fixture)), read(t, filepath.Join("controls", fixture))) {
				t.Fatalf("runner fixture differs from canonical DER: %s", root)
			}
		}
	}
	for _, name := range []string{"main.go", "certificate_trust.go", "certificate_trust_test.go", "certificate_trust_diagnostics_test.go"} {
		if !bytes.Equal(read(t, filepath.Join(mac, name)), read(t, filepath.Join(linux, name))) {
			t.Fatalf("runner shell copies differ: %s", name)
		}
	}
	// Bounded factory inventory; wire tests separately exercise validation and delivery.
	source := string(read(t, filepath.Join(mac, "main.go")))
	for _, required := range []string{"TLSClientConfig: runnerTLSConfig()", "CheckRedirect: secureRedirect", "return connectWebSocketWithTLS(rawURL, token, runnerTLSConfig())", "config, err := certificateTrustConfig(config, nil)", "TLSClientConfig:  config", "refusing secure session downgrade"} {
		if !strings.Contains(source, required) {
			t.Fatalf("missing protected runner factory: %s", required)
		}
	}
	for _, factory := range []string{"&http.Client{", "&http.Transport{", "&websocket.Dialer{"} {
		if strings.Count(source, factory) != 1 {
			t.Fatalf("review new independent runner factory: %s", factory)
		}
	}
	for _, bypass := range []string{"http.DefaultClient", "websocket.DefaultDialer", "DialTLS:", "DialTLSContext:", "NetDialTLSContext:", "InsecureSkipVerify", "TLSClientConfig: &tls.Config"} {
		if strings.Contains(source, bypass) {
			t.Fatalf("review unprotected runner transport: %s", bypass)
		}
	}
}
