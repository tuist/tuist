//go:build !linux

package driver

import "net"

// The allocator is supported only on Linux; never silently skip authentication.
func allocatorRootPeer(net.Conn) bool { return false }
