//go:build linux

package driver

import (
	"net"

	"golang.org/x/sys/unix"
)

// Check kernel credentials independently of the socket mode/hostPath mount.
func allocatorRootPeer(conn net.Conn) bool {
	c, ok := conn.(*net.UnixConn)
	if !ok {
		return false
	}
	raw, err := c.SyscallConn()
	if err != nil {
		return false
	}
	allowed := false
	err = raw.Control(func(fd uintptr) {
		cred, err := unix.GetsockoptUcred(int(fd), unix.SOL_SOCKET, unix.SO_PEERCRED)
		allowed = err == nil && cred.Uid == 0
	})
	return err == nil && allowed
}
