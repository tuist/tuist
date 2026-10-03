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

// resizeRolloutHoldAnnotation marks an OnDelete strategy that a data volume
// resize set, as distinct from one an operator chose to pause an incident. Only
// a marked hold is lifted by the controller.
const resizeRolloutHoldAnnotation = "kura.tuist.dev/resize-rollout-hold"

// A grown claim is replaced one ordinal at a time, and while a rebuilt replica
// is not serving yet, its sibling is the only one that is. With parallel pod
// management a RollingUpdate deletes the highest stale ordinal whether or not
// the others are ready, so any template change in that window restarts the
// serving replica. The resize holds the StatefulSet on OnDelete instead of
// leaving the template untouched, so the template keeps following the
// instance (the CPU schedule cap in particular) without rolling a running pod.
func (r *KuraInstanceReconciler) reconcileStatefulSetDuringResize(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	held, err := r.holdRolloutForResize(ctx, instance)
	if err != nil || !held {
		return err
	}
	if err := r.reconcileStatefulSet(ctx, instance); err != nil {
		return err
	}
	if err := r.replacePodsStrandedOnCPU(ctx, instance); err != nil {
		return err
	}
	// A waiting resize never reaches the status write at the end of a full
	// reconcile, and an unpersisted schedule cap would let the next pass put
	// the uncapped request back on the template.
	return r.Status().Update(ctx, instance)
}

// holdRolloutForResize switches the StatefulSet to OnDelete and marks the
// switch as the resize's. It reports whether the template can be reconciled
// without rolling a running pod: the StatefulSet exists, is not being
// replaced, and is on OnDelete, whoever set it. A positive rolling partition
// is an operator's pause and is left alone.
func (r *KuraInstanceReconciler) holdRolloutForResize(ctx context.Context, instance *kurav1alpha1.KuraInstance) (bool, error) {
	sts := &appsv1.StatefulSet{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		if apierrors.IsNotFound(err) {
			return false, nil
		}
		return false, err
	}
	if sts.DeletionTimestamp != nil {
		return false, nil
	}
	if sts.Spec.UpdateStrategy.Type == appsv1.OnDeleteStatefulSetStrategyType {
		return true, nil
	}
	if rollingPartitioned(sts) {
		return false, nil
	}

	before := sts.DeepCopy()
	sts.Spec.UpdateStrategy = appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType}
	if sts.Annotations == nil {
		sts.Annotations = map[string]string{}
	}
	sts.Annotations[resizeRolloutHoldAnnotation] = "true"
	if err := r.Patch(ctx, sts, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
		return false, err
	}
	log.FromContext(ctx).Info("holding Kura StatefulSet rollout for a data volume resize")
	return true, nil
}

// releaseResizeRolloutHold restores the rolling update once the resize is over
// and every replica is ready, so whatever the template changed in the meantime
// rolls through the ordinary path with a serving standby.
func (r *KuraInstanceReconciler) releaseResizeRolloutHold(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	sts := &appsv1.StatefulSet{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return err
	}
	if _, held := sts.Annotations[resizeRolloutHoldAnnotation]; !held {
		return nil
	}

	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
		return err
	}
	ready := int32(0)
	for i := range pods.Items {
		if pods.Items[i].DeletionTimestamp == nil && podReady(&pods.Items[i]) {
			ready++
		}
	}
	if ready < replicas(instance) {
		return nil
	}

	before := sts.DeepCopy()
	delete(sts.Annotations, resizeRolloutHoldAnnotation)
	if sts.Spec.UpdateStrategy.Type == appsv1.OnDeleteStatefulSetStrategyType {
		sts.Spec.UpdateStrategy = appsv1.StatefulSetUpdateStrategy{
			Type:          appsv1.RollingUpdateStatefulSetStrategyType,
			RollingUpdate: &appsv1.RollingUpdateStatefulSetStrategy{Partition: ptr(int32(0))},
		}
	}
	if err := r.Patch(ctx, sts, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
		return err
	}
	log.FromContext(ctx).Info("released Kura StatefulSet rollout after a data volume resize")
	return nil
}

// replacePodsStrandedOnCPU recreates a replica the scheduler rejected for CPU
// once the held template asks for less. Under OnDelete nothing else replaces
// it, and a pod created before the schedule cap keeps its old reservation.
// Only an unscheduled pod is deleted, so nothing that serves is disturbed.
func (r *KuraInstanceReconciler) replacePodsStrandedOnCPU(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	sts := &appsv1.StatefulSet{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return err
	}
	if _, held := sts.Annotations[resizeRolloutHoldAnnotation]; !held || sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType {
		return nil
	}
	templateMilli := podCPURequestMilli(&corev1.Pod{Spec: sts.Spec.Template.Spec})
	if templateMilli <= 0 {
		return nil
	}

	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
		return err
	}
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.DeletionTimestamp != nil || pod.Spec.NodeName != "" || podReady(pod) || !podUnschedulableForCPU(pod) {
			continue
		}
		requested := podCPURequestMilli(pod)
		if requested <= templateMilli {
			continue
		}
		// Do not delete a pod that the scheduler bound after the observation.
		err := r.Delete(ctx, pod, &client.DeleteOptions{Preconditions: &metav1.Preconditions{UID: &pod.UID, ResourceVersion: &pod.ResourceVersion}})
		if apierrors.IsNotFound(err) || apierrors.IsConflict(err) {
			continue
		}
		if err != nil {
			return err
		}
		log.FromContext(ctx).Info("replacing Kura pod unschedulable for CPU during a data volume resize", "pod", pod.Name, "fromMilli", requested, "toMilli", templateMilli)
	}
	return nil
}

func rollingPartitioned(sts *appsv1.StatefulSet) bool {
	rolling := sts.Spec.UpdateStrategy.RollingUpdate
	return rolling != nil && rolling.Partition != nil && *rolling.Partition > 0
}

// rolloutPausedByOperator reports an update strategy an operator chose to
// stop rollouts with. The resize's own hold is not one: the controller placed
// it and replaces pods under it itself.
func rolloutPausedByOperator(sts *appsv1.StatefulSet) bool {
	if sts.Spec.UpdateStrategy.Type == appsv1.OnDeleteStatefulSetStrategyType {
		_, held := sts.Annotations[resizeRolloutHoldAnnotation]
		return !held
	}
	return rollingPartitioned(sts)
}
