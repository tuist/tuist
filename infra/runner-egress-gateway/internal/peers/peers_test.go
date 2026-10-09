package peers

import (
	"net"
	"net/netip"
	"reflect"
	"testing"

	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

var peerCIDR = netip.MustParsePrefix("100.64.0.0/10")

func testKey(t *testing.T, seed byte) wgtypes.Key {
	t.Helper()
	var raw [wgtypes.KeyLen]byte
	for i := range raw {
		raw[i] = seed
	}
	key, err := wgtypes.NewKey(raw[:])
	if err != nil {
		t.Fatal(err)
	}
	return key
}

func node(name, key string, addresses ...corev1.NodeAddress) *corev1.Node {
	n := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: name}}
	if key != "" {
		n.Annotations = map[string]string{PublicKeyAnnotation: key}
	}
	n.Status.Addresses = addresses
	return n
}

func internal(ip string) corev1.NodeAddress {
	return corev1.NodeAddress{Type: corev1.NodeInternalIP, Address: ip}
}

func TestFromNodes(t *testing.T) {
	k1, k2, k3, own := testKey(t, 1), testKey(t, 2), testKey(t, 3), testKey(t, 9)

	nodes := []*corev1.Node{
		node("mac-b", k2.String(), internal("100.100.0.2")),
		node("mac-a", k1.String(), corev1.NodeAddress{Type: corev1.NodeHostName, Address: "mac-a"}, internal("fd7a:115c::1"), internal("100.100.0.1")),
		node("linux", "", internal("10.0.0.5")),
		node("bad-key", "not-a-key", internal("100.100.0.9")),
		node("zero-key", wgtypes.Key{}.String(), internal("100.100.0.10")),
		node("own-key", own.String(), internal("100.100.0.11")),
		node("no-ip", k3.String()),
		node("outside", k3.String(), internal("192.168.1.10")),
		node("external-only", k3.String(), corev1.NodeAddress{Type: corev1.NodeExternalIP, Address: "100.100.0.12"}),
		nil,
	}

	desired, skipped := FromNodes(nodes, peerCIDR, own)

	wantDesired := []Peer{
		{Node: "mac-a", PublicKey: k1, Address: netip.MustParseAddr("100.100.0.1")},
		{Node: "mac-b", PublicKey: k2, Address: netip.MustParseAddr("100.100.0.2")},
	}
	if !reflect.DeepEqual(desired, wantDesired) {
		t.Fatalf("desired = %+v, want %+v", desired, wantDesired)
	}

	gotSkipped := map[string]bool{}
	for _, s := range skipped {
		gotSkipped[s.Node] = true
	}
	for _, name := range []string{"bad-key", "zero-key", "own-key", "no-ip", "outside", "external-only"} {
		if !gotSkipped[name] {
			t.Errorf("expected %s to be skipped, skipped = %+v", name, skipped)
		}
	}
	if gotSkipped["linux"] {
		t.Errorf("nodes without the annotation must be ignored, not skipped")
	}
}

func TestFromNodesSkipsDuplicates(t *testing.T) {
	k1, k2, k3, k4 := testKey(t, 1), testKey(t, 2), testKey(t, 3), testKey(t, 4)
	nodes := []*corev1.Node{
		node("a", k1.String(), internal("100.100.0.1")),
		node("b", k1.String(), internal("100.100.0.2")),
		node("c", k2.String(), internal("100.100.0.3")),
		node("d", k3.String(), internal("100.100.0.3")),
		node("e", k4.String(), internal("100.100.0.4")),
	}
	desired, skipped := FromNodes(nodes, peerCIDR, wgtypes.Key{})
	if len(desired) != 1 || desired[0].Node != "e" {
		t.Fatalf("desired = %+v", desired)
	}
	if len(skipped) != 4 {
		t.Fatalf("skipped = %+v", skipped)
	}
}

func ipNet(ip string) net.IPNet {
	return net.IPNet{IP: net.ParseIP(ip).To4(), Mask: net.CIDRMask(32, 32)}
}

func TestDiff(t *testing.T) {
	k1, k2, k3, k4 := testKey(t, 1), testKey(t, 2), testKey(t, 3), testKey(t, 4)

	current := []wgtypes.Peer{
		{PublicKey: k1, AllowedIPs: []net.IPNet{ipNet("100.100.0.1")}},
		{PublicKey: k2, AllowedIPs: []net.IPNet{ipNet("100.100.0.99")}},
		{PublicKey: k3, AllowedIPs: []net.IPNet{ipNet("100.100.0.3")}},
	}
	desired := []Peer{
		{Node: "a", PublicKey: k1, Address: netip.MustParseAddr("100.100.0.1")},
		{Node: "b", PublicKey: k2, Address: netip.MustParseAddr("100.100.0.2")},
		{Node: "d", PublicKey: k4, Address: netip.MustParseAddr("100.100.0.4")},
	}

	got := Diff(current, desired)
	want := []wgtypes.PeerConfig{
		{PublicKey: k3, Remove: true},
		{PublicKey: k2, ReplaceAllowedIPs: true, AllowedIPs: []net.IPNet{ipNet("100.100.0.2")}},
		{PublicKey: k4, ReplaceAllowedIPs: true, AllowedIPs: []net.IPNet{ipNet("100.100.0.4")}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Diff =\n%+v\nwant\n%+v", got, want)
	}
}

func TestDiffNoChanges(t *testing.T) {
	k1 := testKey(t, 1)
	current := []wgtypes.Peer{{PublicKey: k1, AllowedIPs: []net.IPNet{ipNet("100.100.0.1")}}}
	desired := []Peer{{Node: "a", PublicKey: k1, Address: netip.MustParseAddr("100.100.0.1")}}
	if got := Diff(current, desired); len(got) != 0 {
		t.Fatalf("Diff = %+v, want no changes", got)
	}
}

func TestDiffReplacesExtraAllowedIPs(t *testing.T) {
	k1 := testKey(t, 1)
	current := []wgtypes.Peer{{PublicKey: k1, AllowedIPs: []net.IPNet{ipNet("100.100.0.1"), ipNet("0.0.0.0")}}}
	desired := []Peer{{Node: "a", PublicKey: k1, Address: netip.MustParseAddr("100.100.0.1")}}
	got := Diff(current, desired)
	if len(got) != 1 || !got[0].ReplaceAllowedIPs || len(got[0].AllowedIPs) != 1 {
		t.Fatalf("Diff = %+v", got)
	}
}

func TestDiffRemovesAll(t *testing.T) {
	k1 := testKey(t, 1)
	current := []wgtypes.Peer{{PublicKey: k1, AllowedIPs: []net.IPNet{ipNet("100.100.0.1")}}}
	got := Diff(current, nil)
	if len(got) != 1 || !got[0].Remove {
		t.Fatalf("Diff = %+v", got)
	}
}

func TestCandidateFor(t *testing.T) {
	k1 := testKey(t, 1)
	a := CandidateFor(node("a", " "+k1.String()+"\n", internal("100.100.0.1")))
	if !a.HasKey || a.Key != k1.String() || a.InternalIP != "100.100.0.1" {
		t.Fatalf("candidate = %+v", a)
	}
	b := CandidateFor(node("b", ""))
	if b.HasKey || b.InternalIP != "" {
		t.Fatalf("candidate = %+v", b)
	}
}
