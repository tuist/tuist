package tart

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDetachedSandboxLogsSurviveLauncherExit(t *testing.T) {
	if directory := os.Getenv("TUIST_DETACHED_TEST_DIRECTORY"); directory != "" {
		c := &Client{Binary: filepath.Join(directory, "runtime"), LogDir: directory}
		if _, err := c.StartWithOptions(context.Background(), "sandbox", RunOptions{DetachedLogs: true}); err != nil {
			os.Exit(2)
		}
		os.Exit(0)
	}
	directory := t.TempDir()
	script := "#!/bin/sh\nfor i in $(seq 1 100); do\n if [ -f \"$TUIST_DETACHED_TEST_DIRECTORY/continue\" ]; then echo survived-launcher; exit 0; fi\n sleep 0.05\ndone\nexit 1\n"
	if err := os.WriteFile(filepath.Join(directory, "runtime"), []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(os.Args[0], "-test.run=^TestDetachedSandboxLogsSurviveLauncherExit$")
	cmd.Env = append(os.Environ(), "TUIST_DETACHED_TEST_DIRECTORY="+directory)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("launcher: %s %v", output, err)
	}
	if err := os.WriteFile(filepath.Join(directory, "continue"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(6 * time.Second)
	for time.Now().Before(deadline) {
		data, _ := os.ReadFile(filepath.Join(directory, "sandbox.log"))
		if strings.Contains(string(data), "survived-launcher") {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("sandbox stdout depended on the dead launcher")
}

func TestLaunchGuardCancellationDoesNotStartVMAndReleasesGate(t *testing.T) {
	c := lifecycleClient(t, `echo started > "$TART_HOME/started"`)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	released := false
	c.LaunchGuard = func(context.Context, string) (func(), error) { cancel(); return func() { released = true }, nil }
	if _, err := c.StartWithOptions(ctx, "ci", RunOptions{}); err != context.Canceled {
		t.Fatalf("got %v", err)
	}
	if !released {
		t.Fatal("launch gate leaked")
	}
	if _, err := os.Stat(filepath.Join(c.HomeDir, "started")); !os.IsNotExist(err) {
		t.Fatal("cancelled launch started VM")
	}
}
