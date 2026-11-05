//go:build linux

package network

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/vishvananda/netlink"
	"github.com/vishvananda/netns"
	"golang.org/x/sys/unix"
)

// This test needs the owned disposable worker's NET_ADMIN capability. It uses
// two unused high slots, refuses existing names/devices and always tears down.
// Ordinary unit test runs never mutate a network namespace.
func TestNetlinkLabConcurrentNamespacesAndRepair(t *testing.T) {
	if os.Getenv("RBE_LAB") != "disposable" || os.Getenv("RBE_NETWORK_TEST") != "1" {
		t.Skip("requires explicit disposable lab network test opt-in")
	}
	m := NewManager(slog.Default())
	if err := m.UseNetlink(); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	type entry struct {
		ns   string
		slot int
	}
	entries := []entry{{fmt.Sprintf("sbx-nl-%d-a", os.Getpid()), MaxSlots - 1}, {fmt.Sprintf("sbx-nl-%d-b", os.Getpid()), MaxSlots - 2}}
	for _, e := range entries {
		if _, err := os.Stat("/var/run/netns/" + e.ns); !os.IsNotExist(err) {
			t.Fatalf("namespace %s is not available: %v", e.ns, err)
		}
		if _, err := netlink.LinkByName(VethHostName(e.slot)); err == nil {
			t.Fatalf("slot %d is already occupied", e.slot)
		} else {
			var missing netlink.LinkNotFoundError
			if !errors.As(err, &missing) {
				t.Fatalf("inspect slot %d: %v", e.slot, err)
			}
		}
	}
	defer func() {
		for _, e := range entries {
			if err := m.Teardown(context.Background(), e.ns, e.slot); err != nil {
				t.Errorf("cleanup: %v", err)
			}
		}
	}()
	for pass := 0; pass < 2; pass++ {
		done := make(chan error, len(entries))
		for _, e := range entries {
			go func() { done <- m.Setup(ctx, e.ns, e.slot) }()
		}
		for range entries {
			if err := <-done; err != nil {
				t.Error(err)
			}
		}
		if t.Failed() {
			t.FailNow()
		}
		for _, e := range entries {
			if err := inspectNativeNamespace(e.ns, e.slot); err != nil {
				t.Fatal(err)
			}
			for _, rule := range [][]string{
				{"nat", "POSTROUTING", "-s", GuestNet, "-o", VethNetnsName, "-j", "MASQUERADE"},
				{"mangle", "FORWARD", "-p", "tcp", "--tcp-flags", "SYN,RST", "SYN", "-j", "TCPMSS", "--clamp-mss-to-pmtu"},
			} {
				args := append([]string{"netns", "exec", e.ns, "iptables", "-w", "5", "-t", rule[0], "-C", rule[1]}, rule[2:]...)
				if err := m.run(ctx, "ip", args...); err != nil {
					t.Fatal(err)
				}
			}
		}
	}
	// Repair must fail closed when a device with the expected name has the
	// wrong kind; do not silently attach a VM to arbitrary existing links.
	broken := entries[0]
	if err := m.run(ctx, "ip", "-n", broken.ns, "link", "del", TapName); err != nil {
		t.Fatal(err)
	}
	if err := m.run(ctx, "ip", "-n", broken.ns, "link", "add", TapName, "type", "dummy"); err != nil {
		t.Fatal(err)
	}
	if err := m.Setup(ctx, broken.ns, broken.slot); err == nil || !strings.Contains(err.Error(), "not a TAP device") {
		t.Fatalf("unexpected result for incompatible existing device: %v", err)
	}
	for _, e := range entries {
		if err := m.Teardown(ctx, e.ns, e.slot); err != nil {
			t.Fatal(err)
		}
		if _, err := os.Stat("/var/run/netns/" + e.ns); !os.IsNotExist(err) {
			t.Fatalf("namespace survived deletion: %v", err)
		}
		if _, err := netlink.LinkByName(VethHostName(e.slot)); err == nil {
			t.Fatal("pod veth survived deletion")
		}
	}
}

func inspectNativeNamespace(ns string, slot int) error {
	namespace, err := netns.GetFromName(ns)
	if err != nil {
		return err
	}
	defer namespace.Close()
	guest, err := netlink.NewHandleAt(namespace, unix.NETLINK_ROUTE)
	if err != nil {
		return err
	}
	defer guest.Close()
	addrs, _ := SlotAddresses(slot)
	host, err := netlink.LinkByName(VethHostName(slot))
	if err != nil {
		return err
	}
	hostAddrs, err := netlink.AddrList(host, netlink.FAMILY_V4)
	if err != nil {
		return err
	}
	if len(hostAddrs) != 1 || hostAddrs[0].IPNet.String() != addrs.PodCIDR() || host.Attrs().Flags&net.FlagUp == 0 {
		return fmt.Errorf("slot %d host address or flags: %v, %v", slot, hostAddrs, host.Attrs().Flags)
	}
	for name, expected := range map[string]string{TapName: TapAddr, VethNetnsName: addrs.NetnsCIDR()} {
		link, err := guest.LinkByName(name)
		if err != nil {
			return err
		}
		addresses, err := guest.AddrList(link, netlink.FAMILY_V4)
		if err != nil {
			return err
		}
		if len(addresses) != 1 || addresses[0].IPNet.String() != expected || link.Attrs().Flags&net.FlagUp == 0 {
			return fmt.Errorf("%s/%s address or flags: %v, %v", ns, name, addresses, link.Attrs().Flags)
		}
	}
	routes, err := guest.RouteList(nil, netlink.FAMILY_V4)
	if err != nil {
		return err
	}
	for _, route := range routes {
		defaultRoute := route.Dst == nil
		if route.Dst != nil {
			ones, _ := route.Dst.Mask.Size()
			defaultRoute = ones == 0
		}
		if defaultRoute && strings.EqualFold(route.Gw.String(), addrs.Pod.String()) {
			return nil
		}
	}
	return fmt.Errorf("%s has no expected default route through %s: %+v", ns, addrs.Pod, routes)
}
