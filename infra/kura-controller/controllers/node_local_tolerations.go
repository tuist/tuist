package controllers

import (
	"slices"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/klog/v2"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// Evicting a node-local replica cannot move its volume to another host. It
// only throws away a warm process during a control-plane network partition,
// making recovery depend on startup discovery reaching that control plane.
// Adopt the defaults on creation or image change, so a controller deploy does
// not itself roll the fleet. Explicit instance tolerations remain authoritative.
func nodeLocalTolerations(instance *kurav1alpha1.KuraInstance, sts *appsv1.StatefulSet) []corev1.Toleration {
	tolerations := slices.Clone(instance.Spec.Tolerations)
	if !nodeLocalStorageClass(instance.Spec.StorageClassName) {
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
		if slices.ContainsFunc(tolerations, func(t corev1.Toleration) bool { return toleratesTaint(t, taint) }) {
			continue
		}
		retained := slices.ContainsFunc(sts.Spec.Template.Spec.Tolerations, func(t corev1.Toleration) bool {
			return t.TolerationSeconds == nil && toleratesTaint(t, taint)
		})
		if adopt || retained {
			tolerations = append(tolerations, corev1.Toleration{
				Key: key, Operator: corev1.TolerationOpExists, Effect: corev1.TaintEffectNoExecute,
			})
		}
	}
	return tolerations
}

// Kubernetes 1.36 requires an explicit logger and whether numeric Lt/Gt
// toleration operators are enabled. This check only matches Exists/Equal.
func toleratesTaint(t corev1.Toleration, taint *corev1.Taint) bool {
	return t.ToleratesTaint(klog.Background(), taint, false)
}

const (
	thinLocalStorageClass      = "kura-thin-encrypted-nvme"
	lvmLocalStorageClass       = "kura-lvm-nvme"
	localPathStorageClass      = "scw-local-nvme"
	encryptedLocalStorageClass = "kura-encrypted-nvme"
	// encryptedLocalTopologyKey is the topology key the kura-volumes.tuist.dev
	// CSI driver pins its PVs with; its value is the node name.
	encryptedLocalTopologyKey = "topology.kura-volumes.tuist.dev/node"
)

// nodeLocalStorageClass reports whether a storage class carves volumes on one
// node's disk, so a bound volume can never follow its pod to another host.
func nodeLocalStorageClass(name string) bool {
	return name == thinLocalStorageClass || name == lvmLocalStorageClass || name == localPathStorageClass || name == encryptedLocalStorageClass
}
