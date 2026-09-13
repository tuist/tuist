package agent

import (
	"encoding/json"
	"testing"
)

// Captured from `tc -s -j class show dev kura-egress0` on a shaped node. HTB
// prints its xstats (lended/borrowed/giants/tokens) into the same JSON object
// as the generic stats rather than beside it, so a struct that nests them one
// level out parses zeros forever without failing — hence a real payload.
const tcClassPayload = `[
  {"class":"htb","handle":"1:1","root":true,"rate":125000000,"ceil":125000000,
   "stats":{"bytes":1106874188,"packets":4654623,"drops":0,"overlimits":187224,"requeues":0,
            "backlog":0,"qlen":0,"lended":133607,"borrowed":0,"giants":0,"tokens":193,"ctokens":193}},
  {"class":"htb","handle":"1:2d03","parent":"1:1","leaf":"0x8428","prio":0,"rate":25000000,"ceil":37500000,
   "stats":{"bytes":1106834188,"packets":4654308,"drops":7,"overlimits":263561,"requeues":0,
            "backlog":4096,"qlen":0,"lended":4263735,"borrowed":133607,"giants":0,"tokens":966,"ctokens":644}},
  {"class":"fq_codel","handle":"8428:2bf","parent":"8428:",
   "stats":{"drops":0,"overlimits":0,"requeues":0,"backlog":0,"qlen":0,"deficit":65495}}
]`

func TestTCClassParsesHTBStats(t *testing.T) {
	var classes []tcClass
	if err := json.Unmarshal([]byte(tcClassPayload), &classes); err != nil {
		t.Fatal(err)
	}
	if len(classes) != 3 {
		t.Fatalf("classes = %d, want 3", len(classes))
	}

	tenant := classes[1]
	minor, ok := tenant.minor()
	if !ok || minor != 0x2d03 {
		t.Fatalf("minor = %x (ok=%v), want 2d03", minor, ok)
	}
	if tenant.Stats.Bytes != 1106834188 || tenant.Stats.Drops != 7 || tenant.Stats.Backlog != 4096 {
		t.Fatalf("generic stats = %+v", tenant.Stats)
	}
	if tenant.Stats.Lended != 4263735 || tenant.Stats.Borrowed != 133607 {
		t.Fatalf("lended/borrowed = %d/%d, want 4263735/133607", tenant.Stats.Lended, tenant.Stats.Borrowed)
	}
	// Bytes per second, the unit tc reports and the one rate(sent_bytes)
	// is compared against.
	if tenant.Rate != 25000000 || tenant.Ceil != 37500000 {
		t.Fatalf("rate/ceil = %d/%d, want 25000000/37500000", tenant.Rate, tenant.Ceil)
	}

	// The root class is reported as such so Stats can skip it, and a leaf
	// qdisc entry is not a class at all.
	if minor, ok := classes[0].minor(); !ok || minor != rootClassMinor {
		t.Fatalf("root minor = %x (ok=%v)", minor, ok)
	}
	if _, ok := classes[2].minor(); ok {
		t.Fatal("fq_codel leaf reported as an htb class")
	}
}
