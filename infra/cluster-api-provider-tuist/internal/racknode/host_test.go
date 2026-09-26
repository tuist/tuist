package racknode

import (
	"os"
	"path/filepath"
	"testing"
)

// From the node agent's pod, the host's files are under /proc/1/root, and a
// symlink with an absolute target, as the kubelet keeps its current client
// certificate, points into the host's root, not the pod's.
func TestLocalHostFollowsAbsoluteSymlinksInsideItsRoot(t *testing.T) {
	root := t.TempDir()
	pki := filepath.Join(root, "var/lib/kubelet/pki")
	if err := os.MkdirAll(pki, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pki, "kubelet-client-2026.pem"), []byte("certificate"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("/var/lib/kubelet/pki/kubelet-client-2026.pem", filepath.Join(pki, "kubelet-client-current.pem")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("usr/lib", filepath.Join(root, "lib")); err != nil {
		t.Fatal(err)
	}
	h := LocalHost{Root: root}

	got, err := h.ReadFile(KubeletClientCertPath)
	if err != nil || string(got) != "certificate" {
		t.Fatalf("read %q, %v", got, err)
	}
	if _, ok, err := h.Stat(KubeletClientCertPath); !ok || err != nil {
		t.Fatalf("stat: %v %v", ok, err)
	}
	if err := h.WriteFile("/lib/systemd/system/x.service", []byte("unit"), 0o644); err != nil {
		t.Fatal(err)
	}
	if b, err := os.ReadFile(filepath.Join(root, "usr/lib/systemd/system/x.service")); err != nil || string(b) != "unit" {
		t.Fatalf("a write through a relative directory symlink landed elsewhere: %q %v", b, err)
	}
	if err := h.RemoveAll(KubeletClientCertPath); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(filepath.Join(pki, "kubelet-client-current.pem")); !os.IsNotExist(err) {
		t.Fatalf("removing a symlink left it: %v", err)
	}
	if _, err := os.Stat(filepath.Join(pki, "kubelet-client-2026.pem")); err != nil {
		t.Fatalf("removing a symlink removed what it points to: %v", err)
	}
}
