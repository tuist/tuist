package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// Exercise the public shell command with a fake API, never cluster credentials.
func TestReplacementGuard(t *testing.T) {
	work := t.TempDir()
	kubectl := filepath.Join(work, "kubectl")
	write(t, kubectl, []byte(`#!/bin/sh
printf '%s\n' "$*" > "$GUARD_CALL"
printf '%s' "$GUARD_FIXTURE"
exit "${GUARD_EXIT:-0}"
`))
	if err := os.Chmod(kubectl, 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", work+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("GUARD_CALL", filepath.Join(work, "call"))
	t.Setenv("GUARD_EXIT", "0")
	t.Setenv("GITHUB_STEP_SUMMARY", filepath.Join(work, "summary"))
	t.Setenv("GITHUB_ACTOR", "qualified-operator")
	desired := regexp.MustCompile(`(?m)^\s+image: (\S+)\s*$`).FindAllSubmatch(read(t, "../k8s/mgmt/tailscale.yaml"), -1)
	if len(desired) != 1 {
		t.Fatal("cannot establish desired image")
	}
	fixture := func(image string, extra string) string {
		return fmt.Sprintf(`{"kind":"DaemonSet","metadata":{"name":"tailscale","namespace":"mgmt-tailscale"},"spec":{"template":{"spec":{"containers":[{"name":"tailscale","image":%q}%s]}}}}`, image, extra)
	}
	for _, test := range []struct {
		name, raw string
		ack, pass bool
	}{
		{"absent requires qualification", "", false, false},
		{"qualified install or migration", "", true, true},
		{"unchanged", fixture(string(desired[0][1]), ""), false, true},
		{"replacement blocked", fixture("old-image", ""), false, false},
		{"qualified replacement", fixture("old-image", ""), true, true},
		{"sidecar changes image set", fixture(string(desired[0][1]), `,{"name":"sidecar","image":"other"}`), false, false},
		{"qualified sidecar", fixture(string(desired[0][1]), `,{"name":"sidecar","image":"other"}`), true, true},
		{"malformed JSON", "{", true, false},
		{"missing containers", `{"kind":"DaemonSet"}`, true, false},
		{"wrong topology", strings.ReplaceAll(fixture(string(desired[0][1]), ""), "DaemonSet", "Deployment"), true, false},
		{"old namespace", strings.ReplaceAll(fixture(string(desired[0][1]), ""), "mgmt-tailscale", "mgmt-system"), true, false},
		{"multiple objects", fixture("old", "") + fixture("old", ""), true, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv("GUARD_FIXTURE", test.raw)
			args := []string{"guard.sh", "management-tailscale"}
			if test.ack {
				args = append(args, "--acknowledged")
			}
			command(t, test.pass, "bash", args...)
			if call := strings.TrimSpace(string(read(t, filepath.Join(work, "call")))); call != "--request-timeout=30s -n mgmt-tailscale get daemonset tailscale --ignore-not-found -o json" {
				t.Fatalf("wrong API boundary: %s", call)
			}
		})
	}
	t.Setenv("GUARD_FIXTURE", "")
	t.Setenv("GUARD_EXIT", "1")
	command(t, false, "bash", "guard.sh", "management-tailscale", "--acknowledged")
	if summary := string(read(t, filepath.Join(work, "summary"))); !strings.Contains(summary, "qualified-operator") || !strings.Contains(summary, string(desired[0][1])) {
		t.Fatalf("missing qualification audit: %s", summary)
	}
	command(t, false, "bash", "guard.sh", "unknown")
	command(t, false, "bash", "guard.sh", "management-tailscale", "--typo")
}

func TestReplacementGuardHCCM(t *testing.T) {
	work := t.TempDir()
	kubectl := filepath.Join(work, "kubectl")
	write(t, kubectl, []byte(`#!/bin/sh
test "$*" = '--request-timeout=30s -n kube-system get deployment hcloud-cloud-controller-manager --ignore-not-found -o json' || exit 2
printf '%s' "$GUARD_FIXTURE"
exit "${GUARD_EXIT:-0}"
`))
	if err := os.Chmod(kubectl, 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", work+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("GITHUB_STEP_SUMMARY", filepath.Join(work, "summary"))
	t.Setenv("GUARD_EXIT", "0")
	tag := regexp.MustCompile(`(?m)^  tag: (\S+)\s*$`).FindAllSubmatch(read(t, "../k8s/mgmt/bootstrap/hccm-values.yaml"), -1)
	if len(tag) != 1 {
		t.Fatal("cannot establish desired HCCM tag")
	}
	fixture := func(image string) string {
		return fmt.Sprintf(`{"kind":"Deployment","metadata":{"name":"hcloud-cloud-controller-manager","namespace":"kube-system"},"spec":{"template":{"spec":{"containers":[{"name":"hcloud-cloud-controller-manager","image":%q}]}}}}`, image)
	}
	t.Setenv("GUARD_FIXTURE", fixture("docker.io/hetznercloud/hcloud-cloud-controller-manager:"+string(tag[0][1])))
	command(t, true, "bash", "guard.sh", "hccm")
	for _, raw := range []string{"", fixture("old-image")} {
		t.Setenv("GUARD_FIXTURE", raw)
		command(t, false, "bash", "guard.sh", "hccm")
		command(t, true, "bash", "guard.sh", "hccm", "--acknowledged")
	}
	for _, raw := range []string{"{", `{"spec":{}}`, strings.ReplaceAll(fixture("old-image"), "Deployment", "DaemonSet")} {
		t.Setenv("GUARD_FIXTURE", raw)
		command(t, false, "bash", "guard.sh", "hccm", "--acknowledged")
	}
	t.Setenv("GUARD_FIXTURE", "")
	t.Setenv("GUARD_EXIT", "1")
	command(t, false, "bash", "guard.sh", "hccm", "--acknowledged")
}
