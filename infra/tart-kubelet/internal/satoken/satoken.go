// Package satoken mints short-lived projected ServiceAccount tokens
// via the apiserver TokenRequest API and stages them next to the Pod
// env file the VM consumes.
//
// Why this exists: a "real" kubelet uses the projected-volume
// machinery to drop an SA token into the container's filesystem at
// /var/run/secrets/kubernetes.io/serviceaccount/token. tart-kubelet
// can't reuse that machinery — the workload is a Tart VM, not a
// container, and the VM consumes shared host files via Apple's
// virtio-fs (`tart run --dir env:<host>:ro`). This package mints
// the same kind of token a kubelet would and writes it where the
// VM can read it.
//
// The token is bound to the Pod (via TokenRequestSpec.BoundObjectRef)
// so the apiserver invalidates it the moment the Pod is deleted —
// matching kubelet's automount lifecycle. TTL is short (10 min); the
// caller is responsible for re-running this on each reconcile if
// the Pod is long-running.
package satoken

import (
	"context"
	"fmt"

	authenticationv1 "k8s.io/api/authentication/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// Minter mints a token for a Pod's ServiceAccount and returns the
// raw token bytes.
type Minter interface {
	Mint(ctx context.Context, pod *corev1.Pod) (string, error)
}

// ClientMinter calls the apiserver's TokenRequest endpoint.
type ClientMinter struct {
	Client kubernetes.Interface

	// ExpirationSeconds is the token TTL. Real kubelets rotate the
	// projected token every ~10 min by default; we mint once per
	// VM boot and don't rotate (the dispatch poll runs once,
	// minutes after boot at most), so set this generously.
	ExpirationSeconds int64
}

// Mint produces a bound, audience-default TokenRequest for the SA
// the Pod references in spec.ServiceAccountName. Returns
// (token, nil) on success.
func (m *ClientMinter) Mint(ctx context.Context, pod *corev1.Pod) (string, error) {
	saName := pod.Spec.ServiceAccountName
	if saName == "" {
		saName = "default"
	}
	exp := m.ExpirationSeconds
	if exp <= 0 {
		exp = 3600
	}

	req := &authenticationv1.TokenRequest{
		Spec: authenticationv1.TokenRequestSpec{
			ExpirationSeconds: &exp,
			// Bind the token to this Pod. The apiserver invalidates
			// the token the moment the Pod is deleted, so a leaked
			// token can't outlive its issuing VM.
			BoundObjectRef: &authenticationv1.BoundObjectReference{
				Kind:       "Pod",
				APIVersion: "v1",
				Name:       pod.Name,
				UID:        pod.UID,
			},
		},
	}

	resp, err := m.Client.CoreV1().
		ServiceAccounts(pod.Namespace).
		CreateToken(ctx, saName, req, metav1.CreateOptions{})
	if err != nil {
		return "", fmt.Errorf("tokenrequest %s/%s: %w", pod.Namespace, saName, err)
	}
	return resp.Status.Token, nil
}
