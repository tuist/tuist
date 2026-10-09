package peers

import (
	"bytes"
	"fmt"
	"net"
	"net/netip"
	"sort"
	"strings"

	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
	corev1 "k8s.io/api/core/v1"
)

const PublicKeyAnnotation = "tuist.dev/runner-egress-public-key"

type Peer struct {
	Node      string
	PublicKey wgtypes.Key
	Address   netip.Addr
}

func (p Peer) AllowedIP() net.IPNet {
	return net.IPNet{IP: net.IP(p.Address.AsSlice()), Mask: net.CIDRMask(32, 32)}
}

type Skipped struct {
	Node   string
	Reason string
}

// Candidate is the peer-relevant part of a Node: its key annotation and its
// first IPv4 InternalIP. Two Nodes with equal candidates produce the same peer.
type Candidate struct {
	Node       string
	HasKey     bool
	Key        string
	InternalIP string
}

func CandidateFor(node *corev1.Node) Candidate {
	key, hasKey := node.Annotations[PublicKeyAnnotation]
	return Candidate{
		Node:       node.Name,
		HasKey:     hasKey,
		Key:        strings.TrimSpace(key),
		InternalIP: internalIPv4(node),
	}
}

func internalIPv4(node *corev1.Node) string {
	for _, address := range node.Status.Addresses {
		if address.Type != corev1.NodeInternalIP {
			continue
		}
		addr, err := netip.ParseAddr(address.Address)
		if err != nil {
			continue
		}
		addr = addr.Unmap()
		if addr.Is4() {
			return addr.String()
		}
	}
	return ""
}

// FromNodes returns the desired peers sorted by node name. Nodes without the
// annotation are ignored. Nodes with an invalid key, no IPv4 InternalIP inside
// peerCIDR, or a key or address shared with another Node are skipped.
func FromNodes(nodes []*corev1.Node, peerCIDR netip.Prefix, ownPublicKey wgtypes.Key) ([]Peer, []Skipped) {
	sorted := make([]*corev1.Node, 0, len(nodes))
	for _, node := range nodes {
		if node != nil {
			sorted = append(sorted, node)
		}
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Name < sorted[j].Name })

	var candidates []Peer
	var skipped []Skipped
	for _, node := range sorted {
		candidate := CandidateFor(node)
		if !candidate.HasKey {
			continue
		}
		key, err := wgtypes.ParseKey(candidate.Key)
		if err != nil {
			skipped = append(skipped, Skipped{Node: node.Name, Reason: "invalid public key"})
			continue
		}
		if key == (wgtypes.Key{}) {
			skipped = append(skipped, Skipped{Node: node.Name, Reason: "all-zero public key"})
			continue
		}
		if key == ownPublicKey {
			skipped = append(skipped, Skipped{Node: node.Name, Reason: "public key equals the gateway's own key"})
			continue
		}
		if candidate.InternalIP == "" {
			skipped = append(skipped, Skipped{Node: node.Name, Reason: "no IPv4 InternalIP"})
			continue
		}
		addr := netip.MustParseAddr(candidate.InternalIP)
		if !peerCIDR.Contains(addr) {
			skipped = append(skipped, Skipped{Node: node.Name, Reason: fmt.Sprintf("InternalIP %s is outside %s", addr, peerCIDR)})
			continue
		}
		candidates = append(candidates, Peer{Node: node.Name, PublicKey: key, Address: addr})
	}

	keyCount := map[wgtypes.Key]int{}
	addrCount := map[netip.Addr]int{}
	for _, peer := range candidates {
		keyCount[peer.PublicKey]++
		addrCount[peer.Address]++
	}

	desired := make([]Peer, 0, len(candidates))
	for _, peer := range candidates {
		switch {
		case keyCount[peer.PublicKey] > 1:
			skipped = append(skipped, Skipped{Node: peer.Node, Reason: "public key is shared with another Node"})
		case addrCount[peer.Address] > 1:
			skipped = append(skipped, Skipped{Node: peer.Node, Reason: fmt.Sprintf("InternalIP %s is shared with another Node", peer.Address)})
		default:
			desired = append(desired, peer)
		}
	}
	return desired, skipped
}

// Diff returns the per-peer changes that turn current into desired. Peers
// that already match are left alone so their sessions are not reset.
func Diff(current []wgtypes.Peer, desired []Peer) []wgtypes.PeerConfig {
	want := make(map[wgtypes.Key]Peer, len(desired))
	for _, peer := range desired {
		want[peer.PublicKey] = peer
	}
	have := make(map[wgtypes.Key]wgtypes.Peer, len(current))
	for _, peer := range current {
		have[peer.PublicKey] = peer
	}

	var removals, upserts []wgtypes.PeerConfig
	for key := range have {
		if _, ok := want[key]; !ok {
			removals = append(removals, wgtypes.PeerConfig{PublicKey: key, Remove: true})
		}
	}
	for key, peer := range want {
		existing, ok := have[key]
		if ok && allowedIPsMatch(existing.AllowedIPs, peer.AllowedIP()) {
			continue
		}
		upserts = append(upserts, wgtypes.PeerConfig{
			PublicKey:         key,
			ReplaceAllowedIPs: true,
			AllowedIPs:        []net.IPNet{peer.AllowedIP()},
		})
	}

	byKey := func(configs []wgtypes.PeerConfig) {
		sort.Slice(configs, func(i, j int) bool {
			return bytes.Compare(configs[i].PublicKey[:], configs[j].PublicKey[:]) < 0
		})
	}
	byKey(removals)
	byKey(upserts)
	return append(removals, upserts...)
}

func allowedIPsMatch(current []net.IPNet, want net.IPNet) bool {
	if len(current) != 1 {
		return false
	}
	ones, bits := current[0].Mask.Size()
	wantOnes, wantBits := want.Mask.Size()
	return ones == wantOnes && bits == wantBits && current[0].IP.Equal(want.IP)
}
