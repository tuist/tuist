package controllers

import (
	"context"
	"encoding/json"
	"slices"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const (
	connectivityProfileEnv = "KURA_CONNECTIVITY_PROFILE"
	connectivityConfigEnv  = "KURA_CONNECTIVITY_CONFIG_FILE"
	connectivityAnnotation = "kura.tuist.dev/connectivity-diagnostics"
	connectivityVolume     = "connectivity-diagnostics"
	connectivityDirectory  = "/etc/kura/connectivity"
	connectivityFile       = connectivityDirectory + "/selection.json"
)

func ValidConnectivityProfile(profile string) bool {
	return profile == "production" || profile == "staging" || profile == "canary"
}

// Install the inert projection only alongside an ordinary image change. Incident
// activation and expiry never enter the StatefulSet's template or revision.
func (r *KuraInstanceReconciler) configureConnectivityDiagnostics(instance *kurav1alpha1.KuraInstance, template, previous *corev1.PodTemplateSpec) {
	adopt := r.ConnectivityDiagnosticsPrepare || connectivityMounted(previous.Spec)
	for _, container := range previous.Spec.Containers {
		if container.Name == kuraContainerName && container.Image == instance.Spec.Image {
			adopt = connectivityMounted(previous.Spec)
		}
	}
	for i := range template.Spec.Containers {
		container := &template.Spec.Containers[i]
		if container.Name != kuraContainerName {
			continue
		}
		container.Env = slices.DeleteFunc(container.Env, func(env corev1.EnvVar) bool {
			return env.Name == connectivityProfileEnv || env.Name == connectivityConfigEnv
		})
		if !adopt {
			// Retain the old template verbatim until its normal runtime upgrade;
			// neither enabling nor removing legacy diagnostics warrants a roll.
			for _, old := range previous.Spec.Containers {
				if old.Name != kuraContainerName {
					continue
				}
				for _, env := range old.Env {
					if env.Name == connectivityProfileEnv || env.Name == connectivityConfigEnv {
						container.Env = append(container.Env, env)
					}
				}
			}
			continue
		}
		container.Env = append(container.Env, corev1.EnvVar{Name: connectivityConfigEnv, Value: connectivityFile})
		container.VolumeMounts = append(container.VolumeMounts, corev1.VolumeMount{Name: connectivityVolume, MountPath: connectivityDirectory, ReadOnly: true})
	}
	if !adopt {
		if value, ok := previous.Annotations[connectivityAnnotation]; ok {
			template.Annotations[connectivityAnnotation] = value
		}
	}
	if adopt {
		delete(template.Annotations, connectivityAnnotation)
		template.Spec.Volumes = append(template.Spec.Volumes, corev1.Volume{
			Name: connectivityVolume,
			VolumeSource: corev1.VolumeSource{DownwardAPI: &corev1.DownwardAPIVolumeSource{Items: []corev1.DownwardAPIVolumeFile{{
				Path: "selection.json", FieldRef: &corev1.ObjectFieldSelector{APIVersion: "v1", FieldPath: "metadata.annotations['" + connectivityAnnotation + "']"},
			}}}},
		})
	}
}

func connectivityMounted(spec corev1.PodSpec) bool {
	for _, container := range spec.Containers {
		if container.Name != kuraContainerName {
			continue
		}
		for _, mount := range container.VolumeMounts {
			if mount.Name == connectivityVolume && mount.MountPath == connectivityDirectory && mount.ReadOnly && mount.SubPath == "" && mount.SubPathExpr == "" {
				for _, volume := range spec.Volumes {
					if volume.Name == connectivityVolume && volume.DownwardAPI != nil {
						for _, item := range volume.DownwardAPI.Items {
							if item.Path == "selection.json" && item.FieldRef != nil && item.FieldRef.FieldPath == "metadata.annotations['"+connectivityAnnotation+"']" {
								return true
							}
						}
					}
				}
			}
		}
	}
	return false
}

func (r *KuraInstanceReconciler) reconcileConnectivityDiagnostics(ctx context.Context, instance *kurav1alpha1.KuraInstance, pods []corev1.Pod) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	value := ""
	now := time.Now()
	if slices.Contains(r.ConnectivityDiagnosticsInstances, instance.Name) && ValidConnectivityProfile(r.Environment) && r.ConnectivityDiagnosticsExpiresAt.After(now) && r.ConnectivityDiagnosticsExpiresAt.Sub(now) <= 24*time.Hour {
		encoded, err := json.Marshal(struct {
			Profile   string `json:"profile"`
			ExpiresAt int64  `json:"expires_at_unix_seconds"`
		}{r.Environment, r.ConnectivityDiagnosticsExpiresAt.Unix()})
		if err != nil {
			return err
		}
		value = string(encoded)
	}
	for i := range pods {
		pod := &pods[i]
		owner := metav1.GetControllerOf(pod)
		if !connectivityMounted(pod.Spec) || owner == nil || owner.Kind != "StatefulSet" || owner.Name != instance.Name || pod.Annotations[connectivityAnnotation] == value {
			continue
		}
		before := pod.DeepCopy()
		if value == "" {
			delete(pod.Annotations, connectivityAnnotation)
		} else {
			if pod.Annotations == nil {
				pod.Annotations = map[string]string{}
			}
			pod.Annotations[connectivityAnnotation] = value
		}
		if err := r.Patch(ctx, pod, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
			return err
		}
	}
	return nil
}
