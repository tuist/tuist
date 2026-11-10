package macos

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
)

// LeaseCordonAnnotation marks a cordon a lease placed, valued with the env the
// host is changing hands with. Written in the same patch as the cordon, so
// only a lease's cordon is ever lifted by one.
const LeaseCordonAnnotation = "tuist.dev/lease-cordon"

// ReclaimRuntimeAnnotation on a RackHost takes a lent host's runtime back
// without waiting for the borrower to release it: for a borrower that is gone.
// Whatever still runs on the host in the borrowing cluster is lost.
const ReclaimRuntimeAnnotation = "tuist.dev/reclaim-runtime"

// drainNodeForLease cordons the Node, marking the cordon as the lease's, and
// returns the pods still running work on it. A Node that is gone holds nothing.
// A cordon someone else placed is kept as it is.
func drainNodeForLease(ctx context.Context, c client.Client, name, env string) ([]string, error) {
	node := &corev1.Node{}
	if err := c.Get(ctx, types.NamespacedName{Name: name}, node); err != nil {
		if apierrors.IsNotFound(err) {
			return nil, nil
		}
		return nil, err
	}
	if !node.Spec.Unschedulable {
		base := node.DeepCopy()
		node.Spec.Unschedulable = true
		metav1.SetMetaDataAnnotation(&node.ObjectMeta, LeaseCordonAnnotation, env)
		if err := c.Patch(ctx, node, client.MergeFrom(base)); err != nil {
			return nil, err
		}
	}
	return activePodsOnNode(ctx, c, name)
}

// uncordonNodeAfterLease lifts a cordon a lease placed, and no other.
func uncordonNodeAfterLease(ctx context.Context, c client.Client, name string) error {
	node := &corev1.Node{}
	if err := c.Get(ctx, types.NamespacedName{Name: name}, node); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return err
	}
	if _, marked := node.Annotations[LeaseCordonAnnotation]; !marked {
		return nil
	}
	base := node.DeepCopy()
	node.Spec.Unschedulable = false
	delete(node.Annotations, LeaseCordonAnnotation)
	return c.Patch(ctx, node, client.MergeFrom(base))
}

// activePodsOnNode lists the pods still running work on the Node: neither
// finished, nor a mirror pod, nor a DaemonSet's.
func activePodsOnNode(ctx context.Context, c client.Reader, nodeName string) ([]string, error) {
	pods := &corev1.PodList{}
	if err := c.List(ctx, pods); err != nil {
		return nil, err
	}
	var active []string
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Spec.NodeName != nodeName || pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed {
			continue
		}
		if _, mirror := pod.Annotations[corev1.MirrorPodAnnotationKey]; mirror {
			continue
		}
		if owner := metav1.GetControllerOf(pod); owner != nil && owner.Kind == "DaemonSet" {
			continue
		}
		active = append(active, pod.Namespace+"/"+pod.Name)
	}
	sort.Strings(active)
	return active, nil
}

// leaseKeyFingerprint is the SHA-256 fingerprint of an authorized_keys line,
// empty for one that does not parse.
func leaseKeyFingerprint(key string) string {
	pub, _, _, _, err := ssh.ParseAuthorizedKey([]byte(strings.TrimSpace(key)))
	if err != nil {
		return ""
	}
	return ssh.FingerprintSHA256(pub)
}

// What tart-kubelet publishes on a runner Pod (the runners-controller's
// guestHeartbeatStateAnnotation): `polling` while the guest waits for a job,
// `claimed` once it has one. And the finalizer it holds a runner Pod with
// until it has deleted the Pod's VM.
const (
	runnerHeartbeatStateAnnotation = "tuist.dev/runner-heartbeat-state"
	runnerHeartbeatPolling         = "polling"
	vmCleanupFinalizer             = "tart-kubelet.tuist.dev/vm-cleanup"
)

// deadNodeGrace is how long a Node's tart-kubelet has to have stopped
// reporting before its Pods count as stranded: past a restart, a drift push
// and the node-monitor grace.
const deadNodeGrace = 10 * time.Minute

// strandedRunners returns the warm runners on a Node whose tart-kubelet is
// gone: polling for a job, with no job, when the Node stopped reporting more
// than deadNodeGrace ago. Nothing can finish them, since their finalizer waits
// for that tart-kubelet, and nothing is lost when they go. A runner that had
// claimed a job is not one: its VM may still be running the job.
func strandedRunners(ctx context.Context, c client.Client, nodeName string, now time.Time) (map[string]*corev1.Pod, error) {
	node := &corev1.Node{}
	if err := c.Get(ctx, types.NamespacedName{Name: nodeName}, node); err != nil {
		return nil, client.IgnoreNotFound(err)
	}
	if !nodeGoneSince(node, now.Add(-deadNodeGrace)) {
		return nil, nil
	}
	pods := &corev1.PodList{}
	if err := c.List(ctx, pods); err != nil {
		return nil, err
	}
	stranded := map[string]*corev1.Pod{}
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Spec.NodeName == nodeName && pod.Annotations[runnerHeartbeatStateAnnotation] == runnerHeartbeatPolling {
			stranded[pod.Namespace+"/"+pod.Name] = pod
		}
	}
	return stranded, nil
}

// nodeGoneSince reports a Node that is not Ready and last heard from before.
func nodeGoneSince(node *corev1.Node, before time.Time) bool {
	for _, cond := range node.Status.Conditions {
		if cond.Type != corev1.NodeReady {
			continue
		}
		if cond.Status == corev1.ConditionTrue {
			return false
		}
		heard := cond.LastHeartbeatTime.Time
		if heard.IsZero() {
			heard = cond.LastTransitionTime.Time
		}
		return !heard.IsZero() && heard.Before(before)
	}
	return false
}

// releaseStrandedRunners lets go of stranded runner Pods once the host has a
// tart-kubelet again, whose orphan-VM collector deletes their VMs.
func releaseStrandedRunners(ctx context.Context, c client.Client, pods map[string]*corev1.Pod) error {
	for _, pod := range pods {
		base := pod.DeepCopy()
		if controllerutil.RemoveFinalizer(pod, vmCleanupFinalizer) {
			if err := c.Patch(ctx, pod, client.MergeFrom(base)); err != nil && !apierrors.IsNotFound(err) {
				return fmt.Errorf("release stranded runner %s/%s: %w", pod.Namespace, pod.Name, err)
			}
		}
		if err := c.Delete(ctx, pod, client.GracePeriodSeconds(0)); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete stranded runner %s/%s: %w", pod.Namespace, pod.Name, err)
		}
	}
	return nil
}
