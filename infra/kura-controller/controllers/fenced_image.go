package controllers

import (
	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
)

// Image holds published in status.imageHold. Each names an operator procedure
// the requested image waits on; the controller never completes it alone.
const (
	imageHoldFencedPin         = "FencedImagePin"
	imageHoldFencedReplacement = "FencedReplacement"
	imageHoldRecoveryRollout   = "RecoveryRolloutHold"
)

func heldRuntimeImage(instance *kurav1alpha1.KuraInstance) (string, bool) {
	floor := instance.Annotations["kura.tuist.dev/fenced-runtime-image"]
	if fencedServing(instance) && floor != "" && floor != instance.Spec.Image {
		return floor, true
	}
	return instance.Spec.Image, false
}

// operatorImageHold reports a requested image that is templated but waits on
// manual pod replacement: an activated instance, or a recovery hold, keeps
// OnDelete until an operator replaces the remaining old-revision pods. A
// fully updated set that is not Ready is a failing image, not a hold.
func operatorImageHold(instance *kurav1alpha1.KuraInstance, sts *appsv1.StatefulSet, replicas int32) string {
	if sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType ||
		statefulSetTemplateImage(sts) != instance.Spec.Image ||
		sts.Status.UpdatedReplicas >= replicas {
		return ""
	}
	switch {
	case fencedServing(instance):
		return imageHoldFencedReplacement
	case sts.Annotations[recoveryRolloutHold] == "true":
		return imageHoldRecoveryRollout
	default:
		return ""
	}
}
