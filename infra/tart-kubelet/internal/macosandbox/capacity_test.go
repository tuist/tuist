package macosandbox

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes/fake"
)

func capacityFixture() (*KubeCapacity, *corev1.Node, *Record) {
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "mac-1", UID: "node-1"}, Status: corev1.NodeStatus{Allocatable: corev1.ResourceList{corev1.ResourceCPU: resource.MustParse("16"), corev1.ResourceMemory: resource.MustParse("48Gi")}, Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}}}
	grant, _ := json.Marshal(Grant{CPUMilli: 16000, MemoryBytes: 48 * 1024 * 1024 * 1024, Slots: 2, Allow: true, NodeUID: "node-1", ControlUID: "control-1", ObservedAt: time.Now()})
	node.Annotations = map[string]string{GrantAnnotation: string(grant)}
	k := &KubeCapacity{Kube: fake.NewSimpleClientset(node), Node: node.Name, NodeUID: string(node.UID), Namespace: Namespace, ControlUID: "control-1"}
	return k, node, &Record{NodeUID: "node-1", CreateArgs: protocol.CreateArgs{SandboxID: uuid.NewString(), VCPUs: 8, MemoryMB: 8192}}
}
func TestGrantRequiresFreshMatchingNodeAndControlIdentity(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*corev1.Node, *Grant)
	}{
		{"expired", func(_ *corev1.Node, g *Grant) { g.ObservedAt = time.Now().Add(-16 * time.Second) }},
		{"unknown CI", func(_ *corev1.Node, g *Grant) { g.Allow = false }},
		{"CPU occupied by CI", func(_ *corev1.Node, g *Grant) { g.CPUMilli = 4000 }},
		{"memory occupied by CI", func(_ *corev1.Node, g *Grant) { g.MemoryBytes = 4 * 1024 * 1024 * 1024 }},
		{"VM slots occupied by CI", func(_ *corev1.Node, g *Grant) { g.Slots = 0 }},
		{"replaced node", func(n *corev1.Node, _ *Grant) { n.UID = "replacement" }},
		{"replaced control", func(_ *corev1.Node, g *Grant) { g.ControlUID = "replacement" }},
		{"unknown health", func(n *corev1.Node, _ *Grant) { n.Status.Conditions = nil }},
		{"cordoned", func(n *corev1.Node, _ *Grant) { n.Spec.Unschedulable = true }},
		{"CI reservation", func(n *corev1.Node, _ *Grant) {
			n.Spec.Taints = []corev1.Taint{{Key: "tuist.dev/reserved-for", Effect: corev1.TaintEffectNoSchedule}}
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			k, n, r := capacityFixture()
			var grant Grant
			_ = json.Unmarshal([]byte(n.Annotations[GrantAnnotation]), &grant)
			tc.mutate(n, &grant)
			raw, _ := json.Marshal(grant)
			n.Annotations[GrantAnnotation] = string(raw)
			_, _ = k.Kube.CoreV1().Nodes().Update(context.Background(), n, metav1.UpdateOptions{})
			if !errors.Is(k.Allow(context.Background(), r), ErrCapacity) {
				t.Fatal("unsafe grant accepted")
			}
		})
	}
}
func TestExecutionReservationCountsPendingAndTerminatingCI(t *testing.T) {
	k, _, r := capacityFixture()
	ctx := context.Background()
	if err := k.Reserve(ctx, r); err != nil {
		t.Fatal(err)
	}
	for i, phase := range []corev1.PodPhase{corev1.PodPending, corev1.PodRunning} {
		pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: []string{"pending-ci", "terminating-ci"}[i], Namespace: "ci"}, Spec: corev1.PodSpec{NodeName: k.Node, Containers: []corev1.Container{{Name: "ci", Resources: corev1.ResourceRequirements{Requests: corev1.ResourceList{corev1.ResourceCPU: resource.MustParse("4"), corev1.ResourceMemory: resource.MustParse("8Gi")}}}}}, Status: corev1.PodStatus{Phase: phase}}
		if i == 1 {
			now := metav1.Now()
			pod.DeletionTimestamp = &now
			pod.Finalizers = []string{"runtime-fence"}
		}
		if _, err := k.Kube.CoreV1().Pods("ci").Create(ctx, pod, metav1.CreateOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	if !errors.Is(k.Fits(ctx), ErrCapacity) {
		t.Fatal("three VM slots admitted")
	}
	if err := k.Release(ctx, r); err != nil {
		t.Fatal(err)
	}
	if err := k.Fits(ctx); err != nil {
		t.Fatal(err)
	}
}
func TestRecoveryRecreatesChargeWhileAdmissionRevoked(t *testing.T) {
	k, n, r := capacityFixture()
	ctx := context.Background()
	n.Annotations = nil
	_, _ = k.Kube.CoreV1().Nodes().Update(ctx, n, metav1.UpdateOptions{})
	if k.Reserve(ctx, r) == nil {
		t.Fatal("new admission without grant")
	}
	if err := k.Hold(ctx, r); err != nil {
		t.Fatal(err)
	}
	pod, err := k.Kube.CoreV1().Pods(Namespace).Get(ctx, "macos-sbx-"+r.SandboxID, metav1.GetOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if len(pod.Finalizers) != 1 || pod.Finalizers[0] != ReservationFinalizer {
		t.Fatal("missing fence")
	}
	r.NodeUID = "other-node"
	if k.Release(ctx, r) == nil {
		t.Fatal("released another owner's charge")
	}
}

func TestCILaunchRepairsForceDeletedResidentCharge(t *testing.T) {
	k, _, record := capacityFixture()
	m, runtime, _, args := harness(t)
	args.SandboxID = record.SandboxID
	m.Capacity = k
	ctx := context.Background()
	if err := m.Create(ctx, args); err != nil {
		t.Fatal(err)
	}
	if err := k.Kube.CoreV1().Pods(Namespace).Delete(ctx, "macos-sbx-"+args.SandboxID, metav1.DeleteOptions{}); err != nil {
		t.Fatal(err)
	}
	service := &Service{manager: m, capacity: k, ready: true}
	release, err := service.LaunchGuard(ctx, "ci")
	if err != nil {
		t.Fatal(err)
	}
	release()
	pod, err := k.Kube.CoreV1().Pods(Namespace).Get(ctx, "macos-sbx-"+args.SandboxID, metav1.GetOptions{})
	if err != nil || len(pod.Finalizers) != 1 || runtime.states[args.SandboxID] != "running" {
		t.Fatalf("resident charge not repaired: %v", err)
	}
	pod.Status.Phase = corev1.PodSucceeded
	if _, err = k.Kube.CoreV1().Pods(Namespace).Update(ctx, pod, metav1.UpdateOptions{}); err != nil {
		t.Fatal(err)
	}
	if release, err = service.LaunchGuard(ctx, "ci"); err == nil {
		release()
		t.Fatal("terminal reservation permitted a live VM to disappear from accounting")
	}
}
