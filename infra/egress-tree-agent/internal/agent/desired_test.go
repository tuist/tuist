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
		{Namespace: "kura", Name: "kura-acme-0", IP: "10.0.0.10", Account: "acme", Minor: 0x102, FloorMbps: 700, BurstMbps: 1500},
		{Namespace: "kura", Name: "kura-acme-1", IP: "10.0.0.11", Account: "acme", Minor: 0x102, FloorMbps: 700, BurstMbps: 1500},
		{Namespace: "kura", Name: "kura-other-0", IP: "10.0.0.12", Account: "other", Minor: 0x103, FloorMbps: 300, BurstMbps: 0},
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
	// The account each class's metrics are labelled with: a classid is
	// reused across accounts over time, so it does not identify a tenant on
	// its own.
	if classes[0x102].Account != "acme" || classes[0x103].Account != "other" {
		t.Fatalf("accounts = %q / %q", classes[0x102].Account, classes[0x103].Account)
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

// During a rollout the replicas can disagree on rates; the more permissive
// value wins so a tenant is never under-provisioned by a stale sibling
// annotation.
func TestDesiredRolloutTakesLargerRates(t *testing.T) {
	classes, _ := Desired([]PodShape{
		{Namespace: "kura", Name: "a-0", IP: "10.0.0.10", Minor: 0x102, FloorMbps: 700, BurstMbps: 1500},
		{Namespace: "kura", Name: "a-1", IP: "10.0.0.11", Minor: 0x102, FloorMbps: 900, BurstMbps: 1200},
	})
	if classes[0x102].FloorMbps != 900 || classes[0x102].BurstMbps != 1500 {
		t.Fatalf("class = %+v, want floor 900 burst 1500", classes[0x102])
	}
}

// Burst 0 means "no per-tenant ceiling", so it is the most permissive value:
// removing a ceiling mid-rollout must take effect even while a stale replica
// still carries the old number, in either arrival order.
func TestDesiredRolloutUncappedBurstWins(t *testing.T) {
	for _, pods := range [][]PodShape{
		{
			{Namespace: "kura", Name: "a-0", IP: "10.0.0.10", Minor: 0x102, FloorMbps: 700, BurstMbps: 0},
			{Namespace: "kura", Name: "a-1", IP: "10.0.0.11", Minor: 0x102, FloorMbps: 700, BurstMbps: 1500},
		},
		{
			{Namespace: "kura", Name: "a-1", IP: "10.0.0.11", Minor: 0x102, FloorMbps: 700, BurstMbps: 1500},
			{Namespace: "kura", Name: "a-0", IP: "10.0.0.10", Minor: 0x102, FloorMbps: 700, BurstMbps: 0},
		},
	} {
		classes, _ := Desired(pods)
		if classes[0x102].BurstMbps != 0 {
			t.Fatalf("class = %+v, want burst 0 (uncapped)", classes[0x102])
		}
	}
}

func TestDiffStrings(t *testing.T) {
	added, removed := diffStrings([]string{"10.0.0.1", "10.0.0.2"}, []string{"10.0.0.2", "10.0.0.3"})
	if !reflect.DeepEqual(added, []string{"10.0.0.3"}) {
		t.Fatalf("added = %v", added)
	}
	if !reflect.DeepEqual(removed, []string{"10.0.0.1"}) {
		t.Fatalf("removed = %v", removed)
	}
	added, removed = diffStrings(nil, nil)
	if added != nil || removed != nil {
		t.Fatalf("empty diff = %v / %v", added, removed)
	}
}

// Whatever the annotation says, the class tc is given has to be buildable and
// has to stay inside the box. The dangerous case is a floor above the node
// budget: the ceiling is raised to meet the floor, so an unbounded floor would
// drag a tenant's ceiling past the cap the whole tree exists to hold.
func TestClassRatesStayInsideTheBox(t *testing.T) {
	const node int64 = 1000

	for _, tc := range []struct {
		name                string
		class               TenantClass
		wantFloor, wantCeil int64
	}{
		{"ordinary pair", TenantClass{FloorMbps: 25, BurstMbps: 500}, 25, 500},
		{"no floor gets a trickle", TenantClass{FloorMbps: 0, BurstMbps: 500}, 1, 500},
		{"uncapped burst takes the box", TenantClass{FloorMbps: 25, BurstMbps: 0}, 25, node},
		{"burst over the box is capped", TenantClass{FloorMbps: 25, BurstMbps: 5000}, 25, node},
		{"floor over the box is capped", TenantClass{FloorMbps: 2000, BurstMbps: 1500}, node, node},
		{"ceiling under its floor is raised", TenantClass{FloorMbps: 400, BurstMbps: 100}, 400, 400},
	} {
		t.Run(tc.name, func(t *testing.T) {
			floor, ceil := classRates(tc.class, node)
			if floor != tc.wantFloor || ceil != tc.wantCeil {
				t.Fatalf("rates = %d/%d, want %d/%d", floor, ceil, tc.wantFloor, tc.wantCeil)
			}
			if ceil > node {
				t.Fatalf("ceiling %d escaped the node budget %d", ceil, node)
			}
			if floor > ceil {
				t.Fatalf("floor %d above ceiling %d is unbuildable", floor, ceil)
			}
		})
	}
}

// A pod whose account label has not been rendered yet must not blank out a
// class its labelled replica already names, in either arrival order.
func TestDesiredUnlabelledPodKeepsAccount(t *testing.T) {
	for _, pods := range [][]PodShape{
		{
			{Namespace: "kura", Name: "a-0", IP: "10.0.0.10", Account: "acme", Minor: 0x102},
			{Namespace: "kura", Name: "a-1", IP: "10.0.0.11", Minor: 0x102},
		},
		{
			{Namespace: "kura", Name: "a-1", IP: "10.0.0.11", Minor: 0x102},
			{Namespace: "kura", Name: "a-0", IP: "10.0.0.10", Account: "acme", Minor: 0x102},
		},
	} {
		classes, _ := Desired(pods)
		if classes[0x102].Account != "acme" {
			t.Fatalf("account = %q, want acme", classes[0x102].Account)
		}
	}
}

// The controller gives one classid to one account, so a class's pods agree by
// construction; the merge still has to settle on one handle by value rather
// than by arrival order, because pod order is not stable across cycles and a
// flapping label would break the series.
func TestDesiredAccountIsOrderIndependent(t *testing.T) {
	pods := []PodShape{
		{Namespace: "kura", Name: "a-0", IP: "10.0.0.10", Account: "zeta", Minor: 0x102},
		{Namespace: "kura", Name: "b-0", IP: "10.0.0.11", Account: "acme", Minor: 0x102},
		{Namespace: "kura", Name: "c-0", IP: "10.0.0.12", Account: "other", Minor: 0x103},
	}
	classes, _ := Desired(pods)
	if classes[0x102].Account != "acme" {
		t.Fatalf("account = %q, want the lowest handle", classes[0x102].Account)
	}
	reversed := []PodShape{pods[1], pods[0], pods[2]}
	if classesReversed, _ := Desired(reversed); classesReversed[0x102].Account != "acme" {
		t.Fatalf("account = %q under reversed pod order", classesReversed[0x102].Account)
	}
}
