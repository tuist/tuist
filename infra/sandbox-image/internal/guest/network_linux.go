//go:build linux

package guest

import (
	"errors"
	"fmt"
	"net"
	"time"

	"github.com/vishvananda/netlink"
	"golang.org/x/sys/unix"
)

// ConfigureNetwork brings up lo, gives ifname the address and installs the
// default route. The interface's MAC is left to the VMM. It waits up to wait
// for the interface to appear, since virtio-net can register a moment after
// init starts.
func ConfigureNetwork(ifname, cidr, gateway string, wait time.Duration) error {
	lo, err := netlink.LinkByName("lo")
	if err != nil {
		return fmt.Errorf("lo: %w", err)
	}
	if err := netlink.LinkSetUp(lo); err != nil {
		return fmt.Errorf("lo up: %w", err)
	}

	link, err := waitForLink(ifname, wait)
	if err != nil {
		return err
	}
	addr, err := netlink.ParseAddr(cidr)
	if err != nil {
		return fmt.Errorf("parse %s: %w", cidr, err)
	}
	if err := netlink.AddrReplace(link, addr); err != nil {
		return fmt.Errorf("%s addr %s: %w", ifname, cidr, err)
	}
	if err := netlink.LinkSetUp(link); err != nil {
		return fmt.Errorf("%s up: %w", ifname, err)
	}
	gw := net.ParseIP(gateway)
	if gw == nil {
		return fmt.Errorf("invalid gateway %q", gateway)
	}
	route := &netlink.Route{LinkIndex: link.Attrs().Index, Gw: gw}
	if err := netlink.RouteReplace(route); err != nil {
		return fmt.Errorf("default route via %s: %w", gateway, err)
	}
	return nil
}

// FlushNeighbors drops every learned neighbour entry on ifname, the way
// `ip neigh flush dev` does; permanent and NOARP entries are kept.
func FlushNeighbors(ifname string) error {
	link, err := netlink.LinkByName(ifname)
	if err != nil {
		return err
	}
	neighs, err := netlink.NeighList(link.Attrs().Index, netlink.FAMILY_ALL)
	if err != nil {
		return err
	}
	for i := range neighs {
		if neighs[i].State&(netlink.NUD_PERMANENT|netlink.NUD_NOARP) != 0 {
			continue
		}
		if err := netlink.NeighDel(&neighs[i]); err != nil && !errors.Is(err, unix.ENOENT) {
			return fmt.Errorf("delete %s: %w", neighs[i].IP, err)
		}
	}
	return nil
}

func waitForLink(ifname string, wait time.Duration) (netlink.Link, error) {
	deadline := time.Now().Add(wait)
	for {
		link, err := netlink.LinkByName(ifname)
		if err == nil {
			return link, nil
		}
		if time.Now().After(deadline) {
			return nil, fmt.Errorf("%s did not appear within %s: %w", ifname, wait, err)
		}
		time.Sleep(100 * time.Millisecond)
	}
}
