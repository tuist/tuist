package tart

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestStageEnvFile(t *testing.T) {
	dir := t.TempDir()
	c := &Client{UserDataDir: dir}

	staged, err := c.StageEnvFile("vm-1", map[string]string{
		"DATABASE_URL": "postgres://u:p@h/db",
		"WITH_NEWLINE": "line1\nline2",
	})
	if err != nil {
		t.Fatal(err)
	}
	if staged != filepath.Join(dir, "vm-1") {
		t.Fatalf("staged = %q", staged)
	}

	body, err := os.ReadFile(filepath.Join(staged, "tuist.env"))
	if err != nil {
		t.Fatal(err)
	}
	got := string(body)

	if !strings.Contains(got, "DATABASE_URL=postgres://u:p@h/db\n") {
		t.Errorf("missing DATABASE_URL line: %q", got)
	}
	// Newlines in values must be escaped so the file stays parseable.
	if !strings.Contains(got, `WITH_NEWLINE=line1\nline2`+"\n") {
		t.Errorf("newline not escaped: %q", got)
	}
}

func TestCleanupVMUserData(t *testing.T) {
	dir := t.TempDir()
	c := &Client{UserDataDir: dir}

	target := filepath.Join(dir, "vm-1")
	if err := os.MkdirAll(target, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := c.CleanupVMUserData("vm-1"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Fatalf("expected target removed, got err=%v", err)
	}
}

func TestShellEscape(t *testing.T) {
	cases := map[string]string{
		"simple":      `'simple'`,
		"with space":  `'with space'`,
		`with 'quote`: `'with '\''quote'`,
	}
	for in, want := range cases {
		if got := shellEscape(in); got != want {
			t.Errorf("shellEscape(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestEscapeEnvValue(t *testing.T) {
	if got := escapeEnvValue("a\nb\rc"); got != `a\nb\rc` {
		t.Fatalf("got %q", got)
	}
}

// TestRunHandleExitedAfterSanityWindow simulates the case the
// reviewer flagged: `tart run` returns from the 5s sanity window,
// then the underlying process exits later. The handle must report
// that exit so the reconciler can transition the Pod to Failed
// instead of stranding helm on an indefinite IP poll.
func TestRunHandleExitedAfterSanityWindow(t *testing.T) {
	dir := t.TempDir()
	// Substitute a tiny shell script for the `tart` binary that
	// exits ~0.5s after launch — long enough to pass Run's 5s
	// sanity check would be nicer, but we don't want to slow tests
	// to multi-seconds. Use a 100ms exit, then assert handle
	// eventually reports Exited.
	binPath := filepath.Join(dir, "fake-tart")
	if err := os.WriteFile(binPath, []byte("#!/bin/sh\nsleep 0.1\nexit 7\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	c := &Client{
		Binary:      binPath,
		UserDataDir: filepath.Join(dir, "userdata"),
		LogDir:      filepath.Join(dir, "logs"),
	}

	// Patch the sanity-check window so the test doesn't sleep 5s.
	// We can't override the const without touching production code,
	// so we rely on the script exiting WITHIN the 5s window — which
	// means Run will surface it as an immediate-exit error rather
	// than returning a handle. To exercise the post-window exit
	// path we'd need DI on the timeout; for now lock in the
	// immediate-exit contract, which is the lower bound of the
	// behaviour the reviewer asked us to preserve.
	handle, err := c.Run(context.Background(), "test-vm", nil)
	if err == nil {
		t.Fatalf("expected immediate-exit error, got handle=%v", handle)
	}
	if !strings.Contains(err.Error(), "exited immediately") {
		t.Fatalf("expected immediate-exit error, got %q", err)
	}
}

// TestRunHandleExitedTracksProcess covers the post-sanity-window
// path: Run returns a handle, and a later cmd.Wait result is
// observable through handle.Exited().
func TestRunHandleExitedTracksProcess(t *testing.T) {
	dir := t.TempDir()
	// `sleep 6` outlives the 5s sanity window — Run will return a
	// handle. The script then exits with code 0, which the
	// launcher goroutine must surface through handle.Exited().
	binPath := filepath.Join(dir, "fake-tart")
	if err := os.WriteFile(binPath, []byte("#!/bin/sh\nsleep 6\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	c := &Client{
		Binary:      binPath,
		UserDataDir: filepath.Join(dir, "userdata"),
		LogDir:      filepath.Join(dir, "logs"),
	}

	handle, err := c.Run(context.Background(), "test-vm", nil)
	if err != nil {
		t.Fatalf("unexpected immediate-exit: %v", err)
	}
	if handle == nil {
		t.Fatal("expected non-nil handle")
	}
	if _, exited := handle.Exited(); exited {
		t.Fatal("handle reported exited inside sanity window")
	}

	// Wait for the script's `sleep 6` plus a small margin, then
	// confirm the handle has flipped.
	select {
	case <-handle.Done():
	case <-time.After(10 * time.Second):
		t.Fatal("handle.Done() never closed")
	}
	if _, exited := handle.Exited(); !exited {
		t.Fatal("handle did not report exited after process death")
	}
}

// TestRunInvokesEnsureGUISessionBeforeStartingTart locks in that the
// preflight runs before `tart run`. Without it the kubelet ships
// VMs straight into `Failed to create new HostKey` on hosts whose
// Aqua session got torn down post-bootstrap.
func TestRunInvokesEnsureGUISessionBeforeStartingTart(t *testing.T) {
	dir := t.TempDir()
	binPath := filepath.Join(dir, "fake-tart")
	// Long-lived stub so Run returns a handle (process outlives the
	// 5s sanity window) — we want to assert the preflight ran, not
	// the immediate-exit path which already has coverage above.
	if err := os.WriteFile(binPath, []byte("#!/bin/sh\nsleep 30\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	called := 0
	c := &Client{
		Binary:      binPath,
		UserDataDir: filepath.Join(dir, "userdata"),
		LogDir:      filepath.Join(dir, "logs"),
		EnsureGUISession: func(_ context.Context) error {
			called++
			return nil
		},
	}
	if _, err := c.Run(context.Background(), "test-vm", nil); err != nil {
		t.Fatalf("Run failed: %v", err)
	}
	if called != 1 {
		t.Fatalf("EnsureGUISession called %d times, want 1", called)
	}
}

// TestRunSurfacesEnsureGUISessionFailure locks in that a preflight
// failure short-circuits Run before `tart run` is started. Without
// this, the kubelet would launch the VM into a wall and surface a
// less-actionable error from Tart.
func TestRunSurfacesEnsureGUISessionFailure(t *testing.T) {
	dir := t.TempDir()
	// Sentinel binary that should never run — assert it didn't by
	// checking no log file was created.
	binPath := filepath.Join(dir, "fake-tart-must-not-run")
	if err := os.WriteFile(binPath, []byte("#!/bin/sh\ntouch \"$0.ran\"\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	sentinel := errors.New("preflight rejected")
	c := &Client{
		Binary:      binPath,
		UserDataDir: filepath.Join(dir, "userdata"),
		LogDir:      filepath.Join(dir, "logs"),
		EnsureGUISession: func(_ context.Context) error {
			return sentinel
		},
	}
	_, err := c.Run(context.Background(), "test-vm", nil)
	if err == nil {
		t.Fatal("expected preflight error, got nil")
	}
	if !errors.Is(err, sentinel) {
		t.Fatalf("error chain doesn't wrap sentinel: %v", err)
	}
	if _, statErr := os.Stat(binPath + ".ran"); statErr == nil {
		t.Fatal("fake tart was executed despite preflight failure")
	}
}
