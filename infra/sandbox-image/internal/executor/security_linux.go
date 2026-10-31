//go:build linux

package executor

import (
	"runtime"

	"golang.org/x/sys/unix"
)

func prepareExecution() error {
	// Inherited across the UID drop and exec: guest setuid binaries and file
	// capabilities cannot grant the build access to the root worker credential.
	// prctl is per-thread. Keep the eventual fork/exec on this thread even
	// while the goroutine waits for CAS I/O. Run exits its dedicated goroutine
	// while locked so this irreversible attribute cannot leak to another task.
	runtime.LockOSThread()
	if err := unix.Prctl(unix.PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0); err != nil {
		runtime.UnlockOSThread()
		return err
	}
	return nil
}
