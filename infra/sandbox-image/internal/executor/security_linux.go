//go:build linux

package executor

import (
	"os/exec"
	"runtime"

	"golang.org/x/sys/unix"
)

// startWithoutNewPrivileges forks the action's command from a dedicated thread
// that carries no_new_privs. The attribute is inherited across the UID drop and
// exec: guest setuid binaries and file capabilities cannot grant the build
// access to the root worker credential. prctl is per-thread and irreversible, so
// the goroutine exits while locked and Go destroys the thread rather than
// letting another task inherit it. The rest of the action runs on ordinary
// threads.
func startWithoutNewPrivileges(cmd *exec.Cmd) error {
	done := make(chan error, 1)
	go func() {
		runtime.LockOSThread()
		if err := unix.Prctl(unix.PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0); err != nil {
			done <- err
			return
		}
		done <- cmd.Start()
	}()
	return <-done
}
