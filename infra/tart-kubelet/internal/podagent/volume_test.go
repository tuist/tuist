package podagent

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

// fakeBackend models a runner-cache volume of totalBytes holding inUse, where every file occupies perMaster.
type fakeBackend struct {
	totalBytes uint64
	inUse      uint64
	perMaster  uint64
	notMounted bool
	mountErr   error
}

func (f *fakeBackend) isMounted(string) (bool, error) {
	if f.mountErr != nil {
		return false, f.mountErr
	}
	return !f.notMounted, nil
}

func (f *fakeBackend) capacityBytes(string) (uint64, error) { return f.totalBytes, nil }

func (f *fakeBackend) allocatedBytes(path string) (uint64, error) {
	if _, err := os.Stat(path); err != nil {
		return 0, err
	}
	return f.perMaster, nil
}

func (f *fakeBackend) freeBytes(string) (uint64, error) {
	return saturatingSub(f.totalBytes, f.inUse), nil
}

func (f *fakeBackend) usedBytes(string) (uint64, error) { return f.inUse, nil }

const gib = uint64(1024 * 1024 * 1024)

func newTestSpace(t *testing.T, totalGiB int) (*CacheSpace, *fakeBackend) {
	t.Helper()
	be := &fakeBackend{totalBytes: uint64(totalGiB) * gib, perMaster: gib}
	return NewCacheSpace(t.TempDir(), be), be
}

// m2L is a runner-cache volume at the production M2-L size.
func m2L(t *testing.T) (*CacheSpace, *fakeBackend) {
	t.Helper()
	return newTestSpace(t, 80)
}

func TestCacheSpaceDisabled(t *testing.T) {
	m := NewCacheSpace("", &fakeBackend{})
	if m.Enabled() {
		t.Fatal("a space without a root is enabled")
	}
	if err := m.Start(context.Background()); err != nil {
		t.Fatalf("Start = %v", err)
	}
}

func mkdirFile(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func exists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

func TestSweepRemovesEverythingButCustomVolumesAndHiddenEntries(t *testing.T) {
	m, _ := newTestSpace(t, 100)
	running := map[string]bool{"live-vm": true}
	m.Running = func(_ context.Context, vm string) (bool, error) { return running[vm], nil }
	kept := []string{
		filepath.Join(m.Root, "custom", "masters", "scope", "1.img"),
		filepath.Join(m.Root, "custom", ".lock"),
		filepath.Join(m.Root, ".fseventsd", "log"),
		filepath.Join(m.Root, "branches", "live-vm", ".host-materialized"),
	}
	removed := []string{
		filepath.Join(m.Root, "42", "tuist-cache", "master.sparseimage"),
		filepath.Join(m.Root, "42", "repo-0123456789abcdef", "master.generation"),
		filepath.Join(m.Root, "branches", "gone-vm", "cache.sparseimage"),
		filepath.Join(m.Root, "_converge", "42", "tuist-cache", "head-1.sparseimage"),
		filepath.Join(m.Root, "usage-reports", "report.json"),
		filepath.Join(m.Root, "stray-file"),
	}
	for _, path := range append(append([]string{}, kept...), removed...) {
		mkdirFile(t, path)
	}

	m.sweepLeftovers(context.Background())

	for _, path := range kept {
		if !exists(path) {
			t.Errorf("removed %s", path)
		}
	}
	for _, path := range removed {
		if exists(path) {
			t.Errorf("kept %s", path)
		}
	}
	if exists(filepath.Join(m.Root, "42")) || exists(filepath.Join(m.Root, "_converge")) || exists(filepath.Join(m.Root, "usage-reports")) {
		t.Error("kept an emptied leftover directory")
	}

	running["live-vm"] = false
	m.sweepLeftovers(context.Background())
	if exists(filepath.Join(m.Root, "branches")) {
		t.Error("kept the share of a VM that stopped")
	}
	if !exists(kept[0]) {
		t.Error("removed a custom volume")
	}
}

func TestSweepKeepsTheShareOfAVMItCannotProbe(t *testing.T) {
	m, _ := newTestSpace(t, 100)
	m.Running = func(context.Context, string) (bool, error) { return false, errors.New("pgrep failed") }
	share := filepath.Join(m.Root, "branches", "vm", "cache.sparseimage")
	mkdirFile(t, share)

	m.sweepLeftovers(context.Background())
	if !exists(share) {
		t.Fatal("removed the share of a VM whose state is unknown")
	}

	m.Running = nil
	m.sweepLeftovers(context.Background())
	if !exists(share) {
		t.Fatal("removed a VM share without a way to tell whether it runs")
	}
}

func TestStartSweepsOnlyAMountedRoot(t *testing.T) {
	m, be := newTestSpace(t, 100)
	be.notMounted = true
	m.Running = func(context.Context, string) (bool, error) { return false, nil }
	leftover := filepath.Join(m.Root, "42", "tuist-cache", "master.sparseimage")
	mkdirFile(t, leftover)

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- m.Start(ctx) }()
	time.Sleep(50 * time.Millisecond)
	cancel()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if !exists(leftover) {
		t.Fatal("swept a root that is not a mounted volume")
	}

	be.notMounted = false
	be.inUse = 30 * gib
	ctx, cancel = context.WithCancel(context.Background())
	go func() { done <- m.Start(ctx) }()
	deadline := time.Now().Add(2 * time.Second)
	for exists(leftover) && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	cancel()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if exists(leftover) {
		t.Fatal("kept a leftover on a mounted root")
	}
	if got := testutil.ToFloat64(cacheVolumeRootFreeBytes); got != float64(70*gib) {
		t.Fatalf("root free gauge = %v, want %d", got, 70*gib)
	}
}

func TestAwaitMountedRootReturnsWhenMounted(t *testing.T) {
	m, _ := newTestSpace(t, 100)
	m.mountCheckInterval = time.Hour
	m.mountCheckAttempts = 3

	done := make(chan struct{})
	go func() {
		m.AwaitMountedRoot(context.Background())
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("AwaitMountedRoot should return at once when the root is mounted")
	}
	if got := testutil.ToFloat64(cacheVolumeRootMounted); got != 1 {
		t.Fatalf("root-mounted gauge = %v, want 1", got)
	}
	if got := testutil.ToFloat64(cacheVolumeEnabled); got != 1 {
		t.Fatalf("enabled gauge = %v, want 1", got)
	}
}

func TestAwaitMountedRootDisabledIsNoop(t *testing.T) {
	m := NewCacheSpace("", &fakeBackend{})
	m.AwaitMountedRoot(context.Background())
}

func TestAwaitMountedRootGivesUpWhenUnmounted(t *testing.T) {
	m, be := newTestSpace(t, 100)
	be.notMounted = true
	m.mountCheckInterval = time.Millisecond
	m.mountCheckAttempts = 3

	start := time.Now()
	m.AwaitMountedRoot(context.Background())
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("AwaitMountedRoot took %s; should give up after %d bounded attempts", elapsed, m.mountCheckAttempts)
	}
	if got := testutil.ToFloat64(cacheVolumeRootMounted); got != 0 {
		t.Fatalf("root-mounted gauge = %v, want 0", got)
	}
}

func TestAwaitMountedRootStopsOnContextCancel(t *testing.T) {
	m, be := newTestSpace(t, 100)
	be.notMounted = true
	m.mountCheckInterval = time.Hour
	m.mountCheckAttempts = 100

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	done := make(chan struct{})
	go func() {
		m.AwaitMountedRoot(ctx)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("AwaitMountedRoot should return promptly once the context is cancelled")
	}
}
