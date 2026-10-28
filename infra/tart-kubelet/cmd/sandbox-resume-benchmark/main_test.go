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
	o := options{home: alias, source: "base", mode: "resume", memory: 8192, cpus: 8, cycles: 1, timeout: time.Minute, build: "build.sh", acquire: "acquire.sh"}
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
