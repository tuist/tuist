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

// A bare-metal node advertises its egress budget as tuist.dev/egress-mbps
// capacity without clobbering the kubelet-managed resources, idempotently; a
// cloud node (zero budget) advertises nothing so its cache pods don't pend.
func TestReconcileNodeEgressCapacity(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatalf("add scheme: %v", err)
	}

	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-node"},
		Status:     corev1.NodeStatus{Capacity: corev1.ResourceList{corev1.ResourceCPU: resource.MustParse("8")}},
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(node).WithStatusSubresource(node).Build()

	if err := ReconcileNodeEgressCapacity(context.Background(), c, node, 3000); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	got := &corev1.Node{}
	if err := c.Get(context.Background(), types.NamespacedName{Name: "kura-node"}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	if q := got.Status.Capacity[EgressMbpsResource]; q.Value() != 3000 {
		t.Fatalf("egress capacity = %d, want 3000", q.Value())
	}
	if _, ok := got.Status.Capacity[corev1.ResourceCPU]; !ok {
		t.Fatalf("kubelet-managed cpu capacity must be preserved")
	}

	// Idempotent: re-applying the same value is a no-op, not an error.
	if err := ReconcileNodeEgressCapacity(context.Background(), c, got, 3000); err != nil {
		t.Fatalf("idempotent reconcile: %v", err)
	}

	cloud := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "cloud-node"}}
	cc := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cloud).WithStatusSubresource(cloud).Build()
	if err := ReconcileNodeEgressCapacity(context.Background(), cc, cloud, 0); err != nil {
		t.Fatalf("zero-budget reconcile: %v", err)
	}
	got2 := &corev1.Node{}
	if err := cc.Get(context.Background(), types.NamespacedName{Name: "cloud-node"}, got2); err != nil {
		t.Fatalf("get cloud: %v", err)
	}
	if _, ok := got2.Status.Capacity[EgressMbpsResource]; ok {
		t.Fatalf("cloud node (zero budget) must not advertise egress capacity")
	}
}
