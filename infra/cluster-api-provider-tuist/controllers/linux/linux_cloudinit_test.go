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

	// Bare-metal boxes with a small root + big /data relocate containerd's image
	// store onto /data (guarded so it no-ops without a separate /data and never
	// aborts the join). The cloud-init form does NOT bind-mount the kubelet root —
	// that is SSH-form only (it must precede the config write; asserted below).
	if !strings.Contains(out, `root = \"/data/containerd\"`) ||
		!strings.Contains(out, `findmnt -no SOURCE /data`) {
		t.Fatalf("expected the /data containerd relocation guard, got:\n%s", out)
	}
	if strings.Contains(out, "mount --bind /data/kubelet /var/lib/kubelet") {
		t.Fatalf("cloud-init form must not bind-mount the kubelet root (Instances are single-disk), got:\n%s", out)
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
	// The SSH form binds the kubelet root onto /data BEFORE writing the kubelet
	// config, so a separate-/data box doesn't shadow config.yaml + kubeconfig once
	// the mount lands (the bug that left the kubelet crash-looping on a missing
	// config). Ordering, not just presence, is what matters here.
	mountIdx := strings.Index(script, "mount --bind /data/kubelet /var/lib/kubelet")
	cfgIdx := strings.Index(script, "tee /var/lib/kubelet/config.yaml")
	if mountIdx < 0 || cfgIdx < 0 || mountIdx > cfgIdx {
		t.Fatalf("expected the /data/kubelet bind-mount before the config.yaml write (mount=%d cfg=%d), got:\n%s", mountIdx, cfgIdx, script)
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

func TestRenderLinuxBootstrapScript_NoPasswdSudo(t *testing.T) {
	opts := linuxCloudInitOptions{
		NodeName:       "tuist-tuist-dedibox-fleet-abc",
		KubeconfigYAML: "apiVersion: v1\nkind: Config\n",
		K8sMinor:       "v1.34",
		BootstrapUser:  "tuist",
		SudoPassword:   "Sw0rdFishABCD",
	}
	out := renderLinuxBootstrapScript(opts)

	// The NOPASSWD setup must run BEFORE the first sudo mkdir, escalating once with
	// the install-set password, so every later sudo is non-interactive.
	setup := "echo 'Sw0rdFishABCD' | sudo -S sh -c"
	if !strings.Contains(out, setup) {
		t.Fatalf("expected NOPASSWD setup line %q, got:\n%s", setup, out)
	}
	if !strings.Contains(out, "tuist ALL=(ALL) NOPASSWD:ALL") {
		t.Fatalf("expected the sudoers content, got:\n%s", out)
	}
	if strings.Index(out, setup) > strings.Index(out, "sudo mkdir -p") {
		t.Fatalf("NOPASSWD setup must precede the first sudo command, got:\n%s", out)
	}
	// The password line must be untraced (set +x) so it doesn't leak into the
	// operator's logged bootstrap output on failure.
	if !strings.Contains(out, "set +x\necho 'Sw0rdFishABCD'") {
		t.Fatalf("expected the password echo to be wrapped in set +x, got:\n%s", out)
	}
}

func TestRenderLinuxBootstrapScript_NoSudoPasswordIsNoOp(t *testing.T) {
	// Without a SudoPassword (the Elastic Metal kind, whose install already grants
	// NOPASSWD), no setup line is emitted and the script is unchanged.
	withUser := renderLinuxBootstrapScript(linuxCloudInitOptions{NodeName: "n", KubeconfigYAML: "x\n", K8sMinor: "v1.34", BootstrapUser: "ubuntu"})
	if strings.Contains(withUser, "sudo -S") {
		t.Fatalf("expected no NOPASSWD setup without a SudoPassword, got:\n%s", withUser)
	}
}

func TestRenderLinuxBootstrapScript_PNVlanIsPersistentAndStatic(t *testing.T) {
	script := renderLinuxBootstrapScript(linuxCloudInitOptions{
		NodeName:           "node-a",
		KubeconfigYAML:     "apiVersion: v1\nkind: Config\n",
		K8sMinor:           "v1.34",
		BootstrapUser:      "ubuntu",
		PrivateNetworkVLAN: 3250,
	})

	// The VLAN must be installed as a reboot-durable systemd unit that holds the
	// PN address STATICALLY (DHCP-discover once, then pin it). Assert the unit,
	// the static re-assert, and the VLAN id wired through.
	for _, want := range []string{
		"/etc/systemd/system/tuist-pn0.service",
		"/usr/local/sbin/tuist-pn0-up.sh",
		"ExecStart=/usr/local/sbin/tuist-pn0-up.sh",
		"Restart=always",
		"name pn0 type vlan id 3250",
		"ip addr replace",
		"systemctl enable --now tuist-pn0.service",
	} {
		if !strings.Contains(script, want) {
			t.Fatalf("expected bootstrap script to contain %q, got:\n%s", want, script)
		}
	}

	// Liveness must NOT hang on a renew-forever dhclient: neither the old
	// one-shot `dhclient -nw` nor a supervised `dhclient -d` survives the PN DHCP
	// server going silent (the lease expires and the address is dropped while the
	// process keeps running). That is the bug this static hold replaces.
	for _, banned := range []string{"dhclient -nw pn0", "dhclient -d pn0"} {
		if strings.Contains(script, banned) {
			t.Fatalf("expected no renew-forever dhclient %q, got:\n%s", banned, script)
		}
	}

	// The Instance/cloud-init path never sets a VLAN, so it must render nothing
	// PN-related (and must not emit heredocs that the indented YAML form can't
	// host).
	instance := renderLinuxCloudInit("node-a", "apiVersion: v1\nkind: Config\n", "v1.34", nil)
	if strings.Contains(instance, "pn0") || strings.Contains(instance, "tuist-pn0.service") {
		t.Fatalf("expected no PN-VLAN setup when no VLAN is set, got:\n%s", instance)
	}
}
