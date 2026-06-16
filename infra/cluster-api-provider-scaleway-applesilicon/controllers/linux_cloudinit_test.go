package controllers

import (
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
)

func TestRenderLinuxCloudInit_BootstrapRunsUnderBash(t *testing.T) {
	taints := []corev1.Taint{{Key: "tuist.dev/runner-cache", Value: "true", Effect: corev1.TaintEffectNoSchedule}}
	out := renderLinuxCloudInit("tuist-tuist-kura-fleet-abc", "apiVersion: v1\nkind: Config\n", "v1.34", taints)

	// runcmd must invoke the script under bash; cloud-init runs runcmd itself
	// under dash, which rejects `set -o pipefail` and aborts the bootstrap.
	if !strings.Contains(out, "runcmd:\n  - [bash, /opt/bootstrap-node.sh]") {
		t.Fatalf("expected runcmd to invoke the bootstrap under bash, got:\n%s", out)
	}
	// The pipefail-using bootstrap must live in the bash script, never as a
	// bare runcmd entry (which dash would run).
	runcmdIdx := strings.Index(out, "runcmd:")
	if runcmdIdx >= 0 && strings.Contains(out[runcmdIdx:], "pipefail") {
		t.Fatalf("pipefail must not appear in the dash-run runcmd section, got:\n%s", out[runcmdIdx:])
	}
	if !strings.Contains(out, "#!/usr/bin/env bash") || !strings.Contains(out, "set -euxo pipefail") {
		t.Fatalf("expected a bash bootstrap script with pipefail, got:\n%s", out)
	}
	// The join essentials still render.
	if !strings.Contains(out, "--hostname-override=tuist-tuist-kura-fleet-abc") {
		t.Fatalf("expected hostname-override to the node name, got:\n%s", out)
	}
	if !strings.Contains(out, "--register-with-taints=tuist.dev/runner-cache=true:NoSchedule") {
		t.Fatalf("expected the runner-cache taint registered, got:\n%s", out)
	}
	if !strings.Contains(out, "core:/stable:/v1.34/deb/") {
		t.Fatalf("expected the v1.34 pkgs channel, got:\n%s", out)
	}
}
