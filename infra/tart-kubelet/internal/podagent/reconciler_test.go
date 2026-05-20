package podagent

import (
	"context"
	"testing"

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
