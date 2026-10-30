package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// drainHandoverPrefix names the planned handovers this controller requests
// for a holder whose node is cordoned. Requests without it are an operator's.
const drainHandoverPrefix = "drain-"

// drainHandoverAttempts bounds how many automatic handovers one holder
// incarnation gets. An interrupted freeze refuses writes until its deadline,
// so a handover that keeps failing waits for an operator instead of looping.
const drainHandoverAttempts = 3

// requestDrainHandover hands a positively fenced instance's serving authority
// to its standby once the holder's node is cordoned. Every drain cordons
// first, and the holder's disruption budget refuses its eviction until the
// grant has moved, so the drain waits for the handover instead of stopping
// the writer. A consumed automatic request is cleared; an operator request,
// a recovery or an unsettled grant is left alone.
func (r *KuraInstanceReconciler) requestDrainHandover(ctx context.Context, instance *kurav1alpha1.KuraInstance, pods []corev1.Pod, samples map[string]runtimeStatus) error {
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
	if request := instance.Spec.PlannedHandover; request != nil && strings.HasPrefix(request.ID, drainHandoverPrefix) && request.ID == grant.LastHandover {
		before := instance.DeepCopy()
		instance.Spec.PlannedHandover = nil
		return r.Patch(ctx, instance, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
	}
	if grant.Phase != "Serving" || grant.Handover != nil || grant.Holder.InstanceUID != string(instance.UID) || grant.ExpiresMS <= time.Now().UnixMilli() || len(grant.Holder.Incarnation) < 8 {
		return nil
	}
	if authorityTransitionOpen(instance, grant.LastHandover) {
		return nil
	}
	var holder *corev1.Pod
	for i := range pods {
		if pods[i].Name == grant.PodName && string(pods[i].UID) == grant.Holder.PodUID && pods[i].Spec.NodeName == grant.Holder.Host {
			holder = &pods[i]
		}
	}
	if holder == nil || !podReady(holder) || holder.DeletionTimestamp != nil {
		return nil
	}
	cordoned, err := r.nodeCordoned(ctx, holder.Spec.NodeName)
	if err != nil || !cordoned {
		return err
	}
	prefix := fmt.Sprintf("%s%s-", drainHandoverPrefix, grant.Holder.Incarnation[:8])
	attempt := 1
	if previous, found := strings.CutPrefix(grant.LastHandover, prefix); found {
		number, err := strconv.Atoi(previous)
		if err != nil {
			return nil
		}
		attempt = number + 1
	}
	if attempt > drainHandoverAttempts {
		log.FromContext(ctx).Info("holder node is cordoned but automatic handovers are exhausted; the drain waits for an operator", "pod", holder.Name, "node", holder.Spec.NodeName, "lastHandover", grant.LastHandover)
		return nil
	}
	for i := range pods {
		target := &pods[i]
		sample, fresh := samples[target.Name]
		identity := sample.ServingAuthority.Identity
		if target.Name == holder.Name || target.Spec.NodeName == "" || target.Spec.NodeName == holder.Spec.NodeName || !podReady(target) || target.DeletionTimestamp != nil || !fresh || !runtimeStatusServing(sample) || sample.BackfillInitialCycle != backfillCycleComplete || identity.PodUID != string(target.UID) || identity.Host != target.Spec.NodeName || identity.Incarnation == "" {
			continue
		}
		if cordoned, err := r.nodeCordoned(ctx, target.Spec.NodeName); err != nil || cordoned {
			if err != nil {
				return err
			}
			continue
		}
		before := instance.DeepCopy()
		instance.Spec.PlannedHandover = &kurav1alpha1.PlannedHandoverRequest{ID: prefix + strconv.Itoa(attempt), PodName: target.Name, PodUID: identity.PodUID, Incarnation: identity.Incarnation}
		if err := r.Patch(ctx, instance, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
			return err
		}
		log.FromContext(ctx).Info("requested a planned handover away from a cordoned holder node", "id", instance.Spec.PlannedHandover.ID, "from", holder.Name, "node", holder.Spec.NodeName, "to", target.Name)
		return nil
	}
	return nil
}

func (r *KuraInstanceReconciler) nodeCordoned(ctx context.Context, name string) (bool, error) {
	node := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: name}, node); err != nil {
		if apierrors.IsNotFound(err) {
			return false, nil
		}
		return false, err
	}
	return node.Spec.Unschedulable, nil
}

// fencedHolderPod names the pod whose eviction a positively fenced instance's
// disruption budget refuses: the grant's holder in every phase, since a
// handover, fence or promotion in flight still needs it. "" before the first
// grant.
func (r *KuraInstanceReconciler) fencedHolderPod(ctx context.Context, instance *kurav1alpha1.KuraInstance) (string, error) {
	cm := &corev1.ConfigMap{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: instance.Name + "-serving"}, cm); err != nil {
		if apierrors.IsNotFound(err) {
			return "", nil
		}
		return "", err
	}
	var grant servingGrant
	if err := json.Unmarshal([]byte(cm.Data["grant"]), &grant); err != nil {
		return "", err
	}
	if grant.Epoch == 0 || grant.Holder.InstanceUID != string(instance.UID) {
		return "", nil
	}
	return grant.PodName, nil
}
