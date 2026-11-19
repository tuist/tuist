package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

func TestLogShipperEmbeddedPolicyAndFactories(t *testing.T) {
	var policy struct {
		ID     string   `json:"id"`
		Hashes []string `json:"distrusted_spki_sha256"`
	}
	if err := json.Unmarshal(policyJSON, &policy); err != nil || len(policy.Hashes) != 12 {
		t.Fatal("invalid canonical policy", err)
	}
	for i, hash := range policy.Hashes {
		policy.Hashes[i] = `"` + hash + `"`
	}
	slices.Sort(policy.Hashes)
	root := "../macos-log-shipper"
	trust := string(read(t, filepath.Join(root, "internal/shipper/certificate_trust.go")))
	embedded := regexp.MustCompile(`"[0-9a-f]{64}"`).FindAllString(trust, -1)
	slices.Sort(embedded)
	if !slices.Equal(embedded, policy.Hashes) || !strings.Contains(trust, `const certificateTrustPolicy = "`+policy.ID+`"`) {
		t.Fatal("embedded log shipper policy differs from canonical policy")
	}
	for _, fixture := range []string{"issuer-roots.pem", "distrusted-intermediates.pem"} {
		if !bytes.Equal(read(t, filepath.Join(root, "internal/shipper/testdata/certificate-trust", fixture)), read(t, filepath.Join("controls", fixture))) {
			t.Fatalf("log shipper fixture differs from canonical DER: %s", fixture)
		}
	}
	for path, required := range map[string][]string{
		"internal/shipper/dial.go":      {"certificateTrustClient(&http.Client{", "dialContextVia(magicDNSResolver("},
		"internal/shipper/loki.go":      {"certificateTrustClient(nil, nil)", "client.Do(req)", "privatePushFailure(err)"},
		"cmd/tuist-log-shipper/main.go": {"shipper.NewClient(url, 30*time.Second)", "defer client.CloseIdleConnections()"},
	} {
		for _, marker := range required {
			if !bytes.Contains(read(t, filepath.Join(root, path)), []byte(marker)) {
				t.Fatalf("missing protected log shipper factory in %s: %s", path, marker)
			}
		}
	}
	// Bounded factory inventory; wire tests separately exercise validation and delivery.
	clients, transports, requests := 0, 0, 0
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		source := string(read(t, path))
		clients += strings.Count(source, "http.Client{")
		transports += strings.Count(source, "http.Transport{")
		requests += strings.Count(source, ".Do(req)")
		for _, bypass := range []string{"http.Get(", "http.Post("} {
			if strings.Contains(source, bypass) {
				t.Fatalf("review unprotected log shipper transport: %s in %s", bypass, path)
			}
		}
		if filepath.Base(path) != "certificate_trust.go" && (strings.Contains(source, "http.DefaultTransport") || strings.Contains(source, "http.DefaultClient")) {
			t.Fatalf("default transport bypass in %s", path)
		}
		return nil
	})
	if err != nil || clients != 1 || transports != 1 || requests != 1 {
		t.Fatal("review new independent log shipper factories/requests", err)
	}
}
