package linux

import (
	"encoding/json"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

func edgeConvergeOptions() rackConvergeOptions {
	return rackConvergeOptions{
		NodeName:       "ber1-edge",
		NodeIP:         "100.124.227.31",
		ProviderID:     "rack-linux://ber1/ber1-edge",
		KubeletVersion: "1.34.8",
		K8sMinor:       "v1.34",
		ClusterCAPEM:   []byte("-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n"),
		ClusterDNS:     "10.128.0.10",
		NodeLabels:     map[string]string{"tuist.dev/rack-edge": "ber1"},
		NodeTaints:     []corev1.Taint{{Key: "tuist.dev/rack-edge", Value: "ber1", Effect: corev1.TaintEffectNoSchedule}},
		APIServerURL:   "https://api.example:6443",
		KubernetesAPI:  "https://api.example:6443",
	}
}

func configFile(t *testing.T, cfg infrav1.RackNodeConfig, path string) infrav1.RackNodeFile {
	t.Helper()
	for _, f := range cfg.Files {
		if f.Path == path {
			return f
		}
	}
	t.Fatalf("the configuration writes no %s", path)
	return infrav1.RackNodeFile{}
}

func TestRackNodeConfigRegistersTheNodeAsDeclared(t *testing.T) {
	cfg := rackNodeConfig(edgeConvergeOptions())
	unit := configFile(t, cfg, "/etc/systemd/system/kubelet.service")
	for _, want := range []string{
		"--hostname-override=ber1-edge",
		"--node-ip=100.124.227.31",
		"--node-labels=cilium.io/no-schedule=true,node.cluster.x-k8s.io/instance-type=rack,tuist.dev/rack-edge=ber1",
		"--register-with-taints=tuist.dev/rack-edge=ber1:NoSchedule",
		"--bootstrap-kubeconfig=/var/lib/kubelet/bootstrap-kubeconfig",
		// The operator owns the node's addresses and adds one the control
		// plane can reach.
		"--cloud-provider=external",
	} {
		if !strings.Contains(unit.Content, want) {
			t.Errorf("the kubelet unit lacks %q", want)
		}
	}
	config := configFile(t, cfg, "/var/lib/kubelet/config.yaml")
	for _, want := range []string{"providerID: rack-linux://ber1/ber1-edge", "rotateCertificates: true", "clientCAFile: /var/lib/kubelet/ca.crt"} {
		if !strings.Contains(config.Content, want) {
			t.Errorf("the kubelet config lacks %q", want)
		}
	}
	if unit.Group != "kubelet" || config.Group != "kubelet" {
		t.Errorf("the kubelet's files do not restart it: %q %q", unit.Group, config.Group)
	}
	if !strings.Contains(configFile(t, cfg, "/etc/cni/net.d/10-tuist-rack-local.conflist").Content, `"subnet":"10.254.254.0/24"`) {
		t.Error("the local CNI is not on its range")
	}
	if cfg.Kubelet != (infrav1.RackNodeKubelet{Channel: "v1.34", Version: "1.34.8"}) || cfg.Hostname != "ber1-edge" {
		t.Errorf("kubelet %+v hostname %q", cfg.Kubelet, cfg.Hostname)
	}
	for _, f := range cfg.Files {
		if strings.Contains(f.Content, "token:") {
			t.Errorf("%s carries a token; a bootstrap token goes only in a join's request", f.Path)
		}
	}
}

func TestRackBootstrapKubeconfigCarriesTheToken(t *testing.T) {
	kubeconfig := rackBootstrapKubeconfig("https://api.example:6443", []byte("ca"), "abcdef.0123456789abcdef")
	for _, want := range []string{"token: abcdef.0123456789abcdef", "server: https://api.example:6443"} {
		if !strings.Contains(kubeconfig, want) {
			t.Errorf("the bootstrap kubeconfig lacks %q", want)
		}
	}
}

func TestRackNodeConfigHash(t *testing.T) {
	base := edgeConvergeOptions()
	for name, mutate := range map[string]func(*rackConvergeOptions){
		"API server a join dials": func(o *rackConvergeOptions) { o.APIServerURL = "https://other:6443" },
		"rejoin":                  func(o *rackConvergeOptions) { o.Rejoin = true },
	} {
		same := base
		mutate(&same)
		if rackNodeConfig(same).Hash != rackNodeConfig(base).Hash {
			t.Errorf("the %s changed the configuration hash", name)
		}
	}
	for name, mutate := range map[string]func(*rackConvergeOptions){
		"kubelet version":  func(o *rackConvergeOptions) { o.KubeletVersion = "1.34.9" },
		"tailnet address":  func(o *rackConvergeOptions) { o.NodeIP = "100.64.0.2" },
		"labels":           func(o *rackConvergeOptions) { o.NodeLabels = map[string]string{"a": "b"} },
		"cluster CA":       func(o *rackConvergeOptions) { o.ClusterCAPEM = []byte("other") },
		"API server":       func(o *rackConvergeOptions) { o.KubernetesAPI = "https://other:6443" },
		"management port":  func(o *rackConvergeOptions) { o.ManagementMAC = "38:05:25:38:b5:b5" },
		"hostname":         func(o *rackConvergeOptions) { o.NodeName = "ber1-edge-c" },
		"kubernetes minor": func(o *rackConvergeOptions) { o.K8sMinor = "v1.35" },
		"cluster DNS":      func(o *rackConvergeOptions) { o.ClusterDNS = "10.128.0.11" },
		"node taints":      func(o *rackConvergeOptions) { o.NodeTaints = nil },
		"provider ID":      func(o *rackConvergeOptions) { o.ProviderID = "rack-linux://ber1/other" },
	} {
		changed := base
		mutate(&changed)
		if rackNodeConfig(changed).Hash == rackNodeConfig(base).Hash {
			t.Errorf("a new %s left the configuration hash unchanged", name)
		}
	}
}

func TestParseControlPlaneVersion(t *testing.T) {
	kubelet, minor, ok := parseControlPlaneVersion("v1.34.8")
	if !ok || kubelet != "1.34.8" || minor != "v1.34" {
		t.Fatalf("got %q %q %v", kubelet, minor, ok)
	}
	if _, _, ok := parseControlPlaneVersion("1.34"); ok {
		t.Fatal("parsed a version without a patch release")
	}
}

// A node installed before the seed kept the Bluetooth driver out gets the
// same blacklist from its configuration.
func TestRackNodeConfigKeepsTheBluetoothDriverOut(t *testing.T) {
	f := configFile(t, rackNodeConfig(edgeConvergeOptions()), "/etc/modprobe.d/tuist-rack.conf")
	if f.Content != "blacklist btusb\n" || f.Group != "modules" {
		t.Fatalf("modprobe file %+v", f)
	}
}

// AMT shares the management port with the host, and a port the host does not
// configure stays down, taking AMT's link with it. The configuration keeps the
// port up with no address and no ARP of the host's on it.
func TestRackNodeConfigKeepsTheManagementPortUpForAMT(t *testing.T) {
	opts := edgeConvergeOptions()
	opts.ManagementMAC = "38:05:25:38:b5:b5"
	f := configFile(t, rackNodeConfig(opts), "/etc/systemd/network/10-tuist-management.network")
	want := "[Match]\nMACAddress=38:05:25:38:b5:b5\n\n" +
		"[Link]\nARP=no\nActivationPolicy=always-up\nRequiredForOnline=no\n\n" +
		"[Network]\nLinkLocalAddressing=no\nIPv6AcceptRA=no\n"
	if f.Content != want || f.Group != "network" {
		t.Fatalf("management port %+v", f)
	}
}

func TestRackNodeConfigDropsTheManagementPortWithoutABootMAC(t *testing.T) {
	cfg := rackNodeConfig(edgeConvergeOptions())
	for _, f := range cfg.Files {
		if f.Path == "/etc/systemd/network/10-tuist-management.network" {
			t.Fatal("wrote a management port configuration without a MAC to match")
		}
	}
	removed := false
	for _, f := range cfg.Absent {
		removed = removed || (f.Path == "/etc/systemd/network/10-tuist-management.network" && f.Group == "network")
	}
	if !removed {
		t.Fatalf("absent %+v; a host whose boot MAC was removed keeps its management port configuration", cfg.Absent)
	}
}

// A rack node reaches no Service address, so pods on it that talk to the API
// server, such as the rack's boot server, read the address its kubelet uses
// from the node.
func TestRackNodeConfigWritesTheAPIServerThePodsOnTheNodeUse(t *testing.T) {
	if f := configFile(t, rackNodeConfig(edgeConvergeOptions()), "/etc/tuist/kubernetes-api"); f.Content != "https://api.example:6443\n" {
		t.Fatalf("API server file %+v", f)
	}
}

// A pod on a rack node that is not on the host network reaches anything past
// its node's bridge, such as a public resolver or the server, only through a
// default route the CNI gives it.
func TestRackLocalCNIGivesPodsADefaultRouteThroughTheBridge(t *testing.T) {
	var config struct {
		Plugins []struct {
			Type      string `json:"type"`
			IsGateway bool   `json:"isGateway"`
			IPMasq    bool   `json:"ipMasq"`
			IPAM      struct {
				Routes []struct {
					Dst string `json:"dst"`
				} `json:"routes"`
			} `json:"ipam"`
		} `json:"plugins"`
	}
	if err := json.Unmarshal([]byte(rackLocalCNIConfig()), &config); err != nil {
		t.Fatalf("the CNI config is not JSON: %v", err)
	}
	bridge := config.Plugins[0]
	if bridge.Type != "bridge" || !bridge.IsGateway || !bridge.IPMasq {
		t.Fatalf("plugin %+v, want the masquerading gateway bridge", bridge)
	}
	if len(bridge.IPAM.Routes) != 1 || bridge.IPAM.Routes[0].Dst != "0.0.0.0/0" {
		t.Fatalf("routes %+v, want a default route", bridge.IPAM.Routes)
	}
}

// A pod on a rack node gets the cluster's in-cluster API address
// (KUBERNETES_SERVICE_HOST, the kubernetes Service), which no Service routing
// reaches there. The node translates it to the API server it joined through.
func TestRackNodeConfigRoutesTheKubernetesServiceToTheAPIServer(t *testing.T) {
	o := edgeConvergeOptions()
	o.KubernetesAPI = "https://49.12.18.71:443"
	o.KubernetesServiceIP = "10.128.0.1"
	cfg := rackNodeConfig(o)

	rules := configFile(t, cfg, rackKubernetesServicePath).Content
	for _, want := range []string{
		"delete table ip tuist_kubernetes_service",
		"type nat hook prerouting priority dstnat",
		"type nat hook output priority dstnat",
		"ip daddr 10.128.0.1 tcp dport 443 dnat to 49.12.18.71:443",
	} {
		if !strings.Contains(rules, want) {
			t.Errorf("the rules lack %q:\n%s", want, rules)
		}
	}
	if len(cfg.Nftables) != 1 || cfg.Nftables[0] != rackKubernetesServicePath {
		t.Fatalf("nftables %v, want the rules loaded", cfg.Nftables)
	}
}

func TestRackNodeConfigLeavesTheKubernetesServiceAloneWithoutAnAddressToTranslateTo(t *testing.T) {
	for name, o := range map[string]rackConvergeOptions{
		"no service address": func() rackConvergeOptions {
			o := edgeConvergeOptions()
			o.KubernetesAPI = "https://49.12.18.71:443"
			return o
		}(),
		"an API server hostname": func() rackConvergeOptions { o := edgeConvergeOptions(); o.KubernetesServiceIP = "10.128.0.1"; return o }(),
	} {
		cfg := rackNodeConfig(o)
		if len(cfg.Nftables) != 0 {
			t.Errorf("%s: loads %v", name, cfg.Nftables)
		}
		removed := false
		for _, f := range cfg.Absent {
			removed = removed || f.Path == rackKubernetesServicePath
		}
		if !removed {
			t.Errorf("%s: leaves an earlier rules file in place", name)
		}
	}
}
