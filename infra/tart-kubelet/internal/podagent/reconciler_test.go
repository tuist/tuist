package podagent

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestCompletePodDeletionRemovesFinalizerAndDeletesPod(t *testing.T) {
	ctx := context.Background()
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:  "default",
			Name:       "xcresult-processor",
			Finalizers: []string{PodFinalizer},
		},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{{Name: "processor", Image: "ghcr.io/tuist/xcresult-processor:test"}},
		},
	}
	kubeClient := newPodTestClient(t, pod)
	storedPod := getPod(t, ctx, kubeClient, types.NamespacedName{Namespace: "default", Name: "xcresult-processor"})

	reconciler := &Reconciler{CachedClient: kubeClient}
	if err := reconciler.completePodDeletion(ctx, storedPod); err != nil {
		t.Fatalf("completePodDeletion: %v", err)
	}

	assertPodDeleted(t, ctx, kubeClient, types.NamespacedName{Namespace: "default", Name: "xcresult-processor"})
}

func TestCompletePodDeletionDeletesPodWithoutFinalizer(t *testing.T) {
	ctx := context.Background()
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: "default",
			Name:      "already-cleaned",
		},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{{Name: "processor", Image: "ghcr.io/tuist/xcresult-processor:test"}},
		},
	}
	kubeClient := newPodTestClient(t, pod)
	storedPod := getPod(t, ctx, kubeClient, types.NamespacedName{Namespace: "default", Name: "already-cleaned"})

	reconciler := &Reconciler{CachedClient: kubeClient}
	if err := reconciler.completePodDeletion(ctx, storedPod); err != nil {
		t.Fatalf("completePodDeletion: %v", err)
	}

	assertPodDeleted(t, ctx, kubeClient, types.NamespacedName{Namespace: "default", Name: "already-cleaned"})
}

// Regression guard: when a Pod is BOTH in a terminal phase AND has
// DeletionTimestamp set (the steady state once the runners-controller
// observes a Succeeded Pod and issues a Delete on it), the
// reconciler must run the deletion branch — drop the finalizer and
// force-complete the API-object deletion. The previous ordering had
// the terminal-phase early-return ahead of the DeletionTimestamp
// check, which left every Succeeded Pod wedged in Terminating with
// the vm-cleanup finalizer holding it open.
func TestReconcileTerminalPodWithDeletionTimestampRemovesFinalizer(t *testing.T) {
	ctx := context.Background()
	deletionTime := metav1.Now()
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:         "tuist-runners",
			Name:              "runner-stuck-terminating",
			Finalizers:        []string{PodFinalizer},
			DeletionTimestamp: &deletionTime,
		},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{{Name: "runner", Image: "ghcr.io/tuist/tuist-runner:test"}},
		},
		Status: corev1.PodStatus{Phase: corev1.PodSucceeded},
	}
	kubeClient := newPodTestClient(t, pod)
	reconciler := &Reconciler{
		CachedClient: kubeClient,
		// Tart and Store are unused on this path: deletePod ->
		// deleteByKey returns nil when Store.Get yields no entry,
		// which is the steady state for terminal Pods (the VM was
		// already cleaned up when its `tart run` exited).
		Store: NewStore(),
	}

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{
		NamespacedName: types.NamespacedName{Namespace: "tuist-runners", Name: "runner-stuck-terminating"},
	}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}

	assertPodDeleted(t, ctx, kubeClient, types.NamespacedName{Namespace: "tuist-runners", Name: "runner-stuck-terminating"})
}

// TestRunningContainerStatusesReportsReady guards the kubectl READY
// column for VM-backed Pods. tart-kubelet has no per-container CRI, so
// it must synthesize containerStatuses; without ready=true a healthy
// VM reads 0/N READY and is easily misread as an outage. The statuses
// mirror the Pod Ready condition the reconciler sets when the VM is up.
func TestRunningContainerStatusesReportsReady(t *testing.T) {
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Namespace: "tuist", Name: "xcresult-processor-abc"},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{{Name: "xcresult-processor", Image: "ghcr.io/tuist/tuist:sha-x"}},
		},
	}
	startedAt := metav1.Now()

	statuses := runningContainerStatuses(pod, "vm-abc", startedAt)

	if len(statuses) != 1 {
		t.Fatalf("expected 1 container status (Pod ↔ VM is 1:1), got %d", len(statuses))
	}
	cs := statuses[0]
	if !cs.Ready {
		t.Fatalf("expected Ready=true so kubectl shows N/N for a running VM")
	}
	if cs.Started == nil || !*cs.Started {
		t.Fatalf("expected Started=true, got %v", cs.Started)
	}
	if cs.State.Running == nil {
		t.Fatalf("expected Running state, got %+v", cs.State)
	}
	if !cs.State.Running.StartedAt.Equal(&startedAt) {
		t.Fatalf("expected StartedAt to mirror the VM start time")
	}
	if cs.Name != "xcresult-processor" || cs.Image != "ghcr.io/tuist/tuist:sha-x" {
		t.Fatalf("expected name/image mirrored from the spec, got %q/%q", cs.Name, cs.Image)
	}
	if cs.ContainerID != "tart://vm-abc" {
		t.Fatalf("expected ContainerID to carry the VM name, got %q", cs.ContainerID)
	}
}

func TestVNCRelayRequestedUsesHostControlFile(t *testing.T) {
	dir := t.TempDir()
	r := &Reconciler{VNCControlDir: dir}
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist-runners", Name: "runner-abc"}}

	requested, err := r.vncRelayRequested(pod)
	if err != nil {
		t.Fatalf("vncRelayRequested without file: %v", err)
	}
	if requested {
		t.Fatal("relay requested without host control file")
	}

	if err := os.MkdirAll(filepath.Join(dir, "requests"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(r.vncRequestPath(pod.Namespace, pod.Name), []byte{}, 0o600); err != nil {
		t.Fatal(err)
	}
	requested, err = r.vncRelayRequested(pod)
	if err != nil {
		t.Fatalf("vncRelayRequested with file: %v", err)
	}
	if !requested {
		t.Fatal("relay not requested despite host control file")
	}
}

func TestVNCRelayRequestedUsesPodAnnotation(t *testing.T) {
	r := &Reconciler{VNCControlDir: t.TempDir()}
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:   "tuist-runners",
			Name:        "runner-annotated",
			Annotations: map[string]string{vncSessionIDAnnotation: "123"},
		},
	}

	requested, err := r.vncRelayRequested(pod)
	if err != nil {
		t.Fatalf("vncRelayRequested with pod annotation: %v", err)
	}
	if !requested {
		t.Fatal("relay not requested despite server-owned pod annotation")
	}
}

func TestVNCCapableRunnerPodRequiresRunnerLabel(t *testing.T) {
	if vncCapableRunnerPod(&corev1.Pod{}) {
		t.Fatal("pod without runner label should not launch Tart VNC")
	}
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Labels: map[string]string{"tuist.dev/runner": "true"}}}
	if !vncCapableRunnerPod(pod) {
		t.Fatal("runner pod should launch Tart VNC")
	}
}

func TestVNCURLIncludesPassword(t *testing.T) {
	if got, want := vncURL("100.64.1.2", 49152, "secret-pass"), "vnc://:secret-pass@100.64.1.2:49152"; got != want {
		t.Fatalf("vncURL IPv4 = %q, want %q", got, want)
	}
	if got, want := vncURL("fd7a:115c:a1e0::1", 49152, "secret-pass"), "vnc://:secret-pass@[fd7a:115c:a1e0::1]:49152"; got != want {
		t.Fatalf("vncURL IPv6 = %q, want %q", got, want)
	}
}

func TestWriteVNCStateUsesHostControlStateAndRemovesItOnStop(t *testing.T) {
	dir := t.TempDir()
	r := &Reconciler{NodeIP: "127.0.0.1", VNCControlDir: dir}
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist-runners", Name: "runner-abc"}}

	fw, err := NewTCPForwarder("127.0.0.1:0", func() (string, error) {
		return "127.0.0.1:5901", nil
	}, TCPForwarderOptions{})
	if err != nil {
		t.Fatalf("NewTCPForwarder: %v", err)
	}
	entry := &Entry{VMName: "vm-runner-abc", VNCForwarder: fw}

	if err := r.writeVNCState(context.Background(), pod, entry, tart.VNCInfo{Host: "127.0.0.1", Port: 5901, Password: "secret-pass"}); err != nil {
		t.Fatalf("writeVNCState: %v", err)
	}

	statePath := r.vncStatePath(pod.Namespace, pod.Name)
	info, err := os.Stat(statePath)
	if err != nil {
		t.Fatalf("stat VNC state: %v", err)
	}
	if got, want := info.Mode().Perm(), os.FileMode(0o600); got != want {
		t.Fatalf("state mode = %v, want %v", got, want)
	}

	var state vncRelayState
	body, err := os.ReadFile(statePath)
	if err != nil {
		t.Fatalf("read VNC state: %v", err)
	}
	if err := json.Unmarshal(body, &state); err != nil {
		t.Fatalf("unmarshal VNC state: %v", err)
	}
	tcpAddr := fw.Addr().(*net.TCPAddr)
	if got, want := state.RelayURL, vncURL("127.0.0.1", tcpAddr.Port, "secret-pass"); got != want {
		t.Fatalf("relay_url = %q, want %q", got, want)
	}

	r.stopVNCForwarder(pod.Namespace, pod.Name, entry)
	if _, err := os.Stat(statePath); !os.IsNotExist(err) {
		t.Fatalf("state file still exists after stop: %v", err)
	}
}

func TestWriteVNCStatePatchesServerRelayAnnotations(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:   "tuist-runners",
			Name:        "runner-annotated",
			Annotations: map[string]string{vncSessionIDAnnotation: "123"},
		},
	}
	kubeClient := newPodTestClient(t, pod)
	r := &Reconciler{CachedClient: kubeClient, NodeIP: "127.0.0.1", VNCControlDir: dir}

	fw, err := NewTCPForwarder("127.0.0.1:0", func() (string, error) {
		return "127.0.0.1:5901", nil
	}, TCPForwarderOptions{})
	if err != nil {
		t.Fatalf("NewTCPForwarder: %v", err)
	}
	defer fw.Stop()

	entry := &Entry{VMName: "vm-runner-annotated", VNCForwarder: fw}
	storedPod := getPod(t, ctx, kubeClient, types.NamespacedName{Namespace: "tuist-runners", Name: "runner-annotated"})

	if err := r.writeVNCState(ctx, storedPod, entry, tart.VNCInfo{Host: "127.0.0.1", Port: 5901, Password: "secret-pass"}); err != nil {
		t.Fatalf("writeVNCState: %v", err)
	}

	updatedPod := getPod(t, ctx, kubeClient, types.NamespacedName{Namespace: "tuist-runners", Name: "runner-annotated"})
	tcpAddr := fw.Addr().(*net.TCPAddr)
	if got, want := updatedPod.Annotations[vncStateAnnotation], "ready"; got != want {
		t.Fatalf("state annotation = %q, want %q", got, want)
	}
	if got, want := updatedPod.Annotations[vncRelayHostAnnotation], "127.0.0.1"; got != want {
		t.Fatalf("relay host annotation = %q, want %q", got, want)
	}
	if got, want := updatedPod.Annotations[vncRelayPortAnnotation], strconv.Itoa(tcpAddr.Port); got != want {
		t.Fatalf("relay port annotation = %q, want %q", got, want)
	}
	if updatedPod.Annotations[vncRelayReadyAtAnnotation] == "" {
		t.Fatal("missing relay ready timestamp annotation")
	}
}

func newPodTestClient(t *testing.T, objects ...runtime.Object) client.Client {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatalf("add core scheme: %v", err)
	}
	return fake.NewClientBuilder().WithScheme(scheme).WithRuntimeObjects(objects...).Build()
}

func assertPodDeleted(t *testing.T, ctx context.Context, kubeClient client.Client, name types.NamespacedName) {
	t.Helper()
	pod := &corev1.Pod{}
	if err := kubeClient.Get(ctx, name, pod); !apierrors.IsNotFound(err) {
		t.Fatalf("pod still exists: %v", err)
	}
}

func getPod(t *testing.T, ctx context.Context, kubeClient client.Client, name types.NamespacedName) *corev1.Pod {
	t.Helper()
	pod := &corev1.Pod{}
	if err := kubeClient.Get(ctx, name, pod); err != nil {
		t.Fatalf("get pod: %v", err)
	}
	return pod
}
