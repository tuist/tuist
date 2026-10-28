package rackboot

import (
	"net"
	"syscall"

	"golang.org/x/sys/unix"
)

// freebindListenConfig binds to an address this node does not hold yet, which
// the provisioning address is on the edge that is not the site's master.
func freebindListenConfig() *net.ListenConfig {
	return &net.ListenConfig{Control: func(_, _ string, c syscall.RawConn) error {
		var sockErr error
		if err := c.Control(func(fd uintptr) {
			sockErr = unix.SetsockoptInt(int(fd), unix.SOL_IP, unix.IP_FREEBIND, 1)
		}); err != nil {
			return err
		}
		return sockErr
	}}
}
