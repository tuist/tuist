//go:build linux

package executor

import (
	"net"

	"github.com/mdlayher/vsock"
)

func dialHost() (net.Conn, error) { return vsock.Dial(vsock.Host, hostBlobPort, nil) }
