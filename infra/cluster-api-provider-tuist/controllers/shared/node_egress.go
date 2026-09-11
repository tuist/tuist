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

// NodeEgressMbps is the budget the node currently advertises, or 0 when it
// advertises none.
func NodeEgressMbps(node *corev1.Node) int32 {
	quantity, ok := node.Status.Capacity[EgressMbpsResource]
	if !ok {
		return 0
	}
	value, ok := quantity.AsInt64()
	if !ok || value <= 0 {
		return 0
	}
	return int32(value)
}

// ReconcileNodeEgressCapacity advertises mbps as the node's
// tuist.dev/egress-mbps extended-resource capacity, idempotently, and removes
// the capacity when mbps <= 0 (cloud nodes whose NIC isn't shared). Custom
// extended resources live in node status and must be set via the status
// subresource; a JSON merge patch adds or removes the key without disturbing
// the kubelet-managed cpu/memory/ephemeral-storage. Callers re-apply it on every
// reconcile so a kubelet re-registration that resets status can't strand it.
func ReconcileNodeEgressCapacity(ctx context.Context, c client.Client, node *corev1.Node, mbps int32) error {
	cur, present := node.Status.Capacity[EgressMbpsResource]
	if mbps <= 0 {
		if !present {
			return nil
		}
		patch := client.MergeFrom(node.DeepCopy())
		delete(node.Status.Capacity, EgressMbpsResource)
		return c.Status().Patch(ctx, node, patch)
	}
	want := *resource.NewQuantity(int64(mbps), resource.DecimalSI)
	if present && cur.Cmp(want) == 0 {
		return nil
	}
	patch := client.MergeFrom(node.DeepCopy())
	if node.Status.Capacity == nil {
		node.Status.Capacity = corev1.ResourceList{}
	}
	node.Status.Capacity[EgressMbpsResource] = want
	return c.Status().Patch(ctx, node, patch)
}
