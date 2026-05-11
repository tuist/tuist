// Package podtemplate builds the runner Pod manifest from a
// RunnerPool spec. The Pod is single-shot: launchd inside the VM
// runs dispatch-poll, which reads the projected ServiceAccount
// token, POSTs it to the Tuist server's dispatch endpoint as a
// Bearer token, gets a JIT runner config back when a queue entry
// is claimed, execs `./run.sh --jitconfig`, runs one job, halts
// the VM.
//
// At boot the Pod has no customer binding — the SA carries
// `tuist.dev/runner-pool=<pool>` only. The server stamps
// `tuist.dev/runner-pool-owner=<account>` onto the Pod's labels
// at the moment it claims a queue entry (so subsequent
// `max_concurrent` counts include this Pod).
package podtemplate

import (
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

// Build returns the Pod manifest the controller stamps on the API
// server. `dispatchURL` is the customer-server's runner-dispatch
// endpoint (`/api/internal/runners/dispatch`). Sourced from
// helm at deploy time and threaded through the RunnerPool spec
// or the controller's flag.
func Build(pool *tuistv1.RunnerPool, podName, saName, dispatchURL string) *corev1.Pod {
	cpu := resource.NewMilliQuantity(int64(pool.Spec.PodCPUMilli), resource.DecimalSI)
	mem := resource.NewQuantity(int64(pool.Spec.PodMemoryMB)*1024*1024, resource.BinarySI)

	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      podName,
			Namespace: pool.Namespace,
			Labels: map[string]string{
				"app.kubernetes.io/name":      "tuist-runner",
				"app.kubernetes.io/component": "runner",
				// NetworkPolicy in the runners namespace selects on
				// `tuist.dev/runner=true`. Don't drop it.
				"tuist.dev/runner":      "true",
				"tuist.dev/runner-pool": pool.Name,
			},
		},
		Spec: corev1.PodSpec{
			ServiceAccountName: saName,
			// projected SA token is auto-mounted at
			// /var/run/secrets/kubernetes.io/serviceaccount/token by
			// default; explicit `true` for clarity.
			AutomountServiceAccountToken: ptr(true),
			NodeSelector: map[string]string{
				"kubernetes.io/os":  "darwin",
				"tuist.dev/runtime": "tart",
				"tuist.dev/fleet":   pool.Spec.FleetSelector,
			},
			Tolerations: []corev1.Toleration{
				{
					Key:      "tuist.dev/macos",
					Operator: corev1.TolerationOpExists,
					Effect:   corev1.TaintEffectNoSchedule,
				},
			},
			// No restart: ephemeral runner. After `./run.sh
			// --jitconfig` exits, the dispatch-poll EXIT trap halts
			// the VM and tart-kubelet flips the Pod to Succeeded.
			RestartPolicy: corev1.RestartPolicyNever,
			Containers: []corev1.Container{
				{
					Name:  "runner",
					Image: pool.Spec.Image,
					Resources: corev1.ResourceRequirements{
						Requests: corev1.ResourceList{
							corev1.ResourceCPU:    *cpu,
							corev1.ResourceMemory: *mem,
						},
					},
					Env: []corev1.EnvVar{
						{Name: "TUIST_RUNNER_DISPATCH_URL", Value: dispatchURL},
						{Name: "TUIST_RUNNER_POOL", Value: pool.Name},
						{
							Name: "TUIST_RUNNER_POD_NAME",
							ValueFrom: &corev1.EnvVarSource{
								FieldRef: &corev1.ObjectFieldSelector{FieldPath: "metadata.name"},
							},
						},
					},
				},
			},
		},
	}
}

// BuildServiceAccount returns the per-Pod ServiceAccount manifest.
// Carries `tuist.dev/runner-pool=<name>` so the dispatch endpoint
// can resolve "this SA belongs to which fleet's pool" after
// TokenReview validates the bearer token.
func BuildServiceAccount(pool *tuistv1.RunnerPool, saName string) *corev1.ServiceAccount {
	return &corev1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{
			Name:      saName,
			Namespace: pool.Namespace,
			Labels: map[string]string{
				"app.kubernetes.io/name":      "tuist-runner",
				"app.kubernetes.io/component": "runner-sa",
				"tuist.dev/runner-pool":       pool.Name,
			},
		},
		// Disable auto-mount on the SA itself; the Pod opts in via
		// AutomountServiceAccountToken on its spec. Keeping the
		// default false means a stray Pod that references this SA
		// without explicit opt-in doesn't get a token.
		AutomountServiceAccountToken: ptr(false),
	}
}

func ptr[T any](v T) *T {
	return &v
}
