package controllers

import (
	"strings"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
)

const kuraDiskResource corev1.ResourceName = "tuist.dev/kura-disk"

func diskResource(instance *kurav1alpha1.KuraInstance) corev1.ResourceName {
	if instance.Spec.StorageClassName == thinLocalStorageClass || instance.Spec.DiskResource == string(kuraDiskResource) {
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

// In ceiling-backed-v1 scheduling reserves the full virtual device, including
// workspace and metadata. Allocator floors/grants never change this reservation.
// Keep this formula identical to the CSI ThinVirtualBytes versioned contract.
func diskReservation(instance *kurav1alpha1.KuraInstance) resource.Quantity {
	q := storageQuantity(instance)
	if instance.Spec.StorageClassName != thinLocalStorageClass {
		return q
	}
	const mib = int64(1 << 20)
	cache := (q.Value() + mib - 1) / mib * mib
	size := cache + (2 << 30) + (288 << 20) + (cache+19)/20
	virtual := (size + (64 << 20) - 1) / (64 << 20) * (64 << 20)
	return *resource.NewQuantity(virtual, resource.BinarySI)
}

func verifiedStorageBacking(instance *kurav1alpha1.KuraInstance, pv *corev1.PersistentVolume) bool {
	if pv.Spec.CSI == nil || pv.Spec.CSI.Driver != "kura-volumes.tuist.dev" {
		return false
	}
	if instance.Spec.StorageClassName == thinLocalStorageClass {
		return pv.Spec.CSI.VolumeAttributes["backing"] == "thin" && pv.Spec.CSI.VolumeAttributes["layout"] == "thin-luks-xfs-v1" && pv.Spec.CSI.VolumeAttributes["capacity_mode"] == "ceiling-backed-v1"
	}
	return pv.Spec.CSI.VolumeAttributes["backing"] == "lvm"
}
