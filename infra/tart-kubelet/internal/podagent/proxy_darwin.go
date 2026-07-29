//go:build darwin

package podagent

import (
	"net"

	"golang.org/x/sys/unix"
)

// setBoundInterface scopes the socket to ifIndex via IP_BOUND_IF
// (IPv4) or IPV6_BOUND_IF (IPv6) so the connect() honours the vmnet
// bridge's IFSCOPE route instead of the host's primary interface. See
// bindDialToTargetInterface for why this is needed on macOS.
func setBoundInterface(fd int, ip net.IP, ifIndex int) error {
	if ip.To4() != nil {
		return unix.SetsockoptInt(fd, unix.IPPROTO_IP, unix.IP_BOUND_IF, ifIndex)
	}
	return unix.SetsockoptInt(fd, unix.IPPROTO_IPV6, unix.IPV6_BOUND_IF, ifIndex)
}
