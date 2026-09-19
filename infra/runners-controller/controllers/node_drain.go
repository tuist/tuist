package controllers

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

// reapIdlePodsOnCordonedNodes retires warm-pool Pods sitting on a node
// that is on its way out, and is one half of making a node replacement
// safe for customer jobs. The other half is the `MachineDrainRule` in
// `infra/k8s/clusters/machinedrainrules.yaml`, which sets
// `behavior: WaitCompleted` for runner Pods so Cluster API waits for
// them to finish instead of evicting them.
//
// That drain rule alone would never converge. A runner Pod is
// single-shot, so a Pod running a job reaches a terminal phase on its
// own and satisfies `WaitCompleted` — but an *idle* Pod is a dispatch
// poller with nothing to finish. It polls for as long as it exists, so
// `WaitCompleted` would wait on it forever and the drain would never
// complete. Nothing else clears it either: the cordon stops new Pods
// landing but does not remove the ones already bound.
//
// So the controller retires them here. An idle Pod is pure warm
// capacity — no customer work is attached to it — so deleting it costs
// nothing beyond a cold start, and the autoscaler replaces it on a node
// that can still accept Pods. What remains on the draining node is only
// Pods running jobs, each of which completes on its own, at which point
// the drain finishes and Cluster API deletes the Machine.
//
// Idleness is read through `isIdle`, deliberately not through the
// `tuist.dev/runner-pool-owner` label. A `PodDisruptionBudget` could
// only select on labels, and that label is best-effort: the server
// degrades to running a job without it rather than dropping the job
// when the apiserver patch fails. `isIdle` also accepts a terminated
// `poller` init container as proof of a claim, which is the signal that
// holds when the label stamp did not land — so a Pod running a job is
// never reaped here even if it carries no owner label.
//
// Returns the Pods that survived, so the caller's accounting excludes
// what was just deleted rather than counting Pods that no longer exist.
func (r *RunnerPoolReconciler) reapIdlePodsOnCordonedNodes(
	ctx context.Context,
	pods []corev1.Pod,
) ([]corev1.Pod, int, error) {
	logger := log.FromContext(ctx)

	// Nodes are read once each: a pool's Pods concentrate on a handful
	// of nodes, and a drain reconciles repeatedly while it waits.
	draining := map[string]bool{}
	kept := make([]corev1.Pod, 0, len(pods))
	reaped := 0

	for i := range pods {
		pod := pods[i]

		nodeName := pod.Spec.NodeName
		if nodeName == "" || !isAlive(&pod) || !isIdle(&pod) {
			kept = append(kept, pod)
			continue
		}

		isDraining, ok := draining[nodeName]
		if !ok {
			var err error
			isDraining, err = r.nodeIsDraining(ctx, nodeName)
			if err != nil {
				return nil, reaped, err
			}
			draining[nodeName] = isDraining
		}
		if !isDraining {
			kept = append(kept, pod)
			continue
		}

		logger.Info("retire idle runner pod on a draining node",
			"pod", pod.Name,
			"node", nodeName,
		)
		if r.Recorder != nil {
			r.Recorder.Eventf(&pod, corev1.EventTypeNormal, "RunnerPodRetiredForNodeDrain",
				"Node %s is draining; retiring this idle runner so the drain can finish. "+
					"Runners executing a job are left to complete.",
				nodeName)
		}
		if err := r.reapRunner(ctx, &pod); err != nil {
			return nil, reaped, fmt.Errorf("reap idle pod on draining node %s: %w", nodeName, err)
		}
		reaped++
	}

	return kept, reaped, nil
}

// drainingNodePredicate narrows Node events to nodes that are on their
// way out. A runner fleet's nodes are otherwise noisy — kubelet updates
// status every few seconds — and the steady-state reconcile already
// covers everything else.
func drainingNodePredicate() predicate.Predicate {
	return predicate.NewPredicateFuncs(func(obj client.Object) bool {
		node, ok := obj.(*corev1.Node)
		if !ok {
			return false
		}
		return node.Spec.Unschedulable || !node.DeletionTimestamp.IsZero()
	})
}

// enqueueAllRunnerPools fans a Node event out to every RunnerPool. The
// Pod-to-pool direction is not indexed, and a node hosts Pods from any
// pool sharing its fleet selector, so narrowing here would mean either
// an index or a list of that node's Pods per event. Pools number in the
// handful and the predicate above keeps these events rare, so the fan-out
// is cheaper than either.
//
// Without this watch a cordon waits for the 60-second steady-state
// requeue before idle Pods are retired, and that delay is added to every
// node replacement — the drain cannot finish until the reap has run.
func (r *RunnerPoolReconciler) enqueueAllRunnerPools(ctx context.Context, _ client.Object) []reconcile.Request {
	pools := &tuistv1.RunnerPoolList{}
	if err := r.List(ctx, pools); err != nil {
		log.FromContext(ctx).Error(err, "list runner pools for a node event")
		return nil
	}
	requests := make([]reconcile.Request, 0, len(pools.Items))
	for i := range pools.Items {
		requests = append(requests, reconcile.Request{
			NamespacedName: client.ObjectKeyFromObject(&pools.Items[i]),
		})
	}
	return requests
}

// nodeIsDraining reports whether a node is being taken out of service:
// cordoned, or already marked for deletion. Cluster API cordons before
// it drains, so `spec.unschedulable` is the signal that a Machine
// replacement has started.
//
// A node that cannot be read is reported as not draining. Reaping is
// destructive and an unreadable node is ambiguous — a transient read
// failure must not be able to retire warm capacity fleet-wide. A Pod
// whose node has genuinely disappeared is handled by the orphan paths,
// not here.
func (r *RunnerPoolReconciler) nodeIsDraining(ctx context.Context, name string) (bool, error) {
	node := &corev1.Node{}
	if err := r.Get(ctx, client.ObjectKey{Name: name}, node); err != nil {
		if apierrors.IsNotFound(err) {
			return false, nil
		}
		return false, fmt.Errorf("get node %s: %w", name, err)
	}
	return node.Spec.Unschedulable || !node.DeletionTimestamp.IsZero(), nil
}
