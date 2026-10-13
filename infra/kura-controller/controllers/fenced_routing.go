package controllers

import (
	"context"
	"encoding/json"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

func (r *KuraInstanceReconciler) fencedPrimary(ctx context.Context, instance *kurav1alpha1.KuraInstance, samples map[string]runtimeStatus) (string, error) {
	cm := &corev1.ConfigMap{}
	reader := r.APIReader
	if reader == nil {
		reader = r.Client
	}
	if err := reader.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: instance.Name + "-serving"}, cm); err != nil {
		if apierrors.IsNotFound(err) {
			return "fenced-unavailable", nil
		}
		return "", err
	}
	var grant servingGrant
	if err := json.Unmarshal([]byte(cm.Data["grant"]), &grant); err != nil {
		return "", err
	}
	now := time.Now().UnixMilli()
	if (grant.Phase != "Serving" && grant.Phase != "Quiescing") || grant.Holder.InstanceUID != string(instance.UID) || grant.ExpiresMS <= now+2000 || grant.ExpiresMS > now+15000 {
		return "fenced-unavailable", nil
	}
	if sample, fresh := samples[grant.PodName]; fresh {
		if !sample.ServingAuthority.Valid || sample.ServingAuthority.Epoch != grant.Epoch || sample.ServingAuthority.Identity != grant.Holder {
			return "fenced-unavailable", nil
		}
		return grant.PodName, nil
	}

	// A route is not authority: the runtime still checks this grant at
	// admission and publication. Retain only the existing holder, never
	// select or renew a writer from a missing observation.
	service := &corev1.Service{}
	if err := reader.Get(ctx, client.ObjectKeyFromObject(instance), service); err != nil {
		if apierrors.IsNotFound(err) {
			return "fenced-unavailable", nil
		}
		return "", err
	}
	if service.Spec.Selector[podNameLabel] != grant.PodName {
		return "fenced-unavailable", nil
	}
	pod := &corev1.Pod{}
	if err := reader.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: grant.PodName}, pod); err != nil {
		if apierrors.IsNotFound(err) {
			return "fenced-unavailable", nil
		}
		return "", err
	}
	if string(pod.UID) != grant.Holder.PodUID || pod.Spec.NodeName != grant.Holder.Host || !podReady(pod) || pod.DeletionTimestamp != nil || !runtimePredatesGrant(pod, grant) {
		return "fenced-unavailable", nil
	}
	log.FromContext(ctx).Info("retained serving route during unavailable runtime observation", "pod", grant.PodName, "epoch", grant.Epoch, "phase", grant.Phase, "expiresMS", grant.ExpiresMS)
	return grant.PodName, nil
}

func runtimePredatesGrant(pod *corev1.Pod, grant servingGrant) bool {
	for _, container := range pod.Status.ContainerStatuses {
		if container.Name == "kura" && container.State.Running != nil {
			started := container.State.Running.StartedAt
			// Pod timestamps have second precision and may come from a
			// different host clock. Require a process older than renewal's
			// two-second safety allowance rather than infer an incarnation.
			return !started.IsZero() && started.UnixMilli()+2000 < grant.ExpiresMS-15000
		}
	}
	return false
}
