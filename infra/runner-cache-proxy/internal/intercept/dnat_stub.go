//go:build !linux && !darwin

package intercept

import (
	"net"
	"net/netip"
)

// unsupportedOriginalDst keeps the package buildable on platforms without
// a DNAT recovery mechanism (e.g. developer CI on neither Linux nor
// macOS). The proxy only runs on Linux nodes and Mac minis in production.
type unsupportedOriginalDst struct{}

func platformOriginalDst() OriginalDst { return unsupportedOriginalDst{} }

func (unsupportedOriginalDst) Lookup(*net.TCPConn) (netip.AddrPort, error) {
	return netip.AddrPort{}, ErrUnsupported
}
