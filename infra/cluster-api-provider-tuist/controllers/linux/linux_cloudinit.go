package linux

import (
	"context"
	"fmt"
	"strings"
	"time"

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

	// ClusterCAPEM is the cluster CA bundle (PEM). When set, the bootstrap
	// writes it to kubeletClientCAPath and points the kubelet's
	// authentication.x509.clientCAFile at it, so the kubelet trusts the
	// apiserver's --kubelet-client-certificate when it dials :10250 for
	// /containerLogs, /exec, and /port-forward. Without it the apiserver's
	// client cert can't be verified, the request authenticates as anonymous,
	// and (anonymous disabled) those streaming endpoints 401 — so kubectl logs
	// / exec against the node fail even once the address + serving cert are
	// right. These are the same bytes the kubeconfig embeds as
	// certificate-authority-data; the kubelet needs them as an on-disk file.
	ClusterCAPEM []byte

	// K8sMinor is the pkgs.k8s.io channel (e.g. "v1.34").
	//
	// Moving this to v1.36 or later silently drops the memory-floor protection
	// in kubeletMemoryGovernanceBlock: v1.36 gates it behind a new
	// memoryReservationPolicy field that defaults to None, so MemoryQoS becomes
	// a no-op here (memoryThrottlingFactor is already pinned to 1.0, which
	// disables the other half). Add `memoryReservationPolicy: TieredReservation`
	// in the same change — and not before, since an unknown field fails
	// KubeletConfiguration's strict decode and the kubelet refuses to start.
	K8sMinor string

	// Taints are rendered into kubelet's --register-with-taints.
	Taints []corev1.Taint

	// KataRuntime installs kata-static, registers the kata-qemu handler with
	// containerd, and labels the node for the kata-qemu RuntimeClass. Off for
	// cache fleets, which run ordinary runc Pods and should not pay the
	// download. See kataSetup for why this is safe to append to the distro
	// containerd's config rather than replacing the runtime.
	KataRuntime bool

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

	// kernelHardeningSysctlContent turns a silent kernel lockup into an
	// auto-rebooting panic instead of an indefinite freeze. A frozen bare-metal
	// box otherwise sits Node NotReady forever (the default kernel.panic=0 never
	// reboots), which strands its observability node-exporter DaemonSet pod below
	// full availability, times out the observability chart's `helm --wait`, and
	// wedges every deploy. The soft/hard lockup detectors panic on a stuck CPU;
	// panic_on_oops promotes an oops to a panic; kernel.panic=10 reboots 10s after
	// any panic. Applied to /etc/sysctl.d/99-tuist-hardening.conf.
	kernelHardeningSysctlContent = `kernel.softlockup_panic = 1
kernel.hardlockup_panic = 1
kernel.panic_on_oops = 1
kernel.panic = 10
`

	// watchdogDropInContent arms systemd's hardware watchdog: systemd pings
	// /dev/watchdog every RuntimeWatchdogSec, so if PID 1 itself wedges (a total
	// freeze that starves even the kernel lockup detectors the panic sysctls rely
	// on) the hardware watchdog fires and resets the box. This is the backstop the
	// panic sysctls can't provide. Boxes with no watchdog device just log and
	// ignore it. Written to /etc/systemd/system.conf.d/10-tuist-watchdog.conf.
	watchdogDropInContent = `[Manager]
RuntimeWatchdogSec=30s
RebootWatchdogSec=5min
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

	// kubeletClientCAPath is where the self-join drops the cluster CA so the
	// kubelet's authentication.x509.clientCAFile can verify the apiserver's
	// --kubelet-client-certificate. Kept under /var/lib/kubelet so it rides the
	// same /data bind-mount as the kubeconfig on separate-/data boxes (Dedibox),
	// rather than a path the mount would shadow.
	kubeletClientCAPath = "/var/lib/kubelet/ca.crt"
)

// kubeletMemoryGovernanceBlock is the memory half of the self-join kubelet
// config: how much of the box is held back from Pods, when the kubelet steps in
// as memory runs out, and how a Pod's request is protected while it does.
//
// Reservations. system/kube-reserved carve the daemons that live OUTSIDE any
// Pod (kubelet, containerd, systemd, kernel) out of allocatable. Without them
// allocatable equals capacity and the scheduler can promise Pods the whole box.
// They are flat daemon costs, so they do not scale with box size; the eviction
// threshold is a percentage so that headroom does. Deliberately lighter than the
// runner pool's 2Gi+2Gi/10% (see infra/k8s/clusters/bare-metal.yaml): these
// boxes are a quarter the size and run a handful of cache instances rather than
// dozens of microVMs whose guest RAM is their request.
//
// evictionHard REPLACES the kubelet's defaults wholesale rather than merging
// (mergeDefaultEvictionSettings defaults to false, and an omitted signal is set
// to 0 rather than left at its default), so all five disk and memory signals are
// restated. imagefs is its own filesystem on these boxes — bootstrapBody points
// containerd's root at /data wherever /data is a separate mount — so
// imagefs.inodesFree is not covered by the nodefs signals on /.
//
// Only memory.available moves off its default: 100Mi on a 31GiB box is thin
// enough that the
// kernel OOM killer usually wins the race, turning contention into a SIGKILL
// mid-transfer instead of an evicted Pod with an event. The signal subtracts
// inactive_file, so a cache node's reclaimable artifact page cache does not
// count toward it and a percentage threshold is safe on a file-serving box.
//
// MemoryQoS maps a Pod's request onto cgroup v2 memory.min/memory.low. Without
// it a request never reaches the kernel at all, so reclaim takes from whoever
// the LRU picks rather than from whoever is furthest above their own
// reservation — which is the whole premise of running cache Pods with a memory
// ceiling above their floor (see the kura-controller's memory profile). The
// feature is alpha and off by default; it is enabled here deliberately.
//
// memoryThrottlingFactor is pinned to 1.0, which sets memory.high to the limit
// and disables early throttling, keeping only the memory.min/memory.low
// protection. The default 0.9 would put memory.high at
// requests + 0.9*(limits-requests), and memory.high triggers on memory.current,
// which counts clean page cache. A warm Kura node holds clean artifact pages at
// its hard watermark as normal steady state (Kura's own shedding deliberately
// excludes them, keying off pressure_bytes instead), so early throttling would
// stall a perfectly healthy cache node reclaiming cache it is supposed to hold.
const kubeletMemoryGovernanceBlock = `systemReserved:
  cpu: 500m
  memory: 1Gi
kubeReserved:
  cpu: 500m
  memory: 1Gi
evictionHard:
  memory.available: 5%
  nodefs.available: 10%
  nodefs.inodesFree: 5%
  imagefs.available: 15%
  imagefs.inodesFree: 5%
featureGates:
  MemoryQoS: true
memoryThrottlingFactor: 1.0
`

// kubeletConfigContent renders the KubeletConfiguration for the self-join
// kubelet.
//
// Two fields deliberately differ from the kubeadm ClusterClass kubelet config
// the Hetzner nodes run, because the self-join kubelet authenticates as an
// operator-minted ServiceAccount, not a system:node:<name> identity:
//
//   - x509.clientCAFile is set (when clientCAFile != "") to the cluster CA the
//     bootstrap drops on disk, so the kubelet trusts the apiserver's
//     --kubelet-client-certificate for /containerLogs, /exec, and
//     /port-forward. Without it those requests authenticate as anonymous and,
//     with anonymous disabled, 401. The ClusterClass sets the same field for
//     the same reason.
//   - serverTLSBootstrap is intentionally NOT set (defaults to false), so the
//     kubelet serves a self-signed :10250 cert instead of requesting a
//     CA-signed one via CSR. serverTLSBootstrap would leave this kubelet with
//     no serving cert at all: the built-in serving-CSR approver only approves
//     when the requesting identity equals the CSR CN (system:node:<name>), and
//     a ServiceAccount requester never matches, so the CSR stays pending and
//     every :10250 dial fails `tls: internal error`. Nothing in the cluster
//     verifies kubelet serving certs (the apiserver sets no
//     --kubelet-certificate-authority; metrics-server runs --kubelet-insecure-tls),
//     so the self-signed cert is accepted — which is the whole point.
//
// clusterDNS, when non-empty, is appended as the kubelet's clusterDNS (a
// single-entry list) so pods resolve in-cluster Services; empty omits it
// (kubelet then logs MissingClusterDNS and falls back to host DNS).
func kubeletConfigContent(clusterDNS, clientCAFile string) string {
	x509Block := ""
	if clientCAFile != "" {
		x509Block = fmt.Sprintf("  x509:\n    clientCAFile: %s\n", clientCAFile)
	}
	config := `apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
` + x509Block + `authorization:
  mode: Webhook
clusterDomain: cluster.local
runtimeRequestTimeout: 5m
` + kubeletMemoryGovernanceBlock
	if clusterDNS != "" {
		config += fmt.Sprintf("clusterDNS:\n  - %s\n", clusterDNS)
	}
	return config
}

// clientCAFilePath returns the on-disk clientCAFile path when the options carry
// a cluster CA to write, or "" when they don't (keeping the kubelet config
// clientCAFile-free and rendering byte-identical to the pre-CA form).
func clientCAFilePath(opts linuxCloudInitOptions) string {
	if len(opts.ClusterCAPEM) == 0 {
		return ""
	}
	return kubeletClientCAPath
}

// kubeletUnitContent renders the kubelet systemd unit with the node's
// hostname-override, any register-with-taints argument, and the
// node.cluster.x-k8s.io/instance-type label (provider-specific).
func kubeletUnitContent(nodeName, taintArg, instanceType, extraNodeLabels string) string {
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
  %s--node-labels=node.cluster.x-k8s.io/instance-type=%s%s
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
`, nodeName, taintArg, instanceType, extraNodeLabels)
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
func bootstrapBody(k8sMinor, sudo, sudoE string, writeFile func(producer, path string) string, vlanSetup, kataSetup, containerdQuota string) string {
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
	hardeningSysctl := writeFile(
		"printf '%s' "+shellSingleQuote(kernelHardeningSysctlContent),
		"/etc/sysctl.d/99-tuist-hardening.conf",
	)
	watchdogDropIn := writeFile(
		"printf '%s' "+shellSingleQuote(watchdogDropInContent),
		"/etc/systemd/system.conf.d/10-tuist-watchdog.conf",
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
# Bare-metal lockup hardening: turn a silent kernel freeze into an auto-reboot so
# a hung box self-heals instead of sitting Node NotReady forever, which drops the
# observability node-exporter DaemonSet below full availability and wedges every
# deploy. The panic sysctls reboot on a detected lockup/oops; the systemd hardware
# watchdog resets the box if PID 1 itself wedges. Both are applied tolerantly (a
# missing knob or absent watchdog device must never abort the self-join).
%[2]smkdir -p /etc/sysctl.d /etc/systemd/system.conf.d
%[8]s
%[2]ssysctl -p /etc/sysctl.d/99-tuist-hardening.conf 2>/dev/null || true
%[9]s
%[2]ssystemctl daemon-reexec || true
export DEBIAN_FRONTEND=noninteractive
%[3]sapt-get update
%[3]sapt-get install -y apt-transport-https ca-certificates curl gpg containerd xfsprogs
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
%[10]s# The kura cache PVCs use a local-path StorageClass that carves each PV as a
# directory under /opt/local-path-provisioner. Bind that onto /data too, so the
# cache volumes land on the big disk rather than the ~20G root: without it two
# co-located replicas (replicas>=2 on a single box) fill the root and the second
# wedges on ENOSPC mid-bootstrap. Persisted via fstab (nofail) so it survives a
# reboot. Same guard as containerd above: a no-op where /data is not its own
# mounted filesystem, trailing 'true' keeps set -e happy.
%[2]ssh -c 'mountpoint -q /data && [ "$(findmnt -no SOURCE /data)" != "$(findmnt -no SOURCE /)" ] && { mkdir -p /data/local-path-provisioner /opt/local-path-provisioner; mountpoint -q /opt/local-path-provisioner || { grep -q " /opt/local-path-provisioner " /etc/fstab || echo "/data/local-path-provisioner /opt/local-path-provisioner none bind,nofail 0 0" >> /etc/fstab; mount --bind /data/local-path-provisioner /opt/local-path-provisioner; }; }; true'
%[11]s%[2]ssystemctl restart containerd
%[2]ssystemctl enable containerd
%[2]smkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/%[1]s/deb/Release.key | %[2]sgpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
%[5]s
%[3]sapt-get update
%[3]sapt-get install -y kubelet
%[2]sapt-mark hold kubelet
%[2]ssystemctl daemon-reload
%[2]ssystemctl enable --now kubelet`,
		k8sMinor, sudo, sudoE, containerdConfig, aptSource, mirrorHosts, vlanSetup, hardeningSysctl, watchdogDropIn,
		containerdQuota, kataSetup)
}

// vlanBringUp renders the PN-VLAN setup prepended to the bootstrap body when a
// VLAN id is set. Elastic Metal delivers the PN as a tagged VLAN on the primary
// NIC that the host must bring up itself before kubelet starts. The primary NIC
// name varies by hardware (e.g. enp65s0f0), so detect it at runtime: prefer the
// default-route interface, else the first non-lo physical NIC. Empty (and
// therefore a no-op) for the Instance kind, whose PN auto-DHCPs as a second
// interface.
//
// The bring-up is installed as a supervised systemd unit, not run once inline. A
// bare `ip link` + backgrounded `dhclient -nw` does not survive a reboot and is
// never renewed if that dhclient process dies, so the node silently loses its PN
// address (and with it the runner-cache NodePort) while still reporting Ready on
// its public NIC — invisible to the control plane, since kubelet binds the
// public InternalIP.
//
// The unit holds the address STATICALLY rather than leasing it for the life of
// the node. Scaleway's PN DHCP has been observed to stop ACKing renewals: a
// renew-forever dhclient (`dhclient -d` under Restart=always) keeps running, so
// Restart never fires, yet the lease still expires and the kernel drops the
// address — the exact silent-blackhole this unit exists to prevent. Instead the
// script DHCPs once to discover the IPAM-assigned address (the PN allocates it
// per attachment, so it is stable), caches it, and then re-asserts it as a
// static address with no expiry. pn0 is re-created on every boot, and the cached
// address re-applied, making the PN address durable across reboots, lease churn,
// and a silent DHCP server. The heredocs keep this on the SSH (non-indented)
// bootstrap path; the Instance/cloud-init path always passes vlan==0 and renders
// nothing here.
func vlanBringUp(sudo string, vlan uint32) string {
	if vlan == 0 {
		return ""
	}
	return fmt.Sprintf(`%[1]stee /usr/local/sbin/tuist-pn0-up.sh > /dev/null <<'TUIST_PN_EOF'
#!/usr/bin/env bash
set -eu
PRIMARY_NIC="$(ip -o route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -n1)"
if [ -z "$PRIMARY_NIC" ]; then
  PRIMARY_NIC="$(for n in /sys/class/net/*; do ifn="$(basename "$n")"; case "$ifn" in lo|pn*) continue;; esac; if [ -e "$n/device" ]; then echo "$ifn"; break; fi; done)"
fi
ip link show pn0 >/dev/null 2>&1 || ip link add link "$PRIMARY_NIC" name pn0 type vlan id %[2]d
ip link set pn0 up
CIDR_CACHE=/var/lib/tuist/pn0-cidr
if [ ! -s "$CIDR_CACHE" ]; then
  mkdir -p /var/lib/tuist
  for _ in $(seq 1 30); do
    timeout 15 dhclient -1 pn0 >/dev/null 2>&1 || true
    discovered="$(ip -4 -o addr show pn0 2>/dev/null | awk '{print $4; exit}' || true)"
    if [ -n "$discovered" ]; then printf '%%s\n' "$discovered" > "$CIDR_CACHE"; break; fi
    sleep 10
  done
fi
pkill -f 'dhclient.*pn0' >/dev/null 2>&1 || true
cidr="$(cat "$CIDR_CACHE" 2>/dev/null || true)"
if [ -z "$cidr" ]; then
  echo "pn0: PN address not assigned yet (IPAM lag); will retry" >&2
  exit 1
fi
while true; do
  ip addr replace "$cidr" dev pn0 2>/dev/null || true
  sleep 60
done
TUIST_PN_EOF
%[1]schmod 0755 /usr/local/sbin/tuist-pn0-up.sh
%[1]stee /etc/systemd/system/tuist-pn0.service > /dev/null <<'TUIST_PN_EOF'
[Unit]
Description=Tuist runner-cache Private Network VLAN (pn0)
Wants=network-online.target
After=network-online.target
[Service]
Type=exec
ExecStart=/usr/local/sbin/tuist-pn0-up.sh
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
TUIST_PN_EOF
%[1]ssystemctl daemon-reload
%[1]ssystemctl enable --now tuist-pn0.service || true
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
	body := indent(bootstrapBody(opts.K8sMinor, sudo, sudoE, writeFile, vlanSetup, kataSetup(sudo, sudoE, opts.KataRuntime), containerdQuotaSetup(sudo, writeFile, hostsKuraCacheVolumes(opts.Taints))), "      ")

	// Optional cluster-CA write_files entry: written so the kubelet's
	// clientCAFile can verify the apiserver's client cert (see
	// kubeletConfigContent). Empty (no leading entry) when no CA is supplied,
	// leaving the rendered output byte-identical to the pre-CA form.
	caEntry := ""
	if len(opts.ClusterCAPEM) > 0 {
		caEntry = fmt.Sprintf("  - path: %s\n    permissions: '0644'\n    content: |\n%s\n",
			kubeletClientCAPath, indent(string(opts.ClusterCAPEM), "      "))
	}

	return fmt.Sprintf(`#cloud-config
write_files:
  - path: /var/lib/kubelet/kubeconfig
    permissions: '0600'
    content: |
%[1]s
%[7]s  - path: /etc/modules-load.d/k8s.conf
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
		indent(kubeletUnitContent(opts.NodeName, taintArg, instanceTypeOrDefault(opts.InstanceType), kataNodeLabelsArg(opts.KataRuntime)), "      "),
		indent(kubeletConfigContent(opts.ClusterDNS, clientCAFilePath(opts)), "      "),
		body,
		caEntry,
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
	body := bootstrapBody(opts.K8sMinor, sudo, sudoE, writeFile, vlanSetup, kataSetup(sudo, sudoE, opts.KataRuntime), containerdQuotaSetup(sudo, writeFile, hostsKuraCacheVolumes(opts.Taints)))

	heredoc := func(path, content string) string {
		// `<<'EOF'` keeps the body literal (no shell expansion of $ or `).
		writer := sudo + "tee " + path + " > /dev/null"
		return fmt.Sprintf("%s <<'TUIST_EOF'\n%sTUIST_EOF", writer, ensureTrailingNewline(content))
	}

	// Optional cluster-CA heredoc, dropped alongside the kubeconfig so the
	// kubelet's clientCAFile can verify the apiserver's client cert (see
	// kubeletConfigContent). Trailing newline so the next heredoc stays on its
	// own line; empty when no CA is supplied.
	caWrite := ""
	if len(opts.ClusterCAPEM) > 0 {
		caWrite = heredoc(kubeletClientCAPath, string(opts.ClusterCAPEM)) + "\n"
	}

	return fmt.Sprintf(`#!/usr/bin/env bash
set -euxo pipefail
%[8]s%[1]smkdir -p /var/lib/kubelet /etc/modules-load.d /etc/sysctl.d /etc/systemd/system /opt
# Turn project quotas on for /data before anything mounts off it: XFS only takes
# quota accounting at mount time, and the bind below would pin the filesystem
# busy. Aborts the join on a box whose /data cannot carry per-account quotas.
%[11]s
# Bring up the kubelet root's /data bind-mount BEFORE writing its config below, so
# a box with a separate /data disk doesn't shadow config.yaml + kubeconfig once
# the mount lands (which left the kubelet crash-looping on a missing config).
%[9]s
%[2]s
%[1]schmod 0600 /var/lib/kubelet/kubeconfig
%[10]s%[3]s
%[4]s
%[5]s
%[6]s
%[7]s
`,
		sudo,
		heredoc("/var/lib/kubelet/kubeconfig", opts.KubeconfigYAML),
		heredoc("/etc/modules-load.d/k8s.conf", modulesLoadContent),
		heredoc("/etc/sysctl.d/99-k8s.conf", sysctlContent),
		heredoc("/etc/systemd/system/kubelet.service", kubeletUnitContent(opts.NodeName, taintArg, instanceTypeOrDefault(opts.InstanceType), kataNodeLabelsArg(opts.KataRuntime))),
		heredoc("/var/lib/kubelet/config.yaml", kubeletConfigContent(opts.ClusterDNS, clientCAFilePath(opts))),
		body,
		nopasswdSetup(opts.BootstrapUser, opts.SudoPassword),
		dataKubeletMount(sudo),
		caWrite,
		dataProjectQuotaSetup(sudo, writeFile),
	)
}

// dataProjectQuotaPath is where the self-join drops the script that turns
// project quotas on for /data. Kept on disk (rather than inlined) because it is
// also the recovery step an operator runs by hand after changing /etc/fstab.
const dataProjectQuotaPath = "/usr/local/sbin/tuist-data-prjquota.sh"

// dataProjectQuotaScript makes /data carry XFS project quotas, or refuses to let
// the box join.
//
// Every Kura cache directory on these boxes is a local-path PV: a directory on
// /data. A directory has no size, so nothing in Kubernetes bounds what one
// account's instance writes. The pod's ephemeral-storage request is scheduler
// admission at placement time, and an ephemeral-storage LIMIT would be enforced
// against the pod's writable layer, logs and emptyDir, none of which is where
// the cache lives. XFS project quotas are the only real boundary, and they are
// what the provisioner's per-volume hooks set. One instance filling the box
// crosses kubelet's eviction line and takes down every tenant on it, not just
// the account that filled it.
//
// Two things make this a hard failure rather than a warning. Quota accounting is
// a mount-time decision on XFS (`mount -o remount` cannot add it), so the
// remount has to happen here, before anything binds onto /data, or not until the
// next reboot. And a box that joins without it looks completely healthy while
// being the one thing this change exists to prevent: unbounded, shared, and
// only visibly wrong once a tenant has already taken the box down. Failing the
// join surfaces that as a Machine that never goes Ready.
//
// A box with no separate /data (the single-filesystem Elastic Metal shape) is
// left alone: it has no /data for cache directories to land on, so there is
// nothing here to enforce.
const dataProjectQuotaScript = `#!/usr/bin/env bash
set -euo pipefail

data=/data

mountpoint -q "$data" || exit 0
[ "$(findmnt -no SOURCE "$data")" != "$(findmnt -no SOURCE /)" ] || exit 0

fstype="$(findmnt -no FSTYPE "$data")"
if [ "$fstype" != xfs ]; then
  echo "tuist: $data is $fstype, but per-account cache quotas need xfs project quotas." >&2
  echo "tuist: this box predates the xfs /data layout and cannot grow one in place; reinstall it (mise run baremetal:prep-ovh / prep-dedibox) before it can rejoin." >&2
  exit 1
fi

has_project_quota() {
  case ",$(findmnt -no OPTIONS "$data")," in
    *,prjquota,*|*,pquota,*) return 0 ;;
  esac
  return 1
}

if ! has_project_quota; then
  if ! grep -qE "^[^#]+[[:space:]]+/data[[:space:]]" /etc/fstab; then
    echo "tuist: $data is mounted but has no /etc/fstab entry to add prjquota to." >&2
    exit 1
  fi
  # Rewrite only the /data options field; awk leaves every other line byte-identical
  # because it only rebuilds a record whose fields it assigned. Written back through
  # cat so /etc/fstab keeps its own inode and permissions.
  awk '$1 !~ /^#/ && $2 == "/data" && $4 !~ /(^|,)(prjquota|pquota)(,|$)/ { $4 = $4 ",prjquota" } { print }' /etc/fstab > /tmp/fstab.tuist
  cat /tmp/fstab.tuist > /etc/fstab
  rm -f /tmp/fstab.tuist
  # Safe at this point in the join: nothing has bind-mounted off /data yet, so
  # the cycle cannot hit EBUSY and no running workload sees it disappear.
  umount "$data"
  mount "$data"
fi

if ! has_project_quota; then
  echo "tuist: $data remounted without project quotas active; refusing to join an unbounded cache box." >&2
  exit 1
fi
`

// kuraCacheTaintKey marks a box as a Kura cache region. Every cache fleet
// template hardcodes it (ovh-fleet.yaml, ovh-fleets.yaml's default,
// dedibox-fleet.yaml); a pool that is not a cache region overrides nodeTaints
// with its own, which is already what keeps it out of the cache-only surfaces
// keyed off that map. Reusing it here keeps one source of truth for "is this a
// cache box" rather than adding a second that can drift from the taint.
const kuraCacheTaintKey = "tuist.dev/kura-cache"

// hostsKuraCacheVolumes reports whether tenant cache volumes land on this box's
// /data, which is the only thing the image-store quota exists to protect.
//
// Absence of the taint means no quota. The two ways to be wrong here are
// asymmetric: quota-ing a box that has no tenants buys nothing and costs a hard
// ENOSPC ceiling that no GC can clear (image GC keys on the filesystem, which is
// nowhere near full), while skipping a box that does have tenants only returns
// it to the defence-in-depth it had before the quota existed.
func hostsKuraCacheVolumes(taints []corev1.Taint) bool {
	for _, taint := range taints {
		if taint.Key == kuraCacheTaintKey {
			return true
		}
	}
	return false
}

// containerdProjectID is the reserved XFS project for the image store. Volume
// projects are hashed into [1000, 16000999] by the provisioner hook, so a small
// fixed id below that range cannot collide with one.
const containerdProjectID = 100

// containerdQuotaBytes caps the image store at 64 GiB. The number is chosen to
// sit several times above the fleet's real image footprint and still be a small
// share of a cache box, because the two ways to get it wrong are asymmetric.
//
// Too low and containerd hits ENOSPC on a pull while the filesystem still has
// room, which the kubelet cannot resolve: image GC triggers on the FILESYSTEM's
// available space, not on a project's, so nothing would reclaim anything and
// the node would simply stop being able to start pods. Too high and it stops
// being a bound. So this is deliberately a backstop against unbounded growth
// rather than a tight fit, and it is worth revisiting against what the exporter
// reports for project 100 once there is fleet data.
const containerdQuotaBytes = 64 * 1024 * 1024 * 1024

// containerdQuotaPath is where the self-join drops the image-store quota script.
const containerdQuotaPath = "/usr/local/sbin/tuist-containerd-quota.sh"

// containerdQuotaScript gives the relocated image store its own project quota.
//
// Tenant volumes are each bounded by their own project, but they all draw from
// one pool, and the image store draws from the same pool without being anyone's
// tenant. A per-volume quota is a ceiling, not a reservation, so a tenant that
// stays inside its own ceiling can still be denied space that something else
// took first. Nothing else bounds containerd here: the kubelet's image GC keys
// on the filesystem's available space, so it only reclaims once the whole box is
// nearly full, by which point tenants have already been squeezed.
//
// Unlike dataProjectQuotaScript this does NOT fail the join. A box that reaches
// this point has already proven it can enforce, and every tenant on it is
// bounded either way; what is lost is defence in depth on the shared pool, which
// is the state the box was in before. Refusing to join over it would trade a
// real outage for a theoretical one. Its absence is visible instead: the usage
// exporter reads /etc/projects, so a missing project 100 shows up as the image
// store dropping out of the report.
//
// Bytes only, no inode ceiling. Image layers are inode-heavy and the failure
// mode of a wrong inode bound is the same unrecoverable pull failure described
// on containerdQuotaBytes, with none of the pool protection.
var containerdQuotaScript = fmt.Sprintf(`#!/usr/bin/env bash
set -euo pipefail

data=/data
dir=/data/containerd
projid=%[1]d
bytes=%[2]d

mountpoint -q "$data" || exit 0
[ "$(findmnt -no SOURCE "$data")" != "$(findmnt -no SOURCE /)" ] || exit 0
[ "$(findmnt -no FSTYPE "$data")" = xfs ] || exit 0
case ",$(findmnt -no OPTIONS "$data")," in
  *,prjquota,*|*,pquota,*) ;;
  *) exit 0 ;;
esac

exec 9>/var/lock/tuist-kura-quota.lock
flock 9

mkdir -p "$dir"

# Idempotent: the path is a fixed literal, so a plain filter is enough to drop a
# previous entry before re-adding it.
if [ -f /etc/projects ]; then
  grep -v ":$dir$" /etc/projects > /etc/projects.tuist || true
  cat /etc/projects.tuist > /etc/projects
  rm -f /etc/projects.tuist
fi
printf '%%s:%%s\n' "$projid" "$dir" >> /etc/projects

xfs_quota -x -c "project -s -p $dir $projid" "$data" >/dev/null
xfs_quota -x -c "limit -p bhard=$bytes $projid" "$data"
`, containerdProjectID, containerdQuotaBytes)

// containerdQuotaSetup installs and runs containerdQuotaScript. It has to come
// after the image store has been relocated onto /data (the directory has to
// exist to carry a project) and after apt has installed xfsprogs, which is why
// it lives in bootstrapBody rather than beside the /data mount setup.
func containerdQuotaSetup(sudo string, writeFile func(producer, path string) string, cacheVolumes bool) string {
	if !cacheVolumes {
		return ""
	}
	return strings.Join([]string{
		"# Bound the image store's share of /data. It is the one consumer on that",
		"# filesystem that is not a tenant, and nothing else caps it: image GC keys on",
		"# the FILESYSTEM being 85% full, so on a box whose tenants are light containerd",
		"# can grow into the headroom their quotas were written against and starve them",
		"# below their own ceilings. Tolerated on failure (see containerdQuotaScript).",
		writeFile("printf '%s' "+shellSingleQuote(containerdQuotaScript), containerdQuotaPath),
		sudo + "chmod 0755 " + containerdQuotaPath,
		sudo + "bash " + containerdQuotaPath + " || echo 'tuist: could not bound the containerd image store; continuing' >&2",
		"",
	}, "\n")
}

// dataProjectQuotaSetup installs and runs dataProjectQuotaScript. It has to run
// before ANY bind-mount off /data: enabling quota accounting means a real
// unmount/mount cycle, and the kubelet-root bind two lines later would pin the
// filesystem busy.
func dataProjectQuotaSetup(sudo string, writeFile func(producer, path string) string) string {
	return strings.Join([]string{
		writeFile("printf '%s' "+shellSingleQuote(dataProjectQuotaScript), dataProjectQuotaPath),
		sudo + "chmod 0755 " + dataProjectQuotaPath,
		sudo + "bash " + dataProjectQuotaPath,
	}, "\n")
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

// kataVersion is the kata-containers release installed when KataRuntime is set.
// Pinned and bumped deliberately: kata releases have historically shipped
// install-script regressions, and the guest kernel/image pairing is what runner
// Pods actually boot. Keep it in lockstep with the Hetzner bare-metal worker
// (`infra/k8s/clusters/bare-metal.yaml`), which pre-bakes the same version, so a
// job behaves the same whichever fleet it lands on.
const kataVersion = "3.30.0"

// kataVersionStampPath records which kata release the box has unpacked, so the
// install block above is a no-op on a box that already carries it.
const kataVersionStampPath = "/opt/kata/.tuist-kata-version"

// kataSetup installs kata-static and registers the kata-qemu handler with
// containerd. Empty (a no-op) unless the fleet asked for it, so cache boxes
// neither download it nor carry the runtime block.
//
// This APPENDS to the distro containerd's config rather than replacing
// containerd the way the Hetzner worker template does. That template installs
// containerd 2.x from upstream because Ubuntu Noble shipped 1.7.x, which only
// understands `version = 2` / `io.containerd.grpc.v1.cri` and would silently
// fail to register a handler written in the v3 syntax below. Noble has since
// moved to containerd 2.x (2.2.1 as of this writing, emitting `version = 3`),
// so the apt package the bootstrap already installs parses this block. The
// guard below is what keeps that from being a silent assumption: on a box whose
// containerd is too old to emit a v3 config, the join fails loudly here rather
// than coming up with every kata Pod stuck in creation.
//
// Ordering matters: this runs after the config is generated and after the
// SystemdCgroup rewrite, but before containerd restarts, so the handler is
// registered by the time kubelet first talks to it.
func kataSetup(sudo, sudoE string, enabled bool) string {
	if !enabled {
		return ""
	}
	return fmt.Sprintf(`# ---- Kata Containers %[3]s (runner fleets only) ----
# Fail loud if containerd predates the v3 config syntax the handler below is
# written in: registering it against a v2 config is silently ignored, and the
# node then reports Ready while every runtimeClassName=kata-qemu Pod hangs.
%[1]sgrep -q '^version = 3' /etc/containerd/config.toml || { echo "tuist: containerd config is not version 3; the kata-qemu handler would be ignored. Refusing to join a runner node that cannot run microVM Pods." >&2; exit 1; }
%[2]sapt-get install -y zstd
# kata-static expands with a top-level opt/, so extracting at / lands the shim
# and its bundled qemu under /opt/kata/{bin,libexec,share}. Guarded on a version
# stamp so a re-run costs nothing: the repair loop re-runs this block on every
# retry against a box whose verification keeps failing, and an unguarded pull
# would drag ~250 MiB off GitHub each time. Stamping the version (rather than
# just testing for the shim) keeps a kataVersion bump reinstalling.
if [ "$(cat %[4]s 2>/dev/null)" != "%[3]s" ]; then
  curl -fsSL -o /tmp/kata.tar.zst "https://github.com/kata-containers/kata-containers/releases/download/%[3]s/kata-static-%[3]s-amd64.tar.zst"
  %[1]star --zstd -xf /tmp/kata.tar.zst -C /
  rm -f /tmp/kata.tar.zst
  printf '%%s' "%[3]s" | %[1]stee %[4]s > /dev/null
fi
# Idempotent: a re-bootstrap of an already-kata box must not append twice.
%[1]ssh -c 'grep -q "runtimes.kata-qemu" /etc/containerd/config.toml || cat >> /etc/containerd/config.toml' <<'TUIST_KATA_EOF'

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.kata-qemu]
runtime_type = "io.containerd.kata-qemu.v2"
runtime_path = "/opt/kata/bin/containerd-shim-kata-v2"
privileged_without_host_devices = true
pod_annotations = ["io.katacontainers.*"]
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.kata-qemu.options]
ConfigPath = "/opt/kata/share/defaults/kata-containers/configuration-qemu.toml"
# SystemdCgroup MUST be set on the handler itself. The SystemdCgroup rewrite
# above only touches what the generated default emitted, and this block is
# appended after it, so the kata handler would otherwise keep the false default
# while kubelet runs cgroupDriver: systemd. Under that mismatch the shim creates
# the slice name as a LITERAL directory at the cgroup root instead of nesting it
# under kubepods.slice, nothing ever reclaims those, and the node eventually
# fails every cgroup mkdir with ENOSPC while still reporting Ready. See the
# same block in infra/k8s/clusters/bare-metal.yaml for the measured detail.
SystemdCgroup = true
TUIST_KATA_EOF
`, sudo, sudoE, kataVersion, kataVersionStampPath)
}

// kataNodeLabels are appended to the kubelet's --node-labels when the fleet runs
// kata, and are the same labels the repair loop patches onto a node that joined
// without them. `katacontainers.io/kata-runtime` is what the kata-qemu
// RuntimeClass selects on, so without it a runner Pod never schedules here;
// `tuist.dev/kata-runtime` mirrors the Hetzner workers so anything keying off our
// own label sees both fleets alike. Both sit outside the kubernetes.io/k8s.io
// namespaces the NodeRestriction admission plugin reserves, so a kubelet may
// self-apply them.
//
// An ordered slice, not a map: it renders into the kubelet unit, and a map's
// iteration order would churn that unit's content between reconciles.
var kataNodeLabels = []struct{ Key, Value string }{
	{KataRuntimeSelectorLabel, "true"},
	{"tuist.dev/kata-runtime", "true"},
}

func kataNodeLabelsArg(enabled bool) string {
	if !enabled {
		return ""
	}
	var arg strings.Builder
	for _, label := range kataNodeLabels {
		arg.WriteString("," + label.Key + "=" + label.Value)
	}
	return arg.String()
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
	// Bound the read: the reconcile context has no deadline of its own, so a
	// slow/unreachable read here would block the controller's (single) worker
	// indefinitely and silently stall every subsequent reconcile. On timeout we
	// fall through to an unset clusterDNS, the same best-effort behaviour as any
	// other read failure.
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	svc := &corev1.Service{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: "kube-system", Name: "kube-dns"}, svc); err != nil {
		log.FromContext(ctx).Info("could not resolve kube-dns ClusterIP; kubelet clusterDNS will be unset", "err", err.Error())
		return ""
	}
	return svc.Spec.ClusterIP
}
