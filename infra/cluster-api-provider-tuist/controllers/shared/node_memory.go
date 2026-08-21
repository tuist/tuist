package shared

import (
	"context"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// MemoryCeilingMibResource is the integer extended resource a shared bare-metal
// node advertises so the scheduler can bin-pack memory *ceilings*. The Kura
// cache pods request it (request == limit) via the matching string in the
// kura-controller; this is the capacity side.
const MemoryCeilingMibResource corev1.ResourceName = "tuist.dev/memory-ceiling-mib"

// MemoryCeilingOversubscription is how far the sum of pod memory ceilings on a
// box may exceed its allocatable memory.
//
// It exists because ceilings and floors answer different questions. A pod's
// floor (requests.memory) is a standing reservation the native bin-pack already
// keeps within allocatable, and once the kubelet runs with MemoryQoS it is also
// the pod's unreclaimable cgroup memory.min — so every pod is always guaranteed
// its floor. Everything a pod uses above its floor is best-effort, reclaimed by
// the kernel from whoever is furthest above their own floor when the box gets
// tight. Cache pods are idle most of the time and burst rarely and briefly, so
// letting those best-effort regions overlap is what makes dense packing pay.
//
// The factor bounds how badly they may overlap. Too low and the box is packed
// no denser than it would be with request == limit; too high and reclaim has
// more to claw back than it can, and the OOM killer arrives instead. Two keeps
// the worst case within what reclaim can absorb on the current fleet, whose
// nodes peak near a fifth of their physical memory.
const MemoryCeilingOversubscription = 2

// ReconcileNodeMemoryCeilingCapacity advertises the node's memory ceiling
// budget as tuist.dev/memory-ceiling-mib capacity, idempotently.
//
// Unlike the egress budget, which is a property of the box's NIC that
// Kubernetes cannot observe, this is derived from the node's own allocatable
// memory — allocatable already nets out the kubelet's system and kube
// reservations and its eviction threshold, so it is the honest denominator.
//
// No-op when the node reports no allocatable memory (it has not finished
// registering) or the capacity already matches. Custom extended resources live
// in node status and must be set via the status subresource; a JSON merge patch
// adds the key without disturbing the kubelet-managed cpu/memory. Callers
// re-apply it on every reconcile so a kubelet re-registration that resets
// status cannot strand it, and so the budget follows a node whose allocatable
// changes.
func ReconcileNodeMemoryCeilingCapacity(ctx context.Context, c client.Client, node *corev1.Node) error {
	allocatable, ok := node.Status.Allocatable[corev1.ResourceMemory]
	if !ok {
		return nil
	}
	mib := allocatable.Value() / (1024 * 1024) * MemoryCeilingOversubscription
	if mib <= 0 {
		return nil
	}
	want := *resource.NewQuantity(mib, resource.DecimalSI)
	if cur, ok := node.Status.Capacity[MemoryCeilingMibResource]; ok && cur.Cmp(want) == 0 {
		return nil
	}
	patch := client.MergeFrom(node.DeepCopy())
	if node.Status.Capacity == nil {
		node.Status.Capacity = corev1.ResourceList{}
	}
	node.Status.Capacity[MemoryCeilingMibResource] = want
	return c.Status().Patch(ctx, node, patch)
}
