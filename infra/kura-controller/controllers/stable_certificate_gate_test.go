package controllers

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestStableCertificatePromotionGate(t *testing.T) {
	if _, err := exec.LookPath("jq"); err != nil {
		t.Fatal("jq is required for the certificate gate tests")
	}
	_, file, _, _ := runtime.Caller(0)
	script := filepath.Join(filepath.Dir(file), "..", "..", "cache-dns", "wait-for-certificate.sh")
	settings := `{"kuraController":{"enabled":true,"stableDNS":{"enabled":true},"namespace":"kura","publicWildcardCertificate":{"secretName":"kura-public-wildcard-tls"}}}`
	ready := `{"metadata":{"generation":2},"spec":{"dnsNames":["*.kura.tuist.dev","*.cache.tuist.dev"]},"status":{"conditions":[{"type":"Ready","status":"True","observedGeneration":2}]}}`
	for _, tc := range []struct {
		name, settings, first, next string
		wantOK, wantWait            bool
	}{
		{name: "disabled", settings: `{"kuraController":{"enabled":true,"stableDNS":{"enabled":false}}}`, wantOK: true},
		{name: "current certificate", settings: settings, first: ready, wantOK: true},
		{name: "old hostname set", settings: settings, first: strings.ReplaceAll(ready, `,"*.cache.tuist.dev"`, ""), wantWait: true},
		{name: "stale ready condition", settings: settings, first: strings.ReplaceAll(ready, `"observedGeneration":2`, `"observedGeneration":1`), wantWait: true},
		{name: "issuance pending", settings: settings, first: strings.ReplaceAll(ready, `"status":"True"`, `"status":"False"`), wantWait: true},
		{name: "wait for current generation", settings: settings, first: `{}`, next: ready, wantOK: true, wantWait: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			commands := map[string]string{
				"helm":    "printf '%s\\n' \"$TEST_SETTINGS\"\n",
				"kubectl": "if [ -e \"$TEST_DIR/polled\" ]; then printf '%s\\n' \"$TEST_NEXT_CERT\"; else touch \"$TEST_DIR/polled\"; printf '%s\\n' \"$TEST_FIRST_CERT\"; fi\n",
				"sleep":   "touch \"$TEST_DIR/slept\"\n[ \"$TEST_STOP_WAIT\" != true ]\n",
			}
			for name, body := range commands {
				if err := os.WriteFile(filepath.Join(dir, name), []byte("#!/bin/sh\n"+body), 0755); err != nil {
					t.Fatal(err)
				}
			}
			stop := "true"
			if tc.next != "" {
				stop = "false"
			}
			cmd := exec.Command("bash", script)
			cmd.Env = append(os.Environ(), "PATH="+dir+string(os.PathListSeparator)+os.Getenv("PATH"), "HELM_RELEASE_NAME=tuist", "NAMESPACE=tuist-canary", "TEST_DIR="+dir, "TEST_SETTINGS="+tc.settings, "TEST_FIRST_CERT="+tc.first, "TEST_NEXT_CERT="+tc.next, "TEST_STOP_WAIT="+stop)
			output, err := cmd.CombinedOutput()
			if (err == nil) != tc.wantOK {
				t.Fatalf("success=%v want=%v: %s", err == nil, tc.wantOK, output)
			}
			_, err = os.Stat(filepath.Join(dir, "slept"))
			if (err == nil) != tc.wantWait {
				t.Fatalf("waited=%v want=%v: %s", err == nil, tc.wantWait, output)
			}
		})
	}
}
