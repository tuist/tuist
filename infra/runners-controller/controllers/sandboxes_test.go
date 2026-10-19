package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sort"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

const gib = int64(1024 * 1024 * 1024)

// sandboxDaemonPod is a sandboxd Pod asking for `askedGiB`, of which the
// kubelet has allocated `allocatedGiB`; a growth it deferred carries the
// PodResizePending condition.
func sandboxDaemonPod(name, node string, askedGiB, allocatedGiB int64, deferred bool) *corev1.Pod {
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist-sandboxes", Labels: map[string]string{sandboxdLabel: "true"}},
		Spec: corev1.PodSpec{
			NodeName: node,
			Containers: []corev1.Container{{
				Name: sandboxdContainer,
				Resources: corev1.ResourceRequirements{
					Requests: corev1.ResourceList{corev1.ResourceMemory: *resource.NewQuantity(askedGiB*gib, resource.BinarySI)},
				},
			}},
		},
		Status: corev1.PodStatus{
			Phase: corev1.PodRunning,
			ContainerStatuses: []corev1.ContainerStatus{{
				Name:               sandboxdContainer,
				AllocatedResources: corev1.ResourceList{corev1.ResourceMemory: *resource.NewQuantity(allocatedGiB*gib, resource.BinarySI)},
			}},
		},
	}
	if deferred {
		pod.Status.Conditions = []corev1.PodCondition{{
			Type:   podResizePendingType,
			Status: corev1.ConditionTrue,
			Reason: podResizeDeferredReason,
		}}
	}
	return pod
}

// idleLinuxRunner is a warm Linux runner whose poller started `warmFor`
// ago, holding `memGiB` on `node`.
func idleLinuxRunner(name, pool, node string, memGiB int64, warmFor time.Duration) *corev1.Pod {
	pod := newRunnerPod(name, "ghcr.io/tuist/tuist-linux-runner:test", corev1.PodPending, pool)
	pod.Spec.NodeName = node
	pod.Spec.Containers[0].Resources.Requests = corev1.ResourceList{corev1.ResourceMemory: *resource.NewQuantity(memGiB*gib, resource.BinarySI)}
	pod.Status.InitContainerStatuses = []corev1.ContainerStatus{{
		Name:  "poller",
		State: corev1.ContainerState{Running: &corev1.ContainerStateRunning{StartedAt: metav1.NewTime(preemptionNow.Add(-warmFor))}},
	}}
	return pod
}

func busyLinuxRunner(name, pool, node string, memGiB int64) *corev1.Pod {
	pod := idleLinuxRunner(name, pool, node, memGiB, time.Hour)
	pod.Labels["tuist.dev/runner-pool-owner"] = "tuist"
	return pod
}

func sandboxFixture(t *testing.T, objs ...client.Object) (*AutoscalerReconciler, client.Client) {
	t.Helper()
	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(objs...).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(scaling.Signals{Fleet: r.URL.Query().Get("fleet"), Claimed: 1, Occupied: 1, P95ConcurrentLastHour: 4})
	}))
	t.Cleanup(server.Close)
	tokenPath := filepath.Join(t.TempDir(), "token")
	_ = os.WriteFile(tokenPath, []byte("test-token"), 0o600)
	sc := scaling.NewClient(server.URL)
	sc.TokenPath = tokenPath

	return &AutoscalerReconciler{
		Client:             c,
		Scheme:             scheme,
		SignalsClient:      sc,
		PollInterval:       time.Millisecond,
		Now:                func() time.Time { return preemptionNow },
		SandboxesNamespace: "tuist-sandboxes",
	}, c
}

func TestSandboxDaemonsReadWhatTheSchedulerCountsAndWhatAGrowthWaitsFor(t *testing.T) {
	unbound := sandboxDaemonPod("sandboxd-unbound", "", 8, 8, false)
	r, _ := sandboxFixture(t,
		sandboxDaemonPod("sandboxd-a", "node-a", 16, 8, true),
		sandboxDaemonPod("sandboxd-b", "node-b", 8, 8, false),
		unbound,
	)

	daemons := r.sandboxDaemons(context.Background())
	sort.Slice(daemons, func(a, b int) bool { return daemons[a].name < daemons[b].name })
	if len(daemons) != 2 {
		t.Fatalf("daemons = %+v, want the two bound ones", daemons)
	}
	if daemons[0].memory != 16*gib || daemons[0].deferred != 8*gib {
		t.Errorf("deferred growth: %+v, want 16 GiB counted and 8 GiB waiting", daemons[0])
	}
	if daemons[1].memory != 8*gib || daemons[1].deferred != 0 {
		t.Errorf("steady daemon: %+v, want 8 GiB and nothing waiting", daemons[1])
	}
}

func TestSandboxDaemonsAreOffWithoutANamespace(t *testing.T) {
	r, _ := sandboxFixture(t, sandboxDaemonPod("sandboxd-a", "node-a", 16, 8, true))
	r.SandboxesNamespace = ""

	if daemons := r.sandboxDaemons(context.Background()); len(daemons) != 0 {
		t.Fatalf("daemons = %+v, want none when the chart runs no sandboxes", daemons)
	}
}

func TestFleetBudgetKeepsSandboxCarveOutsOut(t *testing.T) {
	r, _ := sandboxFixture(t,
		linuxNode("node-a", 64),
		linuxNode("node-b", 64),
		sandboxDaemonPod("sandboxd-a", "node-a", 16, 8, true),
		sandboxDaemonPod("sandboxd-b", "node-b", 8, 8, false),
		sandboxDaemonPod("sandboxd-elsewhere", "node-c", 32, 32, false),
	)
	r.MemReserveFraction = 0.9

	budget, err := r.fleetAllocatableMemory(context.Background(), "runners-linux")
	if err != nil {
		t.Fatal(err)
	}
	// 0.9 of 128 GiB, less the 16 GiB growth the scheduler already counts
	// and the 8 GiB floor; the daemon on a node outside the fleet is not
	// this fleet's.
	total := float64(128 * gib)
	want := int64(total*0.9) - 24*gib
	if budget != want {
		t.Fatalf("budget = %d, want %d", budget, want)
	}
}

func TestPlanSandboxPreemptionTakesTheOldestWarmRunnersUntilTheGrowthIsCovered(t *testing.T) {
	pod := func(name string, memGiB int64) *corev1.Pod {
		return idleLinuxRunner(name, "linux-8gb", "node-a", memGiB, time.Hour)
	}
	candidates := map[string][]sandboxCandidate{
		"node-a": {
			{pod: pod("young", 8), pool: "linux-8gb", since: preemptionNow.Add(-5 * time.Minute)},
			{pod: pod("old", 8), pool: "linux-8gb", since: preemptionNow.Add(-time.Hour)},
			{pod: pod("middle", 4), pool: "linux-4gb", since: preemptionNow.Add(-30 * time.Minute)},
		},
		"node-b": {
			{pod: pod("other-node", 8), pool: "linux-8gb", since: preemptionNow.Add(-time.Hour)},
		},
	}

	got := planSandboxPreemption(map[string]int64{"node-a": 10 * gib}, nil, candidates)
	var names []string
	for _, c := range got {
		names = append(names, c.pod.Name)
	}
	if fmt.Sprint(names) != "[old middle]" {
		t.Fatalf("chosen = %v, want the oldest runners until 10 GiB is covered", names)
	}

	if got := planSandboxPreemption(map[string]int64{"node-a": 10 * gib}, map[string]int64{"node-a": 10 * gib}, candidates); len(got) != 0 {
		t.Fatalf("chosen = %d runners, want none once retiring runners already cover the growth", len(got))
	}
}

func TestAutoscaler_RetiresIdleRunnersOnANodeWhoseSandboxGrowthIsDeferred(t *testing.T) {
	pool := linuxFleetPool("linux-8gb", 5, 8192, 0, 10)
	r, c := sandboxFixture(t,
		pool,
		linuxNode("node-a", 64),
		linuxNode("node-b", 64),
		sandboxDaemonPod("sandboxd-a", "node-a", 16, 8, true),
		busyLinuxRunner("busy-a", pool.Name, "node-a", 8),
		idleLinuxRunner("idle-a-old", pool.Name, "node-a", 8, time.Hour),
		idleLinuxRunner("idle-a-young", pool.Name, "node-a", 8, 10*time.Minute),
		idleLinuxRunner("idle-a-just-warm", pool.Name, "node-a", 8, 30*time.Second),
		idleLinuxRunner("idle-b", pool.Name, "node-b", 8, time.Hour),
	)

	reconcileOnce(t, r, pool.Name)

	marked := markedPods(t, c, pool.Name)
	if fmt.Sprint(marked) != "[idle-a-old=sandboxes]" {
		t.Fatalf("marked = %v, want only the oldest idle runner on the node whose growth waits", marked)
	}
	got := &tuistv1.RunnerPool{}
	_ = c.Get(context.Background(), client.ObjectKeyFromObject(pool), got)
	if got.Spec.Replicas != 4 {
		t.Fatalf("Replicas = %d, want 4", got.Spec.Replicas)
	}

	// The next tick sees that runner on its way off the node and takes no
	// more for the same growth.
	reconcileOnce(t, r, pool.Name)
	if marked := markedPods(t, c, pool.Name); len(marked) != 1 {
		t.Fatalf("marked = %v after a second tick, want still one", marked)
	}
}

func TestAutoscaler_LeavesRunnersAloneWithoutADeferredGrowth(t *testing.T) {
	pool := linuxFleetPool("linux-8gb", 2, 8192, 2, 10)
	r, c := sandboxFixture(t,
		pool,
		linuxNode("node-a", 64),
		sandboxDaemonPod("sandboxd-a", "node-a", 16, 16, false),
		idleLinuxRunner("idle-a", pool.Name, "node-a", 8, time.Hour),
		idleLinuxRunner("idle-b", pool.Name, "node-a", 8, time.Hour),
	)

	reconcileOnce(t, r, pool.Name)

	if marked := markedPods(t, c, pool.Name); len(marked) != 0 {
		t.Fatalf("marked = %v, want none", marked)
	}
}

func TestAutoscaler_RemembersARetiredRunnerAfterItLeavesTheAPI(t *testing.T) {
	pool := linuxFleetPool("linux-8gb", 2, 8192, 0, 10)
	r, c := sandboxFixture(t,
		pool,
		linuxNode("node-a", 64),
		sandboxDaemonPod("sandboxd-a", "node-a", 9, 8, true),
		idleLinuxRunner("idle-old", pool.Name, "node-a", 8, time.Hour),
		idleLinuxRunner("idle-young", pool.Name, "node-a", 8, 10*time.Minute),
	)

	reconcileOnce(t, r, pool.Name)
	if marked := markedPods(t, c, pool.Name); fmt.Sprint(marked) != "[idle-old=sandboxes]" {
		t.Fatalf("marked = %v, want the oldest idle runner", marked)
	}

	// The retired Pod is gone before the kubelet applies the growth.
	gone := &corev1.Pod{}
	_ = c.Get(context.Background(), client.ObjectKey{Namespace: "tuist-runners", Name: "idle-old"}, gone)
	if err := c.Delete(context.Background(), gone); err != nil {
		t.Fatal(err)
	}

	reconcileOnce(t, r, pool.Name)
	if marked := markedPods(t, c, pool.Name); len(marked) != 0 {
		t.Fatalf("marked = %v, want no second runner for the same 1 GiB growth", marked)
	}
}
