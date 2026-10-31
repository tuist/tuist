//go:build linux

package executor

import (
	"context"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"testing"

	"golang.org/x/sys/unix"
)

func TestNoNewPrivilegesSurvivesSchedulingAndExec(t *testing.T) {
	if os.Getenv("SBX_TEST_SECURITY_CHILD") == "1" {
		// The subprocess keeps this irreversible thread attribute out of
		// the test runner. Exercise the same preparation used by run().
		if err := prepareExecution(); err != nil {
			t.Fatal(err)
		}
		defer runtime.UnlockOSThread()
		thread := unix.Gettid()
		for i := 0; i < 100; i++ {
			runtime.Gosched()
		}
		if unix.Gettid() != thread {
			t.Fatal("execution moved to another thread")
		}
		output, err := exec.Command("/bin/cat", "/proc/self/status").Output()
		if err != nil || !strings.Contains(string(output), "NoNewPrivs:\t1") {
			t.Fatalf("child privilege restriction missing: %v", err)
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
