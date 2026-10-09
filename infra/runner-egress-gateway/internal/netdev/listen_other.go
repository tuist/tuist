//go:build !linux

package netdev

import (
	"context"
	"net"
)

func ListenFreebind(ctx context.Context, address string) (net.Listener, error) {
	var config net.ListenConfig
	return config.Listen(ctx, "tcp4", address)
}
