// Package envresolver resolves Pod env into a flat string map by
// reading Secrets and ConfigMaps from the cluster API server, exactly
// like a real kubelet would.
//
// Resolution order matches kubelet: `envFrom` first, then `env`. `env`
// entries override `envFrom` keys with the same name. Optional refs
// silently skip on miss; required refs return an error so the caller
// can fail the Pod and let the controller requeue.
package envresolver

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// Resolver reads Secrets and ConfigMaps from a k8s API client.
type Resolver struct {
	K8s client.Reader
}

// Resolve produces the effective env map for a container. The pod
// argument is needed for namespace + fieldRef resolution (Pod-name,
// Pod-namespace, etc.).
func (r *Resolver) Resolve(ctx context.Context, pod *corev1.Pod, c corev1.Container) (map[string]string, error) {
	out := map[string]string{}

	for _, ef := range c.EnvFrom {
		if err := r.applyEnvFrom(ctx, pod.Namespace, ef, out); err != nil {
			return nil, err
		}
	}

	for _, e := range c.Env {
		val, ok, err := r.resolveEnvVar(ctx, pod, e)
		if err != nil {
			return nil, err
		}
		if ok {
			out[e.Name] = val
		}
	}

	return out, nil
}

func (r *Resolver) applyEnvFrom(ctx context.Context, namespace string, ef corev1.EnvFromSource, out map[string]string) error {
	prefix := ef.Prefix
	switch {
	case ef.SecretRef != nil:
		sec := &corev1.Secret{}
		err := r.K8s.Get(ctx, client.ObjectKey{Namespace: namespace, Name: ef.SecretRef.Name}, sec)
		if err != nil {
			if optional(ef.SecretRef.Optional) && apierrors.IsNotFound(err) {
				return nil
			}
			return fmt.Errorf("envFrom secret %s/%s: %w", namespace, ef.SecretRef.Name, err)
		}
		for k, v := range sec.Data {
			out[prefix+k] = string(v)
		}
	case ef.ConfigMapRef != nil:
		cm := &corev1.ConfigMap{}
		err := r.K8s.Get(ctx, client.ObjectKey{Namespace: namespace, Name: ef.ConfigMapRef.Name}, cm)
		if err != nil {
			if optional(ef.ConfigMapRef.Optional) && apierrors.IsNotFound(err) {
				return nil
			}
			return fmt.Errorf("envFrom configmap %s/%s: %w", namespace, ef.ConfigMapRef.Name, err)
		}
		for k, v := range cm.Data {
			out[prefix+k] = v
		}
	}
	return nil
}

// resolveEnvVar returns (value, present, error). present=false means
// the env var should be omitted (an optional ref missed).
func (r *Resolver) resolveEnvVar(ctx context.Context, pod *corev1.Pod, e corev1.EnvVar) (string, bool, error) {
	if e.ValueFrom == nil {
		return e.Value, true, nil
	}
	switch {
	case e.ValueFrom.SecretKeyRef != nil:
		ref := e.ValueFrom.SecretKeyRef
		sec := &corev1.Secret{}
		err := r.K8s.Get(ctx, client.ObjectKey{Namespace: pod.Namespace, Name: ref.Name}, sec)
		if err != nil {
			if optional(ref.Optional) && apierrors.IsNotFound(err) {
				return "", false, nil
			}
			return "", false, fmt.Errorf("env %s: get secret %s: %w", e.Name, ref.Name, err)
		}
		data, ok := sec.Data[ref.Key]
		if !ok {
			if optional(ref.Optional) {
				return "", false, nil
			}
			return "", false, fmt.Errorf("env %s: secret %s missing key %s", e.Name, ref.Name, ref.Key)
		}
		return string(data), true, nil
	case e.ValueFrom.ConfigMapKeyRef != nil:
		ref := e.ValueFrom.ConfigMapKeyRef
		cm := &corev1.ConfigMap{}
		err := r.K8s.Get(ctx, client.ObjectKey{Namespace: pod.Namespace, Name: ref.Name}, cm)
		if err != nil {
			if optional(ref.Optional) && apierrors.IsNotFound(err) {
				return "", false, nil
			}
			return "", false, fmt.Errorf("env %s: get configmap %s: %w", e.Name, ref.Name, err)
		}
		v, ok := cm.Data[ref.Key]
		if !ok {
			if optional(ref.Optional) {
				return "", false, nil
			}
			return "", false, fmt.Errorf("env %s: configmap %s missing key %s", e.Name, ref.Name, ref.Key)
		}
		return v, true, nil
	case e.ValueFrom.FieldRef != nil:
		// Common fieldRef cases. Anything unrecognized is silently
		// dropped rather than failing the Pod — matches what kubelet
		// does for unsupported field paths in older API versions.
		switch e.ValueFrom.FieldRef.FieldPath {
		case "metadata.name":
			return pod.Name, true, nil
		case "metadata.namespace":
			return pod.Namespace, true, nil
		case "metadata.uid":
			return string(pod.UID), true, nil
		case "spec.serviceAccountName":
			return pod.Spec.ServiceAccountName, true, nil
		case "spec.nodeName":
			return pod.Spec.NodeName, true, nil
		}
		return "", false, nil
	}
	return "", false, nil
}

func optional(opt *bool) bool {
	return opt != nil && *opt
}
