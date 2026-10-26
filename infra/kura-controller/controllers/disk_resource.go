package controllers

import (
	"strings"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
)

const kuraDiskResource corev1.ResourceName = "tuist.dev/kura-disk"

func diskResource(instance *kurav1alpha1.KuraInstance) corev1.ResourceName {
	if instance.Spec.DiskResource == string(kuraDiskResource) {
		return kuraDiskResource
	}
	return corev1.ResourceEphemeralStorage
}

func kuraDiskRequest(spec corev1.PodSpec, disk corev1.ResourceName) resource.Quantity {
	for _, container := range spec.Containers {
		if container.Name == kuraContainerName {
			return container.Resources.Requests[disk]
		}
	}
	return resource.Quantity{}
}

func podUnschedulableForDisk(pod *corev1.Pod, disk corev1.ResourceName) bool {
	if pod.Status.Phase != corev1.PodPending {
		return false
	}
	for _, condition := range pod.Status.Conditions {
		if condition.Type == corev1.PodScheduled && condition.Status == corev1.ConditionFalse &&
			condition.Reason == corev1.PodReasonUnschedulable && strings.Contains(condition.Message, "Insufficient "+string(disk)) {
			return true
		}
	}
	return false
}
