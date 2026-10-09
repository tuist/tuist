package linux

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net"
	"net/url"
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

	rackKubernetesServicePath = "/etc/tuist/kubernetes-service.nft"

	// rackStaticPodPath is where the kubelet runs static pods from: what a
	// node runs before it reaches the API server, such as an edge's rack-edge
	// after a cold boot.
	rackStaticPodPath = "/etc/kubernetes/manifests"
)

// rackConvergeOptions is everything a rack node's configuration renders
// from.
type rackConvergeOptions struct {
	NodeName string
	// Role is the host's spec.role. An edge routes the rack to the internet
	// over uplinks that carry no address of the host's (rackEdgeFiles).
	Role       string
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

	// KubernetesServiceIP is the kubernetes Service's ClusterIP, the API
	// address in-cluster clients are given. The node translates it to
	// KubernetesAPI, so those clients work on it unchanged.
	KubernetesServiceIP string

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
// names for host-network pods. Static pods run from rackStaticPodPath.
func rackKubeletConfig(o rackConvergeOptions) string {
	return kubeletConfigContent(o.ClusterDNS, kubeletClientCAPath) + fmt.Sprintf(`providerID: %s
rotateCertificates: true
resolvConf: /etc/resolv.conf
staticPodPath: %s
`, o.ProviderID, rackStaticPodPath)
}

// rackLocalCNIConfig is the node-local pod network. The bridge is the pods'
// default gateway and masquerades them behind the node, so a pod off the host
// network reaches what the node reaches.
func rackLocalCNIConfig() string {
	return fmt.Sprintf(`{"cniVersion":"1.0.0","name":"rack-local","plugins":[{"type":"bridge","bridge":"cni-racklocal","isGateway":true,"ipMasq":true,"ipam":{"type":"host-local","ranges":[[{"subnet":"%s"}]],"routes":[{"dst":"0.0.0.0/0"}]}},{"type":"portmap","capabilities":{"portMappings":true}}]}
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
		Hostname:    o.NodeName,
		Directories: []string{rackStaticPodPath},
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
	if rules := rackKubernetesServiceRules(o); rules != "" {
		cfg.Files = append(cfg.Files, file(rackKubernetesServicePath, "none", rules))
		cfg.Nftables = []string{rackKubernetesServicePath}
	} else {
		cfg.Absent = append(cfg.Absent, infrav1.RackNodeFile{Path: rackKubernetesServicePath, Group: "none"})
	}
	if o.ManagementMAC != "" {
		cfg.Files = append(cfg.Files, file(rackManagementNetworkPath, "network", rackManagementNetwork(o.ManagementMAC)))
	} else {
		cfg.Absent = append(cfg.Absent, infrav1.RackNodeFile{Path: rackManagementNetworkPath, Group: "network"})
	}
	for _, f := range rackEdgeFiles() {
		if o.Role == "edge" {
			cfg.Files = append(cfg.Files, file(f.Path, f.Group, f.Content))
		} else {
			cfg.Absent = append(cfg.Absent, infrav1.RackNodeFile{Path: f.Path, Group: f.Group})
		}
	}
	if o.Role == "edge" {
		cfg.Sysctl = append(cfg.Sysctl, infrav1.RackNodeSysctl{Path: rackEdgeSysctlPath})
	}
	body, _ := json.Marshal(cfg)
	sum := sha256.Sum256(body)
	cfg.Hash = hex.EncodeToString(sum[:])
	return cfg
}

// rackKubernetesServiceRules translates the kubernetes Service's address to
// the API server the node joined through, for pods on the node's own network
// and on the host's. It needs both as IP addresses, and is empty otherwise:
// nftables translates to an address, not a name.
func rackKubernetesServiceRules(o rackConvergeOptions) string {
	service := net.ParseIP(o.KubernetesServiceIP)
	api, err := url.Parse(o.KubernetesAPI)
	if service.To4() == nil || err != nil {
		return ""
	}
	host, port := api.Hostname(), api.Port()
	if port == "" {
		port = "443"
	}
	if net.ParseIP(host).To4() == nil {
		return ""
	}
	rule := fmt.Sprintf("ip daddr %s tcp dport 443 dnat to %s:%s", service, host, port)
	return fmt.Sprintf(`table ip tuist_kubernetes_service
delete table ip tuist_kubernetes_service
table ip tuist_kubernetes_service {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    %[1]s
  }
  chain output {
    type nat hook output priority dstnat; policy accept;
    %[1]s
  }
}
`, rule)
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

const (
	rackEdgeUplinksNetworkPath = "/etc/systemd/network/05-tuist-edge-uplinks.network"
	rackEdgeNetworkdPath       = "/etc/systemd/networkd.conf.d/10-tuist-edge.conf"
	rackEdgeResolvedPath       = "/etc/systemd/resolved.conf.d/10-tuist-edge.conf"
	rackEdgeSysctlPath         = "/etc/sysctl.d/99-tuist-edge.conf"
)

// rackEdgeFiles are an edge's host networking. The rack-edge pod puts the
// WAN on a VLAN interface of its own (wan0) and routes over the X710 uplinks
// (driver i40e) itself, with `ip route` and keepalived, so the uplinks carry
// no address of the host's.
//
// The uplinks' file sorts before netplan's 10-netplan-uplinks.network, which
// the install leaves with DHCP on them, and networkd applies the first file
// that matches a link. It keeps them up with no address, no DHCP, no IPv6
// link-local and no router advertisements, configured without carrier, and
// boot does not wait for them.
//
// networkd leaves routes and routing policy rules it did not configure alone,
// as keepalived's and the pod's on the uplinks. With no address on the
// uplinks, systemd-resolved learns no resolver from them, so the edge
// resolves through global ones.
//
// A nexthop on an uplink whose link is down is skipped, since the pod's
// routes to the ToRs are multipath over both uplinks. No interface takes
// router advertisements by default, so wan0, which the pod creates, never
// takes one from upstream.
func rackEdgeFiles() []infrav1.RackNodeFile {
	return []infrav1.RackNodeFile{
		{Path: rackEdgeUplinksNetworkPath, Group: "network", Content: `[Match]
Driver=i40e

[Link]
ActivationPolicy=always-up
RequiredForOnline=no

[Network]
DHCP=no
LinkLocalAddressing=no
IPv6AcceptRA=no
ConfigureWithoutCarrier=yes
`},
		{Path: rackEdgeNetworkdPath, Group: "networkd", Content: `[Network]
ManageForeignRoutes=no
ManageForeignRoutingPolicyRules=no
`},
		{Path: rackEdgeResolvedPath, Group: "resolved", Content: `[Resolve]
DNS=1.1.1.1 8.8.8.8
`},
		{Path: rackEdgeSysctlPath, Group: "sysctl", Content: `net.ipv4.conf.all.ignore_routes_with_linkdown = 1
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
`},
	}
}
