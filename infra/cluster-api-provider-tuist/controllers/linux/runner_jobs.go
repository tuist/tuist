package linux

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const (
	runnerPodNamespace        = "tuist-runners"
	runnerPodLabel            = "tuist.dev/runner"
	runnerJobsRecheckInterval = 30 * time.Second
)

// holdReleaseForRunnerJobs cordons the box's Node and returns the runner Pods
// on it still running a CI job. Cluster API never drains Machines in these
// clusters (they have no control plane Machines), so this is the runner
// fleet's drain: job Pods are waited on, never evicted, and the
// runners-controller retires idle runner Pods once the Node is cordoned. A
// terminating Pod on an unreachable Node is not waited on, since its kubelet
// can never confirm it.
func holdReleaseForRunnerJobs(ctx context.Context, c client.Client, nodeName string) ([]string, error) {
	node := &corev1.Node{}
	if err := c.Get(ctx, types.NamespacedName{Name: nodeName}, node); err != nil {
		if apierrors.IsNotFound(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("get Node %s: %w", nodeName, err)
	}
	if !node.Spec.Unschedulable {
		base := node.DeepCopy()
		node.Spec.Unschedulable = true
		if err := c.Patch(ctx, node, client.MergeFrom(base)); err != nil {
			return nil, fmt.Errorf("cordon Node %s: %w", nodeName, err)
		}
	}

	pods := &corev1.PodList{}
	if err := c.List(ctx, pods, client.InNamespace(runnerPodNamespace), client.MatchingLabels{runnerPodLabel: "true"}); err != nil {
		return nil, fmt.Errorf("list runner Pods: %w", err)
	}
	unreachable := nodeUnreachable(node)
	var running []string
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Spec.NodeName != nodeName || pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed {
			continue
		}
		if unreachable && pod.DeletionTimestamp != nil {
			continue
		}
		running = append(running, pod.Name)
	}
	sort.Strings(running)
	return running, nil
}

func releaseHeldMessage(nodeName string, running []string) string {
	shown := running
	if len(shown) > 5 {
		shown = shown[:5]
	}
	return fmt.Sprintf("Node %s is cordoned; the release waits for %d runner job(s) to finish: %s",
		nodeName, len(running), strings.Join(shown, ", "))
}

func nodeUnreachable(node *corev1.Node) bool {
	for _, cond := range node.Status.Conditions {
		if cond.Type == corev1.NodeReady {
			return cond.Status == corev1.ConditionUnknown
		}
	}
	return false
}
