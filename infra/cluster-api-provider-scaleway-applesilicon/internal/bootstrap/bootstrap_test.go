package bootstrap

import (
	"strings"
	"testing"
)

func TestEncodeKCPasswordPadsToTwelveBytes(t *testing.T) {
	out := encodeKCPassword("hello")
	if len(out) < 12 {
		t.Fatalf("expected ≥12 bytes, got %d", len(out))
	}
	// First 5 bytes should be the password XOR'd with the magic key.
	for i, c := range []byte("hello") {
		want := c ^ kcpasswordKey[i%len(kcpasswordKey)]
		if out[i] != want {
			t.Fatalf("byte %d: got %#x, want %#x", i, out[i], want)
		}
	}
}

func TestKubeletConfigIncludesContainerRuntimeEndpoint(t *testing.T) {
	got := kubeletConfig()
	if !strings.Contains(got, "containerRuntimeEndpoint: unix:///var/run/tart-cri/tart-cri.sock") {
		t.Fatalf("kubelet config missing CRI socket path:\n%s", got)
	}
	if !strings.Contains(got, "cgroupsPerQOS: false") {
		t.Fatalf("kubelet config should disable cgroups (macOS):\n%s", got)
	}
}

func TestCNIConflistEmbedsPodCIDR(t *testing.T) {
	got := cniConflist("10.42.7.0/24")
	if !strings.Contains(got, `"podCIDR": "10.42.7.0/24"`) {
		t.Fatalf("CNI conflist missing podCIDR:\n%s", got)
	}
}

func TestKubeletPlistInjectsHostname(t *testing.T) {
	got := kubeletPlist(Config{Hostname: "mac-mini-staging-01"})
	if !strings.Contains(got, "--hostname-override=mac-mini-staging-01") {
		t.Fatalf("kubelet plist missing hostname override:\n%s", got)
	}
	if !strings.Contains(got, "tuist.dev/macos=true:NoSchedule") {
		t.Fatalf("kubelet plist missing macOS taint:\n%s", got)
	}
}

func TestBootstrapKubeconfigRendersJoinMaterial(t *testing.T) {
	got := bootstrapKubeconfig(Config{
		APIServer:      "https://api.tuist.dev:6443",
		CACertData:     "FAKEHASH",
		BootstrapToken: "abcdef.0123456789abcdef",
	})
	for _, want := range []string{
		"server: https://api.tuist.dev:6443",
		"certificate-authority-data: FAKEHASH",
		"token: abcdef.0123456789abcdef",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("kubeconfig missing %q:\n%s", want, got)
		}
	}
}

func TestShellEscape_HandlesSingleQuotes(t *testing.T) {
	got := shellEscape("a'b")
	if got != `'a'\''b'` {
		t.Fatalf("got %q, want %q", got, `'a'\''b'`)
	}
}
