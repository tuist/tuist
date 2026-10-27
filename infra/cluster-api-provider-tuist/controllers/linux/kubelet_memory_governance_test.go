package linux

import (
	"testing"

	"sigs.k8s.io/yaml"
)

// The rendered config is written straight to /var/lib/kubelet/config.yaml and
// the kubelet is restarted. A malformed document does not degrade anything — it
// stops the kubelet from starting, on every node of all three Linux fleets at
// once, because the drift loop fingerprints this same content. Parsing it here
// is the cheapest guard against that.
//
// This checks shape and values, not field names against the kubelet's schema
// (k8s.io/kubelet is not a dependency), so a typo'd key would still slip
// through as an ignored field.
func TestKubeletConfigContentParses(t *testing.T) {
	var parsed map[string]any
	if err := yaml.Unmarshal([]byte(kubeletConfigContent("10.96.0.10", kubeletClientCAPath)), &parsed); err != nil {
		t.Fatalf("rendered kubelet config is not valid YAML: %v", err)
	}

	if got := parsed["clusterDomain"]; got != "cluster.local" {
		t.Fatalf("clusterDomain = %v, want cluster.local", got)
	}
	if got := parsed["clusterDNS"]; got == nil {
		t.Fatal("clusterDNS must survive rendering; a node without it falls back to host DNS")
	}
}

// memory.high is derived as requests + factor*(limits-requests) and triggers on
// memory.current, which counts clean page cache. A Kura node holds clean
// artifact pages at its hard watermark as normal steady state, so any factor
// below 1.0 makes the kernel throttle a healthy cache node into reclaiming the
// cache it exists to hold — fighting the runtime's own shedding, which keys off
// pressure_bytes precisely to exclude those pages. 1.0 pins memory.high to the
// limit, keeping the memory.min/memory.low protection without early throttling.
func TestKubeletConfigDisablesEarlyMemoryThrottling(t *testing.T) {
	var parsed struct {
		FeatureGates           map[string]bool   `json:"featureGates"`
		MemoryThrottlingFactor *float64          `json:"memoryThrottlingFactor"`
		EvictionHard           map[string]string `json:"evictionHard"`
		SystemReserved         map[string]string `json:"systemReserved"`
		KubeReserved           map[string]string `json:"kubeReserved"`
	}
	if err := yaml.Unmarshal([]byte(kubeletConfigContent("", kubeletClientCAPath)), &parsed); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if !parsed.FeatureGates["MemoryQoS"] {
		t.Fatal("MemoryQoS must be on, or a Pod's request never reaches the kernel and the memory floor stays advisory")
	}
	if parsed.MemoryThrottlingFactor == nil {
		t.Fatal("memoryThrottlingFactor must be set explicitly; the 0.9 default throttles on page cache")
	}
	if *parsed.MemoryThrottlingFactor != 1.0 {
		t.Fatalf("memoryThrottlingFactor = %v, want 1.0", *parsed.MemoryThrottlingFactor)
	}

	// Daemons outside any Pod need to come off allocatable before MemoryQoS
	// turns requests into kernel-protected memory, or the scheduler can promise
	// Pods the whole box and the protection squeezes the kubelet itself.
	for name, reserved := range map[string]map[string]string{"systemReserved": parsed.SystemReserved, "kubeReserved": parsed.KubeReserved} {
		if reserved["memory"] == "" {
			t.Fatalf("%s must reserve memory so allocatable is not the whole box", name)
		}
	}
}

// evictionHard replaces the kubelet's defaults wholesale instead of merging, so
// omitting a signal silently disables eviction for it. Restating the disk
// signals is what keeps raising the memory threshold from turning disk pressure
// into an unhandled condition.
func TestKubeletConfigEvictionHardCoversEverySignal(t *testing.T) {
	var parsed struct {
		EvictionHard map[string]string `json:"evictionHard"`
	}
	if err := yaml.Unmarshal([]byte(kubeletConfigContent("", kubeletClientCAPath)), &parsed); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	// Every signal in the kubelet's Linux defaults (DefaultEvictionHard). A
	// signal missing here is disabled on the node, not defaulted.
	for _, signal := range []string{
		"memory.available",
		"nodefs.available",
		"nodefs.inodesFree",
		"imagefs.available",
		"imagefs.inodesFree",
	} {
		if parsed.EvictionHard[signal] == "" {
			t.Fatalf("evictionHard is missing %q; it replaces the defaults rather than merging with them", signal)
		}
	}

	// The kubelet default is 100Mi, thin enough on these boxes that the OOM
	// killer beats the eviction manager and contention becomes a SIGKILL
	// mid-transfer rather than an evicted Pod with an event.
	if got := parsed.EvictionHard["memory.available"]; got == "100Mi" {
		t.Fatalf("memory.available = %q, which is the default that leaves no managed-eviction margin", got)
	}
}
