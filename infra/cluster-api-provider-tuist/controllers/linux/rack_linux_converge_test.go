package linux

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
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

func TestRackConvergeScriptParses(t *testing.T) {
	bash, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("no bash")
	}
	for name, token := range map[string]string{"converge": "", "bootstrap": "abcdef.0123456789abcdef"} {
		t.Run(name, func(t *testing.T) {
			opts := edgeConvergeOptions()
			opts.BootstrapToken = token
			path := filepath.Join(t.TempDir(), "converge.sh")
			if err := os.WriteFile(path, []byte(renderRackConvergeScript(opts)), 0o600); err != nil {
				t.Fatal(err)
			}
			if out, err := exec.Command(bash, "-n", path).CombinedOutput(); err != nil {
				t.Fatalf("bash -n: %v\n%s", err, out)
			}
		})
	}
}

// apt-cache keeps writing after the kubelet_package lookup has its answer, as
// it does on a host with the repository's whole release history; under
// pipefail, the lookup still succeeds.
func TestRackConvergeScriptFindsTheKubeletPackageInALongListing(t *testing.T) {
	bash, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("no bash")
	}
	script := renderRackConvergeScript(edgeConvergeOptions())
	start := strings.Index(script, "kubelet_package() {")
	if start < 0 {
		t.Fatal("script has no kubelet_package")
	}
	end := strings.Index(script[start:], "\n}\n")
	dir := t.TempDir()
	fake := `#!/bin/sh
echo "   kubelet | 1.34.6-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages"
sleep 0.2
i=5
while [ $i -ge 0 ]; do
  echo "   kubelet | 1.34.$i-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages"
  i=$((i - 1))
done
`
	if err := os.WriteFile(filepath.Join(dir, "apt-cache"), []byte(fake), 0o755); err != nil {
		t.Fatal(err)
	}
	lookup := "set -euo pipefail\n" + script[start:start+end+3] + `package=$(kubelet_package 1.34.6)
echo "$package"
`
	cmd := exec.Command(bash, "-c", lookup)
	cmd.Env = append(os.Environ(), "PATH="+dir+":"+os.Getenv("PATH"))
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("lookup failed: %v\n%s", err, out)
	}
	if got := strings.TrimSpace(string(out)); got != "1.34.6-1.1" {
		t.Fatalf("got %q, want 1.34.6-1.1", got)
	}
}

func TestRackConvergeScriptRegistersTheNodeAsDeclared(t *testing.T) {
	script := renderRackConvergeScript(edgeConvergeOptions())
	for _, want := range []string{
		"--hostname-override=ber1-edge",
		"--node-ip=100.124.227.31",
		"--node-labels=cilium.io/no-schedule=true,node.cluster.x-k8s.io/instance-type=rack,tuist.dev/rack-edge=ber1",
		"--register-with-taints=tuist.dev/rack-edge=ber1:NoSchedule",
		"--bootstrap-kubeconfig=/var/lib/kubelet/bootstrap-kubeconfig",
		"providerID: rack-linux://ber1/ber1-edge",
		"rotateCertificates: true",
		"clientCAFile: /var/lib/kubelet/ca.crt",
		"kubelet_package 1.34.8",
		"pkgs.k8s.io/core:/stable:/v1.34/deb/",
		`"subnet":"10.254.254.0/24"`,
		"rm -f /var/lib/kubelet/bootstrap-kubeconfig\nbootstrap_supplied=0",
	} {
		if !strings.Contains(script, want) {
			t.Errorf("script lacks %q", want)
		}
	}
	if strings.Contains(script, "token:") {
		t.Error("a converge without a bootstrap token wrote a kubeconfig token")
	}
}

func TestRackConvergeScriptCarriesTheBootstrapTokenOnlyWhenAsked(t *testing.T) {
	opts := edgeConvergeOptions()
	opts.BootstrapToken = "abcdef.0123456789abcdef"
	script := renderRackConvergeScript(opts)
	for _, want := range []string{
		"put /var/lib/kubelet/bootstrap-kubeconfig 0600 kubelet",
		"token: abcdef.0123456789abcdef",
		"server: https://api.example:6443",
		"bootstrap_supplied=1",
	} {
		if !strings.Contains(script, want) {
			t.Errorf("bootstrap script lacks %q", want)
		}
	}
}

func TestRackConfigHash(t *testing.T) {
	base := edgeConvergeOptions()
	withToken := base
	withToken.BootstrapToken = "abcdef.0123456789abcdef"
	if rackConfigHash(base) != rackConfigHash(withToken) {
		t.Error("the bootstrap token changed the configuration hash")
	}
	for name, mutate := range map[string]func(*rackConvergeOptions){
		"kubelet version": func(o *rackConvergeOptions) { o.KubeletVersion = "1.34.9" },
		"tailnet address": func(o *rackConvergeOptions) { o.NodeIP = "100.64.0.2" },
		"labels":          func(o *rackConvergeOptions) { o.NodeLabels = map[string]string{"a": "b"} },
		"cluster CA":      func(o *rackConvergeOptions) { o.ClusterCAPEM = []byte("other") },
		"API server":      func(o *rackConvergeOptions) { o.KubernetesAPI = "https://other:6443" },
	} {
		changed := base
		mutate(&changed)
		if rackConfigHash(changed) == rackConfigHash(base) {
			t.Errorf("a new %s left the configuration hash unchanged", name)
		}
	}
	if !strings.Contains(renderRackConvergeScript(base), rackConfigHash(base)) {
		t.Error("the script does not record the hash it converges to")
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

// The kubelet leaves the node's addresses to the operator, which adds the one
// the API server can reach.
func TestRackConvergeScriptLeavesTheNodeAddressesToTheOperator(t *testing.T) {
	if script := renderRackConvergeScript(edgeConvergeOptions()); !strings.Contains(script, "--cloud-provider=external") {
		t.Fatal("the kubelet would overwrite the addresses the operator sets")
	}
}

// A node installed before the seed kept the Bluetooth driver out gets the
// same blacklist from its converge.
func TestRackConvergeScriptKeepsTheBluetoothDriverOut(t *testing.T) {
	script := renderRackConvergeScript(edgeConvergeOptions())
	if !strings.Contains(script, "put /etc/modprobe.d/tuist-rack.conf 0644 modules <<'TUIST_EOF'\nblacklist btusb\nTUIST_EOF\n") {
		t.Fatal("the converge does not keep btusb out")
	}
}

// AMT shares the management port with the host, and a port the host does not
// configure stays down, taking AMT's link with it. The converge keeps the port
// up with no address and no ARP of the host's on it.
func TestRackConvergeScriptKeepsTheManagementPortUpForAMT(t *testing.T) {
	opts := edgeConvergeOptions()
	opts.ManagementMAC = "38:05:25:38:b5:b5"
	script := renderRackConvergeScript(opts)
	want := "put /etc/systemd/network/10-tuist-management.network 0644 network <<'TUIST_EOF'\n" +
		"[Match]\nMACAddress=38:05:25:38:b5:b5\n\n" +
		"[Link]\nARP=no\nActivationPolicy=always-up\nRequiredForOnline=no\n\n" +
		"[Network]\nLinkLocalAddressing=no\nIPv6AcceptRA=no\n" +
		"TUIST_EOF\n"
	if !strings.Contains(script, want) {
		t.Fatalf("the converge does not keep the management port up:\n%s", script)
	}
	if !strings.Contains(script, `if [ -n "${dirty[network]:-}" ]; then networkctl reload; fi`) {
		t.Fatal("a changed management port configuration is not applied")
	}
}

func TestRackConvergeScriptDropsTheManagementPortWithoutABootMAC(t *testing.T) {
	script := renderRackConvergeScript(edgeConvergeOptions())
	if strings.Contains(script, "\nput /etc/systemd/network/10-tuist-management.network") {
		t.Fatal("wrote a management port configuration without a MAC to match")
	}
	if !strings.Contains(script, "unput /etc/systemd/network/10-tuist-management.network network\n") {
		t.Fatal("a host whose boot MAC was removed keeps its management port configuration")
	}
}

// A rack node reaches no Service address, so pods on it that talk to the API
// server, such as the rack's boot server, read the address its kubelet uses
// from the node.
func TestRackConvergeScriptWritesTheAPIServerThePodsOnTheNodeUse(t *testing.T) {
	script := renderRackConvergeScript(edgeConvergeOptions())
	if !strings.Contains(script, "put /etc/tuist/kubernetes-api 0644 api <<'TUIST_EOF'\nhttps://api.example:6443\nTUIST_EOF\n") {
		t.Fatal("the converge does not write the API server's address")
	}
}
