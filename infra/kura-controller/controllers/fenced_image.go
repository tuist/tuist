package controllers

import kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"

func heldRuntimeImage(instance *kurav1alpha1.KuraInstance) (string, bool) {
	floor := instance.Annotations["kura.tuist.dev/fenced-runtime-image"]
	if fencedServing(instance) && floor != "" && floor != instance.Spec.Image {
		return floor, true
	}
	return instance.Spec.Image, false
}
