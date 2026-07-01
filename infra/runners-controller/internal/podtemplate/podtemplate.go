// Package podtemplate builds the runner Pod manifest from a
// RunnerPool spec. The Pod is single-shot: it polls the Tuist
// server's dispatch endpoint with the projected, audience-scoped
// ServiceAccount token as a Bearer token, gets a JIT runner config
// back when a queue entry is claimed, registers the GitHub Actions
// runner against that JIT, runs one job, and exits.
//
// On Linux the Pod is split into two containers for credential
// isolation (see Build): a `poller` init container that holds the
// token and stages the minted JIT, and a `runner` main container
// that holds no token and runs the (untrusted) workflow under only
// the job-scoped JIT. On macOS the whole flow runs inside a single
// Tart VM — the VM is the isolation boundary and tart-kubelet
// projects the token into it separately.
//
// At boot the Pod has no customer binding — the SA carries
// `tuist.dev/runner-pool=<pool>` only. The server stamps
// `tuist.dev/runner-pool-owner=<account>` onto the Pod's labels
// at the moment it claims a queue entry (so subsequent
// `max_concurrent` counts include this Pod).
package podtemplate

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

const (
	// jitMountPath is where the JIT-handoff emptyDir is mounted in
	// both the poller (rw) and runner (ro) containers. Deliberately
	// not under /var/run — the dind sidecar owns that mount in the
	// runner container.
	jitMountPath = "/var/lib/tuist-runner"
	// jitFilePath is the file the poller writes the minted JIT to and
	// the runner reads it from.
	jitFilePath = jitMountPath + "/jit"
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
//
// `dindImage` is the OCI ref of the dockerd sidecar baked into
// every Linux runner Pod (k8s 1.29+ native sidecar). Empty skips
// the sidecar, which is fine for macOS-only installs.
//
// `clusterDNSIP` + `clusterDomain`, when set, ride to macOS Pods as
// TUIST_CLUSTER_DNS_IP / TUIST_CLUSTER_DOMAIN: tart-kubelet stages
// the Pod env into the VM's /etc/tuist.env, and dispatch-poll.sh
// writes an /etc/resolver/<domain> entry from them so the
// dispatch-provided `cache_endpoint_url` (`*.svc.cluster.local`)
// resolves inside the VM. Linux Pods are on the CNI's DNS already
// and don't get them.
//
// Returns an error (fails closed) when a Linux pool would get the
// privileged dind sidecar without `spec.runtimeClass == kata-qemu`.
// The sidecar runs `privileged: true`; that's only safe because the
// kata-qemu microVM is the isolation boundary. Without the runtime
// class the Pod falls back to runc on the host kernel and the
// privileged container escapes onto the bare-metal host — so refuse
// to build it rather than ship an unbounded privileged container.
func Build(pool *tuistv1.RunnerPool, podName, saName, dispatchURL, dispatchInternalURL, dindImage, registryMirror, clusterDNSIP, clusterDomain string) (*corev1.Pod, error) {
	cpu := resource.NewMilliQuantity(int64(pool.Spec.PodCPUMilli), resource.DecimalSI)
	mem := resource.NewQuantity(int64(pool.Spec.PodMemoryMB)*1024*1024, resource.BinarySI)

	if pool.Spec.OS == "linux" && dindImage != "" && pool.Spec.RuntimeClass != "kata-qemu" {
		return nil, fmt.Errorf("refusing to build Linux runner Pod with privileged dind sidecar: pool %q has runtimeClass %q, want kata-qemu", pool.Name, pool.Spec.RuntimeClass)
	}

	nodeSelector, tolerations := schedulingFor(pool)

	effectiveDispatchURL := dispatchURL
	if pool.Spec.OS == "linux" && dispatchInternalURL != "" {
		effectiveDispatchURL = dispatchInternalURL
	}

	linuxPod := pool.Spec.OS == "linux"

	// Env consumed by the dispatch poll loop. On macOS the loop runs
	// inside the Tart VM, so this is the runner container's env. On
	// Linux it runs in the dedicated poller init container.
	dispatchEnv := []corev1.EnvVar{
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

	if !linuxPod && clusterDNSIP != "" {
		// In-VM cluster DNS for the runner-cache path (macOS only:
		// Linux Pods resolve cluster names via the CNI's DNS).
		// dispatch-poll.sh writes /etc/resolver/<domain> from these
		// before its first poll.
		dispatchEnv = append(dispatchEnv,
			corev1.EnvVar{Name: "TUIST_CLUSTER_DNS_IP", Value: clusterDNSIP},
			corev1.EnvVar{Name: "TUIST_CLUSTER_DOMAIN", Value: clusterDomain},
		)
	}

	resources := corev1.ResourceRequirements{
		Requests: corev1.ResourceList{
			corev1.ResourceCPU:    *cpu,
			corev1.ResourceMemory: *mem,
		},
		// kata sizes the microVM from container limits (default 2 GiB
		// without). Setting limit == request gives the VM the budget
		// the chart asks for.
		Limits: corev1.ResourceList{
			corev1.ResourceCPU:    *cpu,
			corev1.ResourceMemory: *mem,
		},
	}

	// Defaults are the macOS shape: a single runner container running
	// the poll loop inside the Tart VM, with the default automount
	// (tart-kubelet projects the audience-scoped token into the VM
	// separately). The Linux branch below overrides all of these.
	automount := true
	runnerEnv := dispatchEnv
	var runnerCommand []string
	var runnerMounts []corev1.VolumeMount
	var volumes []corev1.Volume
	var initContainers []corev1.Container

	if linuxPod {
		// Token isolation (credential split). The dispatch SA token
		// is the one credential a warm Pod holds that can claim a
		// pending workflow_job — it's pool-scoped, not job-scoped, so
		// a Pod that reads it could race the warm pool to claim other
		// tenants' jobs. Untrusted fork workflow code runs in the
		// runner container, so that container must never see it.
		//
		// Split the Pod in two:
		//   * poller (init container) — mounts the token, runs the
		//     dispatch poll loop, and on a claim stages the minted,
		//     job-scoped JIT config onto a shared emptyDir.
		//   * runner (main container) — holds no token. kubelet won't
		//     start it until the poller init container exits, so it
		//     starts only once a JIT is staged, reads it, and runs the
		//     one job. The JIT binds the runner to a single workflow
		//     run, so leaking it post-claim grants nothing the runner
		//     isn't already entitled to.
		//
		// A warm-standby Pod therefore sits in Init (poller polling)
		// rather than Running until a job is claimed.
		automount = false

		volumes = append(volumes,
			// JIT handoff. emptyDir scoped to this single-tenant Pod:
			// the poller (running as root) writes the JIT here, the
			// runner reads it. Unlike the token, the worst a leak
			// yields is the single-job JIT the runner already runs
			// under.
			corev1.Volume{Name: "tuist-runner-jit", VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{}}},
			// Audience-scoped projected token (audience=
			// tuist-runners-dispatch). Default automount is off, so
			// this is the only SA token in the Pod, and it is mounted
			// into the poller alone. Even exfiltrated it is useless
			// against the kube-apiserver (wrong audience, 1h TTL, SA
			// GC'd on Pod exit).
			corev1.Volume{
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
			},
		)

		pollerEnv := append(append([]corev1.EnvVar{}, dispatchEnv...),
			corev1.EnvVar{Name: "TUIST_RUNNER_JIT_OUTPUT_PATH", Value: jitFilePath},
		)

		// The runner container runs run-job.sh: read the staged JIT
		// and exec ./run.sh under it. It carries no dispatch env and
		// no token mount.
		runnerCommand = []string{"/usr/local/bin/run-job.sh"}
		runnerEnv = []corev1.EnvVar{{Name: "TUIST_RUNNER_JIT_PATH", Value: jitFilePath}}
		runnerMounts = []corev1.VolumeMount{{Name: "tuist-runner-jit", MountPath: jitMountPath, ReadOnly: true}}

		// Linux pods get a dockerd sidecar (k8s 1.29+ native sidecar:
		// initContainer with restartPolicy=Always). The runner stays
		// unprivileged; only the sidecar is privileged, bounded by the
		// Pod's kata-qemu microVM. The startupProbe blocks the rest of
		// the Pod (poller init, then runner) from starting until
		// `docker info` succeeds.
		if dindImage != "" {
			// When a pull-through cache URL is configured, point the
			// sidecar's dockerd at it so the job's docker.io pulls go
			// through the in-cluster cache instead of hitting Docker Hub
			// from the host's shared egress IP. --insecure-registry is
			// required because the cache is plain http in-cluster.
			dockerdMirrorFlags := ""
			if registryMirror != "" {
				mirrorHost := strings.TrimPrefix(strings.TrimPrefix(registryMirror, "https://"), "http://")
				dockerdMirrorFlags = " --registry-mirror=" + registryMirror + " --insecure-registry=" + mirrorHost
			}
			volumes = append(volumes,
				corev1.Volume{Name: "dind-sock", VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{}}},
				corev1.Volume{Name: "work", VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{}}},
				// Node-disk emptyDir holding a sparse disk.img file.
				// The dind sidecar loop-mounts that file as an ext4
				// filesystem onto /var/lib/docker so dockerd's
				// overlay2 driver sees a kernel-native fs (real
				// trusted.* xattr support) rather than virtio-fs.
				// Per upstream kata docs (how-to-run-docker-with-
				// kata.md), virtio-fs can't be an overlayfs upper
				// layer — overlay's trusted.overlay.* xattrs trip
				// the host kernel's CAP_SYS_ADMIN gate that
				// virtiofsd can't bypass. tmpfs medium:Memory or a
				// loop-mounted disk image are the only two
				// recommended workarounds; we pick loop-mounted
				// because the disk.img is sparse on virtio-fs and
				// only consumes node-disk bytes as written (no pod-
				// memory tax of tmpfs medium:Memory). Volume name
				// kept as `dind-storage` for consistency with the
				// earlier shape; mount path moved off /var/lib/docker
				// so the dind entrypoint can loop-mount over it.
				corev1.Volume{Name: "dind-storage", VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{}}},
			)
			runnerMounts = append(runnerMounts,
				corev1.VolumeMount{Name: "dind-sock", MountPath: "/var/run"},
				corev1.VolumeMount{Name: "work", MountPath: "/home/runner/actions-runner/_work"},
			)
			runnerEnv = append(runnerEnv, corev1.EnvVar{Name: "DOCKER_HOST", Value: "unix:///var/run/docker.sock"})
			initContainers = append(initContainers, corev1.Container{
				Name:  "dind",
				Image: dindImage,
				// Entrypoint stages, in order:
				//   1. lift nofile rlimit (kata kernel default
				//      1024 starves dockerd + buildkit on heavy
				//      node_modules trees)
				//   2. install e2fsprogs (Alpine docker:*-dind
				//      ships without mkfs.ext4)
				//   3. truncate a sparse 100 GiB disk.img on the
				//      virtio-fs-backed dind-storage volume —
				//      sparse, only consumes node-disk bytes as
				//      written, so this is a ceiling, not an
				//      allocation. Large enough to fit the full
				//      server-build working set (base image, mix
				//      deps, npm tree, swift toolchain, buildkit
				//      caches) with room to spare.
				//   4. mkfs.ext4 + loop-mount it onto /var/lib/
				//      docker — dockerd now sees real ext4 with
				//      trusted.* xattrs and overlay2 initializes
				//      normally (no vfs fallback, no buildkit
				//      runc-native).
				//   5. exec dockerd with --default-ulimit nofile=
				//      so containers it spawns (incl. buildx's
				//      docker-container buildkit container)
				//      inherit the high cap.
				// --group pins the docker.sock GID so the runner
				// user (member of `docker` group, GID 123) can
				// reach it.
				Command: []string{"sh", "-c"},
				Args: []string{
					"set -e && " +
						"ulimit -n 1048576 && " +
						"apk add --no-cache e2fsprogs >/dev/null && " +
						"mkdir -p /mnt/dind-disk && " +
						"truncate -s 100G /mnt/dind-disk/disk.img && " +
						"mkfs.ext4 -q -F /mnt/dind-disk/disk.img && " +
						"mkdir -p /var/lib/docker && " +
						"mount -o loop /mnt/dind-disk/disk.img /var/lib/docker && " +
						"exec dockerd --host=unix:///var/run/docker.sock --group=123 " +
						"--default-ulimit nofile=1048576:1048576" + dockerdMirrorFlags,
				},
				SecurityContext: &corev1.SecurityContext{
					Privileged: ptr(true),
				},
				RestartPolicy: ptr(corev1.ContainerRestartPolicyAlways),
				StartupProbe: &corev1.Probe{
					ProbeHandler:  corev1.ProbeHandler{Exec: &corev1.ExecAction{Command: []string{"docker", "info"}}},
					PeriodSeconds: 2,
					// Was 30. apk add + truncate + mkfs.ext4 +
					// loop mount add ~8 s of pre-dockerd setup;
					// bump the probe ceiling so a slow apt mirror
					// doesn't trip the restart.
					FailureThreshold: 60,
				},
				VolumeMounts: []corev1.VolumeMount{
					{Name: "dind-sock", MountPath: "/var/run"},
					{Name: "work", MountPath: "/home/runner/actions-runner/_work"},
					{Name: "dind-storage", MountPath: "/mnt/dind-disk"},
				},
			})
		}

		// Machine-metrics sampler: a native sidecar (restartPolicy=
		// Always) that samples the microVM's CPU/memory/network/disk and
		// POSTs them to the server for the job detail page's Metrics tab.
		// It holds the dispatch token (trusted code, like the poller —
		// never the customer container) and reads VM-wide /proc plus the
		// JIT emptyDir's backing filesystem for disk. It idles until the
		// poller stages the JIT (i.e. a job is claimed), so warm-standby
		// Pods don't sample. No startupProbe, so it never blocks the
		// poller/runner from starting; kubelet stops it when the runner
		// container exits.
		metricsEnv := append(append([]corev1.EnvVar{}, dispatchEnv...),
			corev1.EnvVar{Name: "TUIST_RUNNER_JIT_PATH", Value: jitFilePath},
		)
		initContainers = append(initContainers, corev1.Container{
			Name:          "metrics",
			Image:         pool.Spec.Image,
			Command:       []string{"/usr/local/bin/metrics-sampler.sh"},
			Env:           metricsEnv,
			RestartPolicy: ptr(corev1.ContainerRestartPolicyAlways),
			VolumeMounts: []corev1.VolumeMount{
				{Name: "tuist-runner-token", MountPath: "/var/run/secrets/tuist-runner", ReadOnly: true},
				{Name: "tuist-runner-jit", MountPath: jitMountPath, ReadOnly: true},
			},
			// Root only to read the token mount and run our trusted
			// sampling script — never customer code.
			SecurityContext: &corev1.SecurityContext{RunAsUser: ptr(int64(0))},
		})

		// poller runs after the dind sidecar (when present) so it
		// waits on the dind startupProbe exactly as the single runner
		// container did before the split.
		initContainers = append(initContainers, corev1.Container{
			Name:    "poller",
			Image:   pool.Spec.Image,
			Command: []string{"/usr/local/bin/dispatch-poll.sh"},
			Env:     pollerEnv,
			VolumeMounts: []corev1.VolumeMount{
				{Name: "tuist-runner-token", MountPath: "/var/run/secrets/tuist-runner", ReadOnly: true},
				{Name: "tuist-runner-jit", MountPath: jitMountPath},
			},
			// Runs as root only so it can write the JIT into the
			// root-owned emptyDir; it executes our trusted poll
			// script, never customer code. The runner container that
			// runs the workflow stays non-root (image USER).
			SecurityContext: &corev1.SecurityContext{RunAsUser: ptr(int64(0))},
		})
	}

	// No kata virtiofsd annotation — earlier attempts (`--xattr`
	// alone, then `--xattrmap=:map::user.virtiofs.::`) didn't fix
	// the EMFILE class because virtio-fs can't be an overlayfs
	// upper layer regardless of virtiofsd config (host kernel
	// gates trusted.* writes on CAP_SYS_ADMIN of virtiofsd's
	// effective uid). The loop-mounted ext4 above sidesteps the
	// problem entirely by giving dockerd a real kernel-native
	// filesystem.
	annotations := map[string]string{}
	if linuxPod && pool.Spec.RuntimeClass == "kata-qemu" {
		// Enable PSI (/proc/pressure/*) in the kata guest so the runner
		// vitals probe can report CPU/memory pressure. The stock kata
		// kernel ships CONFIG_PSI=y but boots with PSI disabled; `psi=1`
		// on the guest cmdline turns it on. The annotation is honored
		// because the containerd kata runtime whitelists
		// `io.katacontainers.*` pod annotations.
		annotations["io.katacontainers.config.hypervisor.kernel_params"] = "psi=1"
	}

	// Mirror the actions/runner diagnostic log (_diag) to the runner
	// container's stdout so it reaches Loki through the pod-log pipeline.
	// The runner's ReturnCode enum only spans 0-7 and run-helper.sh folds
	// unknown codes to exit 0, so a runner that terminates abnormally
	// (e.g. the microVM is torn down mid-job) writes no reason to stdout —
	// its _diag log is the only record, and it dies with the reaped Pod.
	// Streaming _diag makes that exit reason durable.
	runnerEnv = append(runnerEnv, corev1.EnvVar{Name: "ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT", Value: "1"})

	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:        podName,
			Namespace:   pool.Namespace,
			Annotations: annotations,
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
			// dispatch-audience token explicitly into the poller
			// container only — see the Linux branch above.
			AutomountServiceAccountToken: ptr(automount),
			NodeSelector:                 nodeSelector,
			Affinity:                     goldenAffinity(pool),
			Tolerations:                  tolerations,
			Volumes:                      volumes,
			InitContainers:               initContainers,
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
					Name:         "runner",
					Image:        pool.Spec.Image,
					Command:      runnerCommand,
					Resources:    resources,
					VolumeMounts: runnerMounts,
					Env:          runnerEnv,
				},
			},
		},
	}, nil
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

// goldenNodeLabelPrefix namespaces the per-digest Node labels tart-kubelet
// publishes to advertise which golden base VMs a host already holds.
//
// CONTRACT: this prefix and goldenNodeAffinityKey's hashing MUST stay in
// lockstep with tart-kubelet's `podagent.goldenNodeLabelPrefix` /
// `goldenVMName` — the two live in separate Go modules, so they're coupled
// by this convention, not shared code. A mismatch silently disables the
// affinity (no node ever carries the key the controller prefers), which
// degrades to today's image-blind placement rather than breaking
// scheduling, so it's failure-safe but worth a test on both sides.
const goldenNodeLabelPrefix = "tuist.dev/golden-"

// goldenNodeAffinityKey is the Node-label key advertising that a host holds
// the golden base for `image`. The suffix is the same 8-byte SHA-256 prefix
// of the image ref that tart-kubelet embeds in the golden VM name, so both
// sides derive an identical key from the same digest-pinned ref.
func goldenNodeAffinityKey(image string) string {
	sum := sha256.Sum256([]byte(image))
	return goldenNodeLabelPrefix + hex.EncodeToString(sum[:8])
}

// goldenAffinity returns soft node-affinity steering a pool's Pods toward
// hosts that already hold the golden base for its image, so a recycle is a
// local APFS clonefile instead of a multi-GB cold pull. Preferred, not
// required: when no warm host has a free slot the Pod still schedules onto
// a cold host (and pays the one-time materialize) rather than going Pending.
//
// macOS only — Linux runners are kata microVMs with no golden-base concept,
// and `image` re-pull there is a different (much smaller) story. Returns nil
// for Linux so their Pods keep memory-bin-packed placement untouched.
func goldenAffinity(pool *tuistv1.RunnerPool) *corev1.Affinity {
	if pool.Spec.OS == "linux" {
		return nil
	}
	return &corev1.Affinity{
		NodeAffinity: &corev1.NodeAffinity{
			PreferredDuringSchedulingIgnoredDuringExecution: []corev1.PreferredSchedulingTerm{{
				Weight: 100,
				Preference: corev1.NodeSelectorTerm{
					MatchExpressions: []corev1.NodeSelectorRequirement{{
						Key:      goldenNodeAffinityKey(pool.Spec.Image),
						Operator: corev1.NodeSelectorOpExists,
					}},
				},
			}},
		},
	}
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
