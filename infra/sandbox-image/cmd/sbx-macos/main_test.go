//go:build darwin

package main

import (
	"context"
	"os/exec"
	"testing"
	"time"
)

func TestExecExitCodeAndTimeoutFence(t *testing.T) {
	cmd, err := command(request{Cmd: []string{"/bin/sh", "-c", "exit 7"}, Cwd: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	code, err := run(context.Background(), cmd)
	if err != nil || code != 7 {
		t.Fatalf("code=%d err=%v", code, err)
	}
	cmd, err = command(request{Cmd: []string{"/bin/sh", "-c", "sleep 30 & wait"}, Cwd: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	code, err = run(ctx, cmd)
	if err != nil || code != 124 {
		t.Fatalf("timeout code=%d err=%v", code, err)
	}
}
func TestExecFencesBackgroundChildrenAfterLeaderExit(t *testing.T) {
	dir := t.TempDir()
	cmd, err := command(request{Cmd: []string{"/bin/sh", "-c", "sleep 30 </dev/null >/dev/null 2>&1 & echo $! > child"}, Cwd: dir})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = run(context.Background(), cmd); err != nil {
		t.Fatal(err)
	}
	// waitGroup returns only after the process group has disappeared. Checking
	// the actual process table exercises descendant cleanup, not a mocked signal.
	probe := exec.Command("/bin/sh", "-c", "kill -0 $(cat child) 2>/dev/null")
	probe.Dir = dir
	if probe.Run() == nil {
		t.Fatal("background child escaped exec")
	}
}
func TestRejectsMalformedEnvironmentBeforeSpawn(t *testing.T) {
	if _, err := command(request{Cmd: []string{"/usr/bin/true"}, Env: map[string]string{"BAD=KEY": "secret"}}); err == nil {
		t.Fatal("invalid environment accepted")
	}
}
