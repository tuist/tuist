package podmetrics

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

type fakeSource struct {
	byNode map[string]*Summary
}

func (f *fakeSource) NodeSummary(_ context.Context, nodeName string) (*Summary, error) {
	if s, ok := f.byNode[nodeName]; ok {
		return s, nil
	}
	return nil, fmt.Errorf("no summary for node %q", nodeName)
}

type reportCall struct {
	pod     string
	samples []Sample
}

type fakeReporter struct {
	calls []reportCall
}

func (f *fakeReporter) Report(_ context.Context, podName string, samples []Sample) error {
	f.calls = append(f.calls, reportCall{pod: podName, samples: samples})
	return nil
}

func u64(v uint64) *uint64 { return &v }

func runnerPod(name, node, owner string, phase corev1.PodPhase) *corev1.Pod {
	labels := map[string]string{runnerLabel: "true"}
	if owner != "" {
		labels[ownerLabel] = owner
	}
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist-runners", Labels: labels},
		Spec:       corev1.PodSpec{NodeName: node},
		Status:     corev1.PodStatus{Phase: phase},
	}
}

func testNode(name, cpu, mem string) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: name},
		Status: corev1.NodeStatus{
			Allocatable: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse(cpu),
				corev1.ResourceMemory: resource.MustParse(mem),
			},
		},
	}
}

func newSampler(t *testing.T, src SummarySource, rep reporter, objs ...client.Object) *Sampler {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatalf("add corev1 to scheme: %v", err)
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	return &Sampler{
		Client:    c,
		Source:    src,
		Reporter:  rep,
		Namespace: "tuist-runners",
		Now:       func() time.Time { return time.Unix(1_750_000_000, 0) },
	}
}

func TestSampler_ReportsOnlyBusyRunningPods(t *testing.T) {
	src := &fakeSource{byNode: map[string]*Summary{
		"node-a": {Pods: []PodStats{{
			PodRef:           PodReference{Name: "busy-1", Namespace: "tuist-runners"},
			CPU:              &CPUStats{UsageNanoCores: u64(2_000_000_000)},
			Memory:           &MemoryStats{WorkingSetBytes: u64(1 << 30)},
			Network:          &NetworkStats{RxBytes: u64(1000), TxBytes: u64(500)},
			EphemeralStorage: &FsStats{UsedBytes: u64(10 << 30), CapacityBytes: u64(100 << 30)},
		}}},
	}}
	rep := &fakeReporter{}
	s := newSampler(t, src, rep,
		runnerPod("busy-1", "node-a", "42", corev1.PodRunning),
		runnerPod("idle-1", "node-a", "", corev1.PodRunning), // no owner -> skipped
		runnerPod("pending-1", "", "42", corev1.PodPending),  // not running -> skipped
		testNode("node-a", "4", "8Gi"),
	)

	s.sampleOnce(context.Background(), logr.Discard())

	if len(rep.calls) != 1 {
		t.Fatalf("report calls = %d, want 1 (busy-1 only): %+v", len(rep.calls), rep.calls)
	}
	call := rep.calls[0]
	if call.pod != "busy-1" {
		t.Fatalf("reported pod = %q, want busy-1", call.pod)
	}
	got := call.samples[0]
	if got.CPUUsagePercent != 50 {
		t.Errorf("cpu percent = %v, want 50 (2 of 4 cores)", got.CPUUsagePercent)
	}
	if got.MemoryUsedBytes != 1<<30 || got.MemoryTotalBytes != 8<<30 {
		t.Errorf("memory used/total = %d/%d", got.MemoryUsedBytes, got.MemoryTotalBytes)
	}
	if got.DiskUsedBytes != 10<<30 || got.DiskTotalBytes != 100<<30 {
		t.Errorf("disk used/total = %d/%d", got.DiskUsedBytes, got.DiskTotalBytes)
	}
	if got.NetworkBytesIn != 0 || got.NetworkBytesOut != 0 {
		t.Errorf("first-pass network = %d/%d, want 0/0 (no baseline yet)", got.NetworkBytesIn, got.NetworkBytesOut)
	}
}

func TestSampler_NetworkDeltaAcrossPasses(t *testing.T) {
	pod := PodStats{
		PodRef:  PodReference{Name: "busy-1", Namespace: "tuist-runners"},
		CPU:     &CPUStats{UsageNanoCores: u64(1_000_000_000)},
		Network: &NetworkStats{RxBytes: u64(1000), TxBytes: u64(500)},
	}
	src := &fakeSource{byNode: map[string]*Summary{"node-a": {Pods: []PodStats{pod}}}}
	rep := &fakeReporter{}
	s := newSampler(t, src, rep,
		runnerPod("busy-1", "node-a", "42", corev1.PodRunning),
		testNode("node-a", "4", "8Gi"),
	)

	s.sampleOnce(context.Background(), logr.Discard())

	// Second pass: counters advanced by 2000 rx / 1000 tx.
	src.byNode["node-a"].Pods[0].Network = &NetworkStats{RxBytes: u64(3000), TxBytes: u64(1500)}
	s.sampleOnce(context.Background(), logr.Discard())

	if len(rep.calls) != 2 {
		t.Fatalf("report calls = %d, want 2", len(rep.calls))
	}
	got := rep.calls[1].samples[0]
	if got.NetworkBytesIn != 2000 || got.NetworkBytesOut != 1000 {
		t.Errorf("delta network = %d/%d, want 2000/1000", got.NetworkBytesIn, got.NetworkBytesOut)
	}
}

func TestSampler_MatchesPodNamespace(t *testing.T) {
	// The node also hosts a same-named Pod in another namespace; the
	// sampler must report the runner namespace's Pod, not that one.
	src := &fakeSource{byNode: map[string]*Summary{
		"node-a": {Pods: []PodStats{
			{
				PodRef: PodReference{Name: "busy-1", Namespace: "other-namespace"},
				CPU:    &CPUStats{UsageNanoCores: u64(4_000_000_000)},
			},
			{
				PodRef:  PodReference{Name: "busy-1", Namespace: "tuist-runners"},
				CPU:     &CPUStats{UsageNanoCores: u64(1_000_000_000)},
				Network: &NetworkStats{RxBytes: u64(0), TxBytes: u64(0)},
			},
		}},
	}}
	rep := &fakeReporter{}
	s := newSampler(t, src, rep,
		runnerPod("busy-1", "node-a", "42", corev1.PodRunning),
		testNode("node-a", "4", "8Gi"),
	)

	s.sampleOnce(context.Background(), logr.Discard())

	if len(rep.calls) != 1 {
		t.Fatalf("report calls = %d, want 1", len(rep.calls))
	}
	// 1 of 4 cores from the tuist-runners Pod (25%), not 4 of 4 (100%)
	// from the foreign namespace's Pod.
	if got := rep.calls[0].samples[0].CPUUsagePercent; got != 25 {
		t.Errorf("cpu percent = %v, want 25 (matched the wrong namespace?)", got)
	}
}

func TestSampler_SeedsIdleBaselineForFirstBusyInterval(t *testing.T) {
	// A Pod is idle (no owner label) for one pass, then claimed. Its
	// first busy sample must report the network delta since the idle
	// pass, not 0 — otherwise the job's opening spike is lost.
	pod := PodStats{
		PodRef:  PodReference{Name: "runner-1", Namespace: "tuist-runners"},
		Network: &NetworkStats{RxBytes: u64(1000), TxBytes: u64(500)},
	}
	src := &fakeSource{byNode: map[string]*Summary{"node-a": {Pods: []PodStats{pod}}}}
	rep := &fakeReporter{}
	s := newSampler(t, src, rep,
		runnerPod("runner-1", "node-a", "", corev1.PodRunning), // idle: no owner
		testNode("node-a", "4", "8Gi"),
	)

	s.sampleOnce(context.Background(), logr.Discard())
	if len(rep.calls) != 0 {
		t.Fatalf("idle Pod was reported (%d calls); want 0", len(rep.calls))
	}
	if _, ok := s.prev["runner-1"]; !ok {
		t.Fatal("idle Pod's network baseline was not seeded")
	}

	// Pod gets claimed and traffic advances by 5000 rx / 2000 tx.
	var busy corev1.Pod
	if err := s.Client.Get(context.Background(), client.ObjectKey{Namespace: "tuist-runners", Name: "runner-1"}, &busy); err != nil {
		t.Fatalf("get pod: %v", err)
	}
	busy.Labels[ownerLabel] = "42"
	if err := s.Client.Update(context.Background(), &busy); err != nil {
		t.Fatalf("update pod to busy: %v", err)
	}
	src.byNode["node-a"].Pods[0].Network = &NetworkStats{RxBytes: u64(6000), TxBytes: u64(2500)}
	s.sampleOnce(context.Background(), logr.Discard())

	if len(rep.calls) != 1 {
		t.Fatalf("report calls = %d, want 1 (first busy pass)", len(rep.calls))
	}
	got := rep.calls[0].samples[0]
	if got.NetworkBytesIn != 5000 || got.NetworkBytesOut != 2000 {
		t.Errorf("first busy network = %d/%d, want 5000/2000 from the idle baseline", got.NetworkBytesIn, got.NetworkBytesOut)
	}
}

func TestSampler_PrunesStalePods(t *testing.T) {
	src := &fakeSource{byNode: map[string]*Summary{
		"node-a": {Pods: []PodStats{{
			PodRef:  PodReference{Name: "busy-1", Namespace: "tuist-runners"},
			Network: &NetworkStats{RxBytes: u64(1000), TxBytes: u64(500)},
		}}},
	}}
	s := newSampler(t, src, &fakeReporter{},
		runnerPod("busy-1", "node-a", "42", corev1.PodRunning),
		testNode("node-a", "4", "8Gi"),
	)

	s.sampleOnce(context.Background(), logr.Discard())
	if _, ok := s.prev["busy-1"]; !ok {
		t.Fatal("expected busy-1 network baseline retained")
	}

	// Pod gone from the cluster: its delta state should be pruned.
	if err := s.Client.Delete(context.Background(), runnerPod("busy-1", "node-a", "42", corev1.PodRunning)); err != nil {
		t.Fatalf("delete pod: %v", err)
	}
	s.sampleOnce(context.Background(), logr.Discard())
	if _, ok := s.prev["busy-1"]; ok {
		t.Error("expected busy-1 pruned from delta state after it stopped running")
	}
}
