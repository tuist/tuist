package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDeviceLinks(t *testing.T) {
	directory := t.TempDir()
	for range 2 {
		if err := ensureDeviceLinks(directory); err != nil {
			t.Fatal(err)
		}
	}
	for name, target := range map[string]string{
		"fd": "/proc/self/fd", "stdin": "/proc/self/fd/0",
		"stdout": "/proc/self/fd/1", "stderr": "/proc/self/fd/2",
	} {
		got, err := os.Readlink(filepath.Join(directory, name))
		if err != nil || got != target {
			t.Errorf("%s = %q, %v; want %q", name, got, err, target)
		}
	}
}

func TestDeviceLinksPreserveUnexpectedEntries(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "fd")
	if err := os.WriteFile(path, []byte("existing"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := ensureDeviceLinks(directory); err == nil {
		t.Fatal("expected a conflicting entry to fail")
	}
	got, err := os.ReadFile(path)
	if err != nil || string(got) != "existing" {
		t.Fatalf("existing entry changed: %q, %v", got, err)
	}
}
