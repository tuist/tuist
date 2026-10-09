package netdev

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestForwardingEnablesWhenZero(t *testing.T) {
	path := filepath.Join(t.TempDir(), "ip_forward")
	if err := os.WriteFile(path, []byte("0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	enabled, err := Forwarding{Path: path}.Ensure()
	if err != nil || !enabled {
		t.Fatalf("Ensure = %v, %v", enabled, err)
	}
	data, _ := os.ReadFile(path)
	if strings.TrimSpace(string(data)) != "1" {
		t.Fatalf("file = %q", data)
	}
}

func TestForwardingAlreadyEnabledOnReadOnlyFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "ip_forward")
	if err := os.WriteFile(path, []byte("1\n"), 0o444); err != nil {
		t.Fatal(err)
	}
	enabled, err := Forwarding{Path: path}.Ensure()
	if err != nil || !enabled {
		t.Fatalf("Ensure = %v, %v", enabled, err)
	}
}

func TestForwardingReadOnlyZeroFails(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root can write read-only files")
	}
	path := filepath.Join(t.TempDir(), "ip_forward")
	if err := os.WriteFile(path, []byte("0\n"), 0o444); err != nil {
		t.Fatal(err)
	}
	enabled, err := Forwarding{Path: path}.Ensure()
	if err == nil || enabled {
		t.Fatalf("Ensure = %v, %v; want an error", enabled, err)
	}
}

func TestForwardingMissingFile(t *testing.T) {
	enabled, err := Forwarding{Path: filepath.Join(t.TempDir(), "missing", "ip_forward")}.Ensure()
	if err == nil || enabled {
		t.Fatalf("Ensure = %v, %v; want an error", enabled, err)
	}
}
