package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// Standalone runner and host payload builds must not inherit their compiler
// requirement only from go.work. Grafana owns a separate workspace and gate.
func TestInfrastructureSDKDirectives(t *testing.T) {
	root := filepath.Join("..", "..")
	cmd := exec.Command("git", "ls-files", "go.work", "infra/**/go.mod", "kube-impersonator/go.mod")
	cmd.Dir = root
	output, err := cmd.Output()
	if err != nil {
		t.Fatal(err)
	}
	goDirective := regexp.MustCompile(`(?m)^go ([^\s]+)$`)
	debugDirective := regexp.MustCompile(`(?m)^godebug default=([^\s]+)$`)
	for _, path := range strings.Fields(string(output)) {
		if path == "infra/certificate-trust/go.mod" {
			continue // The independent policy probe uses its own Go 1.26 defaults.
		}
		data, err := os.ReadFile(filepath.Join(root, path))
		if err != nil {
			t.Fatal(err)
		}
		pin := goDirective.FindSubmatch(data)
		if len(pin) != 2 || string(pin[1]) != "1.26.10" {
			t.Errorf("%s must require behaviorally qualified Go 1.26.10", path)
		}
		baseline := "go1.25"
		if path == "kube-impersonator/go.mod" {
			baseline = "go1.23"
		}
		defaults := debugDirective.FindSubmatch(data)
		if len(defaults) != 2 || string(defaults[1]) != baseline {
			t.Errorf("%s must retain %s runtime compatibility defaults", path, baseline)
		}
	}
}
