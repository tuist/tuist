package controllers

import (
	"context"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// A Pending pod retains its old reservation after the StatefulSet template
// shrinks. The ordered readiness gate can prevent replacement indefinitely.
// Recreate only unscheduled pods after publishing the smaller template; serving
// replicas follow the ordinary rolling update and retain their cache volumes.
func (r *KuraInstanceReconciler) replacePendingPodsForStorageDecrease(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	desired := storageQuantity(instance)
	if desired.IsZero() {
		return nil
	}
	sts := &appsv1.StatefulSet{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		return err
	}
	if sts.Spec.UpdateStrategy.Type == appsv1.OnDeleteStatefulSetStrategyType ||
		(sts.Spec.UpdateStrategy.RollingUpdate != nil && sts.Spec.UpdateStrategy.RollingUpdate.Partition != nil && *sts.Spec.UpdateStrategy.RollingUpdate.Partition > 0) {
		return nil
	}
	// Reconciliation may read through a stale cache. Never delete a pod until
	// the observed template will recreate it with the intended reservation.
	templateMatches := false
	for _, container := range sts.Spec.Template.Spec.Containers {
		if container.Name == "kura" {
			request := container.Resources.Requests[corev1.ResourceEphemeralStorage]
			templateMatches = request.Cmp(desired) == 0
		}
	}
	if !templateMatches {
		return nil
	}
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
		return err
	}
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.DeletionTimestamp != nil || pod.Spec.NodeName != "" || pod.Status.Phase != corev1.PodPending || podReady(pod) {
			continue
		}
		for _, container := range pod.Spec.Containers {
			request := container.Resources.Requests[corev1.ResourceEphemeralStorage]
			if container.Name != "kura" || request.Cmp(desired) <= 0 {
				continue
			}
			// Do not delete a pod that the scheduler bound after the observation.
			err := r.Delete(ctx, pod, &client.DeleteOptions{Preconditions: &metav1.Preconditions{UID: &pod.UID, ResourceVersion: &pod.ResourceVersion}})
			if err != nil && !apierrors.IsNotFound(err) {
				return err
			}
			log.FromContext(ctx).Info("replacing unscheduled Kura pod after storage decrease", "pod", pod.Name, "from", request.String(), "to", desired.String())
			break
		}
	}
	return nil
}
