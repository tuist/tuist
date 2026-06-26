package linux

import (
	"context"
	"fmt"
	"strings"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// linuxCloudInitOptions parameterizes the self-join bootstrap across the two
// Linux machine kinds. The regular Instance kind uses the zero value
// (root user, no PN VLAN bring-up), delivered as cloud-init user-data; the
// Elastic Metal kind sets BootstrapUser ("ubuntu") and PrivateNetworkVLAN so
// the rendered script escalates with sudo and materializes the tagged-VLAN
// interface before kubelet starts, delivered over SSH.
type linuxCloudInitOptions struct {
	// NodeName is the kubelet --hostname-override so the Node name matches
	// the Machine.
	NodeName string

	// KubeconfigYAML is the rendered kubelet kubeconfig (token-based, from
	// kubeconfig.Builder).
	KubeconfigYAML string

	// K8sMinor is the pkgs.k8s.io channel (e.g. "v1.34").
	K8sMinor string

	// Taints are rendered into kubelet's --register-with-taints.
	Taints []corev1.Taint

	// BootstrapUser is the OS login user the install lands on. Empty (the
	// Instance default) means the bootstrap runs directly as root with no
	// privilege-escalation prefix. A non-root value (Elastic Metal's
	// "ubuntu") prefixes every privileged command with sudo, since the
	// bare-metal Ubuntu install logs in as that user.
	BootstrapUser string

	// PrivateNetworkVLAN, when non-zero, makes the bootstrap bring up the
	// Private Network as a tagged VLAN on the primary NIC and DHCP it before
	// kubelet starts. Instances leave this 0: their PN arrives as an
	// auto-DHCP'd second interface, so no host-side VLAN setup is needed.
	PrivateNetworkVLAN uint32

	// ClusterDNS is the workload cluster's kube-dns ClusterIP, set as the
	// kubelet's clusterDNS so pods resolve in-cluster Services (e.g. the kura
	// peer mesh). Empty omits the setting, leaving kubelet to log
	// MissingClusterDNS and fall back to host DNS.
	ClusterDNS string

	// InstanceType is the value of the node's
	// node.cluster.x-k8s.io/instance-type kubelet label. Empty defaults to
	// "scaleway" so the Scaleway kinds render byte-identically; the OVH kind
	// passes "ovh" so a bare-metal OVH node isn't mislabelled as Scaleway.
	InstanceType string

	// SudoPassword, when set on a non-root BootstrapUser, is the install-set
	// password the self-join uses once (via `sudo -S`) to drop a NOPASSWD sudoers
	// file before any other sudo. It makes passwordless sudo self-established by
	// the bootstrap, so it survives reinstalls with no post-install step. Empty
	// (the default) assumes the user already has NOPASSWD (root, or a fleet whose
	// install grants it).
	SudoPassword string
}

const (
	modulesLoadContent = `overlay
br_netfilter
`
	sysctlContent = `net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
`

	// dockerHubMirrorHostsContent is the containerd registry-host config that
	// routes docker.io pulls through mirror.gcr.io, sidestepping Docker Hub's
	// anonymous pull rate limit. Written to
	// /etc/containerd/certs.d/docker.io/hosts.toml, which containerd reads
	// because bootstrapBody sets the CRI registry config_path to
	// /etc/containerd/certs.d.
	dockerHubMirrorHostsContent = `[host."https://mirror.gcr.io"]
  capabilities = ["pull", "resolve"]
`
)

// kubeletConfigContent renders the KubeletConfiguration. clusterDNS, when
// non-empty, is appended as the kubelet's clusterDNS (a single-entry list) so
// pods resolve in-cluster Services; empty omits it (kubelet then logs
// MissingClusterDNS and falls back to host DNS).
func kubeletConfigContent(clusterDNS string) string {
	config := `apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
authorization:
  mode: Webhook
clusterDomain: cluster.local
runtimeRequestTimeout: 5m
serverTLSBootstrap: true
`
	if clusterDNS != "" {
		config += fmt.Sprintf("clusterDNS:\n  - %s\n", clusterDNS)
	}
	return config
}

// kubeletUnitContent renders the kubelet systemd unit with the node's
// hostname-override, any register-with-taints argument, and the
// node.cluster.x-k8s.io/instance-type label (provider-specific).
func kubeletUnitContent(nodeName, taintArg, instanceType string) string {
	return fmt.Sprintf(`[Unit]
Description=kubelet (tuist runner-cache node)
After=containerd.service network-online.target
Wants=containerd.service network-online.target
[Service]
ExecStart=/usr/bin/kubelet \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --config=/var/lib/kubelet/config.yaml \
  --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
  --hostname-override=%s \
  %s--node-labels=node.cluster.x-k8s.io/instance-type=%s
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
`, nodeName, taintArg, instanceType)
}

// instanceTypeOrDefault keeps the Scaleway kinds rendering the original
// `instance-type=scaleway` label when InstanceType is unset.
func instanceTypeOrDefault(t string) string {
	if t == "" {
		return "scaleway"
	}
	return t
}

// bootstrapBody renders the post-write_files bootstrap steps (swap off, kernel
// modules, containerd, kubelet install + enable), shared by the cloud-init and
// SSH-script forms. sudo/sudoE are the privilege-escalation prefixes (empty for
// root), writeFile redirects into root-owned paths, and vlanSetup optionally
// brings the PN VLAN up first. The leading indent prefix is supplied by the
// caller so it nests correctly under cloud-init's YAML block or stands alone in
// a bare script.
func bootstrapBody(k8sMinor, sudo, sudoE string, writeFile func(producer, path string) string, vlanSetup string) string {
	// Pipe `containerd config default` through sed so the rendered config sets
	// the CRI registry config_path to /etc/containerd/certs.d. containerd v2
	// emits an empty `[plugins."io.containerd.grpc.v1.cri".registry]` table, so
	// append config_path under it; containerd then reads per-registry hosts.toml
	// files from that directory (the docker.io mirror below).
	containerdConfig := writeFile(
		`containerd config default | sed '/\[plugins."io.containerd.grpc.v1.cri".registry\]/a\    config_path = "/etc/containerd/certs.d"'`,
		"/etc/containerd/config.toml",
	)
	mirrorHosts := writeFile(
		"printf '%s' "+shellSingleQuote(dockerHubMirrorHostsContent),
		"/etc/containerd/certs.d/docker.io/hosts.toml",
	)
	aptSource := writeFile(
		fmt.Sprintf(`echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/%s/deb/ /"`, k8sMinor),
		"/etc/apt/sources.list.d/kubernetes.list",
	)
	return fmt.Sprintf(`%[7]s%[2]sswapoff -a
%[2]ssed -ri '/\sswap\s/s/^/#/' /etc/fstab
%[2]smodprobe overlay
%[2]smodprobe br_netfilter
# Remove stale CNI sysctl drop-ins a prior join left behind: they set rp_filter
# on now-absent cilium interfaces, so sysctl --system errors with cannot-stat and
# aborts the self-join on a re-adopted box (-e does not suppress that). Cilium
# recreates its own drop-ins after the node rejoins.
%[2]srm -f /etc/sysctl.d/*cilium* /etc/sysctl.d/*-cilium.conf
%[2]ssysctl --system
export DEBIAN_FRONTEND=noninteractive
%[3]sapt-get update
%[3]sapt-get install -y apt-transport-https ca-certificates curl gpg containerd
%[2]smkdir -p /etc/containerd /etc/containerd/certs.d/docker.io
%[4]s
%[6]s
%[2]ssed -ri 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
# Bare-metal boxes (e.g. Scaleway Dedibox) ship a small root partition plus a
# large separate /data. Point containerd's image store at /data so image pulls
# land on the big disk, not the ~20G root. (The kubelet root is bind-mounted to
# /data earlier, before its config is written, so the mount can't shadow it.)
# Wrapped so it can never abort the join: a no-op where /data is not its own
# mounted filesystem (single-partition Elastic Metal), and the trailing 'true'
# keeps set -e happy regardless.
%[2]ssh -c 'mountpoint -q /data && [ "$(findmnt -no SOURCE /data)" != "$(findmnt -no SOURCE /)" ] && { mkdir -p /data/containerd; sed -ri "s#^root = .*#root = \"/data/containerd\"#" /etc/containerd/config.toml; }; true'
%[2]ssystemctl restart containerd
%[2]ssystemctl enable containerd
%[2]smkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/%[1]s/deb/Release.key | %[2]sgpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
%[5]s
%[3]sapt-get update
%[3]sapt-get install -y kubelet
%[2]sapt-mark hold kubelet
%[2]ssystemctl daemon-reload
%[2]ssystemctl enable --now kubelet`,
		k8sMinor, sudo, sudoE, containerdConfig, aptSource, mirrorHosts, vlanSetup)
}

// vlanBringUp renders the PN-VLAN setup prepended to the bootstrap body when a
// VLAN id is set. Elastic Metal delivers the PN as a tagged VLAN on the primary
// NIC that the host must bring up itself before kubelet starts. The primary NIC
// name varies by hardware (e.g. enp65s0f0), so detect it at runtime: prefer the
// default-route interface, else the first non-lo physical NIC. Empty (and
// therefore a no-op) for the Instance kind, whose PN auto-DHCPs as a second
// interface.
func vlanBringUp(sudo string, vlan uint32) string {
	if vlan == 0 {
		return ""
	}
	return fmt.Sprintf(`PRIMARY_NIC="$(ip -o route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -n1)"
if [ -z "$PRIMARY_NIC" ]; then
  PRIMARY_NIC="$(for n in /sys/class/net/*; do ifn="$(basename "$n")"; case "$ifn" in lo|pn*) continue;; esac; if [ -e "$n/device" ]; then echo "$ifn"; break; fi; done)"
fi
%[1]sip link add link "$PRIMARY_NIC" name pn0 type vlan id %[2]d || true
%[1]sip link set pn0 up
%[1]sdhclient -nw pn0 || %[1]sdhclient pn0 || true
`, sudo, vlan)
}

// escalation returns the (sudo, sudoE) prefixes for the bootstrap commands.
// Empty for root (the Instance kind, byte-identical to the original); "sudo "
// and "sudo -E " for a non-root install user (Elastic Metal's "ubuntu").
func escalation(bootstrapUser string) (sudo, sudoE string) {
	if bootstrapUser != "" && bootstrapUser != "root" {
		return "sudo ", "sudo -E "
	}
	return "", ""
}

// writeFileFunc returns a redirect-into-a-root-owned-path renderer. Under root
// the plain `producer > path` redirect works; under sudo the redirect itself
// runs as the unprivileged user (the file open happens before sudo), so route
// the producer's stdout through `sudo tee` instead.
func writeFileFunc(sudo string) func(producer, path string) string {
	return func(producer, path string) string {
		if sudo == "" {
			return producer + " > " + path
		}
		return producer + " | sudo tee " + path + " > /dev/null"
	}
}

// renderLinuxCloudInit builds the cloud-init user-data that joins a Scaleway
// Linux Instance to the externally-managed (Hetzner/caph) cluster WITHOUT
// kubeadm — mirroring how the Apple Silicon kind bootstraps kubelet directly,
// but as cloud-init instead of SSH. The kubelet authenticates with the
// operator-minted token kubeconfig and self-registers; the controller stamps
// the providerID + pn-ipv4 label afterwards, and CAPI propagates the pool
// label once Machine↔Node is linked.
//
// kubeconfigYAML is the rendered kubelet kubeconfig (token-based, from
// kubeconfig.Builder). k8sMinor is the pkgs.k8s.io channel (e.g. "v1.34").
// nodeName is the --hostname-override so the Node name matches the Machine.
//
// This is the Instance-kind entry point and is byte-for-byte unchanged: it
// delegates to renderLinuxCloudInitWithOptions with the root/no-VLAN defaults.
func renderLinuxCloudInit(nodeName, kubeconfigYAML, k8sMinor string, taints []corev1.Taint) string {
	return renderLinuxCloudInitWithOptions(linuxCloudInitOptions{
		NodeName:       nodeName,
		KubeconfigYAML: kubeconfigYAML,
		K8sMinor:       k8sMinor,
		Taints:         taints,
	})
}

// renderLinuxCloudInitWithOptions is the parameterized cloud-init renderer both
// Linux kinds can use. The Instance kind passes the zero value for
// BootstrapUser and PrivateNetworkVLAN, which reproduces the original
// root-user / no-VLAN output. (Elastic Metal has no cloud-init user-data
// channel, so it uses renderLinuxBootstrapScript over SSH instead — but the
// parameterization lives here so both forms share one source of truth.)
func renderLinuxCloudInitWithOptions(opts linuxCloudInitOptions) string {
	kubelet := indent(opts.KubeconfigYAML, "      ")
	taintArg := taintArgFor(opts.Taints)
	sudo, sudoE := escalation(opts.BootstrapUser)
	writeFile := writeFileFunc(sudo)
	vlanSetup := vlanBringUp(sudo, opts.PrivateNetworkVLAN)
	body := indent(bootstrapBody(opts.K8sMinor, sudo, sudoE, writeFile, vlanSetup), "      ")

	return fmt.Sprintf(`#cloud-config
write_files:
  - path: /var/lib/kubelet/kubeconfig
    permissions: '0600'
    content: |
%[1]s
  - path: /etc/modules-load.d/k8s.conf
    content: |
%[2]s
  - path: /etc/sysctl.d/99-k8s.conf
    content: |
%[3]s
  - path: /etc/systemd/system/kubelet.service
    permissions: '0644'
    content: |
%[4]s
  - path: /var/lib/kubelet/config.yaml
    permissions: '0644'
    content: |
%[5]s
  - path: /opt/bootstrap-node.sh
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      # cloud-init runs runcmd entries under dash, which rejects pipefail with
      # an "Illegal option" error and aborts the whole bootstrap. Keep the
      # bootstrap in a script invoked under bash so pipefail and the curl|gpg
      # pipe fail fast.
      set -euxo pipefail
%[6]s
runcmd:
  - [bash, /opt/bootstrap-node.sh]
`,
		kubelet,
		indent(modulesLoadContent, "      "),
		indent(sysctlContent, "      "),
		indent(kubeletUnitContent(opts.NodeName, taintArg, instanceTypeOrDefault(opts.InstanceType)), "      "),
		indent(kubeletConfigContent(opts.ClusterDNS), "      "),
		body,
	)
}

// renderLinuxBootstrapScript renders the same self-join as a standalone bash
// script for delivery over SSH (Elastic Metal has no cloud-init user-data
// channel). It writes the identical files via heredocs and then runs the shared
// bootstrap body. The script is meant to be piped to `bash` on the host as the
// install user; commands escalate with sudo per BootstrapUser.
func renderLinuxBootstrapScript(opts linuxCloudInitOptions) string {
	taintArg := taintArgFor(opts.Taints)
	sudo, sudoE := escalation(opts.BootstrapUser)
	writeFile := writeFileFunc(sudo)
	vlanSetup := vlanBringUp(sudo, opts.PrivateNetworkVLAN)
	body := bootstrapBody(opts.K8sMinor, sudo, sudoE, writeFile, vlanSetup)

	heredoc := func(path, content string) string {
		// `<<'EOF'` keeps the body literal (no shell expansion of $ or `).
		writer := sudo + "tee " + path + " > /dev/null"
		return fmt.Sprintf("%s <<'TUIST_EOF'\n%sTUIST_EOF", writer, ensureTrailingNewline(content))
	}

	return fmt.Sprintf(`#!/usr/bin/env bash
set -euxo pipefail
%[8]s%[1]smkdir -p /var/lib/kubelet /etc/modules-load.d /etc/sysctl.d /etc/systemd/system /opt
# Bring up the kubelet root's /data bind-mount BEFORE writing its config below, so
# a box with a separate /data disk doesn't shadow config.yaml + kubeconfig once
# the mount lands (which left the kubelet crash-looping on a missing config).
%[9]s
%[2]s
%[1]schmod 0600 /var/lib/kubelet/kubeconfig
%[3]s
%[4]s
%[5]s
%[6]s
%[7]s
`,
		sudo,
		heredoc("/var/lib/kubelet/kubeconfig", opts.KubeconfigYAML),
		heredoc("/etc/modules-load.d/k8s.conf", modulesLoadContent),
		heredoc("/etc/sysctl.d/99-k8s.conf", sysctlContent),
		heredoc("/etc/systemd/system/kubelet.service", kubeletUnitContent(opts.NodeName, taintArg, instanceTypeOrDefault(opts.InstanceType))),
		heredoc("/var/lib/kubelet/config.yaml", kubeletConfigContent(opts.ClusterDNS)),
		body,
		nopasswdSetup(opts.BootstrapUser, opts.SudoPassword),
		dataKubeletMount(sudo),
	)
}

// dataKubeletMount brings up the /data bind-mount for the kubelet root. The
// SSH-script form runs it BEFORE writing the kubelet config so that on a box with
// a separate /data disk (Scaleway Dedibox: small root + large /data) the mount
// doesn't shadow the freshly-written config.yaml + kubeconfig — the bug that left
// the kubelet crash-looping on a missing config file. A no-op (the trailing `true`
// keeps set -e happy) where /data is not its own filesystem (single-partition
// Elastic Metal). containerd's /data root is still set later, in bootstrapBody.
func dataKubeletMount(sudo string) string {
	return sudo + `sh -c 'mountpoint -q /data && [ "$(findmnt -no SOURCE /data)" != "$(findmnt -no SOURCE /)" ] && { mkdir -p /data/kubelet /var/lib/kubelet; mountpoint -q /var/lib/kubelet || { grep -q " /var/lib/kubelet " /etc/fstab || echo "/data/kubelet /var/lib/kubelet none bind,nofail 0 0" >> /etc/fstab; mount --bind /data/kubelet /var/lib/kubelet; }; }; true'`
}

// nopasswdSetup renders the one-time passwordless-sudo bootstrap: it uses the
// install-set sudo password once (via `sudo -S`) to drop a NOPASSWD sudoers file,
// so every later `sudo` in the script runs non-interactively even on a box whose
// install left the user on password sudo. `set +x` around it keeps the password
// out of the traced output the operator logs on a bootstrap failure; `set -e`
// still aborts the join if the password is wrong. Empty (a no-op) for the
// root/no-password case, which never sudo's.
func nopasswdSetup(bootstrapUser, sudoPassword string) string {
	if sudoPassword == "" || bootstrapUser == "" || bootstrapUser == "root" {
		return ""
	}
	path := fmt.Sprintf("/etc/sudoers.d/90-%s-nopasswd", bootstrapUser)
	inner := fmt.Sprintf(`printf "%%s\n" "%s ALL=(ALL) NOPASSWD:ALL" > %s && chmod 440 %s`, bootstrapUser, path, path)
	return fmt.Sprintf("set +x\necho %s | sudo -S sh -c %s\nset -x\n",
		shellSingleQuote(sudoPassword), shellSingleQuote(inner))
}

// taintArgFor renders the --register-with-taints argument (with a trailing
// space so it slots into the kubelet ExecStart line), or "" when there are no
// taints.
func taintArgFor(taints []corev1.Taint) string {
	registerTaints := formatTaints(taints)
	if registerTaints == "" {
		return ""
	}
	return "--register-with-taints=" + registerTaints + " "
}

// formatTaints renders []corev1.Taint as kubelet's --register-with-taints
// value: comma-separated key=value:Effect.
func formatTaints(taints []corev1.Taint) string {
	parts := make([]string, 0, len(taints))
	for _, t := range taints {
		parts = append(parts, fmt.Sprintf("%s=%s:%s", t.Key, t.Value, t.Effect))
	}
	return strings.Join(parts, ",")
}

func indent(s, prefix string) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	for i, l := range lines {
		lines[i] = prefix + l
	}
	return strings.Join(lines, "\n")
}

func ensureTrailingNewline(s string) string {
	if strings.HasSuffix(s, "\n") {
		return s
	}
	return s + "\n"
}

// shellSingleQuote wraps s in single quotes so it survives as a literal shell
// argument (newlines included), escaping any embedded single quotes via the
// '\” idiom.
func shellSingleQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// discoverClusterDNS reads the kube-dns Service ClusterIP from kube-system so
// the self-join can set the kubelet's clusterDNS. It is best-effort: if the
// Service can't be read (RBAC, not found, transient), it returns "" and logs,
// rather than failing the reconcile — an empty clusterDNS just leaves the
// kubelet on host DNS, same as before.
//
// It takes a client.Reader so callers can pass the uncached APIReader: the
// manager's cached client scopes its Services informer to the egress namespace
// (see main.go), so a cached Get of kube-system/kube-dns never resolves.
func discoverClusterDNS(ctx context.Context, r client.Reader) string {
	svc := &corev1.Service{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: "kube-system", Name: "kube-dns"}, svc); err != nil {
		log.FromContext(ctx).Info("could not resolve kube-dns ClusterIP; kubelet clusterDNS will be unset", "err", err.Error())
		return ""
	}
	return svc.Spec.ClusterIP
}
