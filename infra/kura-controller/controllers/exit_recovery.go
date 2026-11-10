package controllers

import (
	"context"
	"encoding/json"
	"fmt"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// requestExitRecovery submits the replica recovery for the ordinal a verified
// exit promotion left behind. Its volume stays marked and never rejoins, so it
// is quarantined and rebuilt from the promoted primary through the ordinary
// journaled recovery, with kubelet's exit report as the fence evidence. An
// operator request in flight, a pod already replaced or a missing claim leaves
// the manual path untouched.
func (r *KuraInstanceReconciler) requestExitRecovery(ctx context.Context, instance *kurav1alpha1.KuraInstance, pods []corev1.Pod) error {
	if !fencedServing(instance) {
		return nil
	}
	cm := &corev1.ConfigMap{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: instance.Name + "-serving"}, cm); err != nil {
		return client.IgnoreNotFound(err)
	}
	var grant servingGrant
	if err := json.Unmarshal([]byte(cm.Data["grant"]), &grant); err != nil {
		return err
	}
	exited := grant.ExitPromotedFrom
	if exited == nil || grant.Phase != "Serving" || grant.FenceEvidence == "" || len(exited.PodUID) < 8 || len(exited.Incarnation) < 8 {
		return nil
	}
	id := fmt.Sprintf("exit-%s-%s", exited.PodUID[:8], exited.Incarnation[len(exited.Incarnation)-8:])
	request, progress := instance.Spec.ReplicaRecovery, instance.Status.ReplicaRecovery
	if progress != nil && progress.Phase != "Verified" {
		return nil
	}
	if request != nil && (request.ID == id || progress == nil || progress.Request.ID != request.ID) {
		return nil
	}
	if progress != nil && progress.Request.ID == id {
		return nil
	}
	var target *corev1.Pod
	for i := range pods {
		if string(pods[i].UID) == exited.PodUID && pods[i].Spec.NodeName == exited.Host {
			target = &pods[i]
		}
	}
	if target == nil || target.Name == grant.PodName {
		return nil
	}
	pvc := &corev1.PersistentVolumeClaim{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: "data-" + target.Name}, pvc); err != nil {
		return client.IgnoreNotFound(err)
	}
	if pvc.Spec.VolumeName == "" {
		return nil
	}
	pv := &corev1.PersistentVolume{}
	if err := r.Get(ctx, types.NamespacedName{Name: pvc.Spec.VolumeName}, pv); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return err
	}
	before := instance.DeepCopy()
	instance.Spec.ReplicaRecovery = &kurav1alpha1.ReplicaRecoveryRequest{
		ID: id, PodName: target.Name, PodUID: exited.PodUID, PVCUID: string(pvc.UID), PVUID: string(pv.UID),
		HostName: exited.Host, FenceEvidence: grant.FenceEvidence,
	}
	if err := r.Patch(ctx, instance, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
		return err
	}
	log.FromContext(ctx).Info("requested replica recovery after a verified exit promotion", "id", id, "pod", target.Name, "host", exited.Host)
	return nil
}
