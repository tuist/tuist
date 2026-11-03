package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"

	kurav1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
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
		return false, r.patchLVMWriteTarget(ctx, source, intent)
	}
	if status.ConnectionIncarnation != intent.SourceIncarnation {
		// The restarted source acknowledged writes no bridge proved, so it is
		// prepared again from the beginning before anything may move.
		intent.SourceIncarnation = status.ConnectionIncarnation
		return false, r.patchLVMWriteTarget(ctx, source, intent)
	}
	destination := &corev1.Pod{}
	if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: intent.Pod}, destination); err != nil {
		return false, err
	}
	if destination.DeletionTimestamp != nil || !podReady(destination) || intent.Target.URL != renderPodNodeURL(instance, destination.Name, instance.Namespace) {
		return false, fmt.Errorf("migration destination changed")
	}
	sample, err := r.runtimeStatusClient(instance).Status(ctx, *destination)
	if err != nil || sample.invalidObservation || !sample.Ready || sample.ConnectionIncarnation == "" {
		return false, fmt.Errorf("migration destination process unavailable: %v", err)
	}
	secret := &corev1.Secret{}
	if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: peerTLSSecretName(instance)}, secret); err != nil {
		return false, err
	}
	preparer, err := r.lvmMigrationPreparer()
	if err != nil {
		return false, err
	}
	serverName := fmt.Sprintf("%s-headless.%s.svc.cluster.local", instance.Name, instance.Namespace)
	if string(destination.UID) != intent.UID && sample.ConnectionIncarnation == intent.Target.Incarnation {
		return false, fmt.Errorf("migration destination changed")
	}
	if sample.ConnectionIncarnation != intent.Target.Incarnation {
		// The destination restarted its process, in the same pod or a replacement
		// at the same URL. The source keeps refusing unproven writes and
		// re-proves its retained data on the new process; the intent names that
		// process only after the source accepted it.
		replacement := migrationTarget{URL: intent.Target.URL, Incarnation: sample.ConnectionIncarnation}
		if err := preparer.Rebind(ctx, *source, serverName, status.ConnectionIncarnation, intent.Target, replacement, secret.Data); err != nil {
			return false, fmt.Errorf("migration destination restarted: %w", err)
		}
		intent.UID = string(destination.UID)
		intent.Target = replacement
		return false, r.patchLVMWriteTarget(ctx, source, intent)
	}
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

func (r *KuraInstanceReconciler) patchLVMWriteTarget(ctx context.Context, source *corev1.Pod, intent lvmWriteTarget) error {
	raw, err := json.Marshal(intent)
	if err != nil {
		return err
	}
	before := source.DeepCopy()
	if source.Annotations == nil {
		source.Annotations = map[string]string{}
	}
	source.Annotations[lvmWriteTargetAnnotation] = string(raw)
	return r.Patch(ctx, source, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
}

func (r *KuraInstanceReconciler) lvmMigrationPreparer() (migrationPreparer, error) {
	if r.PublicConnectionRetirer == nil {
		return tlsPublicConnectionRetirer{}, nil
	}
	preparer, ok := r.PublicConnectionRetirer.(migrationPreparer)
	if !ok {
		return nil, fmt.Errorf("migration preparation unavailable")
	}
	return preparer, nil
}

// Clearing the source node's selection pauses a thin migration. A source that
// was never demoted still serves its own endpoint, so its bridge guards a move
// that will not happen and only slows its writes; the source is returned to
// ordinary replication. A demoted source may already have moved routing and
// keeps its bridge until the move completes.
func (r *KuraInstanceReconciler) abortUnselectedLVMHandoffs(ctx context.Context, instance *kurav1.KuraInstance) error {
	if instance.Spec.StorageClassName != thinLocalStorageClass {
		return nil
	}
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
		return err
	}
	for i := range pods.Items {
		source := &pods.Items[i]
		raw := source.Annotations[lvmWriteTargetAnnotation]
		if raw == "" || source.Annotations[lvmRebuildAnnotation] != "" || source.DeletionTimestamp != nil {
			continue
		}
		selected, err := r.lvmSourceSelected(ctx, instance, source.Name)
		if err != nil || selected {
			return err
		}
		var intent lvmWriteTarget
		if err := json.Unmarshal([]byte(raw), &intent); err != nil {
			return err
		}
		status, err := r.runtimeStatusClient(instance).Status(ctx, *source)
		if err != nil || status.invalidObservation || status.ConnectionIncarnation == "" {
			continue
		}
		secret := &corev1.Secret{}
		if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: peerTLSSecretName(instance)}, secret); err != nil {
			return err
		}
		preparer, err := r.lvmMigrationPreparer()
		if err != nil {
			return err
		}
		serverName := fmt.Sprintf("%s-headless.%s.svc.cluster.local", instance.Name, instance.Namespace)
		if err := preparer.Abort(ctx, *source, serverName, status.ConnectionIncarnation, intent.Target, secret.Data); err != nil {
			return fmt.Errorf("abort migration of %s: %w", source.Name, err)
		}
		before := source.DeepCopy()
		delete(source.Annotations, lvmWriteTargetAnnotation)
		if err := r.Patch(ctx, source, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
			return err
		}
		log.FromContext(ctx).Info("aborted thin migration handoff of an unselected source", "pod", source.Name, "destination", intent.Pod)
	}
	return nil
}

// lvmSourceSelected reports whether a pod may still hand off its volume: its
// claim is pinned to the selected source node, or it is a single-copy
// migration's standby handing the endpoint back.
func (r *KuraInstanceReconciler) lvmSourceSelected(ctx context.Context, instance *kurav1.KuraInstance, pod string) (bool, error) {
	ordinal, ok := podOrdinal(pod, instance.Name)
	if !ok {
		return true, nil
	}
	claim := &corev1.PersistentVolumeClaim{}
	if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: fmt.Sprintf("data-%s-%d", instance.Name, ordinal)}, claim); err != nil {
		if apierrors.IsNotFound(err) {
			return true, nil
		}
		return true, err
	}
	if ordinal == 1 && claim.Annotations[lvmMigrationStandbyAnnotation] != "" && claim.DeletionTimestamp == nil {
		return true, nil
	}
	if claim.Spec.VolumeName == "" {
		return true, nil
	}
	pv := &corev1.PersistentVolume{}
	if err := r.Get(ctx, client.ObjectKey{Name: claim.Spec.VolumeName}, pv); err != nil {
		return true, client.IgnoreNotFound(err)
	}
	hosts := pvRequiredHostnames(pv)
	if len(hosts) != 1 {
		return true, nil
	}
	node := &corev1.Node{}
	if err := r.Get(ctx, client.ObjectKey{Name: hosts[0]}, node); err != nil {
		return true, client.IgnoreNotFound(err)
	}
	return node.Annotations[lvmMigrationNodeAnnotation] == "true", nil
}
