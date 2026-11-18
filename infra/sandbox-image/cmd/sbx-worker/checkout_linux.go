//go:build linux

package main

import (
	"net"

	"github.com/mdlayher/vsock"
)

func dialCheckoutHost(port uint32) (net.Conn, error) { return vsock.Dial(vsock.Host, port, nil) }
