package shared

import (
	"context"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// EgressMbpsResource is the integer extended resource a shared bare-metal node
// advertises so the scheduler can bin-pack egress-floored workloads against the
// box's budget. The Kura cache pods request it (request == limit) via the
// matching string in the kura-controller; this is the capacity side.
const EgressMbpsResource corev1.ResourceName = "tuist.dev/egress-mbps"

// ReconcileNodeEgressCapacity advertises mbps as the node's
// tuist.dev/egress-mbps extended-resource capacity, idempotently. No-op when
// mbps <= 0 (cloud nodes whose NIC isn't shared) or the capacity already
// matches. Custom extended resources live in node status and must be set via the
// status subresource; a JSON merge patch adds the key without disturbing the
// kubelet-managed cpu/memory/ephemeral-storage. Callers re-apply it on every
// reconcile so a kubelet re-registration that resets status can't strand it.
func ReconcileNodeEgressCapacity(ctx context.Context, c client.Client, node *corev1.Node, mbps int32) error {
	if mbps <= 0 {
		return nil
	}
	want := *resource.NewQuantity(int64(mbps), resource.DecimalSI)
	if cur, ok := node.Status.Capacity[EgressMbpsResource]; ok && cur.Cmp(want) == 0 {
		return nil
	}
	patch := client.MergeFrom(node.DeepCopy())
	if node.Status.Capacity == nil {
		node.Status.Capacity = corev1.ResourceList{}
	}
	node.Status.Capacity[EgressMbpsResource] = want
	return c.Status().Patch(ctx, node, patch)
}
