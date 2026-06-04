//go:build linux

package intercept

import (
	"encoding/binary"
	"fmt"
	"net"
	"net/netip"

	"golang.org/x/sys/unix"
)

// soOriginalDst is the netfilter getsockopt that returns the pre-DNAT
// destination of a REDIRECT/DNAT'd connection. It is not exported by
// x/sys/unix on all versions, so we define it.
const soOriginalDst = 80

type linuxOriginalDst struct{}

func platformOriginalDst() OriginalDst { return linuxOriginalDst{} }

// Lookup recovers the original IPv4 destination via SO_ORIGINAL_DST.
func (linuxOriginalDst) Lookup(conn *net.TCPConn) (netip.AddrPort, error) {
	raw, err := conn.SyscallConn()
	if err != nil {
		return netip.AddrPort{}, fmt.Errorf("intercept: syscall conn: %w", err)
	}
	var (
		addr    netip.AddrPort
		sockErr error
	)
	ctrlErr := raw.Control(func(fd uintptr) {
		// The result is a sockaddr_in laid out in the IPv6Mreq's
		// Multiaddr field: [0:2] family, [2:4] port (big-endian),
		// [4:8] IPv4 address.
		mreq, e := unix.GetsockoptIPv6Mreq(int(fd), unix.IPPROTO_IP, soOriginalDst)
		if e != nil {
			sockErr = e
			return
		}
		port := binary.BigEndian.Uint16(mreq.Multiaddr[2:4])
		ip := netip.AddrFrom4([4]byte{mreq.Multiaddr[4], mreq.Multiaddr[5], mreq.Multiaddr[6], mreq.Multiaddr[7]})
		addr = netip.AddrPortFrom(ip, port)
	})
	if ctrlErr != nil {
		return netip.AddrPort{}, fmt.Errorf("intercept: control: %w", ctrlErr)
	}
	if sockErr != nil {
		return netip.AddrPort{}, fmt.Errorf("intercept: SO_ORIGINAL_DST: %w", sockErr)
	}
	if !addr.IsValid() {
		return netip.AddrPort{}, ErrUnsupported
	}
	return addr, nil
}
