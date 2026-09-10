//go:build !linux

package main

import (
	"fmt"
	"net"
)

func listenVsock(uint32) (net.Listener, error) {
	return nil, fmt.Errorf("vsock is only available on linux; use -listen tcp://127.0.0.1:5000")
}
