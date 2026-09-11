package controllers

import (
	"slices"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
)

const connectivityProfileEnv = "KURA_CONNECTIVITY_PROFILE"

func ValidConnectivityProfile(profile string) bool {
	return profile == "production" || profile == "staging" || profile == "canary"
}

func (r *KuraInstanceReconciler) configureConnectivityDiagnostics(instance *kurav1alpha1.KuraInstance, template *corev1.PodTemplateSpec) {
	for i := range template.Spec.Containers {
		container := &template.Spec.Containers[i]
		if container.Name != kuraContainerName {
			continue
		}
		// The deployment's exact instance allowlist owns this setting, including
		// when ExtraEnv contains a stale or independently configured value.
		container.Env = slices.DeleteFunc(container.Env, func(env corev1.EnvVar) bool { return env.Name == connectivityProfileEnv })
		if slices.Contains(r.ConnectivityDiagnosticsInstances, instance.Name) && ValidConnectivityProfile(r.Environment) {
			container.Env = append(container.Env, corev1.EnvVar{Name: connectivityProfileEnv, Value: r.Environment})
		}
	}
}
