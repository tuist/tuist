package racknode

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"io/fs"
	"math/big"
	"strings"
	"testing"
	"time"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

var testNow = time.Date(2026, 9, 26, 12, 0, 0, 0, time.UTC)

type fakeFile struct {
	data []byte
	mode fs.FileMode
}

// fakeHost is a node: files in memory, and commands answered by what the test
// says each prints or how it fails.
type fakeHost struct {
	files    map[string]fakeFile
	answers  map[string]string
	failures map[string]int
	ran      []string
	// onRun lets a test change the host when a command runs.
	onRun func(command string)
}

func newFakeHost() *fakeHost {
	h := &fakeHost{files: map[string]fakeFile{}, answers: map[string]string{
		"dpkg-query -W -f=${Status} containerd": "install ok installed",
		"containerd config default":             "[plugins]\n  SystemdCgroup = false\n",
		"hostnamectl --static":                  "ber1-edge-a\n",
		"apt-cache madison kubelet":             " kubelet | 1.34.8-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages\n kubelet | 1.34.7-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages\n",
		"dpkg-query -W -f=${Version} kubelet":   "1.34.8-1.1",
	}, failures: map[string]int{}}
	h.files[kubeletKeyring] = fakeFile{data: []byte("key"), mode: 0o644}
	h.files[kubeletSources] = fakeFile{data: []byte("deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /\n"), mode: 0o644}
	return h
}

// withIdentity gives the kubelet a client certificate valid until notAfter.
func (h *fakeHost) withIdentity(t *testing.T, notAfter time.Time) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "system:node:ber1-edge-a"}, NotBefore: testNow.Add(-time.Hour), NotAfter: notAfter}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	h.files[KubeletClientCertPath] = fakeFile{data: pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), mode: 0o600}
	h.files[KubeletKubeconfigPath] = fakeFile{data: []byte("apiVersion: v1\n"), mode: 0o600}
}

func (h *fakeHost) ReadFile(p string) ([]byte, error) {
	f, ok := h.files[p]
	if !ok {
		return nil, fs.ErrNotExist
	}
	return f.data, nil
}

func (h *fakeHost) Stat(p string) (fs.FileMode, bool, error) {
	f, ok := h.files[p]
	return f.mode, ok, nil
}

func (h *fakeHost) WriteFile(p string, data []byte, mode fs.FileMode) error {
	h.files[p] = fakeFile{data: append([]byte(nil), data...), mode: mode}
	return nil
}

func (h *fakeHost) RemoveAll(p string) error {
	for name := range h.files {
		if name == p || strings.HasPrefix(name, p+"/") {
			delete(h.files, name)
		}
	}
	return nil
}

func (h *fakeHost) Run(_ context.Context, _ []byte, name string, args ...string) ([]byte, error) {
	command := strings.Join(append([]string{name}, args...), " ")
	h.ran = append(h.ran, command)
	if h.onRun != nil {
		h.onRun(command)
	}
	if code, ok := h.failures[command]; ok {
		return nil, &ExitError{Command: command, Code: code}
	}
	return []byte(h.answers[command]), nil
}

func (h *fakeHost) ranAny(prefix string) bool {
	for _, c := range h.ran {
		if strings.HasPrefix(c, prefix) {
			return true
		}
	}
	return false
}

func testConfig() infrav1.RackNodeConfig {
	return infrav1.RackNodeConfig{
		Hash:     "hash-1",
		Hostname: "ber1-edge-a",
		Files: []infrav1.RackNodeFile{
			{Path: "/etc/modules-load.d/tuist-k8s.conf", Mode: "0644", Group: "modules", Content: "overlay\nbr_netfilter"},
			{Path: "/etc/systemd/network/10-tuist-management.network", Mode: "0644", Group: "network", Content: "[Match]\n"},
			{Path: "/var/lib/kubelet/config.yaml", Mode: "0644", Group: "kubelet", Content: "kind: KubeletConfiguration\n"},
		},
		Absent:     []infrav1.RackNodeFile{{Path: "/etc/tuist/old.conf", Group: "kubelet"}},
		Modules:    []string{"overlay", "br_netfilter"},
		Sysctl:     []infrav1.RackNodeSysctl{{Path: "/etc/sysctl.d/99-tuist-k8s.conf"}, {Path: "/etc/sysctl.d/99-tuist-hardening.conf", Optional: true}},
		Containerd: infrav1.RackNodeContainerd{ConfigPath: "/etc/containerd/config.toml"},
		Kubelet:    infrav1.RackNodeKubelet{Channel: "v1.34", Version: "1.34.8"},
	}
}

func apply(t *testing.T, h *fakeHost, req Request) Result {
	t.Helper()
	res, err := Apply(context.Background(), h, req, Options{Now: func() time.Time { return testNow }, Sleep: func(time.Duration) {}})
	if err != nil {
		t.Fatalf("Apply: %v", err)
	}
	return res
}

func TestApplyWritesTheConfigurationAndRestartsWhatItChanged(t *testing.T) {
	h := newFakeHost()
	h.withIdentity(t, testNow.Add(24*time.Hour))
	h.files["/etc/tuist/old.conf"] = fakeFile{data: []byte("x"), mode: 0o644}

	res := apply(t, h, Request{Config: testConfig()})

	if res.Applied != "hash-1" || res.NeedsBootstrap || res.ForeignJoin {
		t.Fatalf("result %+v", res)
	}
	if got := string(h.files["/etc/modules-load.d/tuist-k8s.conf"].data); got != "overlay\nbr_netfilter\n" {
		t.Fatalf("a file's content %q, want it with a final newline", got)
	}
	if got := string(h.files["/etc/containerd/config.toml"].data); !strings.Contains(got, "SystemdCgroup = true") {
		t.Fatalf("containerd config %q", got)
	}
	if _, ok := h.files["/etc/tuist/old.conf"]; ok {
		t.Fatal("an absent path is still there")
	}
	for _, want := range []string{"modprobe overlay", "modprobe br_netfilter", "sysctl -q -p /etc/sysctl.d/99-tuist-k8s.conf", "networkctl reload", "systemctl restart containerd", "systemctl restart kubelet", "apt-mark hold kubelet"} {
		if !h.ranAny(want) {
			t.Errorf("did not run %q; ran %v", want, h.ran)
		}
	}
	if h.ranAny("systemctl daemon-reexec") {
		t.Error("re-executed systemd, whose configuration did not change")
	}
	if string(h.files[HashPath].data) != "hash-1\n" {
		t.Fatalf("recorded %q", h.files[HashPath].data)
	}

	h.ran = nil
	again := apply(t, h, Request{Config: testConfig()})
	if len(again.Changed) != 0 || len(again.Restarted) != 0 || h.ranAny("systemctl restart") || h.ranAny("networkctl") {
		t.Fatalf("a second apply of the same configuration changed %v and restarted %v", again.Changed, again.Restarted)
	}
}

func TestApplyRestartsADaemonThatIsNotRunning(t *testing.T) {
	h := newFakeHost()
	h.withIdentity(t, testNow.Add(24*time.Hour))
	apply(t, h, Request{Config: testConfig()})
	h.ran = nil
	h.failures["systemctl is-active --quiet kubelet"] = 3

	res := apply(t, h, Request{Config: testConfig()})

	if len(res.Restarted) != 1 || res.Restarted[0] != "kubelet" {
		t.Fatalf("restarted %v", res.Restarted)
	}
}

func TestApplyLeavesAHostKubeadmJoined(t *testing.T) {
	h := newFakeHost()
	h.files["/etc/kubernetes/kubelet.conf"] = fakeFile{data: []byte("x"), mode: 0o600}

	res := apply(t, h, Request{Config: testConfig()})

	if !res.ForeignJoin || len(h.ran) != 0 || len(res.Changed) != 0 {
		t.Fatalf("result %+v ran %v", res, h.ran)
	}
}

func TestApplyAsksForABootstrapTokenWhenTheKubeletHasNoIdentity(t *testing.T) {
	for name, identity := range map[string]time.Time{"none": {}, "expiring": testNow.Add(5 * time.Minute)} {
		t.Run(name, func(t *testing.T) {
			h := newFakeHost()
			if !identity.IsZero() {
				h.withIdentity(t, identity)
			}
			res := apply(t, h, Request{Config: testConfig()})
			if !res.NeedsBootstrap || res.Applied != "" || h.ranAny("systemctl restart") {
				t.Fatalf("result %+v ran %v", res, h.ran)
			}
		})
	}
}

func TestApplyJoinsWithABootstrapKubeconfigAndRemovesIt(t *testing.T) {
	h := newFakeHost()
	h.onRun = func(command string) {
		if command == "systemctl restart kubelet" {
			if _, ok := h.files[BootstrapKubeconfigPath]; !ok {
				t.Error("the kubelet started without its bootstrap kubeconfig")
			}
			h.withIdentity(t, testNow.Add(365*24*time.Hour))
		}
	}

	res := apply(t, h, Request{Config: testConfig(), Bootstrap: "token: abcdef.0123456789abcdef"})

	if res.Applied != "hash-1" || res.NeedsBootstrap {
		t.Fatalf("result %+v", res)
	}
	if _, ok := h.files[BootstrapKubeconfigPath]; ok {
		t.Fatal("the bootstrap kubeconfig, which carries the token, is still on the host")
	}
}

func TestApplyFailsAJoinWhoseKubeletGetsNoCertificate(t *testing.T) {
	h := newFakeHost()
	h.answers["journalctl -u kubelet -n 40 --no-pager"] = "kubelet: bootstrap token rejected"
	clock := testNow
	_, err := Apply(context.Background(), h, Request{Config: testConfig(), Bootstrap: "token: x"},
		Options{Now: func() time.Time { return clock }, Sleep: func(d time.Duration) { clock = clock.Add(d) }})

	if err == nil || !strings.Contains(err.Error(), "bootstrap token rejected") {
		t.Fatalf("err %v", err)
	}
	if _, ok := h.files[BootstrapKubeconfigPath]; ok {
		t.Fatal("left the bootstrap kubeconfig behind")
	}
	if _, ok := h.files[HashPath]; ok {
		t.Fatal("recorded a configuration it did not finish applying")
	}
}

func TestApplyInstallsExactlyTheConfiguredKubeletAndNeverDowngrades(t *testing.T) {
	for name, tc := range map[string]struct {
		installed   string
		newer       bool
		wantInstall bool
	}{
		"older":   {installed: "1.34.7-1.1", wantInstall: true},
		"missing": {installed: "", wantInstall: true},
		"newer":   {installed: "1.35.0-1.1", newer: true},
		"same":    {installed: "1.34.8-1.1"},
	} {
		t.Run(name, func(t *testing.T) {
			h := newFakeHost()
			h.withIdentity(t, testNow.Add(24*time.Hour))
			h.answers["dpkg-query -W -f=${Version} kubelet"] = tc.installed
			if !tc.newer {
				h.failures[fmt.Sprintf("dpkg --compare-versions %s gt 1.34.8-1.1", tc.installed)] = 1
			}
			apply(t, h, Request{Config: testConfig()})
			if got := h.ranAny("env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -y -qq install --allow-change-held-packages kubelet=1.34.8-1.1"); got != tc.wantInstall {
				t.Fatalf("installed %v, want %v; ran %v", got, tc.wantInstall, h.ran)
			}
		})
	}
}

func TestApplyAddsTheKubeletRepositoryForAnotherMinor(t *testing.T) {
	h := newFakeHost()
	h.withIdentity(t, testNow.Add(24*time.Hour))
	cfg := testConfig()
	cfg.Kubelet = infrav1.RackNodeKubelet{Channel: "v1.35", Version: "1.35.1"}
	h.answers["apt-cache madison kubelet"] = " kubelet | 1.35.1-1.1 | https://pkgs.k8s.io/core:/stable:/v1.35/deb  Packages\n"

	apply(t, h, Request{Config: cfg})

	if !strings.Contains(string(h.files[kubeletSources].data), "stable:/v1.35/deb/") {
		t.Fatalf("sources %q", h.files[kubeletSources].data)
	}
	for _, want := range []string{"curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key", "gpg --batch --yes --dearmor -o " + kubeletKeyring, "env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -y -qq update"} {
		if !h.ranAny(want) {
			t.Errorf("did not run %q", want)
		}
	}
}

func TestApplyRenamesTheHostAndRejoinsWithoutItsOldIdentity(t *testing.T) {
	h := newFakeHost()
	h.withIdentity(t, testNow.Add(24*time.Hour))
	h.files["/etc/hosts"] = fakeFile{data: []byte("127.0.0.1 localhost\n127.0.1.1 ber1-edge\n"), mode: 0o644}
	h.answers["hostnamectl --static"] = "ber1-edge\n"

	res := apply(t, h, Request{Config: testConfig(), Rejoin: true})

	if !res.NeedsBootstrap {
		t.Fatalf("result %+v; a rejoin drops the identity, so it needs a bootstrap token", res)
	}
	if !h.ranAny("hostnamectl set-hostname ber1-edge-a") || string(h.files["/etc/hosts"].data) != "127.0.0.1 localhost\n127.0.1.1 ber1-edge-a\n" {
		t.Fatalf("hosts %q ran %v", h.files["/etc/hosts"].data, h.ran)
	}
	if _, ok := h.files[KubeletClientCertPath]; ok {
		t.Fatal("the old identity is still there")
	}
}

func TestApplyTurnsSwapOff(t *testing.T) {
	h := newFakeHost()
	h.withIdentity(t, testNow.Add(24*time.Hour))
	h.answers["swapon --show --noheadings"] = "/swap.img file 4G 0B -2\n"
	h.files["/etc/fstab"] = fakeFile{data: []byte("UUID=abc / ext4 defaults 0 1\n/swap.img none swap sw 0 0\n#/old none swap sw 0 0\n"), mode: 0o644}

	apply(t, h, Request{Config: testConfig()})

	if !h.ranAny("swapoff -a") || string(h.files["/etc/fstab"].data) != "UUID=abc / ext4 defaults 0 1\n#/swap.img none swap sw 0 0\n#/old none swap sw 0 0\n" {
		t.Fatalf("fstab %q", h.files["/etc/fstab"].data)
	}
}
