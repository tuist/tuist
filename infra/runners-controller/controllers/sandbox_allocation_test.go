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
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func sandboxAllocationClient(t *testing.T) *scaling.Client {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
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
