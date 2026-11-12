package controllers

import (
	"context"

	kurav1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const lvmMigrationNodeAnnotation = "tuist.dev/kura-lvm-migrate"

// A StatefulSet has one replacement template for every ordinal. Preserve the
// legacy template until every remaining legacy claim belongs to the selected
// source; otherwise an unrelated restart could request LVM capacity on an
// unconverted host. Instances spanning unconverted hosts require a separate
// placement plan before entering this node-at-a-time migration.
func (r *KuraInstanceReconciler) lvmMigrationTemplateHeld(ctx context.Context, instance *kurav1.KuraInstance) (bool, error) {
	if diskResource(instance) != kuraDiskResource || fencedServing(instance) {
		return false, nil
	}
	replacements, _, err := r.dataVolumesToReplace(ctx, instance, storageQuantity(instance))
	if err != nil {
		return false, err
	}
	for _, volume := range replacements {
		allowed, err := r.lvmMigrationAllowed(ctx, instance, volume)
		if err != nil || !allowed {
			return true, err
		}
	}
	return false, nil
}

// Regional enrollment changes the desired layout, not permission to discard
// every legacy volume. One explicitly selected, cordoned source node may drain
// into prepared capacity; unselected hosts retain their old pods and claims.
func (r *KuraInstanceReconciler) lvmMigrationAllowed(ctx context.Context, instance *kurav1.KuraInstance, volume dataVolumeReplacement) (bool, error) {
	if diskResource(instance) != kuraDiskResource || volume.claim.Spec.VolumeName == "" {
		return true, nil
	}
	pv := &corev1.PersistentVolume{}
	if err := r.Get(ctx, client.ObjectKey{Name: volume.claim.Spec.VolumeName}, pv); err != nil {
		return false, err
	}
	if verifiedStorageBacking(instance, pv) {
		return true, nil
	}
	hosts := pvRequiredHostnames(pv)
	if len(hosts) != 1 {
		return false, nil
	}
	nodes := &corev1.NodeList{}
	if err := r.List(ctx, nodes); err != nil {
		return false, err
	}
	var selected *corev1.Node
	for i := range nodes.Items {
		node := &nodes.Items[i]
		if node.Annotations[lvmMigrationNodeAnnotation] != "true" {
			continue
		}
		if selected != nil {
			return false, nil
		}
		selected = node
	}
	if selected == nil || selected.Name != hosts[0] || !selected.Spec.Unschedulable || selected.DeletionTimestamp != nil {
		return false, nil
	}
	sts := &appsv1.StatefulSet{}
	selector := nodeSelector(instance)
	switch err := r.Get(ctx, client.ObjectKeyFromObject(instance), sts); {
	case apierrors.IsNotFound(err):
		// The immutable claim-template replacement briefly orphans its pods.
	case err != nil:
		return false, err
	default:
		selector = sts.Spec.Template.Spec.NodeSelector
		if instance.Spec.StorageClassName == thinLocalStorageClass {
			selector = nodeSelector(instance)
		}
	}
	// This is a minimum landing check, not a capacity reservation. Kubernetes
	// remains authoritative; preflight the whole source node's claims before
	// marking it so concurrent instances cannot exhaust the spare mid-drain.
	var prepared []corev1.Node
	for _, node := range nodes.Items {
		capacity := node.Status.Allocatable[kuraDiskResource]
		if capacity.Cmp(diskReservation(instance)) >= 0 {
			prepared = append(prepared, node)
		}
	}
	return hasLandingNode(prepared, map[string]bool{selected.Name: true}, selector), nil
}

// lvmHeldTemplate keeps the storage half of a held template: the claim's class
// and size and the disk resource the kura container reserves. Everything else
// follows the instance, so an instance waiting for its source node to be
// selected still takes image and configuration changes on its current hosts.
func lvmHeldTemplate(instance *kurav1.KuraInstance, sts *appsv1.StatefulSet) *kurav1.KuraInstance {
	held := instance.DeepCopy()
	held.Spec.StorageClassName, _ = templateStorageClass(sts)
	if size := templateStorage(sts); !size.IsZero() {
		held.Spec.StorageSize = size.String()
	}
	held.Spec.DiskResource = ""
	if request := kuraDiskRequest(sts.Spec.Template.Spec, kuraDiskResource); !request.IsZero() {
		held.Spec.DiskResource = string(kuraDiskResource)
	}
	return held
}
