package controllers

import (
	"context"
	"fmt"
	"sort"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const (
	// EvacuateNodeAnnotation marks a node whose cache pods should be moved off
	// it, one replica at a time, before it is retired.
	//
	// Deliberately an explicit marker rather than the node's cordon, which is
	// what the runner fleet keys its equivalent off. Reaping an idle runner
	// poller on a cordoned node is free, so reacting to any cordon is safe
	// there. Moving a cache pod is not free: it destroys a node-local volume and
	// makes its replacement refill from a peer. An operator who cordons a box to
	// look at something should not thereby spend a region's warm cache.
	EvacuateNodeAnnotation = "tuist.dev/kura-evacuate"

	// backfillCycleComplete is the value the runtime reports on /status/rollout
	// once a pod's initial peer catch-up has settled. Readiness is NOT a
	// substitute: a pod latches ready at a ring-fullness threshold or when the
	// cycle settles, so a ready pod can still be filling, or be cold on an empty
	// volume. Promoting on readiness alone is what turns a warm move into a cold
	// one.
	backfillCycleComplete = "complete"
)

// evacuateMarkedNodes moves this instance's pods off nodes marked for
// evacuation, one at a time, and reports whether it is still working.
//
// This exists because a cache box cannot be retired in place. Its PVs are
// local-path directories pinned to that host, so a pod cannot follow its volume
// anywhere; the volume has to be abandoned and rebuilt on another box. Doing
// that by hand is a sequence with three ways to go wrong, and it comes up on
// every hardware conversion, every offer change, and every reprovision:
//
//   - Move both replicas at once and the instance has no serving pod at all.
//   - Move the primary first and traffic lands on a pod with an empty volume.
//   - Move the next replica before the last one caught up and the peer it would
//     have refilled from is gone, so the region is cold whatever order was used.
//
// The sequence here closes all three: at most one replica moves per pass, the
// primary moves last, and the next move waits for the previous pod to report a
// completed catch-up rather than merely being ready. One pass runs per
// reconcile, so the reconciler's own requeue is what paces the sequence.
//
// It deliberately does nothing when there is nowhere to land. Evacuating the
// only remaining node turns a working box into a set of Pending pods and an
// unreachable region, which is strictly worse than the box staying up until its
// replacement joins the pool.
func (r *KuraInstanceReconciler) evacuateMarkedNodes(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	logger := log.FromContext(ctx)

	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
		return err
	}
	if len(pods.Items) == 0 {
		return nil
	}

	nodes := &corev1.NodeList{}
	if err := r.List(ctx, nodes); err != nil {
		return err
	}

	leaving := map[string]bool{}
	for i := range nodes.Items {
		if _, marked := nodes.Items[i].Annotations[EvacuateNodeAnnotation]; marked {
			leaving[nodes.Items[i].Name] = true
		}
	}

	stranded := podsOnNodes(pods.Items, leaving)
	if len(stranded) == 0 {
		return nil
	}

	if !hasLandingNode(nodes.Items, leaving, instance) {
		logger.Info("cache pods sit on a node marked for evacuation but no other node can take them; leaving them in place",
			"instance", instance.Name, "pods", len(stranded))
		return nil
	}

	// Anything already moved has to be serving AND caught up before the next
	// replica goes, or the move that follows destroys the peer it would have
	// refilled from.
	if settling, reason := r.movesStillSettling(ctx, pods.Items, leaving); settling {
		logger.V(1).Info("waiting for the previous move to settle before evacuating another replica",
			"instance", instance.Name, "reason", reason)
		return nil
	}

	primary, err := r.selectPrimaryPod(ctx, instance)
	if err != nil {
		return err
	}

	next := nextPodToEvacuate(stranded, primary)
	if next == nil {
		return nil
	}

	if err := r.releaseNodeLocalVolume(ctx, next); err != nil {
		return err
	}
	logger.Info("evacuating a cache pod off a node marked for retirement",
		"instance", instance.Name, "pod", next.Name, "node", next.Spec.NodeName, "wasPrimary", next.Name == primary)
	return nil
}

// podsOnNodes returns the pods sitting on any of the given nodes, ordered by
// name so a pass picks the same pod every time it runs against the same state.
func podsOnNodes(pods []corev1.Pod, nodes map[string]bool) []*corev1.Pod {
	out := []*corev1.Pod{}
	for i := range pods {
		if pods[i].DeletionTimestamp != nil {
			continue
		}
		if nodes[pods[i].Spec.NodeName] {
			out = append(out, &pods[i])
		}
	}
	sort.Slice(out, func(a, b int) bool { return out[a].Name < out[b].Name })
	return out
}

// hasLandingNode reports whether some node that is not being evacuated could
// actually take this instance's pods: Ready, schedulable, and matching whatever
// nodeSelector pins the instance to its region's pool.
func hasLandingNode(nodes []corev1.Node, leaving map[string]bool, instance *kurav1alpha1.KuraInstance) bool {
	for i := range nodes {
		node := &nodes[i]
		if leaving[node.Name] || node.Spec.Unschedulable || node.DeletionTimestamp != nil {
			continue
		}
		if !nodeReady(node) {
			continue
		}
		matches := true
		for key, value := range instance.Spec.NodeSelector {
			if node.Labels[key] != value {
				matches = false
				break
			}
		}
		if matches {
			return true
		}
	}
	return false
}

func nodeReady(node *corev1.Node) bool {
	for _, condition := range node.Status.Conditions {
		if condition.Type == corev1.NodeReady {
			return condition.Status == corev1.ConditionTrue
		}
	}
	return false
}

// movesStillSettling reports whether a previously moved replica has yet to
// finish, and why.
//
// The catch-up signal is the runtime's, not Kubernetes'. A pod latches ready at
// a ring-fullness threshold or when its initial backfill cycle settles, and a
// cycle settles even when a peer stays unreachable, so a ready pod can still be
// filling or be cold on an empty volume. `backfill_initial_cycle` is the
// completeness report (see the region-move note in kura/README.md), and gating
// on it is the difference between a warm handover and a cold one.
//
// When the runtime status cannot be read at all, this reports settling rather
// than proceeding. An unreachable pod is not evidence that a move finished, and
// guessing wrong costs the region's cache rather than a requeue.
func (r *KuraInstanceReconciler) movesStillSettling(ctx context.Context, pods []corev1.Pod, leaving map[string]bool) (bool, string) {
	statusClient := r.RuntimeStatusClient
	if statusClient == nil {
		statusClient = defaultRuntimeStatusClient()
	}

	for i := range pods {
		pod := &pods[i]
		if leaving[pod.Spec.NodeName] {
			// Still on its way out; it is what this pass exists to move.
			continue
		}
		if pod.DeletionTimestamp != nil {
			return true, fmt.Sprintf("pod %s is terminating", pod.Name)
		}
		if !podReady(pod) {
			return true, fmt.Sprintf("pod %s is not ready yet", pod.Name)
		}
		status, err := statusClient.Status(ctx, *pod)
		if err != nil {
			return true, fmt.Sprintf("pod %s rollout status unreadable: %v", pod.Name, err)
		}
		if status.BackfillInitialCycle != backfillCycleComplete {
			return true, fmt.Sprintf("pod %s has not finished catching up (backfill_initial_cycle=%q)", pod.Name, status.BackfillInitialCycle)
		}
	}
	return false, ""
}

// nextPodToEvacuate picks the replica to move, preferring anything that is not
// currently serving traffic. The primary moves last so the region keeps a
// serving pod throughout, and by the time it is the only one left the standby
// has already landed elsewhere and caught up.
func nextPodToEvacuate(stranded []*corev1.Pod, primary string) *corev1.Pod {
	for _, pod := range stranded {
		if pod.Name != primary {
			return pod
		}
	}
	if len(stranded) > 0 {
		return stranded[0]
	}
	return nil
}

// releaseNodeLocalVolume frees a pod from its node by deleting its claim and
// then the pod itself.
//
// The order is load-bearing. A local-path PV carries a hostname affinity to the
// box that carved it, so a pod deleted on its own is rescheduled straight back
// onto the same node by the still-bound claim. Deleting the claim first leaves
// it Terminating under `pvc-protection` until the pod releases it, so the pair
// goes away together and the StatefulSet provisions a fresh volume wherever the
// replacement lands.
func (r *KuraInstanceReconciler) releaseNodeLocalVolume(ctx context.Context, pod *corev1.Pod) error {
	claim := &corev1.PersistentVolumeClaim{}
	claim.SetName(fmt.Sprintf("data-%s", pod.Name))
	claim.SetNamespace(pod.Namespace)
	if err := r.Delete(ctx, claim); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete claim for pod %s: %w", pod.Name, err)
	}
	if err := r.Delete(ctx, pod); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete pod %s: %w", pod.Name, err)
	}
	return nil
}

// kuraInstancesForNode enqueues the instances with pods on a node, so marking a
// box for evacuation starts the moves without waiting for a resync.
func (r *KuraInstanceReconciler) kuraInstancesForNode(ctx context.Context, object client.Object) []ctrl.Request {
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods); err != nil {
		return nil
	}
	seen := map[string]bool{}
	requests := []ctrl.Request{}
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Spec.NodeName != object.GetName() {
			continue
		}
		if pod.Labels["app.kubernetes.io/name"] != "kura" {
			continue
		}
		instance := pod.Labels["app.kubernetes.io/instance"]
		if instance == "" || seen[pod.Namespace+"/"+instance] {
			continue
		}
		seen[pod.Namespace+"/"+instance] = true
		requests = append(requests, ctrl.Request{NamespacedName: client.ObjectKey{Namespace: pod.Namespace, Name: instance}})
	}
	return requests
}
