//go:build darwin

package intercept

import (
	"encoding/binary"
	"fmt"
	"net"
	"net/netip"
	"sync"
	"unsafe"

	"golang.org/x/sys/unix"
)

// DIOCNATLOOK queries pf for the pre-rdr destination of a connection.
// _IOWR('D', 23, struct pfioc_natlook); sizeof(struct pfioc_natlook) is
// 88 on macOS (4×pf_addr[16] + 4×xport[4] + af + proto + variant + pad +
// direction[int32]).
const diocNatlook = 0xC0000000 | (88 << 16) | ('D' << 8) | 23

const (
	pfOut    = 2 // PF_OUT
	afInet   = 2 // AF_INET
	protoTCP = 6 // IPPROTO_TCP
)

// pfiocNatlook mirrors struct pfioc_natlook from macOS pfvar.h. Ports
// live in the first two bytes of each 4-byte xport union, network order.
type pfiocNatlook struct {
	saddr        [16]byte
	daddr        [16]byte
	rsaddr       [16]byte
	rdaddr       [16]byte
	sxport       [4]byte
	dxport       [4]byte
	rsxport      [4]byte
	rdxport      [4]byte
	af           uint8
	proto        uint8
	protoVariant uint8
	_            uint8
	direction    int32
}

type darwinOriginalDst struct {
	once sync.Once
	fd   int
	err  error
}

func platformOriginalDst() OriginalDst { return &darwinOriginalDst{fd: -1} }

func (d *darwinOriginalDst) open() (int, error) {
	d.once.Do(func() {
		fd, err := unix.Open("/dev/pf", unix.O_RDONLY, 0)
		if err != nil {
			d.err = fmt.Errorf("intercept: open /dev/pf: %w", err)
			return
		}
		d.fd = fd
	})
	return d.fd, d.err
}

// Lookup queries pf for the original destination of a redirected IPv4
// connection. saddr/sport is the guest (remote), daddr/dport is the
// proxy's accept (local) address; pf returns rdaddr/rdxport.
func (d *darwinOriginalDst) Lookup(conn *net.TCPConn) (netip.AddrPort, error) {
	fd, err := d.open()
	if err != nil {
		return netip.AddrPort{}, err
	}

	remote, ok1 := conn.RemoteAddr().(*net.TCPAddr)
	local, ok2 := conn.LocalAddr().(*net.TCPAddr)
	if !ok1 || !ok2 {
		return netip.AddrPort{}, fmt.Errorf("intercept: non-TCP addresses")
	}
	remoteIP, ok := netip.AddrFromSlice(remote.IP)
	if !ok {
		return netip.AddrPort{}, fmt.Errorf("intercept: bad remote ip")
	}
	localIP, ok := netip.AddrFromSlice(local.IP)
	if !ok {
		return netip.AddrPort{}, fmt.Errorf("intercept: bad local ip")
	}
	remoteIP = remoteIP.Unmap()
	localIP = localIP.Unmap()
	if !remoteIP.Is4() || !localIP.Is4() {
		return netip.AddrPort{}, ErrUnsupported // IPv6 not wired up
	}

	var nl pfiocNatlook
	nl.af = afInet
	nl.proto = protoTCP
	nl.direction = pfOut
	r4 := remoteIP.As4()
	l4 := localIP.As4()
	copy(nl.saddr[:4], r4[:])
	copy(nl.daddr[:4], l4[:])
	binary.BigEndian.PutUint16(nl.sxport[:2], uint16(remote.Port))
	binary.BigEndian.PutUint16(nl.dxport[:2], uint16(local.Port))

	_, _, errno := unix.Syscall(unix.SYS_IOCTL, uintptr(fd), uintptr(diocNatlook), uintptr(unsafe.Pointer(&nl)))
	if errno != 0 {
		return netip.AddrPort{}, fmt.Errorf("intercept: DIOCNATLOOK: %w", errno)
	}

	rip := netip.AddrFrom4([4]byte{nl.rdaddr[0], nl.rdaddr[1], nl.rdaddr[2], nl.rdaddr[3]})
	rport := binary.BigEndian.Uint16(nl.rdxport[:2])
	return netip.AddrPortFrom(rip, rport), nil
}
