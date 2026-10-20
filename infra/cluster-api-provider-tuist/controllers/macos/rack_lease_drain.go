package macos

import (
	"context"
	"sort"
	"strings"

	"golang.org/x/crypto/ssh"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
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
