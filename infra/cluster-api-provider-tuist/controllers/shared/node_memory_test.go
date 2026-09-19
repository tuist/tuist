package shared

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

// A bare-metal node advertises a bounded memory ceiling budget derived from its
// own allocatable memory, without clobbering the kubelet-managed resources, and
// idempotently.
func TestReconcileNodeMemoryCeilingCapacity(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatalf("add scheme: %v", err)
	}

	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-node"},
		Status: corev1.NodeStatus{
			Capacity: corev1.ResourceList{corev1.ResourceCPU: resource.MustParse("8")},
			Allocatable: corev1.ResourceList{
				corev1.ResourceMemory: resource.MustParse("30Gi"),
			},
		},
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(node).WithStatusSubresource(node).Build()

	if err := ReconcileNodeMemoryCeilingCapacity(context.Background(), c, node); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	got := &corev1.Node{}
	if err := c.Get(context.Background(), types.NamespacedName{Name: "kura-node"}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	want := int64(30*1024) * MemoryCeilingOversubscription
	if q := got.Status.Capacity[MemoryCeilingMibResource]; q.Value() != want {
		t.Fatalf("memory ceiling capacity = %d, want %d", q.Value(), want)
	}
	if _, ok := got.Status.Capacity[corev1.ResourceCPU]; !ok {
		t.Fatalf("kubelet-managed cpu capacity must be preserved")
	}

	// Idempotent: re-applying the same value is a no-op, not an error.
	if err := ReconcileNodeMemoryCeilingCapacity(context.Background(), c, got); err != nil {
		t.Fatalf("idempotent reconcile: %v", err)
	}

	// The budget must stay above allocatable, or ceilings would bin-pack no
	// denser than floors already do and the oversubscription would buy nothing.
	allocatableMib := int64(30 * 1024)
	if want <= allocatableMib {
		t.Fatalf("ceiling budget %d must exceed allocatable %d MiB", want, allocatableMib)
	}
}

// A node that has not finished registering reports no allocatable memory.
// Advertising a zero budget there would make every cache pod unschedulable, so
// the reconciler waits instead.
func TestReconcileNodeMemoryCeilingCapacitySkipsUnregisteredNode(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatalf("add scheme: %v", err)
	}

	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "fresh-node"}}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(node).WithStatusSubresource(node).Build()

	if err := ReconcileNodeMemoryCeilingCapacity(context.Background(), c, node); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	got := &corev1.Node{}
	if err := c.Get(context.Background(), types.NamespacedName{Name: "fresh-node"}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	if _, ok := got.Status.Capacity[MemoryCeilingMibResource]; ok {
		t.Fatalf("a node with no allocatable memory must not advertise a ceiling budget")
	}
}
