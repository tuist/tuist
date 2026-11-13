package macosandbox

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes/fake"
	ktesting "k8s.io/client-go/testing"
)

func TestUnjournaledVMBlocksCIWithoutControlPod(t *testing.T) {
	capacity, node, _ := capacityFixture()
	s := &Service{Kube: capacity.Kube, Node: node.Name, Root: t.TempDir()}
	orphan := filepath.Join(s.Root, "tart", "vms", "sbx-orphan")
	if err := os.MkdirAll(orphan, 0700); err != nil {
		t.Fatal(err)
	}
	var controlUID string
	var cancel context.CancelFunc
	ctx := context.Background()
	if err := s.tick(ctx, ctx, &controlUID, &cancel); err == nil {
		t.Fatal("orphan VM without a journal was treated as an empty store")
	}
	if unlock, err := s.LaunchGuard(ctx, "ci-vm"); err == nil {
		unlock()
		t.Fatal("CI admitted while sandbox ownership was unknown")
	}
	// Simulate operator reconciliation, then verify the CI-only path recovers.
	if err := os.Remove(orphan); err != nil {
		t.Fatal(err)
	}
	if err := s.tick(ctx, ctx, &controlUID, &cancel); err != nil {
		t.Fatal(err)
	}
	unlock, err := s.LaunchGuard(ctx, "ci-vm")
	if err != nil {
		t.Fatal(err)
	}
	unlock()
}

// A warm VM still running after a restart takes a VM slot no journal
// charges, so CI must not launch before preparation has deleted it.
func TestLeftoverWarmVMKeepsCIClosed(t *testing.T) {
	capacity, node, _ := capacityFixture()
	s := &Service{Kube: capacity.Kube, Node: node.Name, Root: t.TempDir()}
	if err := os.MkdirAll(filepath.Join(s.Root, "tart", "vms", warmVMPrefix+"pod-uid"), 0700); err != nil {
		t.Fatal(err)
	}
	var controlUID string
	var cancel context.CancelFunc
	ctx := context.Background()
	_ = s.tick(ctx, ctx, &controlUID, &cancel)
	if unlock, err := s.LaunchGuard(ctx, "ci-vm"); err == nil {
		unlock()
		t.Fatal("CI admitted while an unclaimed warm VM may still run")
	}
}

// The fake API normally drops Pods immediately regardless of deletion grace.
// Leave graceful deletes in the tracker, as the real API does without a kubelet
// completing them, so lifecycle tests cannot hide leaked Terminating Pods.
func emulatePodDeletionGrace(k *fake.Clientset) {
	k.PrependReactor("delete", "pods", func(action ktesting.Action) (bool, runtime.Object, error) {
		opts := action.(ktesting.DeleteAction).GetDeleteOptions()
		if opts.GracePeriodSeconds == nil || *opts.GracePeriodSeconds != 0 {
			return true, nil, nil
		}
		return false, nil, nil
	})
}

func TestDeleteControlBeforeRuntimePrepared(t *testing.T) {
	now := metav1.Now()
	control := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{
		Name: "control", Namespace: Namespace, UID: "control-1", DeletionTimestamp: &now,
		Labels: map[string]string{RoleLabel: "control"},
	}, Spec: corev1.PodSpec{NodeName: "mac-1", ServiceAccountName: ServiceAccount}}
	execution := control.DeepCopy()
	execution.Name, execution.UID = "execution", "execution-1"
	execution.Labels[RoleLabel] = "execution"
	execution.Finalizers = []string{ReservationFinalizer}
	foreign := control.DeepCopy()
	foreign.Name, foreign.UID, foreign.Spec.NodeName = "foreign", "foreign-1", "mac-2"
	k := fake.NewSimpleClientset(&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "mac-1"}}, control, execution, foreign)
	emulatePodDeletionGrace(k)
	s := &Service{Kube: k, Node: "mac-1", Root: t.TempDir()}
	ctx, stop := context.WithCancel(context.Background())
	defer stop()
	cancel := context.CancelFunc(stop)
	controlUID := "control-1"
	if err := s.tick(context.Background(), context.Background(), &controlUID, &cancel); err != nil {
		t.Fatal(err)
	}
	if ctx.Err() == nil || cancel != nil || controlUID != "" {
		t.Fatal("deleted control connection remained active")
	}
	if _, err := k.CoreV1().Pods(Namespace).Get(context.Background(), control.Name, metav1.GetOptions{}); !apierrors.IsNotFound(err) {
		t.Fatalf("control Pod was not fully deleted: %v", err)
	}
	for _, name := range []string{execution.Name, foreign.Name} {
		if _, err := k.CoreV1().Pods(Namespace).Get(context.Background(), name, metav1.GetOptions{}); err != nil {
			t.Fatalf("deleted unfenced execution or foreign control %s: %v", name, err)
		}
	}
	for _, action := range k.Actions() {
		if deletion, ok := action.(ktesting.DeleteAction); ok {
			preconditions := deletion.GetDeleteOptions().Preconditions
			if preconditions == nil || preconditions.UID == nil || *preconditions.UID != types.UID("control-1") {
				t.Fatal("control deletion was not identity-fenced")
			}
		}
	}
}

func TestFencedReservationReleaseCompletesPodDeletion(t *testing.T) {
	k, _, r := capacityFixture()
	emulatePodDeletionGrace(k.Kube.(*fake.Clientset))
	ctx := context.Background()
	if err := k.Reserve(ctx, r); err != nil {
		t.Fatal(err)
	}
	if err := k.Release(ctx, r); err != nil {
		t.Fatal(err)
	}
	if _, err := k.Kube.CoreV1().Pods(Namespace).Get(ctx, "macos-sbx-"+r.SandboxID, metav1.GetOptions{}); !apierrors.IsNotFound(err) {
		t.Fatalf("fenced reservation remained Terminating: %v", err)
	}
}

func TestControlPreparationFailureDoesNotBlockCIEviction(t *testing.T) {
	m, runtime, _, args := harness(t)
	capacity, node, _ := capacityFixture()
	m.Capacity = capacity
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := m.Create(ctx, args); err != nil {
		t.Fatal(err)
	}
	if err := m.Pause(ctx, args.SandboxID); err != nil {
		t.Fatal(err)
	}
	// A replacement control Pod cannot connect, while CI has revoked the grant.
	control := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{
		Name: "control", Namespace: Namespace, UID: "replacement",
		Labels:      map[string]string{RoleLabel: "control"},
		Annotations: map[string]string{ConfigAnnotation: `{}`},
	}, Spec: corev1.PodSpec{NodeName: node.Name, ServiceAccountName: ServiceAccount}}
	if _, err := capacity.Kube.CoreV1().Pods(Namespace).Create(ctx, control, metav1.CreateOptions{}); err != nil {
		t.Fatal(err)
	}
	node.Annotations = nil
	if _, err := capacity.Kube.CoreV1().Nodes().Update(ctx, node, metav1.UpdateOptions{}); err != nil {
		t.Fatal(err)
	}
	runtime.saveStarted, runtime.saveRelease = make(chan struct{}), make(chan struct{})
	s := &Service{Kube: capacity.Kube, Node: node.Name, Root: t.TempDir(), manager: m, capacity: capacity, ready: true}
	done := make(chan error, 1)
	go func() { done <- s.Start(ctx) }()
	defer func() {
		cancel()
		if err := <-done; err != nil {
			t.Error(err)
		}
	}()
	select {
	case <-runtime.saveStarted:
	case <-ctx.Done():
		t.Fatal("invalid replacement control configuration blocked CI eviction")
	}
	// A checkpoint in progress must still retain its capacity reservation.
	if _, err := capacity.Kube.CoreV1().Pods(Namespace).Get(ctx, "macos-sbx-"+args.SandboxID, metav1.GetOptions{}); err != nil {
		t.Fatal(err)
	}
	close(runtime.saveRelease)
	for m.Snapshot()[0].Resident {
		select {
		case <-ctx.Done():
			t.Fatal("eviction did not finish")
		case <-time.After(10 * time.Millisecond):
		}
	}
	m.Gate.Lock()
	m.Gate.Unlock()
	if _, err := capacity.Kube.CoreV1().Pods(Namespace).Get(ctx, "macos-sbx-"+args.SandboxID, metav1.GetOptions{}); !apierrors.IsNotFound(err) {
		t.Fatalf("evicted sandbox retained capacity: %v", err)
	}
}

// Template preparation can wait an hour or more for an image pull or disk
// room. The control Pod must be Ready before that, or a chart rollout that
// waits on the DaemonSet times out while hosts prepare in the background.
func TestControlPodReadyBeforeTemplatePreparation(t *testing.T) {
	capacity, node, _ := capacityFixture()
	control := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{
		Name: "control", Namespace: Namespace, UID: "control-1",
		Labels:      map[string]string{RoleLabel: "control"},
		Annotations: map[string]string{ConfigAnnotation: `{"url":"https://tuist.dev","image":"ghcr.io/tuist/tuist-runner@sha256:abc","template":"macos"}`},
	}, Spec: corev1.PodSpec{NodeName: node.Name, ServiceAccountName: ServiceAccount}}
	if _, err := capacity.Kube.CoreV1().Pods(Namespace).Create(context.Background(), control, metav1.CreateOptions{}); err != nil {
		t.Fatal(err)
	}
	s := &Service{Kube: capacity.Kube, Node: node.Name, Root: t.TempDir()}
	// A cancelled context stops the runtime build before it starts, so
	// preparation never finishes during this tick.
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	var controlUID string
	var stop context.CancelFunc
	if err := s.tick(ctx, ctx, &controlUID, &stop); err == nil {
		t.Fatal("preparation finished without building the runtime")
	}
	pod, err := capacity.Kube.CoreV1().Pods(Namespace).Get(context.Background(), control.Name, metav1.GetOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if pod.Status.Phase != corev1.PodRunning || len(pod.Status.Conditions) != 1 || pod.Status.Conditions[0].Type != corev1.PodReady || pod.Status.Conditions[0].Status != corev1.ConditionTrue {
		t.Fatalf("control Pod not Ready while preparation is pending: %+v", pod.Status)
	}

	// After an API outage the node lifecycle controller marks the Pod NotReady
	// and leaves it Running. The next tick must make it Ready again.
	pod.Status.Conditions[0].Status = corev1.ConditionFalse
	if _, err = capacity.Kube.CoreV1().Pods(Namespace).UpdateStatus(context.Background(), pod, metav1.UpdateOptions{}); err != nil {
		t.Fatal(err)
	}
	_ = s.tick(ctx, ctx, &controlUID, &stop)
	pod, err = capacity.Kube.CoreV1().Pods(Namespace).Get(context.Background(), control.Name, metav1.GetOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if pod.Status.Phase != corev1.PodRunning || len(pod.Status.Conditions) != 1 || pod.Status.Conditions[0].Status != corev1.ConditionTrue {
		t.Fatalf("control Pod stayed NotReady after the node recovered: %+v", pod.Status)
	}
}
