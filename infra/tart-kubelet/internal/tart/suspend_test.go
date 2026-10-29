package tart

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func lifecycleClient(t *testing.T, script string) *Client {
	t.Helper()
	dir := t.TempDir()
	bin := filepath.Join(dir, "tart")
	if err := os.WriteFile(bin, []byte("#!/bin/sh\nset -eu\n"+script), 0o700); err != nil {
		t.Fatal(err)
	}
	return &Client{Binary: bin, HomeDir: dir, LogDir: filepath.Join(dir, "logs")}
}

func TestStartWithOptionsReadinessHasNoFiveSecondFloor(t *testing.T) {
	c := lifecycleClient(t, `printf '%s\n' "$@" > "$TART_HOME/args"
echo ready > "$TART_HOME/ready"
while [ ! -f "$TART_HOME/exit" ]; do sleep 0.05; done
`)
	started := time.Now()
	h, err := c.StartWithOptions(t.Context(), "resume-test", RunOptions{Suspendable: true, SharedDirs: []string{"work:/tmp/work:ro"}})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = os.WriteFile(filepath.Join(c.HomeDir, "exit"), nil, 0o600)
		select {
		case <-h.Done():
		case <-time.After(3 * time.Second):
			t.Error("launcher did not exit")
		}
	})
	ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
	defer cancel()
	err = h.WaitReady(ctx, func(context.Context) error {
		_, err := os.Stat(filepath.Join(c.HomeDir, "ready"))
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	if time.Since(started) >= 2*time.Second {
		t.Fatal("successful readiness waited for the runner launch window")
	}
	args, _ := os.ReadFile(filepath.Join(c.HomeDir, "args"))
	if !strings.Contains(string(args), "--suspendable\n") || !strings.Contains(string(args), "work:/tmp/work:ro\n") {
		t.Fatalf("lost device configuration: %s", args)
	}
}

func TestWaitReadyCancelsProbeWhenProcessExits(t *testing.T) {
	h := &RunHandle{Name: "lost-vm", done: make(chan struct{})}
	err := h.WaitReady(t.Context(), func(ctx context.Context) error {
		h.exitErr = errors.New("restore failed")
		close(h.done)
		<-ctx.Done()
		return ctx.Err()
	})
	if err == nil || !strings.Contains(err.Error(), "restore failed") {
		t.Fatalf("error = %v", err)
	}
}

func TestWaitReadyTimeoutDoesNotStopVM(t *testing.T) {
	h := &RunHandle{done: make(chan struct{})}
	ctx, cancel := context.WithTimeout(t.Context(), 50*time.Millisecond)
	defer cancel()
	err := h.WaitReady(ctx, func(ctx context.Context) error { <-ctx.Done(); return ctx.Err() })
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("error = %v", err)
	}
	if _, exited := h.Exited(); exited {
		t.Fatal("a readiness timeout must not release the VM's reservation")
	}
	if err := h.WaitReady(t.Context(), nil); err == nil {
		t.Fatal("missing readiness probe accepted")
	}
}

func TestWaitReadyRejectsExitDuringSuccessfulProbe(t *testing.T) {
	h := &RunHandle{done: make(chan struct{})}
	if err := h.WaitReady(t.Context(), func(context.Context) error { close(h.done); return nil }); err == nil {
		t.Fatal("a successful RPC raced with process exit and was accepted")
	}
}

func TestResumeRefusesColdBoot(t *testing.T) {
	for _, state := range []string{"stopped", "running", "missing"} {
		t.Run(state, func(t *testing.T) {
			c := lifecycleClient(t, `case "$1" in
get) if [ '`+state+`' = missing ]; then echo 'VM not found' >&2; exit 1; fi
echo '{"State":"`+state+`"}' ;;
run) touch "$TART_HOME/started" ;;
esac
`)
			if _, err := c.Resume(t.Context(), "vm", RunOptions{}); err == nil {
				t.Fatal("accepted a VM without restorable state")
			}
			if _, err := os.Stat(filepath.Join(c.HomeDir, "started")); !os.IsNotExist(err) {
				t.Fatal("attempted cold boot")
			}
		})
	}
}

func TestResumeUsesSuspendableConfiguration(t *testing.T) {
	c := lifecycleClient(t, `case "$1" in
get) echo '{"State":"suspended"}' ;;
run) printf '%s\n' "$@" > "$TART_HOME/args" ;;
esac
`)
	h, err := c.Resume(t.Context(), "vm", RunOptions{Disks: []string{"/tmp/workspace.img"}})
	if err != nil {
		t.Fatal(err)
	}
	<-h.Done()
	args, _ := os.ReadFile(filepath.Join(c.HomeDir, "args"))
	if !strings.Contains(string(args), "--suspendable\n") || !strings.Contains(string(args), "--disk\n/tmp/workspace.img\n") {
		t.Fatalf("args = %s", args)
	}
}

func TestSuspendWaitsForSavedState(t *testing.T) {
	c := lifecycleClient(t, `case "$1" in
get) if [ -f "$TART_HOME/saved" ]; then echo '{"State":"suspended"}'; else echo '{"State":"running"}'; fi ;;
suspend) touch "$TART_HOME/signalled" ;;
esac
`)
	ctx, cancel := context.WithTimeout(t.Context(), 3*time.Second)
	defer cancel()
	done := make(chan error, 1)
	h := &RunHandle{Name: "sandbox-save-test", done: make(chan struct{})}
	go func() { done <- c.Suspend(ctx, h) }()
	for {
		if _, err := os.Stat(filepath.Join(c.HomeDir, "signalled")); err == nil {
			break
		}
		select {
		case err := <-done:
			t.Fatalf("suspend completed before snapshot: %v", err)
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case <-time.After(10 * time.Millisecond):
		}
	}
	select {
	case err := <-done:
		t.Fatalf("CLI acknowledgement released capacity: %v", err)
	default:
	}
	if err := os.WriteFile(filepath.Join(c.HomeDir, "saved"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	close(h.done)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestSuspendFencesOldProcess(t *testing.T) {
	c := lifecycleClient(t, `echo '{"State":"suspended"}'`)
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	name := "sandbox-process-fence-test"
	proc := exec.CommandContext(ctx, "/bin/sh", "-c", "sleep 10; :", "tart", "run", name)
	if err := proc.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { cancel(); _ = proc.Wait() }()
	if running, err := c.IsRunning(t.Context(), name); err != nil || !running {
		t.Fatalf("process must be visible before suspension: running=%v, err=%v", running, err)
	}
	deadline, stop := context.WithTimeout(t.Context(), 100*time.Millisecond)
	defer stop()
	h := &RunHandle{Name: name, done: make(chan struct{})}
	close(h.done)
	if err := c.Suspend(deadline, h); err == nil {
		t.Fatal("snapshot existed but old process was not fenced")
	}
}

func TestSuspendRejectsFailedSave(t *testing.T) {
	c := lifecycleClient(t, `case "$1" in
get) if [ -f "$TART_HOME/signalled" ]; then echo '{"State":"stopped"}'; else echo '{"State":"running"}'; fi ;;
suspend) touch "$TART_HOME/signalled" ;;
esac
`)
	h := &RunHandle{Name: "sandbox-failed-save-test", done: make(chan struct{})}
	close(h.done)
	if err := c.Suspend(t.Context(), h); err == nil || !strings.Contains(err.Error(), "without a restorable snapshot") {
		t.Fatalf("failed save counted as released capacity: %v", err)
	}
}

func TestSuspendRejectsPartialSnapshotAfterFailedSave(t *testing.T) {
	c := lifecycleClient(t, `echo '{"State":"suspended"}'`)
	h := &RunHandle{Name: "partial", done: make(chan struct{}), exitErr: errors.New("disk full")}
	close(h.done)
	if err := c.Suspend(t.Context(), h); err == nil || !strings.Contains(err.Error(), "disk full") {
		t.Fatalf("accepted partial snapshot: %v", err)
	}
}

func TestStartCancellationAfterGUICheck(t *testing.T) {
	c := lifecycleClient(t, `touch "$TART_HOME/started"`)
	ctx, cancel := context.WithCancel(t.Context())
	c.EnsureGUISession = func(context.Context) error { cancel(); return nil }
	if _, err := c.StartWithOptions(ctx, "vm", RunOptions{}); !errors.Is(err, context.Canceled) {
		t.Fatalf("error = %v", err)
	}
	if _, err := os.Stat(filepath.Join(c.HomeDir, "started")); !os.IsNotExist(err) {
		t.Fatal("started after cancellation")
	}
}

func TestExecUsesPrivateStoreAndPreservesArguments(t *testing.T) {
	t.Setenv("TART_HOME", "/must-not-use")
	c := lifecycleClient(t, `printf '%s\n' "$TART_HOME" "$@"`)
	out, err := c.Exec(t.Context(), "vm", "/bin/sh", "-c", "printf 'hello world'")
	if err != nil {
		t.Fatal(err)
	}
	want := c.HomeDir + "\nexec\nvm\n/bin/sh\n-c\nprintf 'hello world'\n"
	if string(out) != want {
		t.Fatalf("got %q, want %q", out, want)
	}
	if _, err := c.Exec(t.Context(), "vm"); err == nil {
		t.Fatal("accepted empty command")
	}
}

func TestExecPreservesFailedCommandOutput(t *testing.T) {
	c := lifecycleClient(t, "echo 'test assertion failed'; exit 1\n")
	out, err := c.Exec(t.Context(), "vm", "/bin/false")
	if err == nil || string(out) != "test assertion failed\n" {
		t.Fatalf("lost failed guest command's output: %q, %v", out, err)
	}
}
