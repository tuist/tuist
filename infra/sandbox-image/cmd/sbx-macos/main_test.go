//go:build darwin

package main

import (
	"context"
	"io"
	"os"
	"os/exec"
	"strings"
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

// start re-executes this binary as the worker; stand in for one that reads
// its request and exits.
func TestMain(m *testing.M) {
	if len(os.Args) == 2 && strings.HasPrefix(os.Args[1], "--worker=") {
		_, _ = io.Copy(io.Discard, os.Stdin)
		os.Exit(0)
	}
	os.Exit(m.Run())
}
func TestStartReusesOnlyARunningWorkerWithTheSameID(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	if err := os.MkdirAll(root(), 0700); err != nil {
		t.Fatal(err)
	}
	running := response{ID: "sesn_1", Running: true, PID: 1}
	if err := save(running); err != nil {
		t.Fatal(err)
	}
	if err := dispatch(request{Op: "start", ID: "sesn_1"}); err != nil {
		t.Fatal(err)
	}
	if s, _ := status(); s.PID != 1 {
		t.Fatalf("retried start replaced the running worker: %+v", s)
	}

	// The previous turn's worker of the same session has exited.
	if err := save(response{ID: "sesn_1", ExitCode: 0, PID: 1}); err != nil {
		t.Fatal(err)
	}
	if err := dispatch(request{Op: "start", ID: "sesn_1"}); err != nil {
		t.Fatal(err)
	}
	if s, _ := status(); s.PID == 1 || !s.Running {
		t.Fatalf("next turn did not start a worker: %+v", s)
	}
}
func TestRejectsMalformedEnvironmentBeforeSpawn(t *testing.T) {
	if _, err := command(request{Cmd: []string{"/usr/bin/true"}, Env: map[string]string{"BAD=KEY": "secret"}}); err == nil {
		t.Fatal("invalid environment accepted")
	}
}
