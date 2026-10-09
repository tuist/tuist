//go:build linux

package netdev

import (
	"context"
	"net"
	"syscall"

	"golang.org/x/sys/unix"
)

// ListenFreebind listens on an address that may not be assigned yet, so the
// tunnel health endpoint can bind before wg0 has its address.
func ListenFreebind(ctx context.Context, address string) (net.Listener, error) {
	config := net.ListenConfig{
		Control: func(_, _ string, conn syscall.RawConn) error {
			var sockErr error
			err := conn.Control(func(fd uintptr) {
				sockErr = unix.SetsockoptInt(int(fd), unix.SOL_IP, unix.IP_FREEBIND, 1)
			})
			if err != nil {
				return err
			}
			return sockErr
		},
	}
	return config.Listen(ctx, "tcp4", address)
}
