package controllers

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	"k8s.io/apimachinery/pkg/types"
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
	return thinVirtualQuantity(q.Value())
}

func thinVirtualQuantity(cacheBytes int64) resource.Quantity {
	const mib = int64(1 << 20)
	cache := (cacheBytes + mib - 1) / mib * mib
	size := cache + (2 << 30) + (288 << 20) + (cache+19)/20
	virtual := (size + (64 << 20) - 1) / (64 << 20) * (64 << 20)
	return *resource.NewQuantity(virtual, resource.BinarySI)
}

// templateDiskReservation is the disk reservation the StatefulSet template
// carries. A thin volume keeps the ceiling it was created with, and a shrink
// rebuilds a claim only past oversizedClaim's threshold (and then one replica
// at a time), so a smaller storageSize leaves bound volumes larger than
// diskReservation. Reserving from the spec then makes the scheduler count
// less than the node's thin pool has committed, and it keeps choosing a host
// whose CSI plugin refuses the next volume (kura-bird-eu-west-1, 2026-11-19).
// The template is shared, so it reserves the largest verified thin volume
// bound to any replica.
//
// Raising the reservation rolls the pods, so like the fast probes it is
// adopted only when they are replaced anyway (a new StatefulSet or an image
// change) and kept afterwards. sts is the live StatefulSet, or one without a
// resourceVersion when it does not exist yet.
func (r *KuraInstanceReconciler) templateDiskReservation(ctx context.Context, instance *kurav1alpha1.KuraInstance, sts *appsv1.StatefulSet) (resource.Quantity, error) {
	declared := diskReservation(instance)
	retained, err := r.retainedThinReservation(ctx, instance)
	if err != nil || retained.Cmp(declared) <= 0 {
		return declared, err
	}
	image, _ := heldRuntimeImage(instance)
	if sts.ResourceVersion == "" || podKuraImage(&corev1.Pod{Spec: sts.Spec.Template.Spec}) != image {
		return retained, nil
	}
	current := kuraDiskRequest(sts.Spec.Template.Spec, kuraDiskResource)
	if current.Cmp(retained) > 0 {
		current = retained
	}
	if current.Cmp(declared) < 0 {
		return declared, nil
	}
	return current, nil
}

// setKuraDiskReservation replaces the kura container's thin disk reservation,
// which defaultResources derived from the spec alone.
func setKuraDiskReservation(spec *corev1.PodSpec, instance *kurav1alpha1.KuraInstance, disk resource.Quantity) {
	if instance.Spec.StorageClassName != thinLocalStorageClass || disk.IsZero() {
		return
	}
	for i := range spec.Containers {
		if spec.Containers[i].Name == kuraContainerName {
			spec.Containers[i].Resources.Requests[kuraDiskResource] = disk
			spec.Containers[i].Resources.Limits[kuraDiskResource] = disk
		}
	}
}

// retainedThinReservation is the virtual size of the largest verified thin
// volume bound to one of the instance's replica claims, or zero.
func (r *KuraInstanceReconciler) retainedThinReservation(ctx context.Context, instance *kurav1alpha1.KuraInstance) (resource.Quantity, error) {
	var largest resource.Quantity
	if instance.Spec.StorageClassName != thinLocalStorageClass {
		return largest, nil
	}
	for ordinal := int32(0); ordinal < replicas(instance); ordinal++ {
		pvc := &corev1.PersistentVolumeClaim{}
		if err := r.Get(ctx, types.NamespacedName{Name: fmt.Sprintf("data-%s-%d", instance.Name, ordinal), Namespace: instance.Namespace}, pvc); err != nil {
			if apierrors.IsNotFound(err) {
				continue
			}
			return largest, err
		}
		if pvc.DeletionTimestamp != nil || pvc.Spec.VolumeName == "" || pvcStorageClassName(pvc) != thinLocalStorageClass {
			continue
		}
		pv := &corev1.PersistentVolume{}
		if err := r.Get(ctx, types.NamespacedName{Name: pvc.Spec.VolumeName}, pv); err != nil {
			if apierrors.IsNotFound(err) {
				continue
			}
			return largest, err
		}
		if !verifiedStorageBacking(instance, pv) {
			continue
		}
		cache, err := strconv.ParseInt(pv.Spec.CSI.VolumeAttributes["cache_ceiling_bytes"], 10, 64)
		if err != nil || cache <= 0 {
			continue
		}
		if virtual := thinVirtualQuantity(cache); virtual.Cmp(largest) > 0 {
			largest = virtual
		}
	}
	return largest, nil
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
