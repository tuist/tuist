//go:build !linux

package reapi

import (
	"errors"
	"os"
	"os/exec"
)

func intoCgroup(*exec.Cmd, *os.File) error {
	return errors.New("cgroups need Linux")
}
