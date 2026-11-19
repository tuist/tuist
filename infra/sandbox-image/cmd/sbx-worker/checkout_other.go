//go:build !linux

package main

import (
	"errors"
	"net"
)

// Only the Linux host serves checkouts over vsock; macOS uses its share.
func dialCheckoutHost(uint32) (net.Conn, error) {
	return nil, errors.New("checkout over vsock is only available on Linux")
}
