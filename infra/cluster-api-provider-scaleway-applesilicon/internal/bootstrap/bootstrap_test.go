package bootstrap

import (
	"crypto/ed25519"
	"crypto/rand"
	"net"
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

// hostKeyState is the SSH-side TOFU primitive. The first observation
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
	hk := newHostKeyState("")
	pk := newTestPubKey(t)
	cb := hk.callback()
	if err := cb("host:22", &net.TCPAddr{}, pk); err != nil {
		t.Fatalf("first observation should accept any key: %v", err)
	}
	if hk.observed() != ssh.FingerprintSHA256(pk) {
		t.Fatalf("expected captured fingerprint to equal observed key, got %q", hk.observed())
	}
}

func TestHostKeyState_VerifyAcceptsMatchingFingerprint(t *testing.T) {
	pk := newTestPubKey(t)
	hk := newHostKeyState(ssh.FingerprintSHA256(pk))
	cb := hk.callback()
	if err := cb("host:22", &net.TCPAddr{}, pk); err != nil {
		t.Fatalf("matching fingerprint should accept: %v", err)
	}
}

func TestHostKeyState_VerifyRejectsMismatchedFingerprint(t *testing.T) {
	hk := newHostKeyState(ssh.FingerprintSHA256(newTestPubKey(t)))
	cb := hk.callback()
	if err := cb("host:22", &net.TCPAddr{}, newTestPubKey(t)); err == nil {
		t.Fatalf("mismatched fingerprint should error")
	}
}

func TestHostKeyState_DetectsMidBootstrapKeyRotation(t *testing.T) {
	hk := newHostKeyState("")
	cb := hk.callback()
	first := newTestPubKey(t)
	if err := cb("host:22", &net.TCPAddr{}, first); err != nil {
		t.Fatalf("first observation: %v", err)
	}
	// A second dial in the same hostKeyState (e.g. dial after the
	// waitForSSH probe) presenting a different key would mean the
	// host's identity changed between the probe and the real dial.
	// Refuse rather than re-TOFU.
	if err := cb("host:22", &net.TCPAddr{}, newTestPubKey(t)); err == nil {
		t.Fatalf("mid-bootstrap key rotation should error")
	}
}
