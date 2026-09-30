package controllers

import (
	"context"
	"fmt"
	"strings"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	coordinationv1 "k8s.io/api/coordination/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const recoveryQuarantine = "kura.tuist.dev/recovery-quarantine"
const recoveryRolloutHold = "kura.tuist.dev/recovery-rollout-hold"

// The recovery hold is intentionally never released by the resize state machine.
// An operator resumes rollout after validating the replacement and serving path.
func (r *KuraInstanceReconciler) holdRecoveryRollout(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	sts := &appsv1.StatefulSet{}
	if err := r.Get(ctx, client.ObjectKeyFromObject(instance), sts); err != nil {
		return client.IgnoreNotFound(err)
	}
	before := sts.DeepCopy()
	if sts.Annotations == nil {
		sts.Annotations = map[string]string{}
	}
	sts.Annotations[recoveryRolloutHold] = "true"
	delete(sts.Annotations, resizeRolloutHoldAnnotation)
	sts.Spec.UpdateStrategy = appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType}
	// A controller crash or an unrelated StatefulSet deletion must not collect
	// the survivor's claim while this journal is in flight.
	sts.Spec.PersistentVolumeClaimRetentionPolicy = &appsv1.StatefulSetPersistentVolumeClaimRetentionPolicy{
		WhenDeleted: appsv1.RetainPersistentVolumeClaimRetentionPolicyType,
		WhenScaled:  appsv1.RetainPersistentVolumeClaimRetentionPolicyType,
	}
	return r.Patch(ctx, sts, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
}

func (r *KuraInstanceReconciler) saveReplicaRecovery(ctx context.Context, instance *kurav1alpha1.KuraInstance, status *kurav1alpha1.ReplicaRecoveryStatus) error {
	before := instance.DeepCopy()
	instance.Status.ReplicaRecovery = status
	return r.Status().Patch(ctx, instance, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
}

func recoveryDeleteOptions(object client.Object) *client.DeleteOptions {
	uid, rv := object.GetUID(), object.GetResourceVersion()
	return &client.DeleteOptions{Preconditions: &metav1.Preconditions{UID: &uid, ResourceVersion: &rv}}
}

// Each pass performs at most one irreversible step, after persisting its target.
// The exact source incarnation must stay healthy throughout; a failed rebuild
// never escalates into deleting another ordinal. Old data is quarantined, not GC'd.
func (r *KuraInstanceReconciler) reconcileReplicaRecovery(ctx context.Context, instance *kurav1alpha1.KuraInstance, pods []corev1.Pod, samples map[string]runtimeStatus, primary string) (bool, error) {
	request, progress := instance.Spec.ReplicaRecovery, instance.Status.ReplicaRecovery
	if request == nil && progress == nil {
		return false, nil
	}
	if progress != nil && progress.Phase == "Verified" && (request == nil || request.ID == progress.Request.ID) {
		return false, r.releaseRecoverySlot(ctx, instance, progress.Request.ID)
	}
	if err := r.holdRecoveryRollout(ctx, instance); err != nil {
		return true, err
	}
	if progress != nil && progress.Phase != "Verified" && (request == nil || *request != progress.Request) {
		return true, fmt.Errorf("replica recovery request changed while %s is in progress", progress.Request.ID)
	}
	if request == nil {
		return true, nil
	}
	if request.ID == "" || request.PodUID == "" || request.PVCUID == "" || request.PVUID == "" || request.HostName == "" || strings.TrimSpace(request.FenceEvidence) == "" {
		return true, fmt.Errorf("replica recovery requires immutable pod/PVC/PV identities, host and positive fence evidence")
	}
	ordinalValid := false
	for i := int32(0); i < replicas(instance); i++ {
		ordinalValid = ordinalValid || request.PodName == fmt.Sprintf("%s-%d", instance.Name, i)
	}
	if !ordinalValid || replicas(instance) < 2 {
		return true, fmt.Errorf("replica recovery requires one expected ordinal and a surviving sibling")
	}
	var source *corev1.Pod
	for i := range pods {
		pod := &pods[i]
		sample, fresh := samples[pod.Name]
		if pod.Name == primary && pod.Name != request.PodName && pod.Spec.NodeName != request.HostName && podReady(pod) && fresh && runtimeStatusServing(sample) && sample.BackfillInitialCycle == backfillCycleComplete && sample.ServingAuthority.Identity.Incarnation != "" {
			source = pod
		}
	}
	if source == nil {
		return true, nil
	}
	if err := r.acquireRecoverySlot(ctx, instance, request.ID); err != nil {
		return true, err
	}
	if progress != nil && progress.Phase != "Verified" && (progress.SourcePod != source.Name || progress.SourceUID != string(source.UID) || progress.SourceIncarnation != samples[source.Name].ServingAuthority.Identity.Incarnation) {
		return true, fmt.Errorf("recovery source incarnation changed; explicit investigation required")
	}
	pvc := &corev1.PersistentVolumeClaim{}
	pvcName := "data-" + request.PodName
	pvcErr := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: pvcName}, pvc)
	if pvcErr != nil && !apierrors.IsNotFound(pvcErr) {
		return true, pvcErr
	}
	if progress == nil || progress.Phase == "Verified" {
		if pvcErr != nil || string(pvc.UID) != request.PVCUID || pvc.Spec.VolumeName == "" {
			return true, fmt.Errorf("recovery claim identity mismatch")
		}
		pv := &corev1.PersistentVolume{}
		if err := r.Get(ctx, types.NamespacedName{Name: pvc.Spec.VolumeName}, pv); err != nil {
			return true, err
		}
		if string(pv.UID) != request.PVUID || pv.Spec.ClaimRef == nil || pv.Spec.ClaimRef.UID != pvc.UID {
			return true, fmt.Errorf("recovery volume identity mismatch")
		}
		hosts := pvRequiredHostnames(pv)
		if len(hosts) != 1 || hosts[0] != request.HostName {
			return true, fmt.Errorf("recovery volume must be pinned exclusively to the declared fenced host")
		}
		target := &corev1.Pod{}
		if err := r.Get(ctx, types.NamespacedName{Name: request.PodName, Namespace: instance.Namespace}, target); err != nil {
			return true, err
		}
		if string(target.UID) != request.PodUID || target.Spec.NodeName != request.HostName {
			return true, fmt.Errorf("recovery pod identity mismatch")
		}
		if target.Name == primary {
			return true, fmt.Errorf("fence and promote the survivor before rebuilding the old primary")
		}
		progress = &kurav1alpha1.ReplicaRecoveryStatus{Request: *request, Phase: "Quarantining", SourcePod: source.Name, SourceUID: string(source.UID), PVCName: pvcName, PVName: pv.Name, StartedAt: time.Now().UTC().Format(time.RFC3339)}
		progress.SourceIncarnation = samples[source.Name].ServingAuthority.Identity.Incarnation
		if err := r.reconcileStatefulSet(ctx, instance); err != nil {
			return true, err
		}
		return true, r.saveReplicaRecovery(ctx, instance, progress)
	}
	next := *progress
	switch progress.Phase {
	case "Quarantining":
		pv := &corev1.PersistentVolume{}
		if err := r.Get(ctx, types.NamespacedName{Name: progress.PVName}, pv); err != nil {
			return true, err
		}
		if string(pv.UID) != request.PVUID {
			return true, fmt.Errorf("quarantined volume identity changed")
		}
		before := pv.DeepCopy()
		pv.Spec.PersistentVolumeReclaimPolicy = corev1.PersistentVolumeReclaimRetain
		if pv.Annotations == nil {
			pv.Annotations = map[string]string{}
		}
		pv.Annotations[recoveryQuarantine] = string(instance.UID) + "/" + request.ID
		if err := r.Patch(ctx, pv, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
			return true, err
		}
		next.Phase = "DeletingClaim"
	case "DeletingClaim":
		if pvcErr == nil && string(pvc.UID) == request.PVCUID && pvc.DeletionTimestamp == nil {
			if err := r.Delete(ctx, pvc, recoveryDeleteOptions(pvc)); err != nil {
				return true, client.IgnoreNotFound(err)
			}
		} else if pvcErr == nil && string(pvc.UID) != request.PVCUID {
			return true, fmt.Errorf("claim replaced before old pod was fenced and removed")
		}
		next.Phase = "DeletingPod"
	case "DeletingPod":
		target := &corev1.Pod{}
		err := r.Get(ctx, types.NamespacedName{Name: request.PodName, Namespace: instance.Namespace}, target)
		if err != nil && !apierrors.IsNotFound(err) {
			return true, err
		}
		if err == nil && string(target.UID) == request.PodUID {
			// Force deletion is permitted only by the persisted positive fence declaration.
			options := recoveryDeleteOptions(target)
			options.GracePeriodSeconds = ptr(int64(0))
			if err := r.Delete(ctx, target, options); err != nil {
				return true, client.IgnoreNotFound(err)
			}
		}
		next.Phase = "Rebuilding"
	case "Rebuilding":
		if pvcErr != nil || string(pvc.UID) == request.PVCUID || pvc.Status.Phase != corev1.ClaimBound {
			return true, nil
		}
		for i := range pods {
			pod := &pods[i]
			sample, fresh := samples[pod.Name]
			if pod.Name == request.PodName && string(pod.UID) != request.PodUID && pod.Spec.NodeName != request.HostName && pod.Spec.NodeName != source.Spec.NodeName && podReady(pod) && fresh && runtimeStatusServing(sample) && sample.BackfillInitialCycle == backfillCycleComplete {
				next.Phase, next.VerifiedAt = "Verified", time.Now().UTC().Format(time.RFC3339)
				next.Message = "Replacement bootstrap verified; old PV remains quarantined. This is not a retained-data handover barrier."
			}
		}
		if next.Phase != "Verified" {
			return true, nil
		}
	default:
		return true, fmt.Errorf("unknown replica recovery phase %q", progress.Phase)
	}
	return true, r.saveReplicaRecovery(ctx, instance, &next)
}

// One namespace-wide rebuild is deliberately stricter than per-host limits.
// There is no timeout takeover: an interrupted controller retains ownership
// until verification or an operator resolves the persisted journal.
func (r *KuraInstanceReconciler) acquireRecoverySlot(ctx context.Context, instance *kurav1alpha1.KuraInstance, id string) error {
	key := types.NamespacedName{Namespace: instance.Namespace, Name: "kura-replica-recovery"}
	lease := &coordinationv1.Lease{}
	err := r.Get(ctx, key, lease)
	holder := string(instance.UID) + "/" + id
	if apierrors.IsNotFound(err) {
		return r.Create(ctx, &coordinationv1.Lease{ObjectMeta: metav1.ObjectMeta{Name: key.Name, Namespace: key.Namespace}, Spec: coordinationv1.LeaseSpec{HolderIdentity: &holder}})
	}
	if err != nil {
		return err
	}
	if lease.Spec.HolderIdentity == nil || *lease.Spec.HolderIdentity != holder {
		return fmt.Errorf("another recovery owns the namespace rebuild slot")
	}
	return nil
}

func (r *KuraInstanceReconciler) releaseRecoverySlot(ctx context.Context, instance *kurav1alpha1.KuraInstance, id string) error {
	lease := &coordinationv1.Lease{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: "kura-replica-recovery"}, lease); err != nil {
		return client.IgnoreNotFound(err)
	}
	if lease.Spec.HolderIdentity != nil && *lease.Spec.HolderIdentity == string(instance.UID)+"/"+id {
		return client.IgnoreNotFound(r.Delete(ctx, lease, recoveryDeleteOptions(lease)))
	}
	return nil
}
