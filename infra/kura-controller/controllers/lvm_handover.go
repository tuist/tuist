package controllers

import (
	"context"
	"fmt"

	kurav1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const lvmRebuildAnnotation = "kura.tuist.dev/lvm-rebuild"

// Mark the departing pod before touching its volume. Primary and peer role
// selection consume this intent on the next pass; only observed endpoint
// handoff permits deletion. Existing connections get the normal pod drain.
func (r *KuraInstanceReconciler) lvmHandoverReady(ctx context.Context, instance *kurav1.KuraInstance, ordinal int32) (bool, error) {
	name := fmt.Sprintf("%s-%d", instance.Name, ordinal)
	pod := &corev1.Pod{}
	if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: name}, pod); err != nil {
		if apierrors.IsNotFound(err) {
			return true, nil
		}
		return false, err
	}
	if pod.Annotations[lvmRebuildAnnotation] == "" {
		before := pod.DeepCopy()
		if pod.Annotations == nil {
			pod.Annotations = map[string]string{}
		}
		pod.Annotations[lvmRebuildAnnotation] = "true"
		return false, r.Patch(ctx, pod, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
	}
	served, err := r.servedByAnotherPod(ctx, instance, name)
	if err != nil || !served {
		return false, err
	}
	return r.peerPlaneReleased(ctx, instance, name)
}
