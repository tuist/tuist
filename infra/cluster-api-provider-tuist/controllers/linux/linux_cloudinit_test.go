package linux

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

func TestRenderLinuxCloudInit_DockerHubMirror(t *testing.T) {
	out := renderLinuxCloudInit("node-a", "apiVersion: v1\nkind: Config\n", "v1.34", nil)

	// containerd must point the CRI registry config_path at /etc/containerd/certs.d
	// so per-registry hosts.toml files are honored.
	if !strings.Contains(out, `config_path = "/etc/containerd/certs.d"`) {
		t.Fatalf("expected containerd registry config_path, got:\n%s", out)
	}
	// The docker.io mirror hosts.toml must route through mirror.gcr.io.
	if !strings.Contains(out, "/etc/containerd/certs.d/docker.io/hosts.toml") {
		t.Fatalf("expected the docker.io hosts.toml write, got:\n%s", out)
	}
	if !strings.Contains(out, `[host."https://mirror.gcr.io"]`) ||
		!strings.Contains(out, `capabilities = ["pull", "resolve"]`) {
		t.Fatalf("expected the mirror.gcr.io host entry, got:\n%s", out)
	}

	// Bare-metal boxes with a small root + big /data must relocate containerd's
	// image store and the kubelet root onto /data (guarded so it no-ops without
	// a separate /data and never aborts the join).
	if !strings.Contains(out, `root = \"/data/containerd\"`) ||
		!strings.Contains(out, "mount --bind /data/kubelet /var/lib/kubelet") ||
		!strings.Contains(out, `findmnt -no SOURCE /data`) {
		t.Fatalf("expected the /data relocation guard, got:\n%s", out)
	}

	// The Elastic Metal (SSH script) form must carry the same mirror config.
	script := renderLinuxBootstrapScript(linuxCloudInitOptions{
		NodeName:       "node-a",
		KubeconfigYAML: "apiVersion: v1\nkind: Config\n",
		K8sMinor:       "v1.34",
		BootstrapUser:  "ubuntu",
	})
	if !strings.Contains(script, `config_path = "/etc/containerd/certs.d"`) ||
		!strings.Contains(script, `[host."https://mirror.gcr.io"]`) {
		t.Fatalf("expected the bootstrap script to configure the docker.io mirror, got:\n%s", script)
	}
}

func TestRenderLinuxCloudInit_ClusterDNS(t *testing.T) {
	with := renderLinuxCloudInitWithOptions(linuxCloudInitOptions{
		NodeName:       "node-a",
		KubeconfigYAML: "apiVersion: v1\nkind: Config\n",
		K8sMinor:       "v1.34",
		ClusterDNS:     "10.96.0.10",
	})
	if !strings.Contains(with, "clusterDNS:\n        - 10.96.0.10") {
		t.Fatalf("expected clusterDNS list entry in cloud-init, got:\n%s", with)
	}

	without := renderLinuxCloudInit("node-a", "apiVersion: v1\nkind: Config\n", "v1.34", nil)
	if strings.Contains(without, "clusterDNS:") {
		t.Fatalf("expected clusterDNS omitted when unset, got:\n%s", without)
	}

	// The Elastic Metal (SSH script) form threads clusterDNS too.
	script := renderLinuxBootstrapScript(linuxCloudInitOptions{
		NodeName:       "node-a",
		KubeconfigYAML: "apiVersion: v1\nkind: Config\n",
		K8sMinor:       "v1.34",
		BootstrapUser:  "ubuntu",
		ClusterDNS:     "10.96.0.10",
	})
	if !strings.Contains(script, "clusterDNS:\n  - 10.96.0.10") {
		t.Fatalf("expected clusterDNS list entry in bootstrap script, got:\n%s", script)
	}
}
