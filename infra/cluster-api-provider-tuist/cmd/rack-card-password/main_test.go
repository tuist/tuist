package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackcard"
)

const testKey = "tuist-rack-card-test-root-key-0001"

func writeSite(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	site := `{"site": "ber1", "nodes": [
		{"name": "ber1-pdu-b", "hardware": "evmafc20a", "mac": "00:20:85:B8:0E:3E"},
		{"name": "ber1-ats-2", "hardware": "eats16n", "mac": null},
		{"name": "ber1-tor-a", "hardware": "sx3832", "mac": "aa:bb:cc:dd:ee:ff"}
	]}`
	if err := os.WriteFile(filepath.Join(dir, "ber1.json"), []byte(site), 0o600); err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestPrintsTheDerivedPassword(t *testing.T) {
	sites := writeSite(t)
	for _, tc := range []struct {
		device, role, want string
	}{
		{"ber1-pdu-b", "admin", "Rc7-HERuBCixknqapWIZvsFr"},
		{"ber1-pdu-b", "controller", "Rc7-coXAEWWfo6ZbyOuQ2oIJ"},
		{"ber1-ats-2", "admin", "Rc7-GtFNo2vCP1IoZOXtB1bn"},
	} {
		var out bytes.Buffer
		err := run([]string{"--site", "ber1", "--device", tc.device, "--role", tc.role, "--sites", sites}, strings.NewReader(testKey+"\n"), &out)
		if err != nil {
			t.Fatalf("%s %s: %v", tc.device, tc.role, err)
		}
		if out.String() != tc.want+"\n" {
			t.Fatalf("%s %s printed %q, want %q", tc.device, tc.role, out.String(), tc.want)
		}
	}
	// The same derivation the controller uses.
	if got := rackcard.Password([]byte(testKey), "ber1", "00:20:85:b8:0e:3e", rackcard.RoleAdmin); got != "Rc7-HERuBCixknqapWIZvsFr" {
		t.Fatalf("rackcard.Password = %q", got)
	}
}

func TestRefusesWhatIsNotARackCard(t *testing.T) {
	sites := writeSite(t)
	for name, args := range map[string][]string{
		"an unknown device":  {"--site", "ber1", "--device", "ber1-pdu-z", "--role", "admin"},
		"a switch":           {"--site", "ber1", "--device", "ber1-tor-a", "--role", "admin"},
		"an unknown role":    {"--site", "ber1", "--device", "ber1-pdu-b", "--role", "root"},
		"an unknown site":    {"--site", "ber9", "--device", "ber1-pdu-b", "--role", "admin"},
		"no device":          {"--site", "ber1", "--role", "admin"},
		"a key on the flags": {"--site", "ber1", "--device", "ber1-pdu-b", "--role", "admin", testKey},
	} {
		var out bytes.Buffer
		if err := run(append(args, "--sites", sites), strings.NewReader(testKey), &out); err == nil {
			t.Fatalf("%s: printed %q, want an error", name, out.String())
		}
		if strings.Contains(out.String(), testKey) {
			t.Fatalf("%s: printed the root key", name)
		}
	}
	var out bytes.Buffer
	if err := run([]string{"--site", "ber1", "--device", "ber1-pdu-b", "--role", "admin", "--sites", sites}, strings.NewReader("short\n"), &out); err == nil {
		t.Fatal("took a root key shorter than the minimum")
	}
}
