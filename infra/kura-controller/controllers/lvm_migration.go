package controllers

import (
	"context"

	kurav1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const lvmMigrationNodeAnnotation = "tuist.dev/kura-lvm-migrate"

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
	if pv.Spec.CSI != nil && pv.Spec.CSI.Driver == "kura-volumes.tuist.dev" && pv.Spec.CSI.VolumeAttributes["backing"] == "lvm" {
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
	if err := r.Get(ctx, client.ObjectKeyFromObject(instance), sts); err != nil {
		return false, err
	}
	// This is a minimum landing check, not a capacity reservation. Kubernetes
	// remains authoritative; preflight the whole source node's claims before
	// marking it so concurrent instances cannot exhaust the spare mid-drain.
	var prepared []corev1.Node
	for _, node := range nodes.Items {
		capacity := node.Status.Allocatable[kuraDiskResource]
		if capacity.Cmp(storageQuantity(instance)) >= 0 {
			prepared = append(prepared, node)
		}
	}
	return hasLandingNode(prepared, map[string]bool{selected.Name: true}, sts.Spec.Template.Spec.NodeSelector), nil
}
