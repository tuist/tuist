//go:build linux

package vm

import (
	"errors"
	"fmt"
	"os"
	"os/exec"

	"golang.org/x/sys/unix"
)

// reflink clones src into dst with FICLONE, falling back to coreutils'
// `cp --reflink=always` (which also fails rather than silently copying when
// the filesystem cannot reflink).
func reflink(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	ioctlErr := unix.IoctlFileClone(int(out.Fd()), int(in.Fd()))
	closeErr := out.Close()
	if ioctlErr == nil {
		return closeErr
	}
	_ = os.Remove(dst)
	cp := exec.Command("cp", "--reflink=always", src, dst)
	if output, err := cp.CombinedOutput(); err != nil {
		return fmt.Errorf("FICLONE: %w; cp --reflink=always: %v: %s", ioctlErr, err, output)
	}
	return nil
}

// SetChildSubreaper makes orphaned descendants (Firecracker after its jailer
// parent exits) reparent to this process so waitExit can reap them.
func SetChildSubreaper() error {
	return unix.Prctl(unix.PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0)
}

// waitExit blocks until pid exits. It reaps the process once it is our
// child (after the jailer parent exits) and falls back to existence polling
// while it is not.
func waitExit(pid int) error {
	for {
		var status unix.WaitStatus
		wpid, err := unix.Wait4(pid, &status, unix.WNOHANG, nil)
		switch {
		case errors.Is(err, unix.EINTR):
			continue
		case errors.Is(err, unix.ECHILD):
			if kerr := unix.Kill(pid, 0); errors.Is(kerr, unix.ESRCH) {
				return errors.New("firecracker exited (reaped elsewhere)")
			}
		case err != nil:
			return fmt.Errorf("wait4(%d): %w", pid, err)
		case wpid == pid:
			return exitStatusError(status)
		}
		unix.Nanosleep(&unix.Timespec{Nsec: 200 * 1e6}, nil)
	}
}

func exitStatusError(status unix.WaitStatus) error {
	switch {
	case status.Exited() && status.ExitStatus() == 0:
		return nil
	case status.Exited():
		return fmt.Errorf("exit status %d", status.ExitStatus())
	case status.Signaled():
		return fmt.Errorf("signal: %s", status.Signal())
	default:
		return fmt.Errorf("wait status %d", status)
	}
}
