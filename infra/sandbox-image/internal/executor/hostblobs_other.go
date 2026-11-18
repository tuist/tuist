//go:build !linux

package executor

import (
	"errors"
	"net"
)

func dialHost() (net.Conn, error) { return nil, errors.New("vsock is Linux-only") }

func mountTree(int, int64, string, string) error {
	return errors.New("input tree images are Linux-only")
}
