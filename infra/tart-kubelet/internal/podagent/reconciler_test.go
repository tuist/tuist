package podagent

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
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
