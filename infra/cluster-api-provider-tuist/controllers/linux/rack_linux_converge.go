package linux

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	corev1 "k8s.io/api/core/v1"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackinstall"
)

const (
	// rackLocalCNIRange is the local CNI's pod range: outside the cluster's
	// pod CIDR (192.168.0.0/16), its service CIDR (10.128.0.0/12), the
	// tailnet (100.64.0.0/10) and the rack's own segments.
	rackLocalCNIRange = "10.254.254.0/24"

	rackInstanceType = "rack"

	ciliumNoScheduleLabel = "cilium.io/no-schedule"

	rackBootstrapKubeconfigPath = "/var/lib/kubelet/bootstrap-kubeconfig"

	rackKubernetesAPIPath = "/etc/tuist/kubernetes-api"
)

// rackConvergeOptions is everything a rack node's configuration renders
// from.
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

	// APIServerURL is what a join's bootstrap kubeconfig points the kubelet
	// at. Rejoin drops the kubelet's identity first, for a host joining again
	// under a new name. Neither is part of the configuration.
	APIServerURL string
	Rejoin       bool
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

// rackNodeConfig renders what the host runs as a node, for the node agent
// (internal/racknode) to apply. Its hash covers everything but itself.
func rackNodeConfig(o rackConvergeOptions) infrav1.RackNodeConfig {
	file := func(path, group, content string) infrav1.RackNodeFile {
		return infrav1.RackNodeFile{Path: path, Mode: "0644", Group: group, Content: ensureTrailingNewline(content)}
	}
	cfg := infrav1.RackNodeConfig{
		Hostname: o.NodeName,
		Files: []infrav1.RackNodeFile{
			file("/etc/modules-load.d/tuist-k8s.conf", "modules", modulesLoadContent),
			file(rackinstall.ModprobePath, "modules", rackinstall.ModprobeConf),
			file("/etc/sysctl.d/99-tuist-k8s.conf", "sysctl", sysctlContent),
			file("/etc/sysctl.d/99-tuist-hardening.conf", "sysctl", kernelHardeningSysctlContent),
			file("/etc/systemd/system.conf.d/10-tuist-watchdog.conf", "systemd", watchdogDropInContent),
			file("/etc/containerd/certs.d/docker.io/hosts.toml", "containerd", dockerHubMirrorHostsContent),
			file("/etc/cni/net.d/10-tuist-rack-local.conflist", "cni", rackLocalCNIConfig()),
			file(kubeletClientCAPath, "kubelet", string(o.ClusterCAPEM)),
			file("/var/lib/kubelet/config.yaml", "kubelet", rackKubeletConfig(o)),
			file("/etc/systemd/system/kubelet.service", "kubelet", rackKubeletUnit(o)),
			file(rackKubernetesAPIPath, "api", o.KubernetesAPI),
		},
		Modules: []string{"overlay", "br_netfilter"},
		Sysctl: []infrav1.RackNodeSysctl{
			{Path: "/etc/sysctl.d/99-tuist-k8s.conf"},
			{Path: "/etc/sysctl.d/99-tuist-hardening.conf", Optional: true},
		},
		Containerd: infrav1.RackNodeContainerd{ConfigPath: "/etc/containerd/config.toml"},
		Kubelet:    infrav1.RackNodeKubelet{Channel: o.K8sMinor, Version: o.KubeletVersion},
	}
	if o.ManagementMAC != "" {
		cfg.Files = append(cfg.Files, file(rackManagementNetworkPath, "network", rackManagementNetwork(o.ManagementMAC)))
	} else {
		cfg.Absent = append(cfg.Absent, infrav1.RackNodeFile{Path: rackManagementNetworkPath, Group: "network"})
	}
	body, _ := json.Marshal(cfg)
	sum := sha256.Sum256(body)
	cfg.Hash = hex.EncodeToString(sum[:])
	return cfg
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
