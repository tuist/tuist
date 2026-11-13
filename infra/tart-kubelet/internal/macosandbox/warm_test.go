package macosandbox

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
)

const warmTestImage = "ghcr.io/tuist/tuist-runner@sha256:warm"

func warmHarness(t *testing.T) (*Service, *Manager, *fakeRuntime, *KubeCapacity) {
	t.Helper()
	k, node, _ := capacityFixture()
	runtime := &fakeRuntime{states: map[string]string{}, memory: map[string]string{}}
	m := &Manager{Root: t.TempDir(), NodeUID: string(node.UID), TemplateTag: warmTestImage, RuntimePath: "/runtime/pinned", ToolsPath: "/tools/pinned", Runtime: runtime, Capacity: k}
	if err := m.Load(context.Background()); err != nil {
		t.Fatal(err)
	}
	return &Service{Kube: k.Kube, Node: node.Name, manager: m, capacity: k, ready: true}, m, runtime, k
}

func warmPod(t *testing.T, s *Service, image, memory string) *corev1.Pod {
	t.Helper()
	resources := corev1.ResourceList{corev1.ResourceCPU: resource.MustParse("8"), corev1.ResourceMemory: resource.MustParse(memory)}
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: "warm-" + uuid.NewString()[:8], Namespace: "tuist-runners", Labels: map[string]string{WarmLabel: "true"}},
		Spec:       corev1.PodSpec{NodeName: s.Node, Containers: []corev1.Container{{Name: "runner", Image: image, Resources: corev1.ResourceRequirements{Requests: resources, Limits: resources}}}},
		Status:     corev1.PodStatus{Phase: corev1.PodPending},
	}
	pod.UID = types.UID("uid-" + pod.Name)
	created, err := s.Kube.CoreV1().Pods(pod.Namespace).Create(context.Background(), pod, metav1.CreateOptions{})
	if err != nil {
		t.Fatal(err)
	}
	return created
}

// waitWarmPhase ticks the warm loop until the Pod reaches phase.
func waitWarmPhase(t *testing.T, s *Service, pod *corev1.Pod, phase corev1.PodPhase) *corev1.Pod {
	t.Helper()
	ctx := context.Background()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		_ = s.warmTick(ctx, ctx)
		current, err := s.Kube.CoreV1().Pods(pod.Namespace).Get(ctx, pod.Name, metav1.GetOptions{})
		if err == nil && current.Status.Phase == phase {
			return current
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("warm Pod never reached %s", phase)
	return nil
}

func warmArgs(memoryMB int) protocol.CreateArgs {
	return protocol.CreateArgs{SandboxID: uuid.NewString(), VCPUs: 8, MemoryMB: memoryMB, WorkspaceGB: 10, TemplateTag: warmTestImage}
}

func TestWarmPodBootsAsWarmCapacityAndCreateClaimsIt(t *testing.T) {
	s, m, runtime, k := warmHarness(t)
	ctx := context.Background()
	pod := waitWarmPhase(t, s, warmPod(t, s, warmTestImage, "8Gi"), corev1.PodRunning)
	if len(pod.Finalizers) != 1 || pod.Finalizers[0] != WarmFinalizer {
		t.Fatalf("a booted warm Pod must hold the VM with its finalizer: %v", pod.Finalizers)
	}
	cs := pod.Status.ContainerStatuses
	if len(cs) != 1 || cs[0].State.Running == nil || cs[0].State.Running.StartedAt.IsZero() {
		t.Fatalf("warm capacity needs a running container status with its warm start: %+v", cs)
	}

	a := warmArgs(8192)
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if runtime.creates != 0 {
		t.Fatal("a matching warm VM was available but the sandbox cold-booted")
	}
	if got := m.records[a.SandboxID].VM; got != warmVMPrefix+string(pod.UID) {
		t.Fatalf("claimed record runs on %q", got)
	}
	if !m.onWarmVM(a.SandboxID) {
		t.Fatal("create did not report the warm VM")
	}
	if _, err := k.Kube.CoreV1().Pods(Namespace).Get(ctx, "macos-sbx-"+a.SandboxID, metav1.GetOptions{}); err != nil {
		t.Fatalf("the sandbox's execution reservation is missing: %v", err)
	}
	if _, err := k.Kube.CoreV1().Pods(pod.Namespace).Get(ctx, pod.Name, metav1.GetOptions{}); !apierrors.IsNotFound(err) {
		t.Fatalf("the claimed warm Pod still holds a slot: %v", err)
	}
	if len(m.warm) != 0 {
		t.Fatal("a claimed warm VM can be claimed again")
	}
}

func TestCreateColdBootsWhenNoWarmVMMatches(t *testing.T) {
	s, m, runtime, _ := warmHarness(t)
	waitWarmPhase(t, s, warmPod(t, s, warmTestImage, "8Gi"), corev1.PodRunning)
	a := warmArgs(16384)
	if err := m.Create(context.Background(), a); err != nil {
		t.Fatal(err)
	}
	if runtime.creates != 1 || m.records[a.SandboxID].VM != "" || len(m.warm) != 1 {
		t.Fatalf("a 16 GiB sandbox must cold-boot and leave the 8 GiB warm VM: creates=%d vm=%q warm=%d", runtime.creates, m.records[a.SandboxID].VM, len(m.warm))
	}
}

func TestWarmClaimNeedsTheCIFirstGrant(t *testing.T) {
	s, m, _, k := warmHarness(t)
	ctx := context.Background()
	waitWarmPhase(t, s, warmPod(t, s, warmTestImage, "8Gi"), corev1.PodRunning)
	node, _ := k.Kube.CoreV1().Nodes().Get(ctx, k.Node, metav1.GetOptions{})
	node.Spec.Unschedulable = true
	_, _ = k.Kube.CoreV1().Nodes().Update(ctx, node, metav1.UpdateOptions{})
	if err := m.Create(ctx, warmArgs(8192)); !errors.Is(err, ErrCapacity) {
		t.Fatalf("claim admitted without a grant: %v", err)
	}
	if len(m.warm) != 1 {
		t.Fatal("a refused claim lost the warm VM")
	}
}

func TestDeletedWarmPodDeletesItsVM(t *testing.T) {
	s, m, runtime, _ := warmHarness(t)
	ctx := context.Background()
	pod := waitWarmPhase(t, s, warmPod(t, s, warmTestImage, "8Gi"), corev1.PodRunning)
	now := metav1.Now()
	pod.DeletionTimestamp = &now
	if _, err := s.Kube.CoreV1().Pods(pod.Namespace).Update(ctx, pod, metav1.UpdateOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := s.warmTick(ctx, ctx); err != nil {
		t.Fatal(err)
	}
	current, _ := s.Kube.CoreV1().Pods(pod.Namespace).Get(ctx, pod.Name, metav1.GetOptions{})
	if len(current.Finalizers) != 0 {
		t.Fatal("the warm finalizer outlived its VM")
	}
	runtime.mu.Lock()
	_, left := runtime.states[warmVMPrefix+string(pod.UID)]
	runtime.mu.Unlock()
	if left || len(m.warm) != 0 {
		t.Fatal("a deleted warm Pod left its VM running")
	}
}

func TestWarmPodForAnotherImageFailsInsteadOfBooting(t *testing.T) {
	s, _, runtime, _ := warmHarness(t)
	pod := waitWarmPhase(t, s, warmPod(t, s, "ghcr.io/tuist/tuist-runner@sha256:other", "8Gi"), corev1.PodFailed)
	if pod.Status.Reason != "WarmVMUnsupported" || runtime.warms != 0 {
		t.Fatalf("reason=%q warms=%d", pod.Status.Reason, runtime.warms)
	}
}
