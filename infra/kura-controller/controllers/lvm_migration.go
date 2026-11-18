package controllers

import (
	"context"
	"fmt"

	kurav1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const lvmMigrationNodeAnnotation = "tuist.dev/kura-lvm-migrate"

// A StatefulSet has one replacement template for every ordinal. Preserve the
// legacy template until one of the remaining legacy claims belongs to the
// selected source; otherwise an unrelated restart could request LVM capacity
// on an unconverted host. An instance whose replicas span unconverted hosts
// moves the selected source's replica and keeps the others on their legacy
// claims: their pods keep running under the resize's OnDelete hold until their
// own host is selected, and one whose pod the new template can no longer place
// is rebuilt on its own (lvmLegacyReplicaStranded).
func (r *KuraInstanceReconciler) lvmMigrationTemplateHeld(ctx context.Context, instance *kurav1.KuraInstance) (bool, error) {
	if diskResource(instance) != kuraDiskResource || fencedServing(instance) {
		return false, nil
	}
	replacements, _, err := r.dataVolumesToReplace(ctx, instance, storageQuantity(instance))
	if err != nil || len(replacements) == 0 {
		return false, err
	}
	for _, volume := range replacements {
		allowed, err := r.lvmMigrationAllowed(ctx, instance, volume)
		if err != nil || allowed {
			return false, err
		}
	}
	return true, nil
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
	sts := &appsv1.StatefulSet{}
	selector := nodeSelector(instance)
	switch err := r.Get(ctx, client.ObjectKeyFromObject(instance), sts); {
	case apierrors.IsNotFound(err):
		// The immutable claim-template replacement briefly orphans its pods.
		sts = nil
	case err != nil:
		return false, err
	default:
		selector = sts.Spec.Template.Spec.NodeSelector
		if instance.Spec.StorageClassName == thinLocalStorageClass {
			selector = nodeSelector(instance)
		}
	}
	source := hosts[0]
	if selected == nil || selected.Name != source || !selected.Spec.Unschedulable || selected.DeletionTimestamp != nil {
		stranded, err := r.lvmLegacyReplicaStranded(ctx, instance, sts, volume)
		if err != nil || !stranded {
			return false, err
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
	return hasLandingNode(prepared, map[string]bool{source: true}, selector), nil
}

// lvmLegacyReplicaStranded reports a legacy claim on an unselected host whose
// replica the StatefulSet can no longer run: the template already moved to the
// declared storage (a sibling's host was selected), and the scheduler cannot
// place the replica's recreated pod beside its claim. It serves nothing,
// so rebuilding it on prepared capacity loses only its own copy, which it
// refills from its sibling; leaving it would hold the instance on one replica
// until its host is selected.
func (r *KuraInstanceReconciler) lvmLegacyReplicaStranded(ctx context.Context, instance *kurav1.KuraInstance, sts *appsv1.StatefulSet, volume dataVolumeReplacement) (bool, error) {
	if sts == nil {
		return false, nil
	}
	if class, ok := templateStorageClass(sts); !ok || class != instance.Spec.StorageClassName {
		return false, nil
	}
	pod := &corev1.Pod{}
	switch err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: fmt.Sprintf("%s-%d", instance.Name, volume.ordinal)}, pod); {
	case apierrors.IsNotFound(err):
		// The StatefulSet recreates a deleted pod at once; wait for the
		// scheduler's verdict on it rather than acting in that gap.
		return false, nil
	case err != nil:
		return false, err
	}
	return pod.DeletionTimestamp == nil && podUnschedulable(pod), nil
}

func podUnschedulable(pod *corev1.Pod) bool {
	if pod.Status.Phase != corev1.PodPending || pod.Spec.NodeName != "" {
		return false
	}
	for _, condition := range pod.Status.Conditions {
		if condition.Type == corev1.PodScheduled && condition.Status == corev1.ConditionFalse && condition.Reason == corev1.PodReasonUnschedulable {
			return true
		}
	}
	return false
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
