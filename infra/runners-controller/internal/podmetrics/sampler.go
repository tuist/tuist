package podmetrics

import (
	"context"
	"time"

	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

const (
	// runnerLabel marks every runner Pod the controller creates.
	runnerLabel = "tuist.dev/runner"
	// ownerLabel is stamped by the server when a Pod claims a job; its
	// presence means the Pod is busy running a job. Sampling only
	// owner-stamped Pods skips idle warm-pool Pods (which the server
	// would no-op anyway) and the wasted HTTP calls for them.
	ownerLabel = "tuist.dev/runner-pool-owner"
)

// reporter ships a Pod's samples to the server. Satisfied by *Client;
// an interface so the sampler is testable without HTTP.
type reporter interface {
	Report(ctx context.Context, podName string, samples []Sample) error
}

// Sampler periodically reads each busy runner Pod's machine metrics
// from its node's kubelet Summary and reports them to the Tuist
// server. It is a leader-only manager.Runnable: a single replica
// samples so multiple controller replicas don't double-report.
type Sampler struct {
	// Client is the cached controller-runtime client, used to list
	// runner Pods and read node allocatable capacity.
	Client client.Client
	// Source fetches per-node kubelet Summaries.
	Source SummarySource
	// Reporter POSTs sample batches to the server.
	Reporter reporter

	// Namespace bounds the Pod list to the runners namespace.
	Namespace string
	// Interval between sampling passes.
	Interval time.Duration
	// Now defaults to time.Now; overridable in tests.
	Now func() time.Time

	// prev holds the last cumulative network counters per Pod so we
	// can difference them into per-interval throughput. Accessed only
	// from the single Start goroutine, so no locking is needed.
	prev map[string]netCounters
}

type netCounters struct {
	rxBytes uint64
	txBytes uint64
}

// NeedLeaderElection makes the manager run the sampler on the elected
// leader only.
func (s *Sampler) NeedLeaderElection() bool { return true }

// Start runs the sampling loop until ctx is cancelled, satisfying
// manager.Runnable.
func (s *Sampler) Start(ctx context.Context) error {
	if s.prev == nil {
		s.prev = map[string]netCounters{}
	}
	logger := log.FromContext(ctx).WithName("pod-metrics")
	logger.Info("starting runner Pod metrics sampler", "interval", s.Interval)

	ticker := time.NewTicker(s.Interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			s.sampleOnce(ctx, logger)
		}
	}
}

func (s *Sampler) sampleOnce(ctx context.Context, logger logr.Logger) {
	if s.prev == nil {
		s.prev = map[string]netCounters{}
	}

	var pods corev1.PodList
	if err := s.Client.List(ctx, &pods,
		client.InNamespace(s.Namespace),
		client.MatchingLabels{runnerLabel: "true"},
	); err != nil {
		logger.Error(err, "list runner Pods")
		return
	}

	// Group busy, running Pods by node so each node's kubelet is
	// scraped once regardless of how many Pods it hosts.
	byNode := map[string][]string{}
	live := map[string]struct{}{}
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Status.Phase != corev1.PodRunning || pod.Spec.NodeName == "" {
			continue
		}
		if pod.Labels[ownerLabel] == "" {
			continue
		}
		byNode[pod.Spec.NodeName] = append(byNode[pod.Spec.NodeName], pod.Name)
		live[pod.Name] = struct{}{}
	}

	now := s.now()
	for nodeName, podNames := range byNode {
		summary, err := s.Source.NodeSummary(ctx, nodeName)
		if err != nil {
			logger.Error(err, "fetch node summary", "node", nodeName)
			continue
		}
		cpuCores, memBytes := s.nodeCapacity(ctx, nodeName, logger)

		for _, podName := range podNames {
			stats, ok := summary.pod(podName)
			if !ok {
				continue
			}
			sample := s.buildSample(podName, stats, cpuCores, memBytes, now)
			if err := s.Reporter.Report(ctx, podName, []Sample{sample}); err != nil {
				logger.Error(err, "report Pod metrics", "pod", podName)
			}
		}
	}

	// Drop delta state for Pods that are no longer running so the map
	// stays bounded and a recycled Pod name starts fresh.
	for name := range s.prev {
		if _, ok := live[name]; !ok {
			delete(s.prev, name)
		}
	}
}

// buildSample converts a Pod's kubelet stats into a server-shaped
// sample, differencing the cumulative network counters against the
// previous pass and expressing CPU as a percentage of the node's
// allocatable cores.
func (s *Sampler) buildSample(podName string, stats PodStats, cpuCores float64, memBytes int64, now time.Time) Sample {
	sample := Sample{Timestamp: float64(now.UnixNano()) / 1e9}

	if stats.CPU != nil && stats.CPU.UsageNanoCores != nil && cpuCores > 0 {
		percent := float64(*stats.CPU.UsageNanoCores) / (cpuCores * 1e9) * 100
		sample.CPUUsagePercent = clampPercent(percent)
	}

	if stats.Memory != nil && stats.Memory.WorkingSetBytes != nil {
		sample.MemoryUsedBytes = int64(*stats.Memory.WorkingSetBytes)
	}
	sample.MemoryTotalBytes = memBytes

	if stats.EphemeralStorage != nil {
		if stats.EphemeralStorage.UsedBytes != nil {
			sample.DiskUsedBytes = int64(*stats.EphemeralStorage.UsedBytes)
		}
		if stats.EphemeralStorage.CapacityBytes != nil {
			sample.DiskTotalBytes = int64(*stats.EphemeralStorage.CapacityBytes)
		}
	}

	sample.NetworkBytesIn, sample.NetworkBytesOut = s.networkDelta(podName, stats.Network)

	return sample
}

// networkDelta differences the Pod's cumulative rx/tx counters against
// the previous pass into per-interval bytes. The first sample for a
// Pod (or one after a counter reset) reports 0 and seeds the baseline.
func (s *Sampler) networkDelta(podName string, network *NetworkStats) (int64, int64) {
	if network == nil || network.RxBytes == nil || network.TxBytes == nil {
		return 0, 0
	}
	rx, tx := *network.RxBytes, *network.TxBytes

	prev, seen := s.prev[podName]
	s.prev[podName] = netCounters{rxBytes: rx, txBytes: tx}
	if !seen {
		return 0, 0
	}
	return deltaBytes(rx, prev.rxBytes), deltaBytes(tx, prev.txBytes)
}

// nodeCapacity returns the node's allocatable CPU (cores) and memory
// (bytes), used as the denominators for CPU percentage and the memory
// total. A missing node (transient cache miss) yields 0s, which map to
// a 0-percent / 0-total sample rather than failing the pass.
func (s *Sampler) nodeCapacity(ctx context.Context, nodeName string, logger logr.Logger) (float64, int64) {
	var node corev1.Node
	if err := s.Client.Get(ctx, types.NamespacedName{Name: nodeName}, &node); err != nil {
		logger.Error(err, "get node allocatable", "node", nodeName)
		return 0, 0
	}
	cpu := node.Status.Allocatable.Cpu().AsApproximateFloat64()
	mem := node.Status.Allocatable.Memory().Value()
	return cpu, mem
}

func (s *Sampler) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

func clampPercent(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 100 {
		return 100
	}
	return v
}

// deltaBytes returns cur-prev, treating a counter reset (cur < prev,
// e.g. the Pod's network namespace was recreated) as 0 rather than a
// huge negative spike.
func deltaBytes(cur, prev uint64) int64 {
	if cur < prev {
		return 0
	}
	return int64(cur - prev)
}
