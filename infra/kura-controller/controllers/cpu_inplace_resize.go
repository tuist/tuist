package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/equality"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// cpuResizeHoldAnnotation marks an OnDelete strategy the controller set so a
// CPU request change can reach running pods through pods/resize instead of a
// rolling restart. Its value is the time the templated request last changed.
const cpuResizeHoldAnnotation = "kura.tuist.dev/cpu-resize-hold"

const (
	// A hold whose templated request has not moved for this long falls back to
	// the rolling update, so a resize the kubelet never completes costs no more
	// than the restart it was meant to avoid.
	cpuResizeStallTimeout = 5 * time.Minute

	// Deferred means the node cannot fit the raise now but may once another
	// pod's room frees up, and the kubelet retries it on its own. The running
	// pod keeps its current share meanwhile, so waiting costs nothing.
	cpuResizeDeferredGrace = 2 * time.Minute
)

// Condition types and reasons the kubelet reports for an in-place resize.
// k8s.io/api v0.32 predates their constants.
const (
	podResizePendingCondition    corev1.PodConditionType = "PodResizePending"
	podResizeInProgressCondition corev1.PodConditionType = "PodResizeInProgress"
	podResizeReasonInfeasible                            = "Infeasible"
	podResizeReasonDeferred                              = "Deferred"
)

// holdCPURequestChange puts a template whose only purpose this pass may be a
// new CPU request on OnDelete, in the same write that changes it. A StatefulSet
// revision covers the whole pod template, so on RollingUpdate the request
// change alone restarts every pod, draining clients mid-upload under exactly the
// load that asked for the raise. reconcileCPUResizeHold then resizes the pods in
// place and releases the hold, or releases it straight away when the new
// revision changes anything else.
//
// Only a plain rolling update is taken over. An OnDelete or a partition
// belongs to an operator, a recovery or a storage resize, and a new
// StatefulSet has no pods to restart.
func holdCPURequestChange(sts *appsv1.StatefulSet, previous *corev1.PodTemplateSpec, now time.Time) {
	if sts.ResourceVersion == "" || templateCPURequestMilli(previous) == templateCPURequestMilli(&sts.Spec.Template) {
		return
	}
	if _, held := sts.Annotations[cpuResizeHoldAnnotation]; held {
		sts.Annotations[cpuResizeHoldAnnotation] = now.UTC().Format(time.RFC3339)
		return
	}
	if sts.Spec.UpdateStrategy.Type == appsv1.OnDeleteStatefulSetStrategyType || rollingPartitioned(sts) {
		return
	}
	sts.Spec.UpdateStrategy = appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType}
	if sts.Annotations == nil {
		sts.Annotations = map[string]string{}
	}
	sts.Annotations[cpuResizeHoldAnnotation] = now.UTC().Format(time.RFC3339)
}

// reconcileCPUResizeHold brings every pod of a held StatefulSet to the update
// revision without restarting it. A pod whose revision differs from the update
// revision only in the kura container's CPU request is resized through
// pods/resize and, once the kubelet has applied the new request, relabelled
// with the update revision, which is all the StatefulSet controller compares.
// The hold is released once the StatefulSet controller itself counts every
// replica as updated, so the restored rolling update finds nothing to replace.
//
// Anything else falls back to the rolling update the hold deferred: a revision
// that changes more than the request, a resize the API refuses (a QoS class
// change, for one), or a hold that stops making progress.
func (r *KuraInstanceReconciler) reconcileCPUResizeHold(ctx context.Context, instance *kurav1alpha1.KuraInstance, now time.Time) error {
	reader := r.APIReader
	if reader == nil {
		reader = r.Client
	}
	// Read through to the apiserver: a cached StatefulSet from before this
	// pass's template write still names the previous update revision, and
	// every pod would look current against it.
	sts := &appsv1.StatefulSet{}
	if err := reader.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		return client.IgnoreNotFound(err)
	}
	stamp, held := sts.Annotations[cpuResizeHoldAnnotation]
	if !held || sts.DeletionTimestamp != nil {
		return nil
	}
	if sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType ||
		fencedServing(instance) || instance.Spec.ReplicaRecovery != nil || instance.Status.ReplicaRecovery != nil {
		return r.dropCPUResizeHold(ctx, sts)
	}
	if since, err := time.Parse(time.RFC3339, stamp); err != nil || now.Sub(since) >= cpuResizeStallTimeout {
		log.FromContext(ctx).Info("in-place CPU resize made no progress; falling back to a rolling update", "heldSince", stamp)
		return r.releaseCPUResizeHold(ctx, sts)
	}
	if sts.Status.ObservedGeneration < sts.Generation || sts.Status.UpdateRevision == "" {
		return nil
	}
	target, err := r.revisionTemplate(ctx, reader, sts, sts.Status.UpdateRevision)
	if err != nil {
		return client.IgnoreNotFound(err)
	}
	want := templateCPURequestMilli(target)
	if want <= 0 || want != templateCPURequestMilli(&sts.Spec.Template) {
		return nil
	}

	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
		return err
	}
	settled := true
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.DeletionTimestamp != nil {
			settled = false
			continue
		}
		revision := pod.Labels[appsv1.ControllerRevisionHashLabelKey]
		current := revision == sts.Status.UpdateRevision
		if current && podCPURequestMilli(pod) == want {
			continue
		}
		settled = false
		if !current {
			from, err := r.revisionTemplate(ctx, reader, sts, revision)
			if err != nil && !apierrors.IsNotFound(err) {
				return err
			}
			if err != nil || !templatesDifferOnlyInCPURequest(from, target) {
				log.FromContext(ctx).Info("Kura StatefulSet revision changes more than the CPU request; rolling", "pod", pod.Name, "fromRevision", revision, "toRevision", sts.Status.UpdateRevision)
				return r.releaseCPUResizeHold(ctx, sts)
			}
		}
		if pod.Spec.NodeName == "" {
			// Nothing serves from an unscheduled pod, and OnDelete recreates it
			// from the update revision.
			err := r.Delete(ctx, pod, &client.DeleteOptions{Preconditions: &metav1.Preconditions{UID: &pod.UID, ResourceVersion: &pod.ResourceVersion}})
			if err != nil && !apierrors.IsNotFound(err) && !apierrors.IsConflict(err) {
				return err
			}
			continue
		}
		if podCPURequestMilli(pod) != want {
			if err := r.resizePodCPU(ctx, pod, want); err != nil {
				if apierrors.IsNotFound(err) || apierrors.IsConflict(err) {
					continue
				}
				log.FromContext(ctx).Info("in-place CPU resize refused; falling back to a rolling update", "pod", pod.Name, "error", err.Error())
				return r.releaseCPUResizeHold(ctx, sts)
			}
			log.FromContext(ctx).Info("resizing Kura pod CPU request in place", "pod", pod.Name, "fromMilli", podCPURequestMilli(pod), "toMilli", want)
			continue
		}
		if current || !podCPUResizeApplied(pod, want) {
			continue
		}
		if err := r.relabelPodRevision(ctx, pod, sts.Status.UpdateRevision); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
	}
	// The StatefulSet controller decides what to replace from its own pod
	// cache. Releasing before its status counts every replica as updated could
	// let it act on a pod whose relabel it has not observed yet.
	if !settled || sts.Status.Replicas != replicas(instance) || sts.Status.UpdatedReplicas != sts.Status.Replicas {
		return nil
	}
	return r.releaseCPUResizeHold(ctx, sts)
}

func (r *KuraInstanceReconciler) releaseCPUResizeHold(ctx context.Context, sts *appsv1.StatefulSet) error {
	before := sts.DeepCopy()
	delete(sts.Annotations, cpuResizeHoldAnnotation)
	sts.Spec.UpdateStrategy = appsv1.StatefulSetUpdateStrategy{
		Type:          appsv1.RollingUpdateStatefulSetStrategyType,
		RollingUpdate: &appsv1.RollingUpdateStatefulSetStrategy{Partition: ptr(int32(0))},
	}
	return r.Patch(ctx, sts, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
}

// dropCPUResizeHold forgets the marker once another owner has taken the
// update strategy, leaving that owner's strategy in place.
func (r *KuraInstanceReconciler) dropCPUResizeHold(ctx context.Context, sts *appsv1.StatefulSet) error {
	before := sts.DeepCopy()
	delete(sts.Annotations, cpuResizeHoldAnnotation)
	return r.Patch(ctx, sts, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
}

// resizePodCPU patches the kura container's CPU request through the resize
// subresource. It has to be a strategic merge patch: a JSON merge patch
// replaces the whole containers list and the API rejects the requests it drops.
func (r *KuraInstanceReconciler) resizePodCPU(ctx context.Context, pod *corev1.Pod, milli int32) error {
	patch, err := json.Marshal(map[string]any{
		"spec": map[string]any{
			"containers": []map[string]any{{
				"name": kuraContainerName,
				"resources": map[string]any{
					"requests": map[string]string{string(corev1.ResourceCPU): fmt.Sprintf("%dm", milli)},
				},
			}},
		},
	})
	if err != nil {
		return err
	}
	return r.SubResource("resize").Patch(ctx, pod, client.RawPatch(types.StrategicMergePatchType, patch))
}

func (r *KuraInstanceReconciler) relabelPodRevision(ctx context.Context, pod *corev1.Pod, revision string) error {
	patch, err := json.Marshal(map[string]any{
		"metadata": map[string]any{
			"uid":    pod.UID,
			"labels": map[string]string{appsv1.ControllerRevisionHashLabelKey: revision},
		},
	})
	if err != nil {
		return err
	}
	if err := r.Patch(ctx, pod, client.RawPatch(types.MergePatchType, patch)); err != nil {
		return err
	}
	log.FromContext(ctx).Info("Kura pod reached the StatefulSet update revision in place", "pod", pod.Name, "revision", revision)
	return nil
}

// revisionTemplate decodes the pod template a ControllerRevision of sts
// recorded. The StatefulSet controller stores it as a patch of the form
// {"spec":{"template":{...,"$patch":"replace"}}}.
func (r *KuraInstanceReconciler) revisionTemplate(ctx context.Context, reader client.Reader, sts *appsv1.StatefulSet, name string) (*corev1.PodTemplateSpec, error) {
	if name == "" {
		return nil, apierrors.NewNotFound(appsv1.Resource("controllerrevisions"), name)
	}
	revision := &appsv1.ControllerRevision{}
	if err := reader.Get(ctx, types.NamespacedName{Name: name, Namespace: sts.Namespace}, revision); err != nil {
		return nil, err
	}
	if !metav1.IsControlledBy(revision, sts) {
		return nil, apierrors.NewNotFound(appsv1.Resource("controllerrevisions"), name)
	}
	var data struct {
		Spec struct {
			Template corev1.PodTemplateSpec `json:"template"`
		} `json:"spec"`
	}
	if err := json.Unmarshal(revision.Data.Raw, &data); err != nil {
		return nil, fmt.Errorf("decode controller revision %s: %w", name, err)
	}
	return &data.Spec.Template, nil
}

func templatesDifferOnlyInCPURequest(a, b *corev1.PodTemplateSpec) bool {
	if templateCPURequestMilli(a) <= 0 || templateCPURequestMilli(b) <= 0 {
		return false
	}
	a, b = a.DeepCopy(), b.DeepCopy()
	for _, template := range []*corev1.PodTemplateSpec{a, b} {
		for i := range template.Spec.Containers {
			if template.Spec.Containers[i].Name == kuraContainerName {
				delete(template.Spec.Containers[i].Resources.Requests, corev1.ResourceCPU)
			}
		}
	}
	return equality.Semantic.DeepEqual(a, b)
}

func templateCPURequestMilli(template *corev1.PodTemplateSpec) int32 {
	if template == nil {
		return 0
	}
	return podCPURequestMilli(&corev1.Pod{Spec: template.Spec})
}

// podCPUResizeApplied reports that the kubelet has applied milli to the kura
// container: no resize is pending or in progress, and the container's
// reported resources carry the request.
func podCPUResizeApplied(pod *corev1.Pod, milli int32) bool {
	for _, condition := range pod.Status.Conditions {
		if (condition.Type == podResizePendingCondition || condition.Type == podResizeInProgressCondition) && condition.Status == corev1.ConditionTrue {
			return false
		}
	}
	for _, status := range pod.Status.ContainerStatuses {
		if status.Name != kuraContainerName || status.Resources == nil {
			continue
		}
		return status.Resources.Requests.Cpu().MilliValue() == int64(milli)
	}
	return false
}

// podResizeStuckOnCPU is true when the kubelet will not apply the pod's
// requested CPU on its node: Infeasible at once, Deferred once it has had time
// to free up. The controller only ever resizes CPU, so a pending resize of a
// Kura pod is a CPU one.
func podResizeStuckOnCPU(pod *corev1.Pod, now time.Time) bool {
	for _, condition := range pod.Status.Conditions {
		if condition.Type != podResizePendingCondition || condition.Status != corev1.ConditionTrue {
			continue
		}
		switch condition.Reason {
		case podResizeReasonInfeasible:
			return true
		case podResizeReasonDeferred:
			return now.Sub(condition.LastTransitionTime.Time) >= cpuResizeDeferredGrace
		}
	}
	return false
}
