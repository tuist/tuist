package controllers

import (
	"slices"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
)

func (r *KuraInstanceReconciler) addConnectivityProbe(instance *kurav1alpha1.KuraInstance, template *corev1.PodTemplateSpec) {
	if r.ConnectivityProbeImage == "" || !slices.Contains(r.ConnectivityProbeInstances, instance.Name) {
		return
	}
	// Kura uses no Kubernetes API credentials. Disable admission's automatic
	// token volume for the whole pod so it cannot be injected into the probe.
	template.Spec.AutomountServiceAccountToken = ptr(false)
	template.Spec.Containers = append(template.Spec.Containers, corev1.Container{
		Name:            "connectivity-probe",
		Image:           r.ConnectivityProbeImage,
		ImagePullPolicy: corev1.PullIfNotPresent,
		Command:         []string{"/connectivity-probe"},
		SecurityContext: &corev1.SecurityContext{
			RunAsNonRoot: ptr(true), RunAsUser: ptr(int64(65532)), RunAsGroup: ptr(int64(65532)),
			AllowPrivilegeEscalation: ptr(false), ReadOnlyRootFilesystem: ptr(true),
			Capabilities:   &corev1.Capabilities{Drop: []corev1.Capability{"ALL"}},
			SeccompProfile: &corev1.SeccompProfile{Type: corev1.SeccompProfileTypeRuntimeDefault},
		},
		Resources: corev1.ResourceRequirements{
			Requests: corev1.ResourceList{corev1.ResourceCPU: resource.MustParse("5m"), corev1.ResourceMemory: resource.MustParse("16Mi")},
			Limits:   corev1.ResourceList{corev1.ResourceCPU: resource.MustParse("50m"), corev1.ResourceMemory: resource.MustParse("32Mi")},
		},
	})
}
