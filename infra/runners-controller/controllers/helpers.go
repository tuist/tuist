package controllers

import corev1 "k8s.io/api/core/v1"

// corev1LocalRef is the obvious shorthand. We refer to the pool by
// name from the assignment; same namespace, no kind ambiguity.
func corev1LocalRef(name string) corev1.LocalObjectReference {
	return corev1.LocalObjectReference{Name: name}
}
