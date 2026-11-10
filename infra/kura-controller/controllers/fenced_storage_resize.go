package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// reconcileFencedDataStorageResize grows a positively fenced instance's claims
// without ever touching the replica that holds serving authority. Only a
// standby's volume is rebuilt; the holder's waits until a planned handover
// makes it a standby too. A destination larger than its source is also what
// lets a named handover's retained repair converge on a full ring.
//
// Every step requires a settled Serving grant with no handover or recovery in
// flight, a Ready holder, and no other standby down. A claim only a handover
// can free reports nothing in progress, so the rest of the reconcile keeps
// running while it waits.
func (r *KuraInstanceReconciler) reconcileFencedDataStorageResize(ctx context.Context, instance *kurav1alpha1.KuraInstance) (bool, error) {
	desired := storageQuantity(instance)
	if desired.IsZero() {
		return false, nil
	}
	holder, lastHandover, err := r.settledFencedHolder(ctx, instance)
	if err != nil || holder == "" || authorityTransitionOpen(instance, lastHandover) {
		return false, err
	}

	sts := &appsv1.StatefulSet{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		if apierrors.IsNotFound(err) {
			return true, nil
		}
		return false, err
	}
	if sts.DeletionTimestamp != nil {
		return true, nil
	}

	replacements, deleting, err := r.dataVolumesToReplace(ctx, instance, desired)
	if err != nil {
		return false, err
	}
	if deleting {
		return true, nil
	}
	var standbys []dataVolumeReplacement
	for _, volume := range replacements {
		if fmt.Sprintf("%s-%d", instance.Name, volume.ordinal) != holder {
			standbys = append(standbys, volume)
		}
	}
	if len(standbys) == 0 {
		return false, nil
	}

	if template := templateStorage(sts); !template.IsZero() && template.Cmp(desired) != 0 {
		log.FromContext(ctx).Info(
			"re-templating fenced Kura StatefulSet for a changed claim",
			"from", template.String(), "to", desired.String(),
		)
		if err := r.Delete(ctx, sts, client.PropagationPolicy(metav1.DeletePropagationOrphan)); err != nil && !apierrors.IsNotFound(err) {
			return false, err
		}
		return true, nil
	}
	if err := r.holdRecoveryRollout(ctx, instance); err != nil {
		return true, err
	}

	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
		return false, err
	}
	ready := map[string]bool{}
	for i := range pods.Items {
		ready[pods.Items[i].Name] = podReady(&pods.Items[i]) && pods.Items[i].DeletionTimestamp == nil
	}
	for ordinal := int32(0); ordinal < replicas(instance); ordinal++ {
		name := fmt.Sprintf("%s-%d", instance.Name, ordinal)
		if name != holder && !ready[name] && !replacedOrdinal(standbys, ordinal) {
			// A standby already rebuilt and coming back: wait for it rather
			// than take a second one down.
			return true, nil
		}
	}
	return true, r.rebuildDataVolume(ctx, instance, standbys[0], false)
}

// authorityTransitionOpen reports a planned handover the grant has not yet
// finished or abandoned, or an unfinished replica recovery, during which no
// volume may move.
func authorityTransitionOpen(instance *kurav1alpha1.KuraInstance, lastHandover string) bool {
	if request := instance.Spec.PlannedHandover; request != nil && request.ID != lastHandover {
		return true
	}
	progress := instance.Status.ReplicaRecovery
	if progress != nil && progress.Phase != "Verified" {
		return true
	}
	if request := instance.Spec.ReplicaRecovery; request != nil {
		return progress == nil || progress.Request.ID != request.ID
	}
	return false
}

// settledFencedHolder returns the pod holding an unexpired Serving grant with
// no handover attached, and only while that exact pod is Ready, together with
// the last handover the grant finished or abandoned. Anything else returns "".
func (r *KuraInstanceReconciler) settledFencedHolder(ctx context.Context, instance *kurav1alpha1.KuraInstance) (string, string, error) {
	cm := &corev1.ConfigMap{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: instance.Name + "-serving"}, cm); err != nil {
		if apierrors.IsNotFound(err) {
			return "", "", nil
		}
		return "", "", err
	}
	var grant servingGrant
	if err := json.Unmarshal([]byte(cm.Data["grant"]), &grant); err != nil {
		return "", "", err
	}
	if grant.Phase != "Serving" || grant.Handover != nil || grant.Holder.InstanceUID != string(instance.UID) || grant.ExpiresMS <= time.Now().UnixMilli() {
		return "", "", nil
	}
	pod := &corev1.Pod{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: grant.PodName}, pod); err != nil {
		if apierrors.IsNotFound(err) {
			return "", "", nil
		}
		return "", "", err
	}
	if string(pod.UID) != grant.Holder.PodUID || pod.Spec.NodeName != grant.Holder.Host || !podReady(pod) || pod.DeletionTimestamp != nil {
		return "", "", nil
	}
	return grant.PodName, grant.LastHandover, nil
}

func replacedOrdinal(volumes []dataVolumeReplacement, ordinal int32) bool {
	for _, volume := range volumes {
		if volume.ordinal == ordinal {
			return true
		}
	}
	return false
}
