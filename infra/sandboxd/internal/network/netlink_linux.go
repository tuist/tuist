//go:build linux

package network

import (
	"context"
	"errors"
	"fmt"
	"net"
	"time"

	"github.com/vishvananda/netlink"
	"github.com/vishvananda/netns"
	"golang.org/x/sys/unix"
)

// UseNetlink selects an opt-in link backend. Namespace ownership, NAT, MSS
// clamping, host firewall rules and acknowledged teardown remain unchanged.
// Call only during manager construction, before concurrent lifecycle work.
func (m *Manager) UseNetlink() error {
	m.configureLinks = m.setupNetlinkLinks
	return nil
}

func (m *Manager) setupNetlinkLinks(ctx context.Context, ns string, addrs Addresses) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	namespace, err := netns.GetFromName(ns)
	if err != nil {
		return err
	}
	defer namespace.Close()
	pod, err := netlink.NewHandle(unix.NETLINK_ROUTE)
	if err != nil {
		return err
	}
	defer pod.Close()
	guest, err := netlink.NewHandleAt(namespace, unix.NETLINK_ROUTE)
	if err != nil {
		return err
	}
	defer guest.Close()
	// Per-handle timeouts avoid changing global socket settings during creates.
	for _, handle := range []*netlink.Handle{pod, guest} {
		if err = handle.SetSocketTimeout(time.Second); err != nil {
			return err
		}
	}
	lo, err := guest.LinkByName("lo")
	if err != nil {
		return err
	}
	if err = guest.LinkSetUp(lo); err != nil {
		return err
	}
	// TUNSETIFF operates on the calling thread's namespace, unlike rtnetlink.
	// Keep this single subprocess rather than switching a Go worker's namespace.
	var absent netlink.LinkNotFoundError
	tap, err := guest.LinkByName(TapName)
	if errors.As(err, &absent) {
		if err = m.run(ctx, "ip", "-n", ns, "tuntap", "add", "name", TapName, "mode", "tap"); err != nil {
			return err
		}
	} else if err != nil {
		return err
	} else if device, ok := tap.(*netlink.Tuntap); !ok || device.Mode != netlink.TUNTAP_MODE_TAP {
		return fmt.Errorf("existing %s is not a TAP device", TapName)
	}
	host := VethHostName(addrs.Slot)
	link, err := pod.LinkByName(host)
	if err == nil {
		if err = pod.LinkDel(link); err != nil {
			return err
		}
	} else if !errors.As(err, &absent) {
		return err
	}
	if err = pod.LinkAdd(&netlink.Veth{
		LinkAttrs: netlink.LinkAttrs{Name: host}, PeerName: VethNetnsName,
		PeerNamespace: netlink.NsFd(namespace),
	}); err != nil {
		return err
	}
	for _, entry := range []struct {
		handle *netlink.Handle
		name   string
		cidr   string
	}{{guest, TapName, TapAddr}, {pod, host, addrs.PodCIDR()}, {guest, VethNetnsName, addrs.NetnsCIDR()}} {
		if err = ctx.Err(); err != nil {
			return err
		}
		link, err = entry.handle.LinkByName(entry.name)
		if err != nil {
			return err
		}
		addr, parseErr := netlink.ParseAddr(entry.cidr)
		if parseErr != nil {
			return parseErr
		}
		if err = entry.handle.AddrReplace(link, addr); err != nil {
			return err
		}
		if err = entry.handle.LinkSetUp(link); err != nil {
			return err
		}
	}
	peer, err := guest.LinkByName(VethNetnsName)
	if err != nil {
		return err
	}
	if err = guest.RouteReplace(&netlink.Route{LinkIndex: peer.Attrs().Index, Gw: net.IP(addrs.Pod.AsSlice())}); err != nil {
		return err
	}
	return ctx.Err()
}
