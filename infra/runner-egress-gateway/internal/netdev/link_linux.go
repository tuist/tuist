//go:build linux

package netdev

import (
	"errors"
	"fmt"
	"net"
	"net/netip"

	"github.com/vishvananda/netlink"
	"golang.org/x/sys/unix"
)

type NetlinkLink struct{}

func NewLink() Link { return NetlinkLink{} }

func (NetlinkLink) Ensure(spec LinkSpec) error {
	link, err := netlink.LinkByName(spec.Name)
	var notFound netlink.LinkNotFoundError
	switch {
	case errors.As(err, &notFound):
		attrs := netlink.NewLinkAttrs()
		attrs.Name = spec.Name
		attrs.MTU = spec.MTU
		if err := netlink.LinkAdd(&netlink.Wireguard{LinkAttrs: attrs}); err != nil {
			return fmt.Errorf("create %s: %w", spec.Name, err)
		}
		if link, err = netlink.LinkByName(spec.Name); err != nil {
			return fmt.Errorf("look up %s after creating it: %w", spec.Name, err)
		}
	case err != nil:
		return fmt.Errorf("look up %s: %w", spec.Name, err)
	}

	if link.Type() != "wireguard" {
		return fmt.Errorf("%s exists with type %q, not wireguard", spec.Name, link.Type())
	}
	if link.Attrs().MTU != spec.MTU {
		if err := netlink.LinkSetMTU(link, spec.MTU); err != nil {
			return fmt.Errorf("set %s MTU: %w", spec.Name, err)
		}
	}

	want := &netlink.Addr{IPNet: prefixToIPNet(spec.Address)}
	addrs, err := netlink.AddrList(link, netlink.FAMILY_V4)
	if err != nil {
		return fmt.Errorf("list %s addresses: %w", spec.Name, err)
	}
	for _, addr := range addrs {
		if addr.IPNet.String() == want.IPNet.String() {
			continue
		}
		if err := netlink.AddrDel(link, &addr); err != nil {
			return fmt.Errorf("remove %s from %s: %w", addr.IPNet, spec.Name, err)
		}
	}
	if err := netlink.AddrReplace(link, want); err != nil {
		return fmt.Errorf("set %s on %s: %w", spec.Address, spec.Name, err)
	}

	if link.Attrs().Flags&net.FlagUp == 0 {
		if err := netlink.LinkSetUp(link); err != nil {
			return fmt.Errorf("bring %s up: %w", spec.Name, err)
		}
	}

	route := &netlink.Route{
		LinkIndex: link.Attrs().Index,
		Dst:       prefixToIPNet(spec.Route),
		Scope:     netlink.SCOPE_LINK,
		Protocol:  unix.RTPROT_STATIC,
	}
	if err := netlink.RouteReplace(route); err != nil {
		return fmt.Errorf("route %s via %s: %w", spec.Route, spec.Name, err)
	}
	return nil
}

func prefixToIPNet(prefix netip.Prefix) *net.IPNet {
	bits := 32
	if prefix.Addr().Is6() {
		bits = 128
	}
	return &net.IPNet{IP: net.IP(prefix.Addr().AsSlice()), Mask: net.CIDRMask(prefix.Bits(), bits)}
}
