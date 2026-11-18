//go:build !linux

package network

import "errors"

func (m *Manager) UseNetlink() error { return errors.New("netlink networking requires Linux") }
