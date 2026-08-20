package agent

import (
	"reflect"
	"testing"
)

func TestParseEgressClass(t *testing.T) {
	minor, floor, burst, err := ParseEgressClass(`{"classid":"1:29a","floor_mbps":750,"burst_mbps":1500}`)
	if err != nil {
		t.Fatal(err)
	}
	if minor != 0x29a || floor != 750 || burst != 1500 {
		t.Fatalf("got minor=%x floor=%d burst=%d", minor, floor, burst)
	}
}

// A malformed annotation must fail parsing as a whole: the caller leaves the
// pod on the unshaped (but fully Cilium-processed) path instead of building a
// half-configured class.
func TestParseEgressClassRejects(t *testing.T) {
	for name, value := range map[string]string{
		"not json":        `1:5`,
		"wrong major":     `{"classid":"2:5"}`,
		"root minor":      `{"classid":"1:1"}`,
		"zero minor":      `{"classid":"1:0"}`,
		"non-hex minor":   `{"classid":"1:zz"}`,
		"minor overflow":  `{"classid":"1:10000"}`,
		"negative floor":  `{"classid":"1:5","floor_mbps":-1}`,
		"negative burst":  `{"classid":"1:5","burst_mbps":-1}`,
		"missing classid": `{"floor_mbps":10}`,
	} {
		if _, _, _, err := ParseEgressClass(value); err == nil {
			t.Errorf("%s: expected error for %q", name, value)
		}
	}
}

func TestPriorityForMinor(t *testing.T) {
	if got := PriorityForMinor(0x29a); got != 0x1029a {
		t.Fatalf("priority = %#x, want 0x1029a", got)
	}
	if got := ClassIDString(0x29a); got != "1:29a" {
		t.Fatalf("classid = %q, want 1:29a", got)
	}
}

// Both replicas of an instance share one class (cross-replica 1xC), and each
// pod's sibling set is the other same-class pods on the node — the bypass
// that keeps node-local replication sync off the tenant bucket.
func TestDesiredSharedClassAndSiblings(t *testing.T) {
	classes, attachments := Desired([]PodShape{
		{Namespace: "kura", Name: "kura-acme-0", IP: "10.0.0.10", Minor: 0x102, FloorMbps: 700, BurstMbps: 1500},
		{Namespace: "kura", Name: "kura-acme-1", IP: "10.0.0.11", Minor: 0x102, FloorMbps: 700, BurstMbps: 1500},
		{Namespace: "kura", Name: "kura-other-0", IP: "10.0.0.12", Minor: 0x103, FloorMbps: 300, BurstMbps: 0},
	})

	if len(classes) != 2 {
		t.Fatalf("classes = %+v, want 2", classes)
	}
	if classes[0x102].FloorMbps != 700 || classes[0x102].BurstMbps != 1500 {
		t.Fatalf("class 0x102 = %+v", classes[0x102])
	}
	if classes[0x103].FloorMbps != 300 || classes[0x103].BurstMbps != 0 {
		t.Fatalf("class 0x103 = %+v", classes[0x103])
	}

	if len(attachments) != 3 {
		t.Fatalf("attachments = %+v, want 3", attachments)
	}
	bySibling := map[string][]string{}
	for _, attachment := range attachments {
		bySibling[attachment.Name] = attachment.SiblingIPs
	}
	if !reflect.DeepEqual(bySibling["kura-acme-0"], []string{"10.0.0.11"}) {
		t.Fatalf("kura-acme-0 siblings = %v", bySibling["kura-acme-0"])
	}
	if !reflect.DeepEqual(bySibling["kura-acme-1"], []string{"10.0.0.10"}) {
		t.Fatalf("kura-acme-1 siblings = %v", bySibling["kura-acme-1"])
	}
	if len(bySibling["kura-other-0"]) != 0 {
		t.Fatalf("kura-other-0 siblings = %v", bySibling["kura-other-0"])
	}
}

// During a rollout the replicas can disagree on rates; the larger value wins
// so a tenant is never under-provisioned by a stale sibling annotation.
func TestDesiredRolloutTakesLargerRates(t *testing.T) {
	classes, _ := Desired([]PodShape{
		{Namespace: "kura", Name: "a-0", IP: "10.0.0.10", Minor: 0x102, FloorMbps: 700, BurstMbps: 1500},
		{Namespace: "kura", Name: "a-1", IP: "10.0.0.11", Minor: 0x102, FloorMbps: 900, BurstMbps: 1200},
	})
	if classes[0x102].FloorMbps != 900 || classes[0x102].BurstMbps != 1500 {
		t.Fatalf("class = %+v, want floor 900 burst 1500", classes[0x102])
	}
}
