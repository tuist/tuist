// Package intercept owns the host-side accept loop: it recovers the
// pre-DNAT destination of each guest connection, peeks the SNI, and then
// either MITMs (for the cache plane) or blind-splices (everything else).
package intercept

import (
	"errors"
	"net"
	"net/netip"
)

// ErrUnsupported is returned by the original-destination lookup on
// platforms without a DNAT recovery mechanism wired up.
var ErrUnsupported = errors.New("intercept: original-dst lookup unsupported on this platform")

// OriginalDst recovers the destination a guest dialed before the host's
// pf/nftables DNAT rewrote it to the proxy's listen address.
type OriginalDst interface {
	Lookup(conn *net.TCPConn) (netip.AddrPort, error)
}

// NewOriginalDst returns the platform implementation (Linux
// SO_ORIGINAL_DST, macOS /dev/pf DIOCNATLOOK, or an unsupported stub).
func NewOriginalDst() OriginalDst { return platformOriginalDst() }
