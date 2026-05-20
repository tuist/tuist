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
// server. `dispatchURL` is the externally-reachable dispatch URL
// the Pod uses (`/api/internal/runners/dispatch`); macOS Tart VMs
// bypass cluster networking via vmnet and need this public path.
// `dispatchInternalURL`, when non-empty, overrides for `linux`
// pools — those Pods live on the cluster's CNI and hit Hetzner
// Cloud LB hairpin when they try to reach the public ingress IP
// from inside the cluster, so they must use the in-cluster
// Service URL instead.
func Build(pool *tuistv1.RunnerPool, podName, saName, dispatchURL, dispatchInternalURL string) *corev1.Pod {
	cpu := resource.NewMilliQuantity(int64(pool.Spec.PodCPUMilli), resource.DecimalSI)
	mem := resource.NewQuantity(int64(pool.Spec.PodMemoryMB)*1024*1024, resource.BinarySI)

	nodeSelector, tolerations := schedulingFor(pool)

	effectiveDispatchURL := dispatchURL
	if pool.Spec.OS == "linux" && dispatchInternalURL != "" {
		effectiveDispatchURL = dispatchInternalURL
	}

	// macOS Pods use tart-kubelet's audience-scoped token projection
	// (mounted inside the Tart VM at /etc/tuist-sa-token). Linux
	// Pods need the controller to project the audience-scoped token
	// explicitly — without it, the default-mounted SA token has the
	// kube-apiserver audience and the server's strict TokenReview
	// rejects it with 401. We disable the default automount on the
	// Pod and replace it with a projected volume mounting only the
	// dispatch-audience token at a fixed path the dispatch-poll
	// script reads.
	linuxPod := pool.Spec.OS == "linux"
	var extraVolumes []corev1.Volume
	var extraVolumeMounts []corev1.VolumeMount
	automount := true
	if linuxPod {
		automount = false
		extraVolumes = []corev1.Volume{{
			Name: "tuist-runner-token",
			VolumeSource: corev1.VolumeSource{
				Projected: &corev1.ProjectedVolumeSource{
					Sources: []corev1.VolumeProjection{{
						ServiceAccountToken: &corev1.ServiceAccountTokenProjection{
							Audience:          "tuist-runners-dispatch",
							ExpirationSeconds: ptr(int64(3600)),
							Path:              "token",
						},
					}},
				},
			},
		}}
		extraVolumeMounts = []corev1.VolumeMount{{
			Name:      "tuist-runner-token",
			MountPath: "/var/run/secrets/tuist-runner",
			ReadOnly:  true,
		}}
	}

	env := []corev1.EnvVar{
		{Name: "TUIST_RUNNER_DISPATCH_URL", Value: effectiveDispatchURL},
		{Name: "TUIST_RUNNER_POOL", Value: pool.Name},
		{
			Name: "TUIST_RUNNER_POD_NAME",
			ValueFrom: &corev1.EnvVarSource{
				FieldRef: &corev1.ObjectFieldSelector{FieldPath: "metadata.name"},
			},
		},
		{
			// dispatch-poll.sh keys claim de-dup on (pool, pod_uid)
			// so a recreated-same-name Pod gets a fresh slot. With
			// set -u, the script bails before its first poll if this
			// env is missing.
			Name: "TUIST_RUNNER_POD_UID",
			ValueFrom: &corev1.EnvVarSource{
				FieldRef: &corev1.ObjectFieldSelector{FieldPath: "metadata.uid"},
			},
		},
	}

	// Linux pods always run dockerd inside the container so
	// workflows can use `services:`, `docker build`, and buildx
	// natively. Privileged is bounded by the Pod's kata-qemu
	// microVM, not the host kernel — Linux pools must therefore
	// always set `spec.runtimeClass: kata-qemu`.
	var securityContext *corev1.SecurityContext
	if linuxPod {
		env = append(env, corev1.EnvVar{Name: "DOCKER_HOST", Value: "unix:///var/run/docker.sock"})
		securityContext = &corev1.SecurityContext{Privileged: ptr(true)}
	}

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
			// macOS: default automount (tart-kubelet projects the
			// audience-scoped token separately into the VM).
			// Linux: disable automount and project the
			// dispatch-audience token explicitly — see `extraVolumes`
			// below.
			AutomountServiceAccountToken: ptr(automount),
			NodeSelector:                 nodeSelector,
			Tolerations:                  tolerations,
			Volumes:                      extraVolumes,
			// RuntimeClassName, when set, routes the Pod through a
			// non-default container runtime. Linux bare-metal pools
			// use `kata-fc` (Kata Containers + Firecracker) so each
			// Pod becomes a microVM with its own kernel for real
			// per-tenant isolation. Empty falls back to runc on
			// containerd — fine for macOS (tart-kubelet) and for
			// single-tenant bare-metal during bring-up.
			RuntimeClassName: runtimeClassName(pool),
			// No restart: ephemeral runner. macOS Pods halt the
			// underlying Tart VM via the EXIT trap in dispatch-poll;
			// Linux containers just exit, kubelet flips the Pod to
			// Succeeded, the reconciler reaps it. Same lifecycle,
			// substrate-specific exit mechanics.
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
					SecurityContext: securityContext,
					VolumeMounts:    extraVolumeMounts,
					Env:             env,
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

// runtimeClassName returns a non-nil *string to stamp on
// `Pod.spec.runtimeClassName` when the pool has `spec.runtimeClass`
// set, or nil for the cluster default runtime. We never set an empty
// string — kube-apiserver treats empty as "no class specified" but
// downstream tooling sometimes treats an empty pointer differently
// from a nil one. Use nil for cleanliness.
func runtimeClassName(pool *tuistv1.RunnerPool) *string {
	if pool.Spec.RuntimeClass == "" {
		return nil
	}
	rc := pool.Spec.RuntimeClass
	return &rc
}

// schedulingFor returns the nodeSelector + tolerations for a pool's
// substrate.
//
//   - `darwin` (v1 default): Mac mini nodes running tart-kubelet.
//     `tuist.dev/fleet=<value>` is the chart-managed selector; tart-kubelet
//     sets the label itself outside the CAPI label-sync path. Tolerates
//     `tuist.dev/macos:NoSchedule` so only runner Pods land on Mac minis.
//   - `linux`: Hetzner Robot bare-metal hosts joined to the workload
//     cluster as worker Nodes out-of-band (kubeadm join during host
//     bring-up, not CAPI-managed in v1). The hosts are labeled
//     `node.cluster.x-k8s.io/pool=<FleetSelector>` and tainted
//     `tuist.dev/runner-tier=bare-metal:NoSchedule` so that only runner
//     Pods land on them; everything else (server, system DaemonSets,
//     etc.) stays on the elastic Hetzner Cloud `md-0` pool. Pods
//     tolerate the runner-tier taint and select on the pool label.
//
// Anything else falls back to the darwin shape so a misconfigured CR
// still produces a schedulable Pod against the macOS fleet.
func schedulingFor(pool *tuistv1.RunnerPool) (map[string]string, []corev1.Toleration) {
	switch pool.Spec.OS {
	case "linux":
		return map[string]string{
				"kubernetes.io/os":           "linux",
				"kubernetes.io/arch":         "amd64",
				"node.cluster.x-k8s.io/pool": pool.Spec.FleetSelector,
			}, []corev1.Toleration{
				{
					Key:      "tuist.dev/runner-tier",
					Operator: corev1.TolerationOpEqual,
					Value:    "bare-metal",
					Effect:   corev1.TaintEffectNoSchedule,
				},
			}
	default:
		return map[string]string{
				"kubernetes.io/os":  "darwin",
				"tuist.dev/runtime": "tart",
				"tuist.dev/fleet":   pool.Spec.FleetSelector,
			}, []corev1.Toleration{
				{
					Key:      "tuist.dev/macos",
					Operator: corev1.TolerationOpExists,
					Effect:   corev1.TaintEffectNoSchedule,
				},
			}
	}
}
