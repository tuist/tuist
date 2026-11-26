package controllers

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// primaryHandoffRolloutAnnotation marks an OnDelete strategy the controller set
// so a pod template change replaces the standbys first and the routed primary
// last, once the client and peer roles have moved to an updated, caught-up
// replica.
//
// A RollingUpdate cannot do that. It replaces the highest ordinal first and
// moves on as soon as the replacement is Ready, whichever pod the client
// Service pins: on a two-replica instance whose primary is ordinal 0, it
// deletes the primary a second after its standby came back, before the standby
// is routable for primary selection, and every write in between is answered
// "server is draining" (an N26 us-east rollout, 2026-11-24: ten seconds of
// refused uploads between the primary's deletion and the Service moving).
const primaryHandoffRolloutAnnotation = "kura.tuist.dev/primary-handoff-rollout"

// renderedTemplateDigestAnnotation records a digest of the pod template the
// controller last rendered. A template change is detected against that render,
// not against the live template, which carries the API server's defaults and
// never equals a fresh render.
const renderedTemplateDigestAnnotation = "kura.tuist.dev/rendered-template-digest"

// primaryHandoffEligible reports whether a template change can roll behind a
// primary handoff. A single replica has no successor to hand to, and fencing
// and replica recovery own the update strategy themselves.
func primaryHandoffEligible(instance *kurav1alpha1.KuraInstance) bool {
	return replicas(instance) >= 2 && !fencedServing(instance) &&
		instance.Spec.ReplicaRecovery == nil && instance.Status.ReplicaRecovery == nil
}

func renderedTemplateDigest(template *corev1.PodTemplateSpec) string {
	raw, err := json.Marshal(template)
	if err != nil {
		return ""
	}
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])
}

// holdTemplateChangeForPrimaryHandoff puts a changed template on the primary
// handoff's hold in the same write that changes it, before the StatefulSet
// controller can act on a RollingUpdate. Only a plain rolling update is taken
// over: an OnDelete or a partition already belongs to an operator, a recovery,
// a storage resize or an in-place CPU resize. A StatefulSet without a recorded
// digest only records one, so the first pass after this controller deploys
// cannot mistake its own render for a change.
func holdTemplateChangeForPrimaryHandoff(instance *kurav1alpha1.KuraInstance, sts *appsv1.StatefulSet) {
	digest := renderedTemplateDigest(&sts.Spec.Template)
	previous, recorded := sts.Annotations[renderedTemplateDigestAnnotation]
	if sts.Annotations == nil {
		sts.Annotations = map[string]string{}
	}
	sts.Annotations[renderedTemplateDigestAnnotation] = digest
	if sts.ResourceVersion == "" || !recorded || previous == digest || !primaryHandoffEligible(instance) {
		return
	}
	if sts.Spec.UpdateStrategy.Type == appsv1.OnDeleteStatefulSetStrategyType || rollingPartitioned(sts) {
		return
	}
	holdForPrimaryHandoff(sts)
}

func holdForPrimaryHandoff(sts *appsv1.StatefulSet) {
	sts.Spec.UpdateStrategy = appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType}
	if sts.Annotations == nil {
		sts.Annotations = map[string]string{}
	}
	sts.Annotations[primaryHandoffRolloutAnnotation] = "true"
}

// releaseControllerRolloutHold ends a storage or CPU resize hold. Template
// drift queued up under it still has to roll, so unless the StatefulSet
// already counts every replica as updated, an instance that can hand its
// primary over moves to that hold rather than to a RollingUpdate that would
// replace the primary unannounced.
func releaseControllerRolloutHold(instance *kurav1alpha1.KuraInstance, sts *appsv1.StatefulSet) {
	delete(sts.Annotations, resizeRolloutHoldAnnotation)
	delete(sts.Annotations, cpuResizeHoldAnnotation)
	current := sts.Status.ObservedGeneration >= sts.Generation && sts.Status.UpdateRevision != "" &&
		sts.Status.Replicas == replicas(instance) && sts.Status.UpdatedReplicas == sts.Status.Replicas
	if primaryHandoffEligible(instance) && !current {
		holdForPrimaryHandoff(sts)
		return
	}
	sts.Spec.UpdateStrategy = appsv1.StatefulSetUpdateStrategy{
		Type:          appsv1.RollingUpdateStatefulSetStrategyType,
		RollingUpdate: &appsv1.RollingUpdateStatefulSetStrategy{Partition: ptr(int32(0))},
	}
}

// primaryHandoffHeld reports whether the StatefulSet is on the primary
// handoff's hold.
func primaryHandoffHeld(sts *appsv1.StatefulSet) bool {
	_, held := sts.Annotations[primaryHandoffRolloutAnnotation]
	return held && sts.Spec.UpdateStrategy.Type == appsv1.OnDeleteStatefulSetStrategyType
}

// primaryHandoffDemotions names the pod a held rollout replaces last, so
// primary and gateway selection move both roles off it first. Only the last
// stale pod is demoted: until then the roles stay where they are, which is
// where a RollingUpdate would leave them too, and demoteEvacuatingPods still
// moves nothing until an updated replica is Ready, routable and caught up.
func primaryHandoffDemotions(sts *appsv1.StatefulSet, pods []corev1.Pod) map[string]bool {
	if sts == nil || !primaryHandoffHeld(sts) || sts.Status.UpdateRevision == "" {
		return nil
	}
	stale := map[string]bool{}
	for i := range pods {
		if pods[i].DeletionTimestamp == nil && pods[i].Labels[appsv1.ControllerRevisionHashLabelKey] != sts.Status.UpdateRevision {
			stale[pods[i].Name] = true
		}
	}
	if len(stale) != 1 {
		return nil
	}
	return stale
}

// primaryHandoffStep is the one thing a held rollout does next.
type primaryHandoffStep struct {
	release bool
	replace *corev1.Pod
	// handoff marks the last stale pod, which primary and gateway selection
	// have been told to step off: it is deleted only once both planes have
	// observably moved.
	handoff bool
	wait    string
}

// nextPrimaryHandoffStep replaces one stale pod at a time, every other pod
// Ready, the routed primary last. A stale pod that is not Ready serves
// nothing, so it is replaced at once; that is the case a RollingUpdate cannot
// advance past.
func nextPrimaryHandoffStep(instanceName string, want int32, pods []corev1.Pod, updateRevision, primary string) primaryHandoffStep {
	var stale []*corev1.Pod
	for i := range pods {
		pod := &pods[i]
		if pod.DeletionTimestamp != nil {
			return primaryHandoffStep{wait: fmt.Sprintf("pod %s is terminating", pod.Name)}
		}
		if pod.Labels[appsv1.ControllerRevisionHashLabelKey] != updateRevision {
			stale = append(stale, pod)
		}
	}
	if int32(len(pods)) < want {
		return primaryHandoffStep{wait: fmt.Sprintf("%d/%d replicas exist", len(pods), want)}
	}
	if len(stale) == 0 {
		return primaryHandoffStep{release: true}
	}
	sort.Slice(stale, func(i, j int) bool {
		left, _ := podOrdinal(stale[i].Name, instanceName)
		right, _ := podOrdinal(stale[j].Name, instanceName)
		return left > right
	})
	for _, pod := range stale {
		if pod.Name != primary && !podReady(pod) {
			return primaryHandoffStep{replace: pod}
		}
	}
	for i := range pods {
		if !podReady(&pods[i]) {
			return primaryHandoffStep{wait: fmt.Sprintf("pod %s is not ready", pods[i].Name)}
		}
	}
	if len(stale) > 1 {
		for _, pod := range stale {
			if pod.Name != primary {
				return primaryHandoffStep{replace: pod}
			}
		}
	}
	if stale[0].Name == primary {
		return primaryHandoffStep{wait: fmt.Sprintf("primary %s waits for an updated, caught-up replica to take its role", primary)}
	}
	return primaryHandoffStep{replace: stale[0], handoff: true}
}

// reconcilePrimaryHandoffRollout advances a held rollout by one step and
// reports whether it is still in flight. primary is the pod this pass's
// primary selection routed the client Service to.
func (r *KuraInstanceReconciler) reconcilePrimaryHandoffRollout(ctx context.Context, instance *kurav1alpha1.KuraInstance, primary string) (bool, error) {
	reader := r.APIReader
	if reader == nil {
		reader = r.Client
	}
	// Read through to the apiserver: a cached StatefulSet from before this
	// pass's template write still names the previous update revision, and
	// every pod would look current against it.
	sts := &appsv1.StatefulSet{}
	if err := reader.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		return false, client.IgnoreNotFound(err)
	}
	if _, held := sts.Annotations[primaryHandoffRolloutAnnotation]; !held || sts.DeletionTimestamp != nil {
		return false, nil
	}
	logger := log.FromContext(ctx)
	if !primaryHandoffHeld(sts) || !primaryHandoffEligible(instance) {
		// Another owner took the strategy (fencing, recovery, a resize); leave
		// its strategy and forget the marker.
		before := sts.DeepCopy()
		delete(sts.Annotations, primaryHandoffRolloutAnnotation)
		return false, r.Patch(ctx, sts, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
	}
	if sts.Status.ObservedGeneration < sts.Generation || sts.Status.UpdateRevision == "" {
		return true, nil
	}
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
		return false, err
	}
	step := nextPrimaryHandoffStep(instance.Name, replicas(instance), pods.Items, sts.Status.UpdateRevision, primary)
	switch {
	case step.release:
		// The StatefulSet controller decides what to replace from its own pod
		// cache; release only once its status counts every replica as updated.
		if sts.Status.Replicas != replicas(instance) || sts.Status.UpdatedReplicas != sts.Status.Replicas {
			return true, nil
		}
		before := sts.DeepCopy()
		delete(sts.Annotations, primaryHandoffRolloutAnnotation)
		sts.Spec.UpdateStrategy = appsv1.StatefulSetUpdateStrategy{
			Type:          appsv1.RollingUpdateStatefulSetStrategyType,
			RollingUpdate: &appsv1.RollingUpdateStatefulSetStrategy{Partition: ptr(int32(0))},
		}
		if err := r.Patch(ctx, sts, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
			return true, err
		}
		logger.Info("released Kura StatefulSet rollout after the primary handoff")
		return false, nil
	case step.replace == nil:
		logger.V(1).Info("holding Kura rollout", "reason", step.wait)
		return true, nil
	}
	pod := step.replace
	if step.handoff {
		// A repointed selector is a write; a ready endpoint behind another pod
		// is the fact the deletion rests on, for both pinned planes.
		served, err := r.servedByAnotherPod(ctx, instance, pod.Name)
		if err != nil || !served {
			return true, err
		}
		released, err := r.peerPlaneReleased(ctx, instance, pod.Name)
		if err != nil || !released {
			return true, err
		}
	}
	err := r.Delete(ctx, pod, &client.DeleteOptions{Preconditions: &metav1.Preconditions{UID: &pod.UID, ResourceVersion: &pod.ResourceVersion}})
	if apierrors.IsNotFound(err) || apierrors.IsConflict(err) {
		return true, nil
	}
	if err != nil {
		return true, err
	}
	logger.Info("replacing Kura pod for a template change", "pod", pod.Name, "ready", podReady(pod), "afterHandoff", step.handoff)
	return true, nil
}
