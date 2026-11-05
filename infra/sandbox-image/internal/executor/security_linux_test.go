//go:build linux

package executor

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"testing"

	"golang.org/x/sys/unix"
)

func noNewPrivs(t *testing.T, start func(*exec.Cmd) error) bool {
	t.Helper()
	var status bytes.Buffer
	cmd := exec.Command("/bin/cat", "/proc/self/status")
	cmd.Stdout = &status
	if err := start(cmd); err != nil {
		t.Fatal(err)
	}
	if err := cmd.Wait(); err != nil {
		t.Fatal(err)
	}
	return strings.Contains(status.String(), "NoNewPrivs:\t1")
}

func TestNoNewPrivilegesSurvivesSchedulingAndExec(t *testing.T) {
	if os.Getenv("SBX_TEST_SECURITY_CHILD") == "1" {
		// The subprocess keeps any leaked thread attribute out of the test
		// runner. Commands started without the helper, on whatever threads
		// remain, must never inherit it.
		for i := 0; i < 50; i++ {
			if !noNewPrivs(t, startWithoutNewPrivileges) {
				t.Fatal("child privilege restriction missing")
			}
			runtime.Gosched()
			if noNewPrivs(t, (*exec.Cmd).Start) {
				t.Fatal("privilege restriction leaked to another thread")
			}
		}
		return
	}
	child := exec.Command(os.Args[0], "-test.run=^TestNoNewPrivilegesSurvivesSchedulingAndExec$")
	child.Env = append(os.Environ(), "SBX_TEST_SECURITY_CHILD=1")
	if output, err := child.CombinedOutput(); err != nil {
		t.Fatalf("child: %v\n%s", err, output)
	}
}

func TestRunDoesNotChangeCallerThread(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	before, err := unix.PrctlRetInt(unix.PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 20; i++ {
		if _, err := Run(context.Background(), "invalid-json", ""); err == nil {
			t.Fatal("expected invalid request")
		}
	}
	after, err := unix.PrctlRetInt(unix.PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0)
	if err != nil || after != before {
		t.Fatalf("caller privilege state changed: before=%d after=%d err=%v", before, after, err)
	}
}
