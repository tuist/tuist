package podmetrics

import (
	"encoding/json"
	"testing"
)

// A trimmed real-shaped kubelet /stats/summary payload, asserting the
// field tags we depend on (notably "ephemeral-storage" and the
// nano-cores / working-set names) decode.
const sampleSummaryJSON = `{
  "node": {"nodeName": "node-a"},
  "pods": [
    {
      "podRef": {"name": "busy-1", "namespace": "tuist-runners"},
      "cpu": {"usageNanoCores": 2000000000},
      "memory": {"workingSetBytes": 1073741824},
      "network": {"rxBytes": 1000, "txBytes": 500},
      "ephemeral-storage": {"usedBytes": 10737418240, "capacityBytes": 107374182400}
    }
  ]
}`

func TestSummaryUnmarshalAndLookup(t *testing.T) {
	var s Summary
	if err := json.Unmarshal([]byte(sampleSummaryJSON), &s); err != nil {
		t.Fatalf("decode: %v", err)
	}

	stats, ok := s.pod("tuist-runners", "busy-1")
	if !ok {
		t.Fatal("busy-1 not found in summary")
	}
	if stats.CPU == nil || stats.CPU.UsageNanoCores == nil || *stats.CPU.UsageNanoCores != 2_000_000_000 {
		t.Errorf("cpu usageNanoCores not decoded: %+v", stats.CPU)
	}
	if stats.Memory == nil || *stats.Memory.WorkingSetBytes != 1<<30 {
		t.Errorf("memory workingSetBytes not decoded: %+v", stats.Memory)
	}
	if stats.EphemeralStorage == nil || *stats.EphemeralStorage.CapacityBytes != 100<<30 {
		t.Errorf("ephemeral-storage not decoded: %+v", stats.EphemeralStorage)
	}
	if _, ok := s.pod("tuist-runners", "missing"); ok {
		t.Error("unexpected hit for a pod not in the summary")
	}
	if _, ok := s.pod("other-namespace", "busy-1"); ok {
		t.Error("matched busy-1 in the wrong namespace; names are only namespace-unique")
	}
}
