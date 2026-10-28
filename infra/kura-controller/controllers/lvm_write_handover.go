package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"

	kurav1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const lvmWriteTargetAnnotation = "kura.tuist.dev/lvm-write-target"

type lvmWriteTarget struct {
	Pod               string          `json:"pod"`
	UID               string          `json:"uid"`
	SourceIncarnation string          `json:"sourceIncarnation"`
	Target            migrationTarget `json:"target"`
}

// Persist the exact destination before preparation. A restart of either process
// invalidates the attempt; controller restarts cannot silently choose a new peer.
// Only a destination content receipt permits the later endpoint change.
func (r *KuraInstanceReconciler) lvmWritesPrepared(ctx context.Context, instance *kurav1.KuraInstance, source *corev1.Pod) (bool, error) {
	if instance.Spec.StorageClassName != thinLocalStorageClass {
		return true, nil
	}
	status, err := r.runtimeStatusClient(instance).Status(ctx, *source)
	if err != nil || status.invalidObservation || status.ConnectionIncarnation == "" {
		return false, err
	}
	var intent lvmWriteTarget
	if raw := source.Annotations[lvmWriteTargetAnnotation]; raw != "" {
		if err := json.Unmarshal([]byte(raw), &intent); err != nil {
			return false, err
		}
	} else {
		if source.Annotations[lvmRebuildAnnotation] != "" {
			return false, fmt.Errorf("thin migration has no destination-bound write intent")
		}
		pods := &corev1.PodList{}
		if err := r.List(ctx, pods, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
			return false, err
		}
		sort.Slice(pods.Items, func(i, j int) bool { return pods.Items[i].Name < pods.Items[j].Name })
		for _, candidate := range pods.Items {
			if candidate.Name == source.Name || candidate.DeletionTimestamp != nil || !podReady(&candidate) || candidate.Annotations[lvmRebuildAnnotation] != "" {
				continue
			}
			sample, err := r.runtimeStatusClient(instance).Status(ctx, candidate)
			if err != nil || sample.invalidObservation || !sample.Ready || sample.ConnectionIncarnation == "" || sample.BackfillInitialCycle != backfillCycleComplete || sample.BackfillBudgetExhaustedRealPeers != 0 {
				continue
			}
			intent = lvmWriteTarget{Pod: candidate.Name, UID: string(candidate.UID), SourceIncarnation: status.ConnectionIncarnation, Target: migrationTarget{URL: renderPodNodeURL(instance, candidate.Name, instance.Namespace), Incarnation: sample.ConnectionIncarnation}}
			break
		}
		if intent.Pod == "" {
			return false, nil
		}
		raw, err := json.Marshal(intent)
		if err != nil {
			return false, err
		}
		before := source.DeepCopy()
		if source.Annotations == nil {
			source.Annotations = map[string]string{}
		}
		source.Annotations[lvmWriteTargetAnnotation] = string(raw)
		return false, r.Patch(ctx, source, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
	}
	if status.ConnectionIncarnation != intent.SourceIncarnation {
		return false, fmt.Errorf("migration source restarted")
	}
	destination := &corev1.Pod{}
	if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: intent.Pod}, destination); err != nil {
		return false, err
	}
	if string(destination.UID) != intent.UID || destination.DeletionTimestamp != nil || !podReady(destination) || intent.Target.URL != renderPodNodeURL(instance, destination.Name, instance.Namespace) {
		return false, fmt.Errorf("migration destination changed")
	}
	sample, err := r.runtimeStatusClient(instance).Status(ctx, *destination)
	if err != nil || sample.invalidObservation || !sample.Ready || sample.ConnectionIncarnation != intent.Target.Incarnation {
		return false, fmt.Errorf("migration destination process unavailable or changed: %v", err)
	}
	secret := &corev1.Secret{}
	if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: peerTLSSecretName(instance)}, secret); err != nil {
		return false, err
	}
	var preparer migrationPreparer = tlsPublicConnectionRetirer{}
	if r.PublicConnectionRetirer != nil {
		var ok bool
		preparer, ok = r.PublicConnectionRetirer.(migrationPreparer)
		if !ok {
			return false, fmt.Errorf("migration preparation unavailable")
		}
	}
	serverName := fmt.Sprintf("%s-headless.%s.svc.cluster.local", instance.Name, instance.Namespace)
	return preparer.Prepare(ctx, *source, serverName, status.ConnectionIncarnation, intent.Target, secret.Data)
}

func (r *KuraInstanceReconciler) lvmDestinationServing(ctx context.Context, instance *kurav1.KuraInstance, source *corev1.Pod) (bool, error) {
	if instance.Spec.StorageClassName != thinLocalStorageClass {
		return r.servedByAnotherPod(ctx, instance, source.Name)
	}
	var intent lvmWriteTarget
	if err := json.Unmarshal([]byte(source.Annotations[lvmWriteTargetAnnotation]), &intent); err != nil {
		return false, err
	}
	endpoints := &corev1.Endpoints{}
	if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: instance.Name}, endpoints); err != nil {
		return false, client.IgnoreNotFound(err)
	}
	count := 0
	for _, subset := range endpoints.Subsets {
		for _, address := range subset.Addresses {
			if address.TargetRef == nil || address.TargetRef.Name != intent.Pod || string(address.TargetRef.UID) != intent.UID {
				return false, nil
			}
			count++
		}
	}
	return count > 0, nil
}
