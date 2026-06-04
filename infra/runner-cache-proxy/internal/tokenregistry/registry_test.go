package tokenregistry

import (
	"context"
	"net/netip"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func writeToken(t *testing.T, dir, ip, tok string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, ip), []byte(tok), 0o600); err != nil {
		t.Fatalf("write token: %v", err)
	}
}

func TestLoadAndLookup(t *testing.T) {
	dir := t.TempDir()
	writeToken(t, dir, "192.168.64.3", "token-a\n")
	writeToken(t, dir, "192.168.64.4", "token-b")
	writeToken(t, dir, "not-an-ip", "ignored")

	r := New(dir)
	if err := r.Load(); err != nil {
		t.Fatalf("Load: %v", err)
	}
	if tok, ok := r.Lookup(netip.MustParseAddr("192.168.64.3")); !ok || string(tok) != "token-a" {
		t.Fatalf("lookup .3 = %q,%v", tok, ok)
	}
	if tok, ok := r.Lookup(netip.MustParseAddr("192.168.64.4")); !ok || string(tok) != "token-b" {
		t.Fatalf("lookup .4 = %q,%v", tok, ok)
	}
	if _, ok := r.Lookup(netip.MustParseAddr("10.0.0.1")); ok {
		t.Fatal("unknown IP should miss (fail open)")
	}
	if r.Size() != 2 {
		t.Fatalf("size = %d want 2", r.Size())
	}
}

func TestEmptyDirIsEmpty(t *testing.T) {
	r := New(filepath.Join(t.TempDir(), "does-not-exist"))
	if err := r.Load(); err != nil {
		t.Fatalf("Load on missing dir should not error: %v", err)
	}
	if _, ok := r.Lookup(netip.MustParseAddr("1.2.3.4")); ok {
		t.Fatal("empty registry should miss")
	}
}

func TestWatchReflectsAddAndRemove(t *testing.T) {
	dir := t.TempDir()
	r := New(dir)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() { _ = r.Watch(ctx) }()

	writeToken(t, dir, "192.168.64.9", "tok9")
	waitFor(t, func() bool {
		_, ok := r.Lookup(netip.MustParseAddr("192.168.64.9"))
		return ok
	})

	if err := os.Remove(filepath.Join(dir, "192.168.64.9")); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool {
		_, ok := r.Lookup(netip.MustParseAddr("192.168.64.9"))
		return !ok
	})
}

func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("condition not met within deadline")
}
