package main

import (
	"fmt"
	"os"
	"os/exec"
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
		ack       bool
		status    int
	}{
		{"absent requires qualification", "", false, 3},
		{"qualified install or migration", "", true, 0},
		{"unchanged", fixture(string(desired[0][1]), ""), false, 0},
		{"replacement blocked", fixture("old-image", ""), false, 3},
		{"qualified replacement", fixture("old-image", ""), true, 0},
		{"sidecar changes image set", fixture(string(desired[0][1]), `,{"name":"sidecar","image":"other"}`), false, 3},
		{"qualified sidecar", fixture(string(desired[0][1]), `,{"name":"sidecar","image":"other"}`), true, 0},
		{"malformed JSON", "{", true, 1},
		{"missing containers", `{"kind":"DaemonSet"}`, true, 1},
		{"wrong topology", strings.ReplaceAll(fixture(string(desired[0][1]), ""), "DaemonSet", "Deployment"), true, 1},
		{"old namespace", strings.ReplaceAll(fixture(string(desired[0][1]), ""), "mgmt-tailscale", "mgmt-system"), true, 1},
		{"multiple objects", fixture("old", "") + fixture("old", ""), true, 1},
	} {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv("GUARD_FIXTURE", test.raw)
			args := []string{"guard.sh", "management-tailscale"}
			if test.ack {
				args = append(args, "--acknowledged")
			}
			cmd := exec.Command("bash", args...)
			output, err := cmd.CombinedOutput()
			if cmd.ProcessState == nil || cmd.ProcessState.ExitCode() != test.status {
				t.Fatalf("expected status %d: %v\n%s", test.status, err, output)
			}
			if call := strings.TrimSpace(string(read(t, filepath.Join(work, "call")))); call != "--request-timeout=30s -n mgmt-tailscale get daemonset tailscale --ignore-not-found -o json" {
				t.Fatalf("wrong API boundary: %s", call)
			}
		})
	}
	t.Setenv("GUARD_FIXTURE", "")
	for _, status := range []string{"1", "3"} {
		t.Setenv("GUARD_EXIT", status)
		cmd := exec.Command("bash", "guard.sh", "management-tailscale", "--acknowledged")
		output, err := cmd.CombinedOutput()
		if cmd.ProcessState == nil || cmd.ProcessState.ExitCode() != 1 {
			t.Fatalf("API exit %s must be a read failure, not pending qualification: %v\n%s", status, err, output)
		}
	}
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
