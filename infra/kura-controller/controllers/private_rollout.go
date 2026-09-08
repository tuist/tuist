package controllers

import (
	"context"
	"encoding/json"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	discoveryv1 "k8s.io/api/discovery/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const privateRolloutHandoverAnnotation = "kura.tuist.dev/private-rollout-handover"

// Private two-replica caches cannot let StatefulSet readiness alone advance a
// rollout: readiness may latch before catch-up, and deleting the primary before
// repointing its NodePort leaves running jobs with an empty endpoint.
func privateRolloutEnabled(instance *kurav1alpha1.KuraInstance) bool {
	return instance.Spec.Private && replicas(instance) == 2
}

func privateRolloutWarm(pod *corev1.Pod, samples map[string]runtimeStatus, ringMembers int32) bool {
	status, ok := samples[pod.Name]
	return ok && podReady(pod) && runtimeStatusRoutable(status, ringMembers) &&
		status.BackfillInitialCycle == backfillCycleComplete && status.OutboxMessages == 0
}

func privateRolloutPair(instance *kurav1alpha1.KuraInstance, pods []corev1.Pod) bool {
	if len(pods) != 2 {
		return false
	}
	seen := map[int]bool{}
	for i := range pods {
		ordinal, ok := podOrdinal(pods[i].Name, instance.Name)
		if !ok || ordinal < 0 || ordinal > 1 || seen[ordinal] || pods[i].DeletionTimestamp != nil {
			return false
		}
		seen[ordinal] = true
	}
	return true
}

// Only planned handovers require catch-up. An unhealthy primary can still fail
// over through the existing routability path, accepting the mesh's usual async
// consistency window rather than leaving an already-broken endpoint in place.
func (r *KuraInstanceReconciler) privateRolloutPrimary(ctx context.Context, instance *kurav1alpha1.KuraInstance, current string,
	pods []corev1.Pod, samples map[string]runtimeStatus, health map[string]bool,
) (string, error) {
	fallback := choosePrimaryPod(current, instance.Name, pods, health)
	for i := range pods {
		if pods[i].Name == current && podReady(&pods[i]) && runtimeStatusRoutable(samples[current], 1) {
			// During scale-up the original process can still see only itself.
			// It remains a valid serving endpoint; the new replica must not steal
			// traffic merely because it sees the expanded ring first.
			fallback = current
		}
	}
	if fallback != current || !privateRolloutPair(instance, pods) {
		return fallback, nil
	}
	if instance.Spec.ExposeNodePort && (pods[0].Spec.NodeName == "" || pods[0].Spec.NodeName != pods[1].Spec.NodeName) {
		return fallback, nil
	}
	sts := &appsv1.StatefulSet{}
	if err := r.Get(ctx, client.ObjectKeyFromObject(instance), sts); apierrors.IsNotFound(err) {
		return fallback, nil
	} else if err != nil {
		return "", err
	}
	if !privateRolloutRevisionObserved(sts) {
		return fallback, nil
	}
	var primary, standby *corev1.Pod
	for i := range pods {
		if pods[i].Name == current {
			primary = &pods[i]
		} else {
			standby = &pods[i]
		}
	}
	if primary == nil || standby == nil || primary.Labels[appsv1.StatefulSetRevisionLabel] == sts.Status.UpdateRevision ||
		standby.Labels[appsv1.StatefulSetRevisionLabel] != sts.Status.UpdateRevision {
		return fallback, nil
	}
	if privateRolloutWarm(primary, samples, 2) && privateRolloutWarm(standby, samples, 2) && privateRolloutRingsAgree(samples[primary.Name], samples[standby.Name]) {
		return standby.Name, nil
	}
	return fallback, nil
}

func privateRolloutRingsAgree(a, b runtimeStatus) bool {
	if a.RingFingerprint != "" || b.RingFingerprint != "" {
		return a.RingFingerprint != "" && a.RingFingerprint == b.RingFingerprint
	}
	return a.RingMembers == b.RingMembers
}

func privateRolloutRevisionObserved(sts *appsv1.StatefulSet) bool {
	return sts.Spec.UpdateStrategy.Type == appsv1.OnDeleteStatefulSetStrategyType &&
		sts.Status.ObservedGeneration >= sts.Generation && sts.Status.UpdateRevision != ""
}

type privateRolloutHandover struct {
	Departing types.UID `json:"departing"`
	Serving   types.UID `json:"serving"`
	Revision  string    `json:"revision"`
	Since     time.Time `json:"since"`
}

// OnDelete lets us roll the standby first regardless of ordinal. Existing PVCs
// stay attached to their ordinals. A one-to-two migration creates ordinal 1 on
// the desired template before this method may touch ordinal 0, even if scaling
// and an image/configuration update arrive together.
func (r *KuraInstanceReconciler) reconcilePrivateRollout(ctx context.Context, instance *kurav1alpha1.KuraInstance, now time.Time) error {
	if !privateRolloutEnabled(instance) {
		return nil
	}
	// Use an uncached read after reconcileStatefulSet: deleting against an old
	// observed revision could otherwise replace a pod on the wrong template.
	reader := r.APIReader
	if reader == nil {
		reader = r.Client
	}
	sts := &appsv1.StatefulSet{}
	if err := reader.Get(ctx, client.ObjectKeyFromObject(instance), sts); err != nil {
		return client.IgnoreNotFound(err)
	}
	reset := func() error {
		if _, ok := sts.Annotations[privateRolloutHandoverAnnotation]; !ok {
			return nil
		}
		delete(sts.Annotations, privateRolloutHandoverAnnotation)
		return r.Update(ctx, sts)
	}
	if !privateRolloutRevisionObserved(sts) {
		return reset()
	}
	podList := &corev1.PodList{}
	if err := reader.List(ctx, podList, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
		return err
	}
	pods := podList.Items
	if !privateRolloutPair(instance, pods) {
		return reset()
	}
	service := &corev1.Service{}
	if err := reader.Get(ctx, client.ObjectKeyFromObject(instance), service); err != nil {
		return client.IgnoreNotFound(err)
	}
	var serving, departing *corev1.Pod
	for i := range pods {
		if pods[i].Name == service.Spec.Selector[podNameLabel] {
			serving = &pods[i]
		} else {
			departing = &pods[i]
		}
	}
	if serving == nil || departing == nil || departing.Labels[appsv1.StatefulSetRevisionLabel] == sts.Status.UpdateRevision {
		return reset()
	}
	samples := r.sampleRuntimeStatuses(ctx, instance, pods)
	// A failed or unschedulable standby may have left the ring entirely. The
	// healthy primary still owns the cache and can cover replacement of that
	// non-serving pod; requiring two ring members would deadlock its recovery.
	if !privateRolloutWarm(serving, samples, 1) {
		return reset()
	}
	if podReady(departing) {
		status, ok := samples[departing.Name]
		if !ok || status.OutboxMessages != 0 || !privateRolloutRingsAgree(status, samples[serving.Name]) {
			return reset()
		}
	}
	// Observe the actual cache paths, including the separate NodePort Service.
	// A selector write alone says nothing about EndpointSlice propagation.
	serviceNames := []string{instance.Name}
	if instance.Spec.ExposeNodePort {
		serviceNames = append(serviceNames, externalServiceName(instance))
	}
	for _, name := range serviceNames {
		ready, err := privateRolloutServiceReady(ctx, reader, instance.Namespace, name, serving)
		if err != nil {
			return err
		}
		if !ready {
			return reset()
		}
	}
	// Persist a propagation buffer so a controller restart cannot shorten it.
	// Reset on any regression, pod replacement or new desired revision.
	var handover privateRolloutHandover
	_ = json.Unmarshal([]byte(sts.Annotations[privateRolloutHandoverAnnotation]), &handover)
	if handover.Departing != departing.UID || handover.Serving != serving.UID || handover.Revision != sts.Status.UpdateRevision || handover.Since.IsZero() {
		handover = privateRolloutHandover{Departing: departing.UID, Serving: serving.UID, Revision: sts.Status.UpdateRevision, Since: now}
		encoded, err := json.Marshal(handover)
		if err != nil {
			return err
		}
		if sts.Annotations == nil {
			sts.Annotations = map[string]string{}
		}
		sts.Annotations[privateRolloutHandoverAnnotation] = string(encoded)
		return r.Update(ctx, sts)
	}
	if now.Sub(handover.Since) < time.Duration(preStopDelaySeconds)*time.Second {
		return nil
	}
	// Ordinary deletion invokes SIGUSR1/preStop and the full runtime drain
	// budget. A UID precondition cannot delete a newly recreated ordinal.
	return client.IgnoreNotFound(r.Delete(ctx, departing, &client.DeleteOptions{
		Preconditions: &metav1.Preconditions{UID: &departing.UID},
	}))
}

func privateRolloutServiceReady(ctx context.Context, reader client.Reader, namespace, name string, serving *corev1.Pod) (bool, error) {
	service := &corev1.Service{}
	if err := reader.Get(ctx, client.ObjectKey{Namespace: namespace, Name: name}, service); err != nil {
		return false, client.IgnoreNotFound(err)
	}
	if service.Spec.Selector[podNameLabel] != serving.Name {
		return false, nil
	}
	slices := &discoveryv1.EndpointSliceList{}
	if err := reader.List(ctx, slices, client.InNamespace(namespace), client.MatchingLabels{discoveryv1.LabelServiceName: name}); err != nil {
		return false, err
	}
	found := false
	for _, slice := range slices.Items {
		for _, endpoint := range slice.Endpoints {
			if endpoint.Conditions.Ready == nil || !*endpoint.Conditions.Ready {
				continue
			}
			ref := endpoint.TargetRef
			if ref == nil || ref.Kind != "Pod" || ref.Name != serving.Name || ref.UID != serving.UID ||
				(endpoint.Conditions.Terminating != nil && *endpoint.Conditions.Terminating) {
				return false, nil
			}
			found = len(endpoint.Addresses) > 0 || found
		}
	}
	return found, nil
}
