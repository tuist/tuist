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

func TestCacheVolumeEmbeddedPolicyAndFactories(t *testing.T) {
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
	root := "../linux-runner-image/cmd/tuist-cache-volume"
	embedded := regexp.MustCompile(`"[0-9a-f]{64}"`).FindAllString(string(read(t, filepath.Join(root, "certificate_trust.go"))), -1)
	slices.Sort(embedded)
	if !slices.Equal(embedded, policy.Hashes) {
		t.Fatal("embedded cache-volume policy differs from canonical policy")
	}
	for _, fixture := range []string{"issuer-roots.pem", "distrusted-intermediates.pem"} {
		if !bytes.Equal(read(t, filepath.Join(root, "testdata/certificate-trust", fixture)), read(t, filepath.Join("controls", fixture))) {
			t.Fatalf("cache-volume fixture differs from canonical DER: %s", fixture)
		}
	}
	for path, required := range map[string][]string{
		"main.go":              {"newCacheHTTPClient(30 * time.Second)"},
		"linux_checkout.go":    {"newCacheHTTPClient(timeout)"},
		"docker_cache.go":      {"newCacheHTTPClient(timeout)"},
		"certificate_trust.go": {"certificateTrustTransport(base, additionalBlocked)", "Transport: transport", "return http.ErrUseLastResponse"},
	} {
		for _, marker := range required {
			if !bytes.Contains(read(t, filepath.Join(root, path)), []byte(marker)) {
				t.Fatalf("missing protected cache-volume factory in %s: %s", path, marker)
			}
		}
	}
	// Bounded factory inventory; wire tests separately exercise validation and delivery.
	paths, err := filepath.Glob(filepath.Join(root, "*.go"))
	if err != nil {
		t.Fatal(err)
	}
	clients, requests := 0, 0
	for _, path := range paths {
		if strings.HasSuffix(path, "_test.go") {
			continue
		}
		source := string(read(t, path))
		clients += strings.Count(source, "http.Client{")
		requests += strings.Count(source, ".Do(req)")
		for _, bypass := range []string{"http.DefaultClient", "http.Get(", "http.Post(", "http.Transport{", "attachWithClient(", "attachWithMounter("} {
			if strings.Contains(source, bypass) {
				t.Fatalf("review unprotected cache-volume transport: %s in %s", bypass, path)
			}
		}
		if filepath.Base(path) != "certificate_trust.go" && strings.Contains(source, "http.DefaultTransport") {
			t.Fatalf("default transport bypass in %s", path)
		}
	}
	if clients != 1 || requests != 3 {
		t.Fatal("review new independent cache-volume factories/requests")
	}
}
