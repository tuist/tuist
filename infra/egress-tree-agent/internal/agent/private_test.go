package agent

import (
	"encoding/binary"
	"net"
	"reflect"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func privateNode(name, network, members string, cidrs ...string) *corev1.Node {
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: name, Labels: map[string]string{}, Annotations: map[string]string{}}}
	if network != "" {
		node.Labels[PrivateNetworkLabel] = network
	}
	if members != "" {
		node.Annotations[PrivateNetworkMembersAnnotation] = members
	}
	node.Spec.PodCIDRs = cidrs
	return node
}

// Only peers on the same network with the same installed route membership
// route privately; the node's own CIDR and IPv6 CIDRs are never stamped.
func TestPrivatePeerCIDRs(t *testing.T) {
	self := privateNode("kura", "pn-1", "digest-a", "192.168.121.0/24")
	nodes := []*corev1.Node{
		self,
		privateNode("worker-a", "pn-1", "digest-a", "192.168.118.0/24", "fd00::/64"),
		privateNode("worker-b", "pn-1", "digest-a", "192.168.97.0/24"),
		privateNode("lagging", "pn-1", "digest-b", "192.168.50.0/24"),
		privateNode("other-network", "pn-2", "digest-a", "192.168.60.0/24"),
	}
	got := PrivatePeerCIDRs(self, nodes)
	want := []string{"192.168.118.0/24", "192.168.97.0/24"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("PrivatePeerCIDRs = %v, want %v", got, want)
	}

	// A node that has not installed a membership routes nothing privately.
	if got := PrivatePeerCIDRs(privateNode("kura", "pn-1", "", "192.168.121.0/24"), nodes); got != nil {
		t.Fatalf("unattested self: got %v, want none", got)
	}
}

// The kernel compares the LPM key's address byte for byte against the
// packet's daddr, which is in network order: reading it host-order on a
// little-endian box would build keys that never match.
func TestParseLPMV4ByteOrder(t *testing.T) {
	key, ok := parseLPMV4("192.168.118.7/24")
	if !ok {
		t.Fatal("parse failed")
	}
	var raw [4]byte
	binary.LittleEndian.PutUint32(raw[:], key.Addr)
	if key.PrefixLen != 24 || !net.IP(raw[:]).Equal(net.IPv4(192, 168, 118, 0)) {
		t.Fatalf("key = %+v (addr bytes %v), want /24 of 192.168.118.0", key, raw)
	}
	if _, ok := parseLPMV4("fd00::/64"); ok {
		t.Fatal("IPv6 prefix accepted")
	}
}
