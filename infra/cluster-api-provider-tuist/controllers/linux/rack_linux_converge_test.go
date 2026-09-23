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
