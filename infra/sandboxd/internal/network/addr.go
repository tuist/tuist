// Package network manages the per-sandbox network namespace described in
// infra/sandboxd/AGENTS.md "Network": tap0 in the netns at 10.0.0.1/30, a
// veth pair to the pod on a /30 carved from 172.31.0.0/16 by slot index, and
// MASQUERADE on both sides.
package network

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/netip"
)

const (
	// TapName is the guest-facing device inside every sandbox netns.
	TapName = "tap0"
	// TapAddr is the netns side of the guest link; the guest is always
	// GuestAddr with the fixed MAC.
	TapAddr   = "10.0.0.1/30"
	GuestAddr = "10.0.0.2"
	GuestNet  = "10.0.0.0/30"
	// VethNetnsName is the netns side of the veth pair.
	VethNetnsName = "veth0"
	// SlotNetwork is the range the per-slot /30s are carved from.
	SlotNetwork = "172.31.0.0/16"
	// MaxSlots is the number of /30 subnets in SlotNetwork.
	MaxSlots = 65536 / 4
)

var slotBase = netip.MustParseAddr("172.31.0.0")

// Addresses are the pod-side and netns-side endpoints of one slot's /30.
type Addresses struct {
	Slot   int
	Pod    netip.Addr
	Netns  netip.Addr
	Prefix netip.Prefix
}

func (a Addresses) PodCIDR() string   { return fmt.Sprintf("%s/30", a.Pod) }
func (a Addresses) NetnsCIDR() string { return fmt.Sprintf("%s/30", a.Netns) }

// SlotAddresses maps a slot index to its /30: the n-th /30 of 172.31.0.0/16,
// pod side .y+1, netns side .y+2.
func SlotAddresses(slot int) (Addresses, error) {
	if slot < 0 || slot >= MaxSlots {
		return Addresses{}, fmt.Errorf("slot %d out of range [0,%d)", slot, MaxSlots)
	}
	base := slotBase.As4()
	offset := slot * 4
	base[2] = byte(offset / 256)
	base[3] = byte(offset % 256)
	network := netip.AddrFrom4(base)
	pod := network.Next()
	ns := pod.Next()
	return Addresses{Slot: slot, Pod: pod, Netns: ns, Prefix: netip.PrefixFrom(network, 30)}, nil
}

// VethHostName is the pod-side veth for a slot.
func VethHostName(slot int) string { return fmt.Sprintf("vh%d", slot) }

// NamespaceName is the netns of a sandbox: "sbx-" + the first 12 characters
// of its id.
func NamespaceName(sandboxID string) string {
	id := sandboxID
	if len(id) > 12 {
		id = id[:12]
	}
	return "sbx-" + id
}

// BuildNamespaceName is the netns of a template build. Template ids share
// long prefixes, so this hashes instead of truncating.
func BuildNamespaceName(buildID string) string {
	sum := sha256.Sum256([]byte(buildID))
	return "sbx-tmpl-" + hex.EncodeToString(sum[:4])
}
