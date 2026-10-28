package controllers

import (
	"slices"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// Evicting a node-local replica cannot move its volume to another host. It
// only throws away a warm process during a control-plane network partition,
// making recovery depend on startup discovery reaching that control plane.
// Adopt the defaults on creation or image change, so a controller deploy does
// not itself roll the fleet. Explicit instance tolerations remain authoritative.
func nodeLocalTolerations(instance *kurav1alpha1.KuraInstance, sts *appsv1.StatefulSet) []corev1.Toleration {
	tolerations := slices.Clone(instance.Spec.Tolerations)
	if instance.Spec.StorageClassName != "scw-local-nvme" {
		return tolerations
	}
	adopt := sts.ResourceVersion == ""
	for _, container := range sts.Spec.Template.Spec.Containers {
		if container.Name == kuraContainerName && container.Image != instance.Spec.Image {
			adopt = true
		}
	}
	for _, key := range []string{corev1.TaintNodeNotReady, corev1.TaintNodeUnreachable} {
		taint := &corev1.Taint{Key: key, Effect: corev1.TaintEffectNoExecute}
		if slices.ContainsFunc(tolerations, func(t corev1.Toleration) bool { return t.ToleratesTaint(taint) }) {
			continue
		}
		retained := slices.ContainsFunc(sts.Spec.Template.Spec.Tolerations, func(t corev1.Toleration) bool {
			return t.TolerationSeconds == nil && t.ToleratesTaint(taint)
		})
		if adopt || retained {
			tolerations = append(tolerations, corev1.Toleration{
				Key: key, Operator: corev1.TolerationOpExists, Effect: corev1.TaintEffectNoExecute,
			})
		}
	}
	return tolerations
}
