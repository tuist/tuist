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
// matching kubelet's automount lifecycle. It is minted once at VM
// boot and not rotated, so its TTL (set at the call site) must be
// generous enough to outlive warm-time plus the whole job: besides
// the one-shot dispatch call, the in-VM metrics sampler reuses the
// same token to POST samples for the job's full duration.
//
// The token is also audience-bound. The dispatch endpoint passes
// the same audience to its TokenReview, so a default-audience SA
// token leaked from the guest VM filesystem can't be replayed
// against the apiserver. See `DispatchAudience` for the value;
// the server-side constant lives in
// `Tuist.Kubernetes.Client.runner_dispatch_audience/0` and the
// two must stay in sync.
package satoken

import (
	"context"
	"fmt"

	authenticationv1 "k8s.io/api/authentication/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// DispatchAudience is the audience claim the token carries.
// Must match the server-side TokenReview audience expectation
// (`Tuist.Kubernetes.Client.runner_dispatch_audience/0`).
const DispatchAudience = "tuist-runners-dispatch"

// Minter mints a token for a Pod's ServiceAccount and returns the
// raw token bytes.
type Minter interface {
	Mint(ctx context.Context, pod *corev1.Pod) (string, error)
}

// ClientMinter calls the apiserver's TokenRequest endpoint.
type ClientMinter struct {
	Client kubernetes.Interface

	// ExpirationSeconds is the token TTL. Real kubelets rotate the
	// projected token every ~10 min by default; we mint once per VM
	// boot and don't rotate, so set this generously — the token must
	// outlive warm-time plus the whole job, since the in-VM metrics
	// sampler reuses it to POST for the job's full duration, not just
	// the one-shot dispatch call.
	ExpirationSeconds int64

	// Audiences scopes the token to specific consumers. Defaults
	// to [DispatchAudience] on Mint() if unset. Operator override
	// is supported (different dispatch endpoint name, future
	// audiences for non-runner workloads on the same agent).
	Audiences []string
}

// Mint produces a bound, audience-scoped TokenRequest for the SA
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
	audiences := m.Audiences
	if len(audiences) == 0 {
		audiences = []string{DispatchAudience}
	}

	req := &authenticationv1.TokenRequest{
		Spec: authenticationv1.TokenRequestSpec{
			ExpirationSeconds: &exp,
			// Audience-bind the token. The apiserver records this
			// list in the JWT's `aud` claim and a TokenReview from
			// the dispatch endpoint validates against the same
			// audience. A token leaked from the guest filesystem
			// is single-purpose; in particular, it isn't a
			// default-audience credential for the K8s API server.
			Audiences: audiences,
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
