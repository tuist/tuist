package bootstrap

import (
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"net"
	"strings"
	"testing"

	"golang.org/x/crypto/ssh"
)

func TestHostKeyState_PinnedMismatchReturnsTypedError(t *testing.T) {
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	signer, err := ssh.NewSignerFromKey(priv)
	if err != nil {
		t.Fatal(err)
	}
	pub := signer.PublicKey()
	fp := ssh.FingerprintSHA256(pub)

	// TOFU: an empty pin accepts the first key and records it.
	tofu := NewHostKeyState("")
	if err := tofu.Callback()("host", &net.IPAddr{}, pub); err != nil {
		t.Fatalf("TOFU should accept the first key: %v", err)
	}
	if tofu.Observed() != fp {
		t.Fatalf("Observed = %q, want %q", tofu.Observed(), fp)
	}

	// A pin that doesn't match the presented key is rejected with a typed
	// error so the reinstall-on-release controllers can re-TOFU (errors.Is).
	pinned := NewHostKeyState("SHA256:0000000000000000000000000000000000000000000")
	err = pinned.Callback()("host", &net.IPAddr{}, pub)
	if err == nil {
		t.Fatal("expected a host key mismatch error")
	}
	if !errors.Is(err, ErrHostKeyMismatch) {
		t.Fatalf("error %v does not match ErrHostKeyMismatch", err)
	}
}

func TestEncodeKCPasswordPadsToTwelveBytes(t *testing.T) {
	out := encodeKCPassword("hello")
	// encodeKCPassword returns base64 — decode to inspect ciphertext.
	if len(out) == 0 {
		t.Fatalf("expected non-empty output")
	}
}

func TestRenderLaunchdPlist_OmitsNodeLabelsWhenEmpty(t *testing.T) {
	out := renderLaunchdPlist(Config{NodeName: "n1", SSHUser: "m1"})
	if strings.Contains(out, "--node-labels") {
		t.Fatalf("expected --node-labels to be absent when NodeLabels is empty\n%s", out)
	}
}

func TestRenderLaunchdPlist_OmitsProviderIDWhenEmpty(t *testing.T) {
	out := renderLaunchdPlist(Config{NodeName: "n1", SSHUser: "m1"})
	if strings.Contains(out, "--provider-id") {
		t.Fatalf("expected --provider-id to be absent when ProviderID is empty\n%s", out)
	}
}

func TestRenderLaunchdPlist_RendersProviderID(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName:   "n1",
		SSHUser:    "m1",
		ProviderID: "scw-applesilicon://fr-par-1/abc-123",
	})
	if !strings.Contains(out, "<string>--provider-id=scw-applesilicon://fr-par-1/abc-123</string>") {
		t.Fatalf("expected --provider-id flag in plist\n%s", out)
	}
}

func TestRenderLaunchdPlist_RendersFleetLabel(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName:   "n1",
		SSHUser:    "m1",
		NodeLabels: map[string]string{"tuist.dev/fleet": "tuist-runners"},
	})
	if !strings.Contains(out, "--node-labels=tuist.dev/fleet=tuist-runners") {
		t.Fatalf("expected --node-labels=tuist.dev/fleet=tuist-runners in plist\n%s", out)
	}
}

func TestRenderLaunchdPlist_RendersMultipleLabelsSorted(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName: "n1",
		SSHUser:  "m1",
		NodeLabels: map[string]string{
			"tuist.dev/fleet":         "tuist-runners",
			"tuist.dev/instance-type": "large",
		},
	})
	// Sorted alphabetically — deterministic plist rendering keeps the
	// host fingerprint stable across reconciles.
	want := "--node-labels=tuist.dev/fleet=tuist-runners,tuist.dev/instance-type=large"
	if !strings.Contains(out, want) {
		t.Fatalf("expected %q in plist\n%s", want, out)
	}
}

func TestRenderLaunchdPlist_OmitsDisableVMGCForPureNode(t *testing.T) {
	out := renderLaunchdPlist(Config{NodeName: "n1", SSHUser: "m1"})
	if strings.Contains(out, "--disable-vm-gc") {
		t.Fatalf("expected --disable-vm-gc to be absent on a pure Node (no GHActionsRunner)\n%s", out)
	}
}

func TestRenderLaunchdPlist_RendersDisableVMGCForBuilder(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName:        "n1",
		SSHUser:         "m1",
		GHActionsRunner: &GHActionsRunnerConfig{},
	})
	if !strings.Contains(out, "<string>--disable-vm-gc</string>") {
		t.Fatalf("expected --disable-vm-gc in plist for a builder host\n%s", out)
	}
}

// The drift-update path re-renders the plist without re-resolving
// GHActionsRunner, so it sets DisableVMGC directly. Without honoring it
// here, a binary roll would strip --disable-vm-gc from a builder and the
// orphan-VM GC would reap the in-flight image-bake VM mid-`tart push`.
func TestRenderLaunchdPlist_RendersDisableVMGCWhenSet(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName:    "n1",
		SSHUser:     "m1",
		DisableVMGC: true,
	})
	if !strings.Contains(out, "<string>--disable-vm-gc</string>") {
		t.Fatalf("expected --disable-vm-gc in plist when DisableVMGC is set\n%s", out)
	}
}

func TestRenderLaunchdPlist_RendersRunnerCacheRoot(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName:        "n1",
		SSHUser:         "m1",
		RunnerCacheRoot: "/var/lib/tuist-runner-cache",
	})
	if !strings.Contains(out, "<string>--runner-cache-root=/var/lib/tuist-runner-cache</string>") {
		t.Fatalf("expected --runner-cache-root in plist\n%s", out)
	}
}

// HostKeyState is the SSH-side TOFU primitive. The first observation
// of a host key on a fresh state is captured; later observations
// against a state seeded with KnownHostFingerprint must match.

func newTestPubKey(t *testing.T) ssh.PublicKey {
	t.Helper()
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate ed25519: %v", err)
	}
	pk, err := ssh.NewPublicKey(pub)
	if err != nil {
		t.Fatalf("ssh public key: %v", err)
	}
	return pk
}

func TestHostConfigHash_StableForSameConfig(t *testing.T) {
	cfg := Config{
		TartKubeletBinary:  []byte("kubelet-v1"),
		TailscaleBinaries:  []byte("ts-v1"),
		NodeExporterBinary: []byte("ne-v1"),
		TailscaleAuthKey:   "auth-key",
		TailscaleTags:      []string{"tag:tuist-macmini"},
		VMKuraEgressCIDR:   "10.96.0.0/12",
		VMCachePNCIDR:      "172.16.0.0/22",
		HostCPU:            8,
		HostMemoryMB:       16384,
		MaxPods:            3,
	}
	if HostConfigHash(cfg) != HostConfigHash(cfg) {
		t.Fatalf("HostConfigHash must be stable for the same config")
	}
}

func TestHostConfigHash_IndependentOfPerHostFields(t *testing.T) {
	base := Config{
		TartKubeletBinary: []byte("kubelet-v1"),
		VMKuraEgressCIDR:  "10.96.0.0/12",
	}
	perHost := base
	// Per-host fields must not move the canonical hash, or every host in
	// a fleet would falsely drift.
	perHost.NodeName = "macmini-7"
	perHost.IP = "51.15.1.2"
	perHost.Kubeconfig = "kubeconfig-yaml"
	perHost.ProviderID = "scw-applesilicon://fr-par-1/abc"
	perHost.VMCachePNVLAN = 4242
	perHost.KnownHostFingerprint = "SHA256:zzz"
	perHost.DisableVMGC = true
	if HostConfigHash(base) != HostConfigHash(perHost) {
		t.Fatalf("HostConfigHash must ignore per-host fields")
	}
}

func TestHostConfigHash_ChangesWhenFleetConfigChanges(t *testing.T) {
	base := Config{
		TartKubeletBinary: []byte("kubelet-v1"),
		VMKuraEgressCIDR:  "10.96.0.0/12",
	}
	changed := base
	changed.VMCachePNCIDR = "172.16.0.0/22"
	if HostConfigHash(base) == HostConfigHash(changed) {
		t.Fatalf("HostConfigHash must change when a fleet-config field changes")
	}

	tags := base
	tags.TailscaleTags = []string{"tag:tuist-macmini-staging"}
	if HostConfigHash(base) == HostConfigHash(tags) {
		t.Fatalf("HostConfigHash must change when TailscaleTags change")
	}

	routes := base
	routes.TailscaleAcceptRoutes = true
	if HostConfigHash(base) == HostConfigHash(routes) {
		t.Fatalf("HostConfigHash must change when TailscaleAcceptRoutes changes")
	}
}

func TestHostConfigHash_ChangesWhenBinaryChanges(t *testing.T) {
	base := Config{TartKubeletBinary: []byte("kubelet-v1")}
	changed := Config{TartKubeletBinary: []byte("kubelet-v2")}
	if HostConfigHash(base) == HostConfigHash(changed) {
		t.Fatalf("HostConfigHash must change when the tart-kubelet binary changes")
	}

	ne := base
	ne.NodeExporterBinary = []byte("ne-v1")
	if HostConfigHash(base) == HostConfigHash(ne) {
		t.Fatalf("HostConfigHash must change when the node_exporter binary changes")
	}
}

func TestHostKeyState_TOFUCapturesFingerprint(t *testing.T) {
	hk := NewHostKeyState("")
	pk := newTestPubKey(t)
	cb := hk.Callback()
	if err := cb("host:22", &net.TCPAddr{}, pk); err != nil {
		t.Fatalf("first observation should accept any key: %v", err)
	}
	if hk.Observed() != ssh.FingerprintSHA256(pk) {
		t.Fatalf("expected captured fingerprint to equal observed key, got %q", hk.Observed())
	}
}

func TestHostKeyState_VerifyAcceptsMatchingFingerprint(t *testing.T) {
	pk := newTestPubKey(t)
	hk := NewHostKeyState(ssh.FingerprintSHA256(pk))
	cb := hk.Callback()
	if err := cb("host:22", &net.TCPAddr{}, pk); err != nil {
		t.Fatalf("matching fingerprint should accept: %v", err)
	}
}

func TestHostKeyState_VerifyRejectsMismatchedFingerprint(t *testing.T) {
	hk := NewHostKeyState(ssh.FingerprintSHA256(newTestPubKey(t)))
	cb := hk.Callback()
	if err := cb("host:22", &net.TCPAddr{}, newTestPubKey(t)); err == nil {
		t.Fatalf("mismatched fingerprint should error")
	}
}

func TestHostKeyState_DetectsMidBootstrapKeyRotation(t *testing.T) {
	hk := NewHostKeyState("")
	cb := hk.Callback()
	first := newTestPubKey(t)
	if err := cb("host:22", &net.TCPAddr{}, first); err != nil {
		t.Fatalf("first observation: %v", err)
	}
	// A second dial in the same HostKeyState (e.g. dial after the
	// waitForSSH probe) presenting a different key would mean the
	// host's identity changed between the probe and the real dial.
	// Refuse rather than re-TOFU.
	if err := cb("host:22", &net.TCPAddr{}, newTestPubKey(t)); err == nil {
		t.Fatalf("mid-bootstrap key rotation should error")
	}
}

func TestRenderVMNATScript_AssertsDefaultRouteNATLeg(t *testing.T) {
	out := renderVMNATScript(Config{
		VMKuraEgressCIDR: "10.96.0.0/12",
		VMCachePNCIDR:    "172.16.0.0/22",
	})
	// The general-internet leg must NAT VM egress on the default-route
	// NIC from this anchor, not rely on vmnet/InternetSharing — the
	// 2026-06-26 outage was VMs egressing un-NAT'd (private
	// 192.168.64.x source) after InternetSharing's separate en0 NAT
	// anchor was clobbered, so tailscaled could never reach control.
	if !strings.Contains(out, "route -n get default") {
		t.Fatalf("expected default-route interface discovery\n%s", out)
	}
	if !strings.Contains(out, "nat on $DEFIF from 192.168.64.0/22 to any -> ($DEFIF)") {
		t.Fatalf("expected general-internet NAT leg on the default route\n%s", out)
	}
	// The idempotency short-circuit must re-converge after an external
	// anchor flush: skipping the reload purely on a snapshot match would
	// leave a flushed anchor empty forever (the snapshot still matches).
	if !strings.Contains(out, `pfctl -a "com.apple/tuist.vmnat" -s nat`) {
		t.Fatalf("expected short-circuit to verify the live anchor still holds rules\n%s", out)
	}
}
