package controllers

import (
	"context"
	"encoding/json"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/utils/ptr"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/priorityqueue"
	"testing"
	"time"
)

func TestMacosGrantsAllowQueuedCIButRevokeForReservedUnknownAndUnhealthyHosts(t *testing.T) {
	for _, tc := range []struct {
		name     string
		fleet    *fleetAllocation
		pressure bool
		reserved bool
		allow    bool
	}{
		{"idle", &fleetAllocation{}, false, false, true},
		{"queued elsewhere", &fleetAllocation{members: map[string]fleetMember{"ci": {queued: 1}}}, false, false, true},
		{"reserved for queued CI", &fleetAllocation{members: map[string]fleetMember{"ci": {queued: 1}}}, false, true, false},
		{"unknown", nil, false, false, false},
		{"disk pressure", &fleetAllocation{}, true, false, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			node := linuxNodeWithResources("mac-1", "mac-fleet", 16, 48*1024)
			node.Labels[corev1.LabelOSStable] = "darwin"
			node.UID = "node-uid"
			if tc.reserved {
				node.Spec.Taints = append(node.Spec.Taints, corev1.Taint{Key: podtemplate.ReservationTaintKey, Value: "ci", Effect: corev1.TaintEffectNoSchedule})
			}
			if tc.pressure {
				node.Status.Conditions = append(node.Status.Conditions, corev1.NodeCondition{Type: corev1.NodeDiskPressure, Status: corev1.ConditionUnknown})
			}
			pod := corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "control", Namespace: "tuist-sandboxes", UID: "control-uid", Labels: map[string]string{macosSandboxRole: "control"}}, Spec: corev1.PodSpec{NodeName: node.Name}}
			r, c := sandboxFixture(t, node)
			now := time.Now().UTC()
			if err := r.publishMacosGrants(context.Background(), []corev1.Node{*node}, []corev1.Pod{pod}, tc.fleet, now); err != nil {
				t.Fatal(err)
			}
			if err := c.Get(context.Background(), client.ObjectKey{Name: node.Name}, node); err != nil {
				t.Fatal(err)
			}
			var grant struct {
				Allow      bool      `json:"allow"`
				NodeUID    string    `json:"node_uid"`
				ControlUID string    `json:"control_uid"`
				Observed   time.Time `json:"observed_at"`
			}
			if err := json.Unmarshal([]byte(node.Annotations[macosSandboxGrant]), &grant); err != nil {
				t.Fatal(err)
			}
			if grant.Allow != tc.allow || grant.NodeUID != "node-uid" || grant.ControlUID != "control-uid" || !grant.Observed.Equal(now) {
				t.Fatalf("bad grant: %+v", grant)
			}
		})
	}
}

// A conflict on one host used to end the tick, so every later host kept a
// grant that aged past 15 s and the server refused creates on an idle rack.
func TestMacosGrantConflictRecomputesFromTheFreshNodeAndKeepsPublishing(t *testing.T) {
	first := linuxNodeWithResources("mac-1", "mac-fleet", 16, 48*1024)
	second := linuxNodeWithResources("mac-2", "mac-fleet", 16, 48*1024)
	var pods []corev1.Pod
	for _, node := range []*corev1.Node{first, second} {
		node.Labels[corev1.LabelOSStable] = "darwin"
		node.UID = types.UID(node.Name + "-uid")
		pods = append(pods, corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: node.Name + "-control", Namespace: "tuist-sandboxes", UID: types.UID(node.Name + "-control"), Labels: map[string]string{macosSandboxRole: "control"}}, Spec: corev1.PodSpec{NodeName: node.Name}})
	}
	r, c := sandboxFixture(t, first, second)
	ctx := context.Background()
	var listed corev1.NodeList
	if err := c.List(ctx, &listed); err != nil {
		t.Fatal(err)
	}
	// CI reserves mac-1 after the tick read it.
	var live corev1.Node
	if err := c.Get(ctx, client.ObjectKey{Name: "mac-1"}, &live); err != nil {
		t.Fatal(err)
	}
	live.Spec.Taints = append(live.Spec.Taints, corev1.Taint{Key: podtemplate.ReservationTaintKey, Value: "ci", Effect: corev1.TaintEffectNoSchedule})
	if err := c.Update(ctx, &live); err != nil {
		t.Fatal(err)
	}

	if err := r.publishMacosGrants(ctx, listed.Items, pods, &fleetAllocation{}, time.Now().UTC()); err != nil {
		t.Fatal(err)
	}
	for name, want := range map[string]bool{"mac-1": false, "mac-2": true} {
		var node corev1.Node
		if err := c.Get(ctx, client.ObjectKey{Name: name}, &node); err != nil {
			t.Fatal(err)
		}
		var grant struct {
			Allow bool `json:"allow"`
		}
		if err := json.Unmarshal([]byte(node.Annotations[macosSandboxGrant]), &grant); err != nil {
			t.Fatalf("%s has no grant: %v", name, err)
		}
		if grant.Allow != want {
			t.Fatalf("%s allow = %v, want %v", name, grant.Allow, want)
		}
	}
}

// The fleet's grants are renewed only when its reporter reconciles. On
// 2026-11-24 and 11-25 the autoscaler kept 25 to 41 pools queued for an hour
// at a time, the reporter waited its turn behind them, and every macOS host's
// grant went stale together. Its requeue must come out of the queue first,
// and a pool that stops reporting must not keep that place.
func TestTheGrantReporterLeavesTheQueueAheadOfItsQueuedSiblings(t *testing.T) {
	r, _ := sandboxFixture(t, macosFleetPool("macos-a", "rack", 1, 1, 9), macosFleetPool("macos-b", "rack", 1, 1, 9), macosNode("mac-1", "rack"))
	reporter := reconcileOnce(t, r, "macos-a")
	sibling := reconcileOnce(t, r, "macos-b")

	queue := priorityqueue.New[string]("autoscaler")
	defer queue.ShutDown()
	// controller-runtime keeps the request's last priority when a result
	// sets none; assume the sibling reported before the reporter existed.
	for _, name := range []string{"macos-b", "macos-c", "macos-d", "macos-e"} {
		queue.AddWithOpts(priorityqueue.AddOpts{Priority: new(ptr.Deref(sibling.Priority, sandboxReporterPriority))}, name)
	}
	queue.AddWithOpts(priorityqueue.AddOpts{Priority: reporter.Priority}, "macos-a")
	if first, _, _ := queue.GetWithPriority(); first != "macos-a" {
		t.Fatalf("first out of the queue = %s, want the reporter macos-a (priorities: reporter %v, sibling %v)", first, ptr.Deref(reporter.Priority, -1), ptr.Deref(sibling.Priority, -1))
	}
}

// One pool reports grants for its whole fleet. On 2026-11-23 that was the
// site-pinned `runner-pool-ber1`, so the larch site's hosts got no grant and
// the server skipped all ten of them as `grant_mismatch`.
func TestMacosGrantsReachEverySiteWhenTheReporterIsPinnedToOne(t *testing.T) {
	var objs []client.Object
	for name, site := range map[string]string{"ber1-b04": "ber1", "larch-a01": "larch"} {
		node := linuxNodeWithResources(name, "", 16, 48*1024)
		node.Labels = map[string]string{macosFleetLabel: "rack", corev1.LabelOSStable: macosNodeOSDarwin, podtemplate.RackSiteNodeLabel: site}
		node.UID = types.UID(name + "-uid")
		objs = append(objs, node, &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: name + "-control", Namespace: "tuist-sandboxes", UID: types.UID(name + "-control"), Labels: map[string]string{macosSandboxRole: "control"}}, Spec: corev1.PodSpec{NodeName: name}})
	}
	r, c := sandboxFixture(t, objs...)
	pinned := &tuistv1.RunnerPool{ObjectMeta: metav1.ObjectMeta{Name: "a-ber1"}, Spec: tuistv1.RunnerPoolSpec{OS: "darwin", FleetSelector: "rack", Site: "ber1"}}
	fleet := &fleetAllocation{members: map[string]fleetMember{"a-ber1": {pool: pinned}, "b-larch": {}, "macos-27-1": {}}}
	if err := r.publishSandboxAllocations(context.Background(), pinned, fleet); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"ber1-b04", "larch-a01"} {
		var node corev1.Node
		if err := c.Get(context.Background(), client.ObjectKey{Name: name}, &node); err != nil {
			t.Fatal(err)
		}
		var grant struct {
			NodeUID string `json:"node_uid"`
			Allow   bool   `json:"allow"`
		}
		if err := json.Unmarshal([]byte(node.Annotations[macosSandboxGrant]), &grant); err != nil || grant.NodeUID != name+"-uid" || !grant.Allow {
			t.Fatalf("%s grant = %q (%v)", name, node.Annotations[macosSandboxGrant], err)
		}
	}
}

func TestNativePreemptionAccountsForCPUsAndSlotsNotOnlyMemory(t *testing.T) {
	for _, tc := range []struct {
		cpus int64
		want int
	}{{12, 2}, {16, 1}, {24, 1}} {
		node := linuxNodeWithResources("mac-1", "mac-fleet", tc.cpus, 64*1024)
		warmA := idleLinuxRunner("a", "pool-a", node.Name, 8, time.Hour)
		warmB := idleLinuxRunner("b", "pool-b", node.Name, 8, time.Hour)
		for _, p := range []*corev1.Pod{warmA, warmB} {
			p.Spec.InitContainers = nil
			p.Spec.Containers[0].Resources.Requests[corev1.ResourceCPU] = resource.MustParse("6")
		}
		native := sandboxDaemonPod("sandbox", node.Name, 8, 8, false)
		native.Labels = map[string]string{macosSandboxRole: "execution"}
		native.Spec.Containers[0].Resources.Requests[corev1.ResourceCPU] = resource.MustParse("8")
		candidates := map[string][]sandboxCandidate{node.Name: {{pod: warmA, since: time.Now().Add(-time.Hour)}, {pod: warmB, since: time.Now().Add(-time.Hour)}}}
		chosen := planNativeSandboxPreemption([]corev1.Node{*node}, []corev1.Pod{*warmA, *warmB, *native}, map[string]int64{node.Name: 8 * gib}, candidates, time.Now())
		if len(chosen) != tc.want {
			t.Fatalf("%d CPUs: retired %d, want %d", tc.cpus, len(chosen), tc.want)
		}
	}
}

func TestNativeGrantExcludesBusyCIButLeavesNativeAccountingToServer(t *testing.T) {
	node := linuxNodeWithResources("mac-1", "mac-fleet", 16, 48*1024)
	ci := busyLinuxRunner("ci", "pool", node.Name, 16)
	ci.Spec.InitContainers = nil
	ci.Spec.Containers[0].Resources.Requests[corev1.ResourceCPU] = resource.MustParse("8")
	native := sandboxDaemonPod("native", node.Name, 8, 8, false)
	native.Labels = map[string]string{macosSandboxRole: "execution"}
	native.Spec.Containers[0].Resources.Requests[corev1.ResourceCPU] = resource.MustParse("8")
	room := nativeSandboxRoom(node, []corev1.Pod{*ci, *native}, nil, time.Now())
	if room.cpu != 8000 || room.memory != 32*gib || room.slots != 1 {
		t.Fatalf("CI charge lost or native charge counted twice: %+v", room)
	}
	secondCI := ci.DeepCopy()
	secondCI.Name = "second-ci"
	room = nativeSandboxRoom(node, []corev1.Pod{*ci, *secondCI}, nil, time.Now())
	if room.cpu != 0 || room.slots != 0 {
		t.Fatalf("fully occupied host granted native capacity: %+v", room)
	}
}

func TestNativeGrantCountsAFreshWarmSandboxVMAsRoomButNotAFreshCIRunner(t *testing.T) {
	node := linuxNodeWithResources("mac-1", "mac-fleet", 16, 48*1024)
	pool := func(name string, warm bool) *tuistv1.RunnerPool {
		p := &tuistv1.RunnerPool{ObjectMeta: metav1.ObjectMeta{Name: name, Labels: map[string]string{}}, Spec: tuistv1.RunnerPoolSpec{OS: "darwin", Image: "img"}}
		if warm {
			p.Labels[podtemplate.MacosSandboxWarmLabel] = "true"
		}
		return p
	}
	vm := func(name, poolName string) *corev1.Pod {
		pod := newRunnerPod(name, "img", corev1.PodRunning, poolName)
		pod.Spec.NodeName = node.Name
		pod.Spec.Containers[0].Resources.Requests = corev1.ResourceList{corev1.ResourceCPU: resource.MustParse("8"), corev1.ResourceMemory: *resource.NewQuantity(8*gib, resource.BinarySI)}
		pod.Status.ContainerStatuses = []corev1.ContainerStatus{{Name: "runner", State: corev1.ContainerState{Running: &corev1.ContainerStateRunning{StartedAt: metav1.NewTime(time.Now().Add(-10 * time.Second))}}}}
		return pod
	}
	fleet := &fleetAllocation{members: map[string]fleetMember{"ci": {pool: pool("ci", false)}, "warm": {pool: pool("warm", true)}}}

	room := nativeSandboxRoom(node, []corev1.Pod{*vm("ci-1", "ci"), *vm("warm-1", "warm")}, fleet, time.Now())
	if room.cpu != 8000 || room.slots != 1 {
		t.Fatalf("want the fresh CI runner charged and the fresh warm VM reclaimable: %+v", room)
	}
}

func TestReservationReconcilesOnlyTheDarwinPoolsWithRunnersOnItsHost(t *testing.T) {
	pool := func(name, os string) *tuistv1.RunnerPool {
		return &tuistv1.RunnerPool{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist-runners"}, Spec: tuistv1.RunnerPoolSpec{OS: os}}
	}
	runner := func(name, poolName, node string) *corev1.Pod {
		pod := newRunnerPod(name, "img", corev1.PodRunning, poolName)
		pod.Spec.NodeName = node
		return pod
	}
	r, _ := sandboxFixture(t,
		pool("on-host", "darwin"), pool("elsewhere", "darwin"), pool("empty", "darwin"), pool("linux", "linux"),
		runner("a", "on-host", "mac-1"), runner("b", "elsewhere", "mac-2"), runner("c", "linux", "mac-1"))
	reservation := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "macos-sbx-1", Namespace: "tuist-sandboxes", Labels: map[string]string{macosSandboxRole: "execution"}}, Spec: corev1.PodSpec{NodeName: "mac-1"}}

	requests := r.darwinPools(context.Background(), reservation)
	if len(requests) != 1 || requests[0].Name != "on-host" || requests[0].Namespace != "tuist-runners" {
		t.Fatalf("want only the darwin pool with a runner on mac-1, got %v", requests)
	}
}
