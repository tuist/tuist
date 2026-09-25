package linux

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"sort"
	"strings"

	corev1 "k8s.io/api/core/v1"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackinstall"
)

const (
	// rackConvergeNeedsBootstrap is the converge script's exit status when the
	// kubelet has no valid client certificate and the run carried no
	// bootstrap kubeconfig to get one with.
	rackConvergeNeedsBootstrap = 42

	// rackConvergeForeignJoin is its exit status on a host kubeadm joined.
	rackConvergeForeignJoin = 43

	// rackLocalCNIRange is the local CNI's pod range: outside the cluster's
	// pod CIDR (192.168.0.0/16), its service CIDR (10.128.0.0/12), the
	// tailnet (100.64.0.0/10) and the rack's own segments.
	rackLocalCNIRange = "10.254.254.0/24"

	rackInstanceType = "rack"

	ciliumNoScheduleLabel = "cilium.io/no-schedule"

	rackBootstrapKubeconfigPath = "/var/lib/kubelet/bootstrap-kubeconfig"

	// rackAppliedHashPath records the configuration a converge last finished
	// with, so a run that changed files and failed before restarting the
	// daemons is followed by one that restarts them.
	rackAppliedHashPath = "/var/lib/tuist/rack-converge.hash"

	rackKubernetesAPIPath = "/etc/tuist/kubernetes-api"
)

// rackConvergeOptions is everything the converge script renders from.
type rackConvergeOptions struct {
	NodeName   string
	NodeIP     string
	ProviderID string
	// KubeletVersion is the exact kubelet release to run, without the `v`.
	KubeletVersion string
	// K8sMinor is the pkgs.k8s.io channel, e.g. "v1.34".
	K8sMinor     string
	ClusterCAPEM []byte
	ClusterDNS   string
	NodeLabels   map[string]string
	NodeTaints   []corev1.Taint

	// ManagementMAC is the management port's, the one AMT shares with the
	// host: the host's boot MAC.
	ManagementMAC string

	// KubernetesAPI is the API server the kubelet uses, written to
	// rackKubernetesAPIPath for the pods on the node that talk to it: a rack
	// node reaches no Service address.
	KubernetesAPI string

	// APIServerURL and BootstrapToken, when the token is set, make the run
	// write a bootstrap kubeconfig and wait for the kubelet's certificate.
	// Rejoin drops the kubelet's identity first, for a host joining again
	// under a new name. None of them is part of the configuration hash.
	APIServerURL   string
	BootstrapToken string
	Rejoin         bool
}

// rackNodeLabels are the labels a rack Linux node registers with. Every rack
// node carries the Cilium exclusion: the rack's networks overlap the cluster's
// pod CIDR, so it runs the local CNI instead.
func rackNodeLabels(extra map[string]string) map[string]string {
	labels := map[string]string{
		"node.cluster.x-k8s.io/instance-type": rackInstanceType,
		ciliumNoScheduleLabel:                 "true",
	}
	for k, v := range extra {
		labels[k] = v
	}
	return labels
}

func sortedLabels(labels map[string]string) string {
	keys := make([]string, 0, len(labels))
	for k := range labels {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, k+"="+labels[k])
	}
	return strings.Join(parts, ",")
}

func rackKubeletUnit(o rackConvergeOptions) string {
	var args strings.Builder
	for _, a := range []string{
		"--config=/var/lib/kubelet/config.yaml",
		"--kubeconfig=/var/lib/kubelet/kubeconfig",
		"--bootstrap-kubeconfig=" + rackBootstrapKubeconfigPath,
		"--container-runtime-endpoint=unix:///run/containerd/containerd.sock",
		"--hostname-override=" + o.NodeName,
		"--node-ip=" + o.NodeIP,
		"--node-labels=" + sortedLabels(rackNodeLabels(o.NodeLabels)),
		// The operator owns the node's addresses and adds one the control
		// plane can reach (rack_kubelet_address.go).
		"--cloud-provider=external",
	} {
		args.WriteString(" \\\n  " + a)
	}
	if taints := formatTaints(o.NodeTaints); taints != "" {
		args.WriteString(" \\\n  --register-with-taints=" + taints)
	}
	return fmt.Sprintf(`[Unit]
Description=kubelet (tuist rack node)
After=containerd.service network-online.target tailscaled.service
Wants=containerd.service network-online.target
[Service]
ExecStart=/usr/bin/kubelet%s
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
`, args.String())
}

// rackKubeletConfig is the fleet's self-join kubelet configuration plus what a
// kubelet with a certificate identity needs: rotation and its providerID.
// resolvConf is systemd-resolved's stub, the resolver that answers tailnet
// names for host-network pods.
func rackKubeletConfig(o rackConvergeOptions) string {
	return kubeletConfigContent(o.ClusterDNS, kubeletClientCAPath) + fmt.Sprintf(`providerID: %s
rotateCertificates: true
resolvConf: /etc/resolv.conf
`, o.ProviderID)
}

func rackLocalCNIConfig() string {
	return fmt.Sprintf(`{"cniVersion":"1.0.0","name":"rack-local","plugins":[{"type":"bridge","bridge":"cni-racklocal","isGateway":true,"ipMasq":true,"ipam":{"type":"host-local","ranges":[[{"subnet":"%s"}]]}},{"type":"portmap","capabilities":{"portMappings":true}}]}
`, rackLocalCNIRange)
}

func rackBootstrapKubeconfig(server string, ca []byte, token string) string {
	return fmt.Sprintf(`apiVersion: v1
kind: Config
clusters:
  - name: cluster
    cluster:
      server: %s
      certificate-authority-data: %s
contexts:
  - name: bootstrap
    context:
      cluster: cluster
      user: kubelet-bootstrap
current-context: bootstrap
users:
  - name: kubelet-bootstrap
    user:
      token: %s
`, server, base64.StdEncoding.EncodeToString(ca), token)
}

// rackConfigHash fingerprints what a converge would write, leaving out the
// one-off bootstrap credential.
func rackConfigHash(o rackConvergeOptions) string {
	o.APIServerURL = ""
	o.BootstrapToken = ""
	o.Rejoin = false
	sum := sha256.Sum256([]byte(renderRackConvergeScriptWithHash(o, "")))
	return hex.EncodeToString(sum[:])
}

// renderRackConvergeScript renders the script that joins a rack Linux host and
// keeps it converged. It rewrites only files whose content differs, restarts a
// daemon whose configuration changed or that is not running, and never
// downgrades the kubelet.
func renderRackConvergeScript(o rackConvergeOptions) string {
	return renderRackConvergeScriptWithHash(o, rackConfigHash(o))
}

func renderRackConvergeScriptWithHash(o rackConvergeOptions, hash string) string {
	heredoc := func(path, mode, group, content string) string {
		return fmt.Sprintf("put %s %s %s <<'TUIST_EOF'\n%sTUIST_EOF\n", path, mode, group, ensureTrailingNewline(content))
	}

	var b strings.Builder
	fmt.Fprintf(&b, `#!/usr/bin/env bash
set -euo pipefail
shopt -s lastpipe
trap 'echo "tuist-converge: failed at line $LINENO: $BASH_COMMAND" >&2' ERR

if [ -e /etc/kubernetes/kubelet.conf ] || [ -e /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf ]; then
  echo "tuist-converge: kubeadm joined this host; reinstall it from a stick written by rack:write-install-usb" >&2
  exit %[1]d
fi

declare -A dirty=()
changed=()
restarted=()
if [ "$(cat %[2]s 2>/dev/null || true)" != %[3]s ]; then
  dirty[containerd]=1
  dirty[kubelet]=1
fi
put() {
  local path=$1 mode=$2 group=$3 tmp
  tmp=$(mktemp)
  cat > "$tmp"
  if [ -f "$path" ] && cmp -s "$tmp" "$path" && [ "$(stat -c %%a "$path")" = "${mode#0}" ]; then
    rm -f "$tmp"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  install -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
  changed+=("$path")
  dirty[$group]=1
}
unput() {
  local path=$1 group=$2
  if [ -e "$path" ]; then
    rm -f "$path"
    changed+=("-$path")
    dirty[$group]=1
  fi
}
apt_get() {
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -y -qq "$@"
}
kubelet_package() {
  apt-cache madison kubelet 2>/dev/null | awk -v want="$1-" '!found && index($3, want) == 1 {print $3; found = 1}'
}
has_identity() {
  [ -s /var/lib/kubelet/kubeconfig ] && [ -s /var/lib/kubelet/pki/kubelet-client-current.pem ] &&
    openssl x509 -checkend 600 -noout -in /var/lib/kubelet/pki/kubelet-client-current.pem >/dev/null 2>&1
}

if [ -n "$(swapon --show --noheadings)" ]; then
  swapoff -a
  changed+=(swap)
fi
sed -ri '/\sswap\s/s/^([^#])/#\1/' /etc/fstab

`, rackConvergeForeignJoin, rackAppliedHashPath, shellSingleQuote(hash))

	b.WriteString(heredoc("/etc/modules-load.d/tuist-k8s.conf", "0644", "modules", modulesLoadContent))
	b.WriteString(heredoc(rackinstall.ModprobePath, "0644", "modules", rackinstall.ModprobeConf))
	b.WriteString("modprobe overlay\nmodprobe br_netfilter\n")
	b.WriteString(heredoc("/etc/sysctl.d/99-tuist-k8s.conf", "0644", "sysctl", sysctlContent))
	b.WriteString(heredoc("/etc/sysctl.d/99-tuist-hardening.conf", "0644", "sysctl", kernelHardeningSysctlContent))
	b.WriteString("sysctl -q -p /etc/sysctl.d/99-tuist-k8s.conf\nsysctl -q -p /etc/sysctl.d/99-tuist-hardening.conf 2>/dev/null || true\n")
	if o.ManagementMAC != "" {
		b.WriteString(heredoc(rackManagementNetworkPath, "0644", "network", rackManagementNetwork(o.ManagementMAC)))
	} else {
		b.WriteString("unput " + rackManagementNetworkPath + " network\n")
	}
	b.WriteString(`if [ -n "${dirty[network]:-}" ]; then networkctl reload; fi
`)
	b.WriteString(heredoc("/etc/systemd/system.conf.d/10-tuist-watchdog.conf", "0644", "systemd", watchdogDropInContent))
	b.WriteString(`if [ -n "${dirty[systemd]:-}" ]; then systemctl daemon-reexec; fi

if ! dpkg-query -W -f='${Status}' containerd 2>/dev/null | grep -q 'install ok installed'; then
  apt_get update
  apt_get install containerd
  changed+=(containerd)
  dirty[containerd]=1
fi
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | put /etc/containerd/config.toml 0644 containerd
`)
	b.WriteString(heredoc("/etc/containerd/certs.d/docker.io/hosts.toml", "0644", "containerd", dockerHubMirrorHostsContent))

	fmt.Fprintf(&b, `
keyring=/etc/apt/keyrings/kubernetes-apt-keyring.gpg
source='deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/%[1]s/deb/ /'
refresh=0
if [ ! -s "$keyring" ] || ! grep -qxF "$source" /etc/apt/sources.list.d/kubernetes.list 2>/dev/null; then
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/%[1]s/deb/Release.key | gpg --batch --yes --dearmor -o "$keyring"
  printf '%%s\n' "$source" > /etc/apt/sources.list.d/kubernetes.list
  refresh=1
fi
package=$(kubelet_package %[2]s)
if [ -z "$package" ] || [ "$refresh" = 1 ]; then
  apt_get update
  package=$(kubelet_package %[2]s)
fi
if [ -z "$package" ]; then
  echo "tuist-converge: kubelet %[2]s is not published in pkgs.k8s.io %[1]s" >&2
  exit 1
fi
installed=$(dpkg-query -W -f='${Version}' kubelet 2>/dev/null || true)
if [ "$installed" != "$package" ]; then
  if [ -n "$installed" ] && dpkg --compare-versions "$installed" gt "$package"; then
    echo "tuist-converge: kubelet $installed is newer than $package; leaving it" >&2
  else
    apt_get install --allow-change-held-packages "kubelet=$package"
    changed+=("kubelet=$package")
    dirty[kubelet]=1
  fi
fi
apt-mark hold kubelet >/dev/null

`, o.K8sMinor, o.KubeletVersion)

	b.WriteString(heredoc("/etc/cni/net.d/10-tuist-rack-local.conflist", "0644", "cni", rackLocalCNIConfig()))
	b.WriteString(heredoc(kubeletClientCAPath, "0644", "kubelet", string(o.ClusterCAPEM)))
	b.WriteString(heredoc("/var/lib/kubelet/config.yaml", "0644", "kubelet", rackKubeletConfig(o)))
	b.WriteString(heredoc(rackKubernetesAPIPath, "0644", "api", o.KubernetesAPI))
	b.WriteString(heredoc("/etc/systemd/system/kubelet.service", "0644", "kubelet", rackKubeletUnit(o)))
	if o.BootstrapToken != "" {
		b.WriteString(heredoc(rackBootstrapKubeconfigPath, "0600", "kubelet",
			rackBootstrapKubeconfig(o.APIServerURL, o.ClusterCAPEM, o.BootstrapToken)))
		b.WriteString("bootstrap_supplied=1\n")
	} else {
		b.WriteString("rm -f " + rackBootstrapKubeconfigPath + "\nbootstrap_supplied=0\n")
	}

	fmt.Fprintf(&b, `
name=%s
if [ "$(hostnamectl --static)" != "$name" ]; then
  hostnamectl set-hostname "$name"
  sed -ri "s/^127\\.0\\.1\\.1[[:space:]].*/127.0.1.1 $name/" /etc/hosts
  changed+=(hostname)
fi
`, shellSingleQuote(o.NodeName))
	if o.Rejoin {
		b.WriteString(`systemctl stop kubelet >/dev/null 2>&1 || true
rm -rf /var/lib/kubelet/pki /var/lib/kubelet/kubeconfig
changed+=(identity)
`)
	}
	fmt.Fprintf(&b, `
if ! has_identity && [ "$bootstrap_supplied" = 0 ]; then
  echo "tuist-converge: the kubelet has no client certificate; it needs a bootstrap token" >&2
  echo "tuist-converge: changed=${changed[*]:-none}"
  exit %[1]d
fi

systemctl daemon-reload
systemctl enable containerd kubelet >/dev/null 2>&1
if [ -n "${dirty[containerd]:-}" ] || ! systemctl is-active --quiet containerd; then
  systemctl restart containerd
  restarted+=(containerd)
fi
if [ -n "${dirty[kubelet]:-}" ] || [ "$bootstrap_supplied" = 1 ] || ! systemctl is-active --quiet kubelet; then
  systemctl restart kubelet
  restarted+=(kubelet)
fi

if [ "$bootstrap_supplied" = 1 ]; then
  for _ in $(seq 1 90); do
    has_identity && break
    sleep 2
  done
  rm -f %[2]s
  if ! has_identity; then
    echo "tuist-converge: the kubelet did not get a client certificate" >&2
    journalctl -u kubelet -n 40 --no-pager >&2 || true
    exit 1
  fi
fi

mkdir -p "$(dirname %[3]s)"
printf '%%s\n' %[4]s > %[3]s
echo "tuist-converge: changed=${changed[*]:-none} restarted=${restarted[*]:-none}"
`, rackConvergeNeedsBootstrap, rackBootstrapKubeconfigPath, rackAppliedHashPath, shellSingleQuote(hash))
	return b.String()
}

const rackManagementNetworkPath = "/etc/systemd/network/10-tuist-management.network"

// rackManagementNetwork keeps the management port up for AMT, which shares
// it, with nothing of the host's on it: no address, no IPv6 link-local and no
// ARP, so the host does not answer on the management segment for addresses it
// holds elsewhere.
func rackManagementNetwork(mac string) string {
	return fmt.Sprintf(`[Match]
MACAddress=%s

[Link]
ARP=no
ActivationPolicy=always-up
RequiredForOnline=no

[Network]
LinkLocalAddressing=no
IPv6AcceptRA=no
`, mac)
}
