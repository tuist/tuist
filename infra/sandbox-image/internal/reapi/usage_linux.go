//go:build linux

package reapi

import (
	"os"
	"os/exec"
	"syscall"
)

// intoCgroup makes the command's process start in the cgroup dir names.
func intoCgroup(cmd *exec.Cmd, dir *os.File) error {
	if cmd.SysProcAttr == nil {
		cmd.SysProcAttr = &syscall.SysProcAttr{}
	}
	cmd.SysProcAttr.UseCgroupFD = true
	cmd.SysProcAttr.CgroupFD = int(dir.Fd())
	return nil
}
