//go:build !linux

package vm

import (
	"errors"
	"io"
	"os"
	"os/exec"
	"syscall"
	"time"
)

// reflink on non-Linux hosts exists for tests only: try the platform clone
// (macOS clonefile via cp -c), else copy.
func reflink(src, dst string) error {
	if err := exec.Command("cp", "-c", src, dst).Run(); err == nil {
		return nil
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

func SetChildSubreaper() error { return nil }

func waitExit(pid int) error {
	for {
		if err := syscall.Kill(pid, 0); errors.Is(err, syscall.ESRCH) {
			return nil
		}
		time.Sleep(200 * time.Millisecond)
	}
}
