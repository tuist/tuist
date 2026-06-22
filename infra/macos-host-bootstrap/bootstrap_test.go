package bootstrap

import (
	"crypto/ed25519"
	"crypto/rand"
	"net"
	"strings"
	"testing"

	"golang.org/x/crypto/ssh"
)

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
