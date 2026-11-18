//go:build !linux

package executor

import (
	"errors"
	"net"
)

func dialHost() (net.Conn, error) { return nil, errors.New("vsock is Linux-only") }
