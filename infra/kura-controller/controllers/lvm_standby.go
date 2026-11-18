package controllers

import (
	"context"
	"fmt"

	kurav1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

const lvmMigrationStandbyAnnotation = "kura.tuist.dev/lvm-migration-standby"

// A single-replica instance has no sibling to serve while its only volume
// moves, so its migration runs a temporary second ordinal. The standby lands on
// the declared storage, catches up, and takes the endpoint through the ordinary
// handoff while ordinal 0 is rebuilt; it hands the endpoint back the same way
// before its claim is released. The annotation on the standby's claim is the
// durable record that the second ordinal belongs to the migration, so a claim
// an earlier scale-down retained is never mistaken for it.
//
// lvmMigrationServed returns the instance the pods are reconciled against: the
// declared one, or a copy with the standby counted. Only the copy's replica
// count differs, and it is never written back to the spec.
func (r *KuraInstanceReconciler) lvmMigrationServed(ctx context.Context, instance *kurav1.KuraInstance) (*kurav1.KuraInstance, error) {
	if fencedServing(instance) || diskResource(instance) != kuraDiskResource || replicas(instance) != 1 {
		return instance, nil
	}
	claim := &corev1.PersistentVolumeClaim{}
	switch err := r.Get(ctx, lvmStandbyClaimKey(instance), claim); {
	case apierrors.IsNotFound(err):
		claim = nil
	case err != nil:
		return nil, err
	case claim.DeletionTimestamp != nil:
		return instance, nil
	case claim.Annotations[lvmMigrationStandbyAnnotation] != "":
		return withLVMStandby(instance), nil
	}
	replacements, deleting, err := r.dataVolumesToReplace(ctx, instance, storageQuantity(instance))
	if err != nil || deleting || len(replacements) == 0 {
		return instance, err
	}
	allowed, err := r.lvmMigrationAllowed(ctx, instance, replacements[0])
	if err != nil || !allowed {
		return instance, err
	}
	if claim != nil {
		fits, err := r.lvmStandbyClaimFits(ctx, instance, claim)
		if err != nil {
			return nil, err
		}
		if !fits {
			log.FromContext(ctx).Info("holding single-copy LVM migration: a retained claim occupies the standby ordinal", "pvc", claim.Name)
			return instance, nil
		}
		before := claim.DeepCopy()
		if claim.Annotations == nil {
			claim.Annotations = map[string]string{}
		}
		claim.Annotations[lvmMigrationStandbyAnnotation] = "true"
		if err := r.Patch(ctx, claim, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
			return nil, err
		}
	}
	return withLVMStandby(instance), nil
}

// The StatefulSet creates the standby's claim from the declared template. A
// claim on other storage is one an earlier scale-down retained.
func (r *KuraInstanceReconciler) lvmStandbyClaimFits(ctx context.Context, instance *kurav1.KuraInstance, claim *corev1.PersistentVolumeClaim) (bool, error) {
	if pvcStorageClassName(claim) != instance.Spec.StorageClassName {
		return false, nil
	}
	if size, ok := claim.Spec.Resources.Requests[corev1.ResourceStorage]; !ok || size.Cmp(storageQuantity(instance)) < 0 {
		return false, nil
	}
	if claim.Spec.VolumeName == "" {
		return true, nil
	}
	pv := &corev1.PersistentVolume{}
	if err := r.Get(ctx, client.ObjectKey{Name: claim.Spec.VolumeName}, pv); err != nil {
		return false, client.IgnoreNotFound(err)
	}
	return verifiedStorageBacking(instance, pv), nil
}

// retireLVMMigrationStandby hands the endpoint back to the rebuilt ordinal 0
// once it has caught up, then releases the standby's claim. The next pass sees
// the claim terminating and scales the StatefulSet back to the declared single
// replica, which removes the standby pod and with it the claim. It reports
// whether the retirement is still in progress.
func (r *KuraInstanceReconciler) retireLVMMigrationStandby(ctx context.Context, instance *kurav1.KuraInstance) (bool, error) {
	if replicas(instance) != 2 {
		return false, nil
	}
	claim := &corev1.PersistentVolumeClaim{}
	if err := r.Get(ctx, lvmStandbyClaimKey(instance), claim); err != nil {
		return false, client.IgnoreNotFound(err)
	}
	if claim.Annotations[lvmMigrationStandbyAnnotation] == "" || claim.DeletionTimestamp != nil {
		return false, nil
	}
	source := &corev1.Pod{}
	if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: fmt.Sprintf("%s-0", instance.Name)}, source); err != nil {
		return true, client.IgnoreNotFound(err)
	}
	if source.DeletionTimestamp != nil || !podReady(source) {
		return true, nil
	}
	status, err := r.runtimeStatusClient(instance).Status(ctx, *source)
	if err != nil || status.invalidObservation || !status.Ready || status.BackfillInitialCycle != backfillCycleComplete || status.BackfillBudgetExhaustedRealPeers != 0 {
		return true, nil
	}
	released, err := r.lvmHandoverReady(ctx, instance, 1)
	if err != nil || !released {
		return true, err
	}
	log.FromContext(ctx).Info("releasing the single-copy LVM migration standby", "pvc", claim.Name)
	if err := r.reclaimDataVolume(ctx, claim); err != nil {
		return true, err
	}
	err = r.Delete(ctx, claim, client.Preconditions{UID: &claim.UID})
	return true, client.IgnoreNotFound(err)
}

func lvmStandbyClaimKey(instance *kurav1.KuraInstance) client.ObjectKey {
	return client.ObjectKey{Namespace: instance.Namespace, Name: fmt.Sprintf("data-%s-1", instance.Name)}
}

func withLVMStandby(instance *kurav1.KuraInstance) *kurav1.KuraInstance {
	served := instance.DeepCopy()
	served.Spec.Replicas = ptr(int32(2))
	return served
}
