//go:build linux

package main

import (
	"net"

	"github.com/mdlayher/vsock"
)

func listenVsock(port uint32) (net.Listener, error) {
	listener, err := vsock.Listen(port, nil)
	if err != nil {
		return nil, err
	}
	return hostListener{listener}, nil
}

// The control protocol is privileged. A build inside the guest must not use
// vsock loopback to ask its own agent to run a root command.
type hostListener struct{ net.Listener }

func (l hostListener) Accept() (net.Conn, error) {
	for {
		conn, err := l.Listener.Accept()
		if err != nil {
			return nil, err
		}
		if addr, ok := conn.RemoteAddr().(*vsock.Addr); ok && addr.ContextID == 2 {
			return conn, nil
		}
		conn.Close()
	}
}
