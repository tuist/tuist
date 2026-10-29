package controllers

import (
	"context"
	"encoding/json"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"testing"
	"time"
)

func TestMacosGrantsRevokeForQueuedUnknownAndUnhealthyCI(t *testing.T) {
	for _, tc := range []struct {
		name     string
		fleet    *fleetAllocation
		pressure bool
		allow    bool
	}{
		{"idle", &fleetAllocation{}, false, true},
		{"queued", &fleetAllocation{members: map[string]fleetMember{"ci": {queued: 1}}}, false, false},
		{"unknown", nil, false, false},
		{"disk pressure", &fleetAllocation{}, true, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			node := linuxNodeWithResources("mac-1", "mac-fleet", 16, 48*1024)
			node.Labels[corev1.LabelOSStable] = "darwin"
			node.UID = "node-uid"
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
