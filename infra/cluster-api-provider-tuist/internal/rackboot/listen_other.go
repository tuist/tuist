//go:build !linux

package rackboot

import "net"

func freebindListenConfig() *net.ListenConfig { return &net.ListenConfig{} }
