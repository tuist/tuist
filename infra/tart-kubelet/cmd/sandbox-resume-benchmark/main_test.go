package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestConsumptionObservation(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.vzvmsave")
	if err := os.WriteFile(path, []byte("snapshot"), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), time.Second)
	defer cancel()
	done := observeConsumption(ctx, path)
	select {
	case at := <-done:
		t.Fatalf("existing snapshot reported consumed: %v", at)
	default:
	}
	before := time.Now()
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if at := <-done; at.IsZero() || at.Before(before) {
		t.Fatalf("invalid consumption observation: %v", at)
	}
}

func TestConsumptionCancellationDoesNotInventTiming(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.vzvmsave")
	if err := os.WriteFile(path, []byte("snapshot"), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(t.Context())
	done := observeConsumption(ctx, path)
	cancel()
	if at := <-done; !at.IsZero() {
		t.Fatalf("invented restore timing: %v", at)
	}
}

func TestRequiresReservationAndIsolatedStore(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	regular := filepath.Join(home, ".tart")
	if err := os.Mkdir(regular, 0700); err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(home, "alias")
	if err := os.Symlink(regular, alias); err != nil {
		t.Fatal(err)
	}
	o := options{home: alias, kubeletHome: regular, source: "base", mode: "resume", memory: 8192, cpus: 8, cycles: 1, timeout: time.Minute, build: "build.sh", acquire: "acquire.sh"}
	if err := o.validate(); err == nil {
		t.Fatal("accepted alias of the runner store")
	}
	o.home = t.TempDir()
	o.acquire = ""
	if err := o.validate(); err == nil {
		t.Fatal("accepted missing reservation hook")
	}
	o.acquire = "acquire.sh"
	if err := o.validate(); err != nil {
		t.Fatal(err)
	}
}

func TestStoreIsolationAcrossUsersAndSymlinks(t *testing.T) {
	root := t.TempDir()
	userHome := filepath.Join(root, "operator")
	regular := filepath.Join(userHome, ".tart")
	kubelet := filepath.Join(root, "runner", "store")
	sibling := filepath.Join(userHome, ".tart-benchmark")
	for _, dir := range []string{regular, kubelet, sibling, filepath.Join(regular, "nested"), filepath.Join(kubelet, "nested")} {
		if err := os.MkdirAll(dir, 0700); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("HOME", userHome)
	alias := filepath.Join(root, "alias")
	if err := os.Symlink(kubelet, alias); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, home, protected string
		valid                 bool
	}{
		{"different user store", kubelet, kubelet, false},
		{"nested kubelet store", filepath.Join(kubelet, "nested"), kubelet, false},
		{"ancestor", root, kubelet, false},
		{"alias", alias, kubelet, false},
		{"nested alias", filepath.Join(alias, "nested"), kubelet, false},
		{"protected alias", kubelet, alias, false},
		{"operator store", regular, kubelet, false},
		{"nested operator store", filepath.Join(regular, "nested"), kubelet, false},
		{"sibling prefix", sibling, kubelet, true},
		{"missing kubelet path", sibling, "", false},
		{"relative kubelet path", sibling, "store", false},
		{"nonexistent kubelet path", sibling, filepath.Join(root, "absent"), false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			o := options{home: tc.home, kubeletHome: tc.protected, source: "base", mode: "resume", memory: 8192, cpus: 8, cycles: 1, timeout: time.Minute, build: "build.sh", acquire: "acquire.sh"}
			if err := o.validate(); (err == nil) != tc.valid {
				t.Fatalf("valid=%v: %v", tc.valid, err)
			}
		})
	}
}
