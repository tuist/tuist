//go:build !linux

package executor

import (
	"fmt"
	"os/exec"
)

func startWithoutNewPrivileges(*exec.Cmd) error {
	return fmt.Errorf("remote execution requires Linux")
}
