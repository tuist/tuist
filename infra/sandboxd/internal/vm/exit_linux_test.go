//go:build linux

package vm

import (
	"errors"
	"golang.org/x/sys/unix"
	"os/exec"
	"testing"
)

func TestWaitExitReapsOnlyItsChild(t *testing.T) {
	for _, code := range []string{"0", "7"} {
		t.Run(code, func(t *testing.T) {
			child := exec.Command("/bin/sh", "-c", "exit "+code)
			if err := child.Start(); err != nil {
				t.Fatal(err)
			}
			defer child.Process.Release()
			err := waitExit(child.Process.Pid)
			if (err == nil) != (code == "0") {
				t.Fatalf("exit %s: %v", code, err)
			}
			var status unix.WaitStatus
			if _, err := unix.Wait4(child.Process.Pid, &status, unix.WNOHANG, nil); !errors.Is(err, unix.ECHILD) {
				t.Fatalf("child was not reaped: %v", err)
			}
		})
	}
}
