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
	// The same /data guard relocates the local-path provisioner root, so the kura
	// cache PVCs land on the big disk rather than the ~20G root (otherwise two
	// co-located replicas overflow the root). Lives in the shared body, so it is
	// guarded-no-op here and active in the SSH form below.
	if !strings.Contains(out, "mount --bind /data/local-path-provisioner /opt/local-path-provisioner") {
		t.Fatalf("expected the /data local-path-provisioner bind-mount, got:\n%s", out)
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
	// The SSH form (Dedibox/OVH/Elastic Metal — the boxes with a separate /data)
	// must carry the local-path-provisioner bind-mount so cache PVCs land on /data.
	if !strings.Contains(script, "mount --bind /data/local-path-provisioner /opt/local-path-provisioner") {
		t.Fatalf("expected the SSH form to bind-mount the local-path provisioner root onto /data, got:\n%s", script)
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

func TestRenderLinux_SelfSignedServingCertAndClientCA(t *testing.T) {
	ca := "-----BEGIN CERTIFICATE-----\nMIIBdummyCAbytes\n-----END CERTIFICATE-----\n"

	withCA := renderLinuxBootstrapScript(linuxCloudInitOptions{
		NodeName:       "tuist-tuist-dedibox-fleet-abc",
		KubeconfigYAML: "apiVersion: v1\nkind: Config\n",
		ClusterCAPEM:   []byte(ca),
		K8sMinor:       "v1.34",
		BootstrapUser:  "ubuntu",
	})

	// serverTLSBootstrap must NOT be set. The self-join kubelet authenticates as
	// a ServiceAccount (not system:node:<name>), so its serving CSR is never
	// auto-approved and serverTLSBootstrap would leave it with no :10250 serving
	// cert (`tls: internal error`). A self-signed cert (serverTLSBootstrap unset)
	// is what the apiserver (no --kubelet-certificate-authority) and metrics-server
	// (--kubelet-insecure-tls) accept.
	if strings.Contains(withCA, "serverTLSBootstrap") {
		t.Fatalf("expected serverTLSBootstrap unset so the kubelet self-signs its serving cert, got:\n%s", withCA)
	}
	// The cluster CA is written to disk and wired as clientCAFile so the kubelet
	// trusts the apiserver's client cert; without it /containerLogs, /exec, and
	// /port-forward authenticate as anonymous and 401.
	if !strings.Contains(withCA, "clientCAFile: /var/lib/kubelet/ca.crt") {
		t.Fatalf("expected the kubelet clientCAFile to point at the on-disk CA, got:\n%s", withCA)
	}
	if !strings.Contains(withCA, "tee /var/lib/kubelet/ca.crt > /dev/null <<'TUIST_EOF'") ||
		!strings.Contains(withCA, "-----BEGIN CERTIFICATE-----") {
		t.Fatalf("expected the cluster CA written to /var/lib/kubelet/ca.crt, got:\n%s", withCA)
	}
	// The CA must be written before the kubelet config.yaml that references it.
	caIdx := strings.Index(withCA, "tee /var/lib/kubelet/ca.crt")
	cfgIdx := strings.Index(withCA, "tee /var/lib/kubelet/config.yaml")
	if caIdx < 0 || cfgIdx < 0 || caIdx > cfgIdx {
		t.Fatalf("expected the CA write before the kubelet config write (ca=%d cfg=%d), got:\n%s", caIdx, cfgIdx, withCA)
	}

	// Cloud-init form carries the same CA write_files entry + clientCAFile.
	cloudInit := renderLinuxCloudInitWithOptions(linuxCloudInitOptions{
		NodeName:       "node-a",
		KubeconfigYAML: "apiVersion: v1\nkind: Config\n",
		ClusterCAPEM:   []byte(ca),
		K8sMinor:       "v1.34",
	})
	if !strings.Contains(cloudInit, "path: /var/lib/kubelet/ca.crt") ||
		!strings.Contains(cloudInit, "clientCAFile: /var/lib/kubelet/ca.crt") {
		t.Fatalf("expected the cloud-init form to write the CA + set clientCAFile, got:\n%s", cloudInit)
	}
	if strings.Contains(cloudInit, "serverTLSBootstrap") {
		t.Fatalf("expected serverTLSBootstrap unset in the cloud-init form, got:\n%s", cloudInit)
	}

	// No CA supplied: clientCAFile omitted and no ca.crt written, so a caller that
	// doesn't thread a CA renders exactly as before.
	noCA := renderLinuxBootstrapScript(linuxCloudInitOptions{
		NodeName:       "node-a",
		KubeconfigYAML: "apiVersion: v1\nkind: Config\n",
		K8sMinor:       "v1.34",
		BootstrapUser:  "ubuntu",
	})
	if strings.Contains(noCA, "clientCAFile") || strings.Contains(noCA, "/var/lib/kubelet/ca.crt") {
		t.Fatalf("expected no clientCAFile/CA write when no CA is supplied, got:\n%s", noCA)
	}
}

func TestRenderLinux_LockupHardening(t *testing.T) {
	// Both render forms must harden bare-metal boxes so a silent kernel lockup
	// auto-reboots instead of stranding the node NotReady forever (which drops the
	// observability node-exporter DaemonSet below full availability and wedges every
	// deploy). Assert the panic sysctls and the systemd hardware watchdog land in
	// the cloud-init (Instance) and SSH (Elastic Metal) forms alike, since both
	// share bootstrapBody.
	cloudInit := renderLinuxCloudInit("node-a", "apiVersion: v1\nkind: Config\n", "v1.34", nil)
	script := renderLinuxBootstrapScript(linuxCloudInitOptions{
		NodeName:       "node-a",
		KubeconfigYAML: "apiVersion: v1\nkind: Config\n",
		K8sMinor:       "v1.34",
		BootstrapUser:  "ubuntu",
	})
	for _, out := range []string{cloudInit, script} {
		for _, want := range []string{
			"/etc/sysctl.d/99-tuist-hardening.conf",
			"kernel.softlockup_panic = 1",
			"kernel.panic = 10",
			"/etc/systemd/system.conf.d/10-tuist-watchdog.conf",
			"RuntimeWatchdogSec=30s",
			"systemctl daemon-reexec",
		} {
			if !strings.Contains(out, want) {
				t.Fatalf("expected lockup hardening to contain %q, got:\n%s", want, out)
			}
		}
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

// Project quotas are the only per-account boundary on these shared cache boxes,
// and XFS takes quota accounting at MOUNT time; a remount cannot add it. So the
// enablement has to run before the kubelet-root bind, which would otherwise pin
// /data busy and leave the box joined with quotas off until its next reboot.
func TestBootstrapScriptEnablesDataProjectQuotaBeforeAnyDataBind(t *testing.T) {
	script := renderLinuxBootstrapScript(linuxCloudInitOptions{
		NodeName: "kura-1", KubeconfigYAML: "kubeconfig\n", K8sMinor: "v1.34",
		BootstrapUser: "ubuntu", InstanceType: "ovh",
	})

	quotaIdx := strings.Index(script, "bash "+dataProjectQuotaPath)
	if quotaIdx < 0 {
		t.Fatalf("expected the self-join to run %s, got:\n%s", dataProjectQuotaPath, script)
	}
	kubeletBindIdx := strings.Index(script, "mount --bind /data/kubelet /var/lib/kubelet")
	localPathBindIdx := strings.Index(script, "mount --bind /data/local-path-provisioner /opt/local-path-provisioner")
	if kubeletBindIdx < 0 || localPathBindIdx < 0 {
		t.Fatalf("expected both /data bind-mounts in the SSH form, got:\n%s", script)
	}
	if quotaIdx > kubeletBindIdx || quotaIdx > localPathBindIdx {
		t.Fatalf("project-quota setup at %d must precede the /data binds (kubelet=%d, local-path=%d), got:\n%s",
			quotaIdx, kubeletBindIdx, localPathBindIdx, script)
	}
}

// A box whose /data cannot carry project quotas must not join. It would look
// healthy while being exactly what this exists to prevent: cache directories
// with no per-account ceiling on a filesystem several tenants share, where one
// account filling it evicts every other tenant on the box.
func TestDataProjectQuotaScriptFailsClosed(t *testing.T) {
	if !strings.Contains(dataProjectQuotaScript, `if [ "$fstype" != xfs ]`) {
		t.Fatalf("expected the script to reject a non-xfs /data, got:\n%s", dataProjectQuotaScript)
	}
	// Two exits: a /data that is not xfs at all, and one that came back from the
	// remount without quota accounting on.
	if got := strings.Count(dataProjectQuotaScript, "exit 1"); got < 3 {
		t.Fatalf("expected the script to abort on every unenforceable path, found %d exit 1", got)
	}
	// A single-filesystem box has no /data for cache directories to land on, so
	// there is nothing to enforce and the join proceeds.
	if !strings.Contains(dataProjectQuotaScript, `mountpoint -q "$data" || exit 0`) {
		t.Fatalf("expected a no-op on boxes without a separate /data, got:\n%s", dataProjectQuotaScript)
	}
}

// The provisioner's per-volume quota hooks shell out to xfs_quota on the host,
// so the package has to be there before the first cache PVC is provisioned.
func TestBootstrapInstallsXFSTools(t *testing.T) {
	script := renderLinuxBootstrapScript(linuxCloudInitOptions{NodeName: "n", K8sMinor: "v1.34"})
	if !strings.Contains(script, "containerd xfsprogs") {
		t.Fatalf("expected xfsprogs in the bootstrap apt install, got:\n%s", script)
	}
}

// The image store is the one consumer of /data that is not a tenant, and it is
// otherwise unbounded: the kubelet's image GC triggers on the FILESYSTEM being
// nearly full, so on a box whose tenants are light containerd can grow into the
// headroom their quotas were written against and starve them below their own
// ceilings. Its quota can only be applied after the store has been relocated
// onto /data (the directory has to exist to carry a project) and after apt has
// installed xfsprogs.
func TestBootstrapBoundsContainerdImageStoreAfterItsPrerequisites(t *testing.T) {
	script := renderLinuxBootstrapScript(linuxCloudInitOptions{
		NodeName: "kura-1", KubeconfigYAML: "kubeconfig\n", K8sMinor: "v1.34",
		BootstrapUser: "ubuntu", InstanceType: "ovh",
	})

	quotaIdx := strings.Index(script, "bash "+containerdQuotaPath)
	if quotaIdx < 0 {
		t.Fatalf("expected the self-join to run %s, got:\n%s", containerdQuotaPath, script)
	}
	aptIdx := strings.Index(script, "containerd xfsprogs")
	relocateIdx := strings.Index(script, "mkdir -p /data/containerd")
	if aptIdx < 0 || relocateIdx < 0 {
		t.Fatalf("expected the apt install and the image-store relocation, got:\n%s", script)
	}
	if quotaIdx < aptIdx || quotaIdx < relocateIdx {
		t.Fatalf("containerd quota at %d must follow apt (%d) and the relocation (%d), got:\n%s",
			quotaIdx, aptIdx, relocateIdx, script)
	}
}

// Unlike the /data mount setup, a failed image-store quota must NOT fail the
// join. Every tenant on the box is bounded either way; what is lost is defence
// in depth on the shared pool, which is the state the box was in before.
func TestContainerdQuotaDoesNotFailTheJoin(t *testing.T) {
	script := renderLinuxBootstrapScript(linuxCloudInitOptions{NodeName: "n", K8sMinor: "v1.34"})
	line := "bash " + containerdQuotaPath + " || echo"
	if !strings.Contains(script, line) {
		t.Fatalf("expected the containerd quota step to be tolerated, got:\n%s", script)
	}
}

// The reserved project id must stay clear of the range the provisioner hook
// hashes volume directories into, or the image store and a cache volume would
// share one ceiling.
func TestContainerdProjectIDCannotCollideWithAVolume(t *testing.T) {
	// The hook computes `crc % 16000000 + 1000`, so volumes occupy [1000, 16000999].
	if containerdProjectID <= 0 || containerdProjectID >= 1000 {
		t.Fatalf("containerd project id = %d, want a reserved id below the volume range", containerdProjectID)
	}
	if !strings.Contains(containerdQuotaScript, "bhard=$bytes") || strings.Contains(containerdQuotaScript, "ihard=") {
		t.Fatal("expected a byte ceiling and no inode ceiling on the image store")
	}
}

// TestRenderLinux_KataRuntime pins both halves of the runner-fleet opt-in: a box
// that asked for kata gets the runtime AND the label the kata-qemu RuntimeClass
// selects on, and a box that did not gets neither. The negative half is the one
// that matters operationally — the four Kura cache fleets share this renderer,
// and silently handing them a kata download plus a containerd runtime block is a
// change to a live cache node's runtime for no reason.
func TestRenderLinux_KataRuntime(t *testing.T) {
	opts := linuxCloudInitOptions{
		NodeName:       "tuist-tuist-ovh-fleet-runners-linux-abc",
		KubeconfigYAML: "apiVersion: v1\nkind: Config\n",
		K8sMinor:       "v1.34",
		BootstrapUser:  "ubuntu",
	}

	optsKata := opts
	optsKata.KataRuntime = true
	withKata := renderLinuxBootstrapScript(optsKata)

	for _, want := range []string{
		"kata-static-" + kataVersion + "-amd64.tar.zst",
		"runtime_path = \"/opt/kata/bin/containerd-shim-kata-v2\"",
		"katacontainers.io/kata-runtime=true",
		"tuist.dev/kata-runtime=true",
		// Set on the handler itself: the earlier rewrite only touches what the
		// generated default emitted, and this block is appended after it.
		"SystemdCgroup = true",
	} {
		if !strings.Contains(withKata, want) {
			t.Errorf("kata-enabled render is missing %q", want)
		}
	}

	// The handler is registered under containerd's v3 config syntax, so a box
	// whose containerd still emits v2 would accept the join and then fail every
	// kata Pod. The guard has to abort the join instead.
	if !strings.Contains(withKata, "grep -q '^version = 3' /etc/containerd/config.toml") {
		t.Errorf("kata-enabled render must refuse to join a box whose containerd config is not version 3")
	}

	// Appending twice on a re-bootstrap would give containerd a duplicate
	// runtime table, so the append is guarded.
	if !strings.Contains(withKata, `grep -q "runtimes.kata-qemu" /etc/containerd/config.toml ||`) {
		t.Errorf("the kata containerd block must be appended idempotently")
	}

	// Ordering: the handler has to be registered before containerd restarts,
	// or kubelet talks to a containerd that has never seen it.
	kataIdx := strings.Index(withKata, "runtimes.kata-qemu")
	restartIdx := strings.Index(withKata, "systemctl restart containerd")
	if kataIdx < 0 || restartIdx < 0 || kataIdx > restartIdx {
		t.Errorf("expected the kata block before the containerd restart (kata=%d restart=%d)", kataIdx, restartIdx)
	}

	// Cache fleets: nothing kata anywhere, including the node labels.
	withoutKata := renderLinuxBootstrapScript(opts)
	for _, unwanted := range []string{"kata-static", "kata-qemu", "katacontainers.io/kata-runtime"} {
		if strings.Contains(withoutKata, unwanted) {
			t.Errorf("cache-fleet render must not contain %q", unwanted)
		}
	}
}
