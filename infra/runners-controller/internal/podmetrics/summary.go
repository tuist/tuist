// Package podmetrics samples per-Pod machine metrics (CPU, memory,
// network, disk) for running runner Pods and ships them to the Tuist
// server's `/api/internal/runners/pods/:pod_name/metrics` endpoint.
//
// The samples power the runner-job Metrics tab in the dashboard. They
// have no GitHub-side source — they describe the runner Pod/VM, which
// only our infrastructure can observe — so the controller is the
// authoritative producer, the same role it already plays for Pod
// lifecycle (`pods/stopped`).
//
// Source of truth is the kubelet's Summary API
// (`/stats/summary`), reached through the apiserver node proxy. One
// call per node returns cAdvisor-derived stats for every Pod on that
// node, so a tick scrapes each node once regardless of how many runner
// Pods it hosts.
package podmetrics

import (
	"context"
	"encoding/json"
	"fmt"

	"k8s.io/client-go/kubernetes"
)

// Summary is the subset of the kubelet `/stats/summary` payload we
// consume. The full schema is large and versioned; decoding only the
// fields we read keeps us decoupled from the parts we don't.
type Summary struct {
	Pods []PodStats `json:"pods"`
}

// PodStats is one Pod's slice of a node's Summary. Pointers distinguish
// "kubelet reported 0" from "field absent", so a missing counter maps
// to a 0 sample rather than a bogus delta.
type PodStats struct {
	PodRef           PodReference  `json:"podRef"`
	CPU              *CPUStats     `json:"cpu"`
	Memory           *MemoryStats  `json:"memory"`
	Network          *NetworkStats `json:"network"`
	EphemeralStorage *FsStats      `json:"ephemeral-storage"`
}

type PodReference struct {
	Name      string `json:"name"`
	Namespace string `json:"namespace"`
}

type CPUStats struct {
	// UsageNanoCores is the kubelet's instantaneous CPU rate over its
	// own window (nanocores; 1e9 == one core fully busy), so we don't
	// need to difference cumulative counters ourselves.
	UsageNanoCores *uint64 `json:"usageNanoCores"`
}

type MemoryStats struct {
	WorkingSetBytes *uint64 `json:"workingSetBytes"`
}

// NetworkStats counters are cumulative since the Pod's network
// namespace came up; the sampler differences consecutive samples into
// per-interval throughput.
type NetworkStats struct {
	RxBytes *uint64 `json:"rxBytes"`
	TxBytes *uint64 `json:"txBytes"`
}

type FsStats struct {
	UsedBytes     *uint64 `json:"usedBytes"`
	CapacityBytes *uint64 `json:"capacityBytes"`
}

// pod returns the stats for podName and whether the node reported them.
func (s *Summary) pod(podName string) (PodStats, bool) {
	for i := range s.Pods {
		if s.Pods[i].PodRef.Name == podName {
			return s.Pods[i], true
		}
	}
	return PodStats{}, false
}

// SummarySource fetches a node's kubelet Summary. The sampler depends
// on this interface so tests can inject a fake without an apiserver.
type SummarySource interface {
	NodeSummary(ctx context.Context, nodeName string) (*Summary, error)
}

// KubeletSource reads `/stats/summary` from a node's kubelet via the
// apiserver node proxy (`GET /api/v1/nodes/<node>/proxy/stats/summary`),
// which requires the `nodes/proxy` RBAC verb. Proxying through the
// apiserver reuses its kubelet auth rather than dialing kubelets
// directly.
type KubeletSource struct {
	Clientset kubernetes.Interface
}

func (k *KubeletSource) NodeSummary(ctx context.Context, nodeName string) (*Summary, error) {
	raw, err := k.Clientset.CoreV1().RESTClient().
		Get().
		Resource("nodes").
		Name(nodeName).
		SubResource("proxy").
		Suffix("stats", "summary").
		DoRaw(ctx)
	if err != nil {
		return nil, fmt.Errorf("podmetrics: fetch node %q summary: %w", nodeName, err)
	}

	var summary Summary
	if err := json.Unmarshal(raw, &summary); err != nil {
		return nil, fmt.Errorf("podmetrics: decode node %q summary: %w", nodeName, err)
	}
	return &summary, nil
}
