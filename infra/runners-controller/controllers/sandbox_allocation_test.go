package controllers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/go-logr/logr"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func sandboxAllocationClient(t *testing.T) *scaling.Client {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if req.URL.Path == "/" && req.Header.Get("Authorization") == "Bearer test-token" {
			// The pool's demand: a reservation is for a queued job.
			_ = json.NewEncoder(w).Encode(scaling.Signals{Queued: 1})
			return
		}
		if req.URL.Path != "/api/internal/sandboxes/allocation" || req.Header.Get("Authorization") != "Bearer test-token" {
			t.Error("wrong allocation path or authentication")
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	t.Cleanup(server.Close)
	path := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(path, []byte("test-token"), 0600); err != nil {
		t.Fatal(err)
	}
	c := scaling.NewClient(server.URL)
	c.TokenPath = path
	return c
}

func TestSandboxAllocationAccountsForBusyWarmAndOtherPods(t *testing.T) {
	node := linuxNodeWithResources("node-a", "runners-linux", 32, 64*1024)
	pool := linuxFleetPool("small", 1, 8192, 1, 10)
	fleet := &fleetAllocation{members: map[string]fleetMember{pool.Name: {pool: pool}}}
	warm := idleLinuxRunner("warm", pool.Name, node.Name, 8, time.Hour)
	busy := busyLinuxRunner("busy", pool.Name, node.Name, 16)
	other := idleLinuxRunner("other", "unknown", node.Name, 4, time.Hour)
	other.Spec.Overhead = corev1.ResourceList{corev1.ResourceMemory: resource.MustParse("1Gi")}
	daemon := sandboxDaemonPod("daemon", node.Name, 12, 12, false)
	pods := []corev1.Pod{*warm, *busy, *other, *daemon}
	allocation := planSandboxAllocation(node, sandboxDaemon{name: daemon.Name, node: node.Name, memory: 12 * gib}, pods, fleet)
	if allocation.Reclaim || allocation.FreeBytes != 23*gib || allocation.MemoryBytes != 43*gib {
		t.Fatalf("unexpected allocation: %+v", allocation)
	}
	// A second host's capacity is independent, even with the same ceiling.
	otherNode := linuxNodeWithResources("node-b", "runners-linux", 32, 32*1024)
	allocation = planSandboxAllocation(otherNode, sandboxDaemon{name: "daemon-b", node: otherNode.Name, memory: gib}, []corev1.Pod{*sandboxDaemonPod("daemon-b", otherNode.Name, 1, 1, false)}, fleet)
	if allocation.FreeBytes != 31*gib || allocation.MemoryBytes != 32*gib {
		t.Fatalf("unexpected second host: %+v", allocation)
	}
}

func TestSandboxAllocationReportsUnrequestedCPU(t *testing.T) {
	node := linuxNodeWithResources("node-a", "runners-linux", 32, 64*1024)
	pool := linuxFleetPool("small", 1, 8192, 1, 10)
	fleet := &fleetAllocation{members: map[string]fleetMember{pool.Name: {pool: pool}}}
	cpu := func(milli int64) corev1.ResourceList {
		return corev1.ResourceList{corev1.ResourceCPU: *resource.NewMilliQuantity(milli, resource.DecimalSI)}
	}
	// An exclusive-CPU runner budgets at the Pod level, plus its RuntimeClass overhead.
	exclusive := busyLinuxRunner("exclusive", pool.Name, node.Name, 16)
	exclusive.Spec.Resources = &corev1.ResourceRequirements{Requests: cpu(8000)}
	exclusive.Spec.Overhead = cpu(250)
	shared := idleLinuxRunner("shared", pool.Name, node.Name, 2, time.Hour)
	shared.Spec.Containers[0].Resources.Requests[corev1.ResourceCPU] = resource.MustParse("1")
	// The daemon asked to shrink to 500m; until the kubelet applies it,
	// it still holds the 3 cores it had.
	daemon := sandboxDaemonPod("daemon", node.Name, 1, 1, false)
	daemon.Spec.Containers[0].Resources.Requests[corev1.ResourceCPU] = resource.MustParse("500m")
	daemon.Status.ContainerStatuses[0].AllocatedResources[corev1.ResourceCPU] = resource.MustParse("3")
	finished := busyLinuxRunner("finished", pool.Name, node.Name, 4)
	finished.Spec.Containers[0].Resources.Requests[corev1.ResourceCPU] = resource.MustParse("4")
	finished.Status.Phase = corev1.PodSucceeded
	pods := []corev1.Pod{*exclusive, *shared, *daemon, *finished}
	allocation := planSandboxAllocation(node, sandboxDaemon{name: daemon.Name, node: node.Name, memory: gib}, pods, fleet)
	if allocation.CPUFreeMilli != 32000-8250-1000-3000 {
		t.Fatalf("cpu free = %d, want %d", allocation.CPUFreeMilli, 32000-8250-1000-3000)
	}
	// Only the idle warm runner's CPU can be reclaimed.
	if allocation.CPUReclaimableMilli != 1000 {
		t.Fatalf("cpu reclaimable = %d, want the idle runner's 1000m", allocation.CPUReclaimableMilli)
	}

	// A runner retired for the growth keeps counting until it is gone, so
	// the server does not lower the growth and let a replacement take it.
	leaving := idleLinuxRunner("leaving", pool.Name, node.Name, 2, time.Hour)
	leaving.Spec.Containers[0].Resources.Requests[corev1.ResourceCPU] = resource.MustParse("2")
	leaving.DeletionTimestamp = &metav1.Time{Time: preemptionNow}
	leaving.Finalizers = []string{"test"}
	withLeaving := planSandboxAllocation(node, sandboxDaemon{name: daemon.Name, node: node.Name, memory: gib}, []corev1.Pod{*exclusive, *shared, *daemon, *finished, *leaving}, fleet)
	if withLeaving.CPUReclaimableMilli != 3000 || withLeaving.CPUFreeMilli != allocation.CPUFreeMilli-2000 {
		t.Fatalf("with a leaving runner: free %d, reclaimable %d; want %d and 3000", withLeaving.CPUFreeMilli, withLeaving.CPUReclaimableMilli, allocation.CPUFreeMilli-2000)
	}

	// A growth the kubelet deferred counts at what it allocated, so the
	// server can lower a request that stopped fitting.
	daemon.Spec.Containers[0].Resources.Requests[corev1.ResourceCPU] = resource.MustParse("12")
	pods = []corev1.Pod{*exclusive, *shared, *daemon, *finished}
	allocation = planSandboxAllocation(node, sandboxDaemon{name: daemon.Name, node: node.Name, memory: gib}, pods, fleet)
	if allocation.CPUFreeMilli != 32000-8250-1000-3000 {
		t.Fatalf("cpu free with a deferred growth = %d, want %d", allocation.CPUFreeMilli, 32000-8250-1000-3000)
	}
	if got := allocationPodRequest(exclusive, corev1.ResourceMemory); got != 16*gib {
		t.Fatalf("memory of a CPU-only Pod budget = %d, want the containers' 16 GiB", got)
	}
}

func TestSandboxAllocationAllowsQueuedCIButProtectsReservations(t *testing.T) {
	node := linuxNodeWithResources("node-a", "runners-linux", 32, 64*1024)
	daemon := sandboxDaemon{name: "daemon", node: node.Name, memory: gib}
	pool := linuxFleetPool("small", 1, 8192, 1, 10)
	fleet := &fleetAllocation{members: map[string]fleetMember{pool.Name: {pool: pool, queued: 1}}}
	pods := []corev1.Pod{*sandboxDaemonPod("daemon", node.Name, 1, 1, false), *busyLinuxRunner("busy", pool.Name, node.Name, 16)}
	allocation := planSandboxAllocation(node, daemon, pods, fleet)
	if allocation.Reclaim || allocation.FreeBytes != 47*gib || allocation.MemoryBytes != 48*gib {
		t.Fatalf("queued CI must not revoke free capacity or reclaim a busy runner: %+v", allocation)
	}
	node.Spec.Taints = []corev1.Taint{{Key: "tuist.dev/reserved-for", Value: "ci", Effect: corev1.TaintEffectNoSchedule}}
	allocation = planSandboxAllocation(node, daemon, pods, fleet)
	if !allocation.Reclaim || allocation.MemoryBytes != 0 {
		t.Fatalf("reservation must revoke admission: %+v", allocation)
	}
	node.Spec.Taints = nil
	allocation = planSandboxAllocation(node, daemon, pods, nil)
	if !allocation.Reclaim || allocation.MemoryBytes != 0 {
		t.Fatalf("unknown fleet must fail closed: %+v", allocation)
	}
}

func TestAllocationDoesNotSpendPendingPodShrink(t *testing.T) {
	pod := idleLinuxRunner("shrinking", "ci", "node", 4, time.Hour)
	pod.Status.ContainerStatuses = []corev1.ContainerStatus{{Name: pod.Spec.Containers[0].Name, AllocatedResources: corev1.ResourceList{corev1.ResourceMemory: resource.MustParse("8Gi")}, Resources: &corev1.ResourceRequirements{Requests: corev1.ResourceList{corev1.ResourceMemory: resource.MustParse("12Gi")}}}}
	if got := allocationPodMemory(pod); got != 12*gib {
		t.Fatalf("got %d, want applied 12 GiB", got)
	}
	if pod.Spec.Containers[0].Resources.Requests.Memory().Value() != 4*gib {
		t.Fatal("mutated original Pod")
	}
}

func TestSandboxPreemptionStopsWhenFleetUnknown(t *testing.T) {
	pool := linuxFleetPool("small", 1, 8192, 1, 10)
	r, _ := sandboxFixture(t, pool)
	for _, fleet := range []*fleetAllocation{nil} {
		changed, err := r.preemptForSandboxGrowth(context.Background(), pool, fleet, time.Now(), logr.Discard())
		if err != nil || changed {
			t.Fatalf("preempted without CI funding: changed=%v err=%v", changed, err)
		}
	}
}

func TestReservationRevokesBeforeTaintAndFailsClosed(t *testing.T) {
	for _, status := range []int{http.StatusNoContent, http.StatusServiceUnavailable} {
		t.Run(http.StatusText(status), func(t *testing.T) {
			node := linuxNodeWithResources("node-a", "runners-linux", 32, 64*1024)
			_, c := sandboxFixture(t, node, sandboxDaemonPod("daemon", node.Name, 12, 12, false))
			var called atomic.Bool
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				called.Store(true)
				current := &corev1.Node{}
				if err := c.Get(req.Context(), client.ObjectKey{Name: node.Name}, current); err != nil {
					t.Error(err)
				}
				if isReserved(current) {
					t.Error("taint was written before revocation")
				}
				var grant scaling.SandboxAllocation
				if err := json.NewDecoder(req.Body).Decode(&grant); err != nil {
					t.Error(err)
				}
				if !grant.Reclaim || grant.MemoryBytes != 0 || grant.Pod != "daemon" {
					t.Errorf("not a revocation: %+v", grant)
				}
				w.WriteHeader(status)
			}))
			defer server.Close()
			signals := sandboxAllocationClient(t)
			signals.BaseURL = server.URL
			r := &RunnerPoolReconciler{Client: c, APIReader: c, SandboxesNamespace: "tuist-sandboxes", SignalsClient: signals}
			err := r.reserveNode(context.Background(), node, "ci", time.Now())
			if !called.Load() || (err == nil) != (status == http.StatusNoContent) {
				t.Fatalf("called=%v err=%v", called.Load(), err)
			}
			current := &corev1.Node{}
			if err := c.Get(context.Background(), client.ObjectKey{Name: node.Name}, current); err != nil {
				t.Fatal(err)
			}
			if isReserved(current) != (status == http.StatusNoContent) {
				t.Fatal("failed revocation must not reserve a node")
			}
		})
	}
}

// A remote execution worker shares the node with the agent daemon, connects
// to the server under its own name and is revoked like it.
func TestReservationRevokesARemoteExecutionWorkerUnderItsOwnName(t *testing.T) {
	node := linuxNodeWithResources("node-a", "runners-linux", 32, 64*1024)
	worker := sandboxDaemonPod("worker", node.Name, 9, 9, false)
	worker.Labels = map[string]string{executionDaemonLabel: "true"}
	_, c := sandboxFixture(t, node, sandboxDaemonPod("daemon", node.Name, 1, 1, false), worker)
	revoked := map[string]string{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		var grant scaling.SandboxAllocation
		if err := json.NewDecoder(req.Body).Decode(&grant); err != nil {
			t.Error(err)
		}
		if !grant.Reclaim {
			t.Errorf("not a revocation: %+v", grant)
		}
		revoked[grant.Node] = grant.Pod
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()
	signals := sandboxAllocationClient(t)
	signals.BaseURL = server.URL
	r := &RunnerPoolReconciler{Client: c, APIReader: c, SandboxesNamespace: "tuist-sandboxes", SignalsClient: signals}
	if err := r.reserveNode(context.Background(), node, "ci", time.Now()); err != nil {
		t.Fatal(err)
	}
	if len(revoked) != 2 || revoked["node-a"] != "daemon" || revoked["node-a.remote-execution"] != "worker" {
		t.Fatalf("revoked = %v, want the agent daemon as node-a and the worker as node-a.remote-execution", revoked)
	}
	daemons, err := listSandboxDaemons(context.Background(), c, "tuist-sandboxes")
	if err != nil {
		t.Fatal(err)
	}
	// Both carve-outs come off the node's runner seats.
	if available := nodeWithoutSandboxes(node, daemons).Status.Allocatable.Memory().Value(); available != 54*gib {
		t.Fatalf("available = %d GiB, want 54", available/gib)
	}
}

func TestSandboxGrowthRetiresOnlyIdleRunnersEvenWithQueuedCI(t *testing.T) {
	pool := linuxFleetPool("small", 2, 8192, 0, 10)
	r, c := sandboxFixture(t, pool, linuxNode("node-a", 64),
		sandboxDaemonPod("daemon", "node-a", 16, 8, true),
		busyLinuxRunner("busy", pool.Name, "node-a", 8),
		idleLinuxRunner("idle", pool.Name, "node-a", 8, time.Hour))
	fleet := &fleetAllocation{members: map[string]fleetMember{pool.Name: {pool: pool, queued: 1}}}
	changed, err := r.preemptForSandboxGrowth(context.Background(), pool, fleet, time.Now(), logr.Discard())
	if err != nil || !changed {
		t.Fatalf("queued CI blocked sandbox growth: changed=%v err=%v", changed, err)
	}
	marked := markedPods(t, c, pool.Name)
	if len(marked) != 1 || marked[0] != "idle=sandboxes" {
		t.Fatalf("unexpected victims: %v", marked)
	}
}

// Each grant on a host running both carve-outs says what it counted the
// other at, so the server can take the other's later growth off it; a host
// with only the agent daemon sends none.
func TestSandboxAllocationsCountTheHostsOtherCarveOut(t *testing.T) {
	pool := linuxFleetPool("small", 1, 8192, 1, 10)
	shared := linuxNodeWithResources("node-a", "runners-linux", 32, 64*1024)
	alone := linuxNodeWithResources("node-b", "runners-linux", 32, 64*1024)
	worker := sandboxDaemonPod("worker", shared.Name, 9, 9, false)
	worker.Labels = map[string]string{executionDaemonLabel: "true"}
	r, _ := sandboxFixture(t, pool, shared, alone, sandboxDaemonPod("daemon", shared.Name, 3, 2, false), worker, sandboxDaemonPod("daemon-b", alone.Name, 1, 1, false))
	grants := map[string]scaling.SandboxAllocation{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		var grant scaling.SandboxAllocation
		if err := json.NewDecoder(req.Body).Decode(&grant); err != nil {
			t.Error(err)
		}
		grants[grant.Node] = grant
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()
	r.SignalsClient = sandboxAllocationClient(t)
	r.SignalsClient.BaseURL = server.URL
	r.SandboxesNamespace = "tuist-sandboxes"
	fleet := &fleetAllocation{members: map[string]fleetMember{pool.Name: {pool: pool}}}
	if err := r.publishSandboxAllocations(context.Background(), pool, fleet); err != nil {
		t.Fatal(err)
	}
	sibling := func(name string) int64 {
		grant, ok := grants[name]
		if !ok {
			t.Fatalf("no grant for %s: %v", name, grants)
		}
		if grant.SiblingMemoryBytes == nil {
			return -1
		}
		return *grant.SiblingMemoryBytes
	}
	if got := sibling("node-a"); got != 9*gib {
		t.Fatalf("agent daemon's grant counted the worker at %d, want 9 GiB", got)
	}
	if got := sibling("node-a.remote-execution"); got != 3*gib {
		t.Fatalf("worker's grant counted the agent daemon at %d, want its 3 GiB request", got)
	}
	if got := sibling("node-b"); got != -1 {
		t.Fatalf("a host with one carve-out sent sibling memory %d", got)
	}
}
