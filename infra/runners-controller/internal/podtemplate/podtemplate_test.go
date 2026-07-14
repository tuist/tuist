package podtemplate

import (
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

const testDindImage = "docker:28-dind"

func basePool(os string) *tuistv1.RunnerPool {
	spec := tuistv1.RunnerPoolSpec{
		OS:            os,
		Image:         "ghcr.io/tuist/tuist-runner:test",
		FleetSelector: "fleet-x",
		DispatchLabel: "tuist-test",
		PodCPUMilli:   4000,
		PodMemoryMB:   16384,
	}
	// Linux pools get the privileged dind sidecar, which Build
	// only permits under the kata-qemu microVM boundary.
	if os == "linux" {
		spec.RuntimeClass = "kata-qemu"
	}
	return &tuistv1.RunnerPool{
		ObjectMeta: metav1.ObjectMeta{Name: "pool-1", Namespace: "tuist-runners"},
		Spec:       spec,
	}
}

func build(t *testing.T, p *tuistv1.RunnerPool) *corev1.Pod {
	t.Helper()
	pod, err := Build(p, "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch", testDindImage, "", "", "")
	if err != nil {
		t.Fatalf("Build returned error: %v", err)
	}
	return pod
}

func TestBuild_MacOSScheduling(t *testing.T) {
	pod := build(t, basePool(""))

	if got, want := pod.Spec.NodeSelector["kubernetes.io/os"], "darwin"; got != want {
		t.Errorf("nodeSelector os = %q, want %q", got, want)
	}
	if got, want := pod.Spec.NodeSelector["tuist.dev/runtime"], "tart"; got != want {
		t.Errorf("nodeSelector runtime = %q, want %q", got, want)
	}
	if got, want := pod.Spec.NodeSelector["tuist.dev/fleet"], "fleet-x"; got != want {
		t.Errorf("nodeSelector fleet = %q, want %q", got, want)
	}
	if len(pod.Spec.Tolerations) != 1 || pod.Spec.Tolerations[0].Key != "tuist.dev/macos" {
		t.Errorf("Tolerations = %+v, want one tuist.dev/macos toleration", pod.Spec.Tolerations)
	}
}

func TestBuild_MacOSGoldenAffinity(t *testing.T) {
	p := basePool("")
	pod := build(t, p)

	aff := pod.Spec.Affinity
	if aff == nil || aff.NodeAffinity == nil {
		t.Fatal("macOS pod is missing golden node affinity")
	}
	terms := aff.NodeAffinity.PreferredDuringSchedulingIgnoredDuringExecution
	if len(terms) != 1 {
		t.Fatalf("preferred terms = %d, want 1", len(terms))
	}
	exprs := terms[0].Preference.MatchExpressions
	if len(exprs) != 1 {
		t.Fatalf("match expressions = %d, want 1", len(exprs))
	}
	if got, want := exprs[0].Key, goldenNodeAffinityKey(p.Spec.Image); got != want {
		t.Fatalf("affinity key = %q, want %q", got, want)
	}
	if exprs[0].Operator != corev1.NodeSelectorOpExists {
		t.Fatalf("affinity operator = %q, want Exists", exprs[0].Operator)
	}
	// Soft, not required: a Pod must still schedule onto a cold host when
	// no warm one is free.
	if aff.NodeAffinity.RequiredDuringSchedulingIgnoredDuringExecution != nil {
		t.Fatal("golden affinity must be preferred, never required")
	}
}

func TestBuild_LinuxHasNoGoldenAffinity(t *testing.T) {
	pod := build(t, basePool("linux"))
	if pod.Spec.Affinity != nil {
		t.Fatalf("linux pod got affinity %+v, want nil (no golden-base concept)", pod.Spec.Affinity)
	}
}

// Pins the golden Node-label key to the exact value tart-kubelet derives for
// the same image (asserted on the other side in podagent's TestGoldenNodeLabel).
// The two live in separate Go modules; this shared literal is the contract.
func TestGoldenNodeAffinityKey_MatchesTartKubelet(t *testing.T) {
	img := "ghcr.io/tuist/tuist-runner@sha256:" + strings.Repeat("a", 64)
	const wantKey = "tuist.dev/golden-9c8af651fdf30b10"
	if got := goldenNodeAffinityKey(img); got != wantKey {
		t.Fatalf("goldenNodeAffinityKey = %q, want %q", got, wantKey)
	}
}

func TestBuild_LinuxScheduling(t *testing.T) {
	pod := build(t, basePool("linux"))
	// Linux pools must use the in-cluster URL — the public path
	// hits Hetzner Cloud LB hairpin and silently times out. The poll
	// loop (and therefore the dispatch URL) lives on the poller init
	// container after the credential split, not the runner.
	poller := initContainerByName(t, pod, "poller")
	if got := envValue(poller.Env, "TUIST_RUNNER_DISPATCH_URL"); got != "http://internal-dispatch" {
		t.Errorf("Linux dispatch URL = %q, want http://internal-dispatch", got)
	}

	if got, want := pod.Spec.NodeSelector["kubernetes.io/os"], "linux"; got != want {
		t.Errorf("nodeSelector os = %q, want %q", got, want)
	}
	if got, want := pod.Spec.NodeSelector["kubernetes.io/arch"], "amd64"; got != want {
		t.Errorf("nodeSelector arch = %q, want %q", got, want)
	}
	if got, want := pod.Spec.NodeSelector["node.cluster.x-k8s.io/pool"], "fleet-x"; got != want {
		t.Errorf("nodeSelector pool = %q, want %q", got, want)
	}
	if _, present := pod.Spec.NodeSelector["tuist.dev/fleet"]; present {
		t.Errorf("nodeSelector should NOT carry tuist.dev/fleet on Linux pools (that's the macOS-only key)")
	}
	if _, present := pod.Spec.NodeSelector["tuist.dev/runtime"]; present {
		t.Errorf("nodeSelector should NOT carry tuist.dev/runtime on Linux pools")
	}
	if len(pod.Spec.Tolerations) != 1 {
		t.Fatalf("Tolerations = %+v, want exactly 1 (bare-metal runner-tier)", pod.Spec.Tolerations)
	}
	tol := pod.Spec.Tolerations[0]
	if tol.Key != "tuist.dev/runner-tier" || tol.Value != "bare-metal" || tol.Effect != "NoSchedule" {
		t.Errorf("Toleration = %+v, want {Key:tuist.dev/runner-tier Value:bare-metal Effect:NoSchedule}", tol)
	}
}

func TestBuild_LinuxMetricsSidecar(t *testing.T) {
	pod := build(t, basePool("linux"))
	m := initContainerByName(t, pod, "metrics")

	// Native sidecar so it runs alongside the job and kubelet stops it
	// when the runner exits.
	if m.RestartPolicy == nil || *m.RestartPolicy != corev1.ContainerRestartPolicyAlways {
		t.Errorf("metrics sidecar RestartPolicy = %v, want Always", m.RestartPolicy)
	}
	if len(m.Command) == 0 || !strings.Contains(m.Command[0], "metrics-sampler.sh") {
		t.Errorf("metrics command = %v, want metrics-sampler.sh", m.Command)
	}
	// Holds the dispatch token (it POSTs authenticated) like the poller,
	// and reads the JIT emptyDir (to gate on a claim + df the disk).
	if !hasVolumeMount(m.VolumeMounts, corev1.VolumeMount{Name: "tuist-runner-token", MountPath: "/var/run/secrets/tuist-runner"}) {
		t.Errorf("metrics sidecar missing tuist-runner-token mount; got %+v", m.VolumeMounts)
	}
	if !hasVolumeMount(m.VolumeMounts, corev1.VolumeMount{Name: "tuist-runner-jit", MountPath: jitMountPath}) {
		t.Errorf("metrics sidecar missing tuist-runner-jit mount; got %+v", m.VolumeMounts)
	}
	// Carries the dispatch env (the in-cluster URL is the metrics base)
	// and the JIT path it waits on before sampling.
	if got := envValue(m.Env, "TUIST_RUNNER_DISPATCH_URL"); got != "http://internal-dispatch" {
		t.Errorf("metrics DISPATCH_URL = %q, want http://internal-dispatch", got)
	}
	if got := envValue(m.Env, "TUIST_RUNNER_JIT_PATH"); got != jitFilePath {
		t.Errorf("metrics JIT_PATH = %q, want %q", got, jitFilePath)
	}
}

func TestBuild_MacOSHasNoMetricsSidecar(t *testing.T) {
	// macOS samples in-VM via a script forked from dispatch-poll.sh, not
	// a sidecar — Build must not add a metrics init container there.
	pod := build(t, basePool(""))
	for _, c := range pod.Spec.InitContainers {
		if c.Name == "metrics" {
			t.Fatalf("macOS pod should have no metrics init container; got %+v", pod.Spec.InitContainers)
		}
	}
}

func TestBuild_UnknownOSFallsBackToMacOS(t *testing.T) {
	// A misconfigured OS field should still produce a schedulable
	// Pod against the macOS fleet rather than fail open.
	pod := build(t, basePool("solaris"))
	if got, want := pod.Spec.NodeSelector["kubernetes.io/os"], "darwin"; got != want {
		t.Errorf("nodeSelector os = %q, want darwin fallback", got)
	}
}

func TestBuild_ClusterDNSEnvOnMacOSOnly(t *testing.T) {
	// macOS Pods carry the in-VM resolver config when the controller
	// has a cluster DNS IP; Linux Pods (CNI DNS) never do, and macOS
	// Pods on a controller without the flag don't either — the env
	// presence is what makes dispatch-poll.sh write /etc/resolver.
	macPod, err := Build(basePool("macos"), "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch", "", "", "10.128.0.10", "cluster.local")
	if err != nil {
		t.Fatalf("Build returned error: %v", err)
	}
	macEnv := macPod.Spec.Containers[0].Env
	if got, want := envValue(macEnv, "TUIST_CLUSTER_DNS_IP"), "10.128.0.10"; got != want {
		t.Errorf("TUIST_CLUSTER_DNS_IP = %q, want %q", got, want)
	}
	if got, want := envValue(macEnv, "TUIST_CLUSTER_DOMAIN"), "cluster.local"; got != want {
		t.Errorf("TUIST_CLUSTER_DOMAIN = %q, want %q", got, want)
	}

	macPodNoDNS, err := Build(basePool("macos"), "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch", "", "", "", "cluster.local")
	if err != nil {
		t.Fatalf("Build returned error: %v", err)
	}
	if got := envValue(macPodNoDNS.Spec.Containers[0].Env, "TUIST_CLUSTER_DNS_IP"); got != "" {
		t.Errorf("TUIST_CLUSTER_DNS_IP = %q on macOS without --cluster-dns-ip, want absent", got)
	}

	linuxPod, err := Build(basePool("linux"), "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch", testDindImage, "", "10.128.0.10", "cluster.local")
	if err != nil {
		t.Fatalf("Build returned error: %v", err)
	}
	for _, c := range append(linuxPod.Spec.InitContainers, linuxPod.Spec.Containers...) {
		if got := envValue(c.Env, "TUIST_CLUSTER_DNS_IP"); got != "" {
			t.Errorf("TUIST_CLUSTER_DNS_IP = %q on linux container %s, want absent", got, c.Name)
		}
	}
}

func TestBuild_RuntimeClassNameStampedWhenSet(t *testing.T) {
	pool := basePool("linux")
	pool.Spec.RuntimeClass = "kata-qemu"
	pod := build(t, pool)
	if pod.Spec.RuntimeClassName == nil {
		t.Fatalf("RuntimeClassName = nil, want \"kata-qemu\"")
	}
	if got := *pod.Spec.RuntimeClassName; got != "kata-qemu" {
		t.Errorf("RuntimeClassName = %q, want \"kata-qemu\"", got)
	}
}

func TestBuild_RuntimeClassNameNilWhenUnset(t *testing.T) {
	// A pool with no RuntimeClass and no dind sidecar (empty
	// dindImage) is allowed to fall back to the default runtime.
	pool := basePool("linux")
	pool.Spec.RuntimeClass = ""
	pod, err := Build(pool, "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch", "", "", "", "")
	if err != nil {
		t.Fatalf("Build returned error: %v", err)
	}
	if pod.Spec.RuntimeClassName != nil {
		t.Errorf("RuntimeClassName = %v, want nil for default runtime", *pod.Spec.RuntimeClassName)
	}
}

func TestBuild_LinuxDindWithoutKataFailsClosed(t *testing.T) {
	// A Linux pool that would get the privileged dind sidecar but
	// isn't pinned to kata-qemu must be refused — otherwise the
	// privileged container runs on the host runtime, escaping the
	// microVM boundary.
	pool := basePool("linux")
	pool.Spec.RuntimeClass = ""
	_, err := Build(pool, "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch", testDindImage, "", "", "")
	if err == nil {
		t.Fatal("Build returned nil error; want refusal for Linux+dind without kata-qemu")
	}

	pool.Spec.RuntimeClass = "some-other-runtime"
	if _, err := Build(pool, "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch", testDindImage, "", "", ""); err == nil {
		t.Fatal("Build accepted non-kata runtimeClass for Linux+dind; want refusal")
	}
}

func TestBuild_LinuxPodGetsDindSidecar(t *testing.T) {
	// Linux pods get a dind native sidecar (initContainer with
	// restartPolicy=Always) instead of running dockerd in the
	// runner container. Mirrors the ARC pattern.
	pod := build(t, basePool("linux"))

	// Three init containers: the dind sidecar first (so its startupProbe
	// gates the rest of the Pod), then the metrics sidecar, then the
	// poller.
	if len(pod.Spec.InitContainers) != 3 {
		t.Fatalf("InitContainers = %d, want 3 (dind sidecar + metrics sidecar + poller)", len(pod.Spec.InitContainers))
	}
	dind := pod.Spec.InitContainers[0]
	if dind.Name != "dind" {
		t.Errorf("first initContainer Name = %q, want \"dind\" (must precede poller so docker is ready)", dind.Name)
	}
	if dind.Image != testDindImage {
		t.Errorf("sidecar Image = %q, want %q", dind.Image, testDindImage)
	}
	if dind.RestartPolicy == nil || *dind.RestartPolicy != corev1.ContainerRestartPolicyAlways {
		t.Errorf("sidecar RestartPolicy = %v, want Always (native sidecar)", dind.RestartPolicy)
	}
	if dind.SecurityContext == nil || dind.SecurityContext.Privileged == nil || !*dind.SecurityContext.Privileged {
		t.Errorf("sidecar SecurityContext = %+v, want privileged=true", dind.SecurityContext)
	}
	if dind.StartupProbe == nil || dind.StartupProbe.Exec == nil {
		t.Fatalf("sidecar missing exec startupProbe; got %+v", dind.StartupProbe)
	}
	if cmd := dind.StartupProbe.Exec.Command; len(cmd) != 2 || cmd[0] != "docker" || cmd[1] != "info" {
		t.Errorf("sidecar startupProbe.exec = %v, want [docker info]", cmd)
	}

	// Runner container stays unprivileged; defense in depth on top
	// of the kata-qemu microVM boundary.
	runner := pod.Spec.Containers[0]
	if runner.SecurityContext != nil && runner.SecurityContext.Privileged != nil && *runner.SecurityContext.Privileged {
		t.Errorf("runner SecurityContext = %+v, want no privileged flag", runner.SecurityContext)
	}

	// DOCKER_HOST points at the shared socket so the runner's
	// docker CLI hits the sidecar's daemon.
	var sawDockerHost bool
	for _, env := range runner.Env {
		if env.Name == "DOCKER_HOST" && env.Value == "unix:///var/run/docker.sock" {
			sawDockerHost = true
		}
	}
	if !sawDockerHost {
		t.Errorf("runner env missing DOCKER_HOST=unix:///var/run/docker.sock; got %+v", runner.Env)
	}

	// Shared between containers: docker.sock + work paths so
	// docker-run -v bind-mounts resolve identically on both sides.
	for _, vm := range []corev1.VolumeMount{
		{Name: "dind-sock", MountPath: "/var/run"},
		{Name: "work", MountPath: "/home/runner/actions-runner/_work"},
	} {
		if !hasVolumeMount(runner.VolumeMounts, vm) {
			t.Errorf("runner missing volumeMount %+v; got %+v", vm, runner.VolumeMounts)
		}
		if !hasVolumeMount(dind.VolumeMounts, vm) {
			t.Errorf("sidecar missing volumeMount %+v; got %+v", vm, dind.VolumeMounts)
		}
	}
	// dind-storage holds the sparse disk.img the dind entrypoint
	// loop-mounts as ext4 onto /var/lib/docker. Mounted at
	// /mnt/dind-disk on the sidecar only; the runner has no
	// business reaching either dockerd's image store or the raw
	// disk image.
	dindStorage := corev1.VolumeMount{Name: "dind-storage", MountPath: "/mnt/dind-disk"}
	if !hasVolumeMount(dind.VolumeMounts, dindStorage) {
		t.Errorf("sidecar missing %+v; got %+v", dindStorage, dind.VolumeMounts)
	}
	if hasVolumeMount(runner.VolumeMounts, dindStorage) {
		t.Errorf("runner should not mount dind-storage")
	}
	for _, v := range []string{"dind-sock", "work", "dind-storage"} {
		if !hasVolume(pod.Spec.Volumes, v) {
			t.Errorf("pod missing volume %q; got %+v", v, pod.Spec.Volumes)
		}
	}

	// dind-storage must be a plain node-disk emptyDir. The
	// loop-mounted ext4 inside the kata VM is what gives dockerd
	// real trusted.* xattr support; medium:Memory would put the
	// disk.img on tmpfs and eat pod memory pointlessly.
	for _, v := range pod.Spec.Volumes {
		if v.Name == "dind-storage" {
			if v.EmptyDir == nil {
				t.Fatalf("dind-storage volume = %+v, want EmptyDir source", v.VolumeSource)
			}
			if v.EmptyDir.Medium != "" {
				t.Errorf("dind-storage EmptyDir.Medium = %q, want \"\" (node disk)", v.EmptyDir.Medium)
			}
		}
	}
}

func TestBuild_LinuxDindRegistryMirror(t *testing.T) {
	// With a mirror URL configured, dockerd launches with
	// --registry-mirror plus a matching --insecure-registry (the
	// in-cluster cache is plain http).
	const mirror = "http://registry-cache.svc:5000"
	pod, err := Build(basePool("linux"), "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch", testDindImage, mirror, "", "")
	if err != nil {
		t.Fatalf("Build returned error: %v", err)
	}
	args := strings.Join(pod.Spec.InitContainers[0].Args, " ")
	if !strings.Contains(args, "--registry-mirror="+mirror) {
		t.Errorf("dind args missing --registry-mirror=%s; got %v", mirror, args)
	}
	if !strings.Contains(args, "--insecure-registry=registry-cache.svc:5000") {
		t.Errorf("dind args missing --insecure-registry for the cache host (scheme must be stripped); got %v", args)
	}
}

func TestBuild_LinuxDindNoRegistryMirrorByDefault(t *testing.T) {
	// Empty mirror → no --registry-mirror flag; dockerd pulls docker.io
	// directly.
	pod := build(t, basePool("linux"))
	args := strings.Join(pod.Spec.InitContainers[0].Args, " ")
	if strings.Contains(args, "--registry-mirror") {
		t.Errorf("dind args must not carry --registry-mirror when none configured; got %v", args)
	}
}

func TestBuild_LinuxPodHasNoKataVirtioFsAnnotation(t *testing.T) {
	// The dind sidecar's entrypoint loop-mounts an ext4 file
	// onto /var/lib/docker, so dockerd never touches virtio-fs
	// for overlay2 — no virtiofsd flag is needed. Earlier
	// attempts to fix overlay-on-virtiofs via --xattr alone, or
	// via --xattrmap, were either silent no-ops (--xattr) or
	// broke kata sandbox creation (--xattrmap, which Rust
	// virtiofsd-rs doesn't accept).
	pod := build(t, basePool("linux"))
	if _, ok := pod.Annotations["io.katacontainers.config.hypervisor.virtio_fs_extra_args"]; ok {
		t.Errorf("Linux pod should not carry virtio_fs_extra_args annotation anymore; got %+v", pod.Annotations)
	}
}

func TestBuild_MacOSPodHasNoKataXattrAnnotation(t *testing.T) {
	pod := build(t, basePool(""))
	if _, ok := pod.Annotations["io.katacontainers.config.hypervisor.virtio_fs_extra_args"]; ok {
		t.Errorf("macOS pod should not carry kata virtiofsd annotations; got %+v", pod.Annotations)
	}
}

func TestBuild_LinuxPodEnablesPSIViaKataAnnotation(t *testing.T) {
	// The vitals probe reads /proc/pressure/* for CPU/memory pressure,
	// but the kata guest kernel boots with PSI off unless psi=1 is on
	// the cmdline. The annotation appends it (whitelisted via the
	// containerd kata runtime's io.katacontainers.* pod_annotations).
	pod := build(t, basePool("linux"))
	if got := pod.Annotations["io.katacontainers.config.hypervisor.kernel_params"]; got != "psi=1" {
		t.Errorf("kernel_params annotation = %q, want \"psi=1\"", got)
	}
}

func TestBuild_MacOSPodHasNoKataKernelParamsAnnotation(t *testing.T) {
	// psi=1 is a kata-guest concern; macOS pods aren't kata, so the
	// annotation must not leak onto them.
	pod := build(t, basePool(""))
	if _, ok := pod.Annotations["io.katacontainers.config.hypervisor.kernel_params"]; ok {
		t.Errorf("macOS pod should not carry kata kernel_params annotation; got %+v", pod.Annotations)
	}
}

func TestBuild_LinuxPodWithoutDindImageSkipsSidecar(t *testing.T) {
	// Empty dindImage (macOS-only install) must not produce a
	// sidecar or DOCKER_HOST env even on a Linux pool.
	pod, err := Build(basePool("linux"), "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch", "", "", "", "")
	if err != nil {
		t.Fatalf("Build returned error: %v", err)
	}
	// The metrics sidecar + poller remain — but no dind sidecar.
	if len(pod.Spec.InitContainers) != 2 {
		t.Fatalf("InitContainers = %d, want 2 (metrics sidecar + poller) when dindImage is empty", len(pod.Spec.InitContainers))
	}
	for _, c := range pod.Spec.InitContainers {
		if c.Name == "dind" {
			t.Errorf("found a dind init container; want none when dindImage is empty")
		}
	}
	_ = initContainerByName(t, pod, "poller")
	for _, env := range pod.Spec.Containers[0].Env {
		if env.Name == "DOCKER_HOST" {
			t.Errorf("runner should not carry DOCKER_HOST when sidecar is absent; got %q", env.Value)
		}
	}
}

func TestBuild_MacOSPodHasNoDindSidecar(t *testing.T) {
	pod := build(t, basePool(""))
	if len(pod.Spec.InitContainers) != 0 {
		t.Errorf("macOS pods must not get the dind sidecar; got %d initContainers", len(pod.Spec.InitContainers))
	}
	for _, env := range pod.Spec.Containers[0].Env {
		if env.Name == "DOCKER_HOST" {
			t.Errorf("macOS pods should not carry DOCKER_HOST; got %q", env.Value)
		}
	}
}

func TestBuild_LinuxCredentialSplit(t *testing.T) {
	// Token isolation: the runner container (which runs untrusted
	// workflow code) must never mount the dispatch token; only the
	// poller does. The handoff is the JIT staged on a shared emptyDir.
	pod := build(t, basePool("linux"))

	runner := containerByName(t, pod, "runner")
	poller := initContainerByName(t, pod, "poller")

	// Runner: no token mount, no dispatch env, JIT mounted read-only,
	// run-job.sh as the entrypoint.
	if hasVolumeMount(runner.VolumeMounts, corev1.VolumeMount{Name: "tuist-runner-token", MountPath: "/var/run/secrets/tuist-runner"}) {
		t.Errorf("runner must NOT mount the dispatch token; got %+v", runner.VolumeMounts)
	}
	for _, name := range []string{"TUIST_RUNNER_DISPATCH_URL", "TUIST_RUNNER_POOL"} {
		if envValue(runner.Env, name) != "" {
			t.Errorf("runner must not carry dispatch env %q; got %+v", name, runner.Env)
		}
	}
	jitMount := corev1.VolumeMount{Name: "tuist-runner-jit", MountPath: jitMountPath}
	if !hasVolumeMount(runner.VolumeMounts, jitMount) {
		t.Errorf("runner missing JIT mount %+v; got %+v", jitMount, runner.VolumeMounts)
	}
	for _, m := range runner.VolumeMounts {
		if m.Name == "tuist-runner-jit" && !m.ReadOnly {
			t.Errorf("runner JIT mount should be read-only; got %+v", m)
		}
	}
	if got, want := runner.Command, []string{"/usr/local/bin/run-job.sh"}; len(got) != 1 || got[0] != want[0] {
		t.Errorf("runner Command = %v, want %v", got, want)
	}
	if envValue(runner.Env, "TUIST_RUNNER_JIT_PATH") != jitFilePath {
		t.Errorf("runner TUIST_RUNNER_JIT_PATH = %q, want %q", envValue(runner.Env, "TUIST_RUNNER_JIT_PATH"), jitFilePath)
	}

	// Poller: holds the token (read-only), can write the JIT, runs the
	// poll loop, and runs as root so it can write to the root-owned
	// emptyDir.
	tokenMount := corev1.VolumeMount{Name: "tuist-runner-token", MountPath: "/var/run/secrets/tuist-runner"}
	if !hasVolumeMount(poller.VolumeMounts, tokenMount) {
		t.Errorf("poller missing token mount %+v; got %+v", tokenMount, poller.VolumeMounts)
	}
	for _, m := range poller.VolumeMounts {
		if m.Name == "tuist-runner-token" && !m.ReadOnly {
			t.Errorf("poller token mount should be read-only; got %+v", m)
		}
		if m.Name == "tuist-runner-jit" && m.ReadOnly {
			t.Errorf("poller JIT mount must be writable; got %+v", m)
		}
	}
	if !hasVolumeMount(poller.VolumeMounts, corev1.VolumeMount{Name: "tuist-runner-jit", MountPath: jitMountPath}) {
		t.Errorf("poller missing writable JIT mount; got %+v", poller.VolumeMounts)
	}
	if envValue(poller.Env, "TUIST_RUNNER_JIT_OUTPUT_PATH") != jitFilePath {
		t.Errorf("poller TUIST_RUNNER_JIT_OUTPUT_PATH = %q, want %q", envValue(poller.Env, "TUIST_RUNNER_JIT_OUTPUT_PATH"), jitFilePath)
	}
	if got, want := poller.Command, []string{"/usr/local/bin/dispatch-poll.sh"}; len(got) != 1 || got[0] != want[0] {
		t.Errorf("poller Command = %v, want %v", got, want)
	}
	if poller.SecurityContext == nil || poller.SecurityContext.RunAsUser == nil || *poller.SecurityContext.RunAsUser != 0 {
		t.Errorf("poller must run as root (uid 0) to write the JIT emptyDir; got %+v", poller.SecurityContext)
	}

	// Both the JIT and token volumes exist on the Pod, and the runner
	// keeps automount off.
	for _, v := range []string{"tuist-runner-jit", "tuist-runner-token"} {
		if !hasVolume(pod.Spec.Volumes, v) {
			t.Errorf("pod missing volume %q; got %+v", v, pod.Spec.Volumes)
		}
	}
	if pod.Spec.AutomountServiceAccountToken == nil || *pod.Spec.AutomountServiceAccountToken {
		t.Errorf("Linux pod must disable default SA token automount; got %v", pod.Spec.AutomountServiceAccountToken)
	}
}

func TestBuild_MacOSHasNoPollerOrTokenVolume(t *testing.T) {
	// macOS keeps the single-container shape: the Tart VM is the
	// isolation boundary and tart-kubelet projects the token into it,
	// so there's no poller init container, no JIT volume, and the
	// runner container carries the dispatch env itself.
	pod := build(t, basePool(""))

	for _, c := range pod.Spec.InitContainers {
		if c.Name == "poller" {
			t.Errorf("macOS pod must not get a poller init container")
		}
	}
	for _, v := range []string{"tuist-runner-jit", "tuist-runner-token"} {
		if hasVolume(pod.Spec.Volumes, v) {
			t.Errorf("macOS pod must not carry volume %q", v)
		}
	}
	runner := containerByName(t, pod, "runner")
	if runner.Command != nil {
		t.Errorf("macOS runner must use the image CMD, not a Command override; got %v", runner.Command)
	}
	if envValue(runner.Env, "TUIST_RUNNER_DISPATCH_URL") != "http://dispatch" {
		t.Errorf("macOS runner dispatch URL = %q, want public http://dispatch", envValue(runner.Env, "TUIST_RUNNER_DISPATCH_URL"))
	}
	if pod.Spec.AutomountServiceAccountToken == nil || !*pod.Spec.AutomountServiceAccountToken {
		t.Errorf("macOS pod must keep default SA token automount on; got %v", pod.Spec.AutomountServiceAccountToken)
	}
}

func TestBuild_RunnerMirrorsDiagLogToStdout(t *testing.T) {
	// ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1 streams the actions/runner
	// _diag log to the runner's stdout so an abnormal exit's reason
	// survives in Loki after the Pod is reaped. It belongs on the runner
	// container in every shape, since that's where the runner binary runs.
	for _, os := range []string{"linux", ""} {
		pod := build(t, basePool(os))
		runner := containerByName(t, pod, "runner")
		if got := envValue(runner.Env, "ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT"); got != "1" {
			t.Errorf("os=%q: runner ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT = %q, want \"1\"; env %+v", os, got, runner.Env)
		}
	}

	// The poller runs dispatch-poll.sh, not the runner binary, so it must
	// not carry the flag.
	pod := build(t, basePool("linux"))
	poller := initContainerByName(t, pod, "poller")
	if got := envValue(poller.Env, "ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT"); got != "" {
		t.Errorf("poller must not carry ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT; got %q", got)
	}
}

func containerByName(t *testing.T, pod *corev1.Pod, name string) corev1.Container {
	t.Helper()
	for _, c := range pod.Spec.Containers {
		if c.Name == name {
			return c
		}
	}
	t.Fatalf("container %q not found; got %+v", name, pod.Spec.Containers)
	return corev1.Container{}
}

func initContainerByName(t *testing.T, pod *corev1.Pod, name string) corev1.Container {
	t.Helper()
	for _, c := range pod.Spec.InitContainers {
		if c.Name == name {
			return c
		}
	}
	t.Fatalf("init container %q not found; got %+v", name, pod.Spec.InitContainers)
	return corev1.Container{}
}

func envValue(env []corev1.EnvVar, name string) string {
	for _, e := range env {
		if e.Name == name {
			return e.Value
		}
	}
	return ""
}

func hasVolumeMount(mounts []corev1.VolumeMount, want corev1.VolumeMount) bool {
	for _, m := range mounts {
		if m.Name == want.Name && m.MountPath == want.MountPath {
			return true
		}
	}
	return false
}

func hasVolume(volumes []corev1.Volume, name string) bool {
	for _, v := range volumes {
		if v.Name == name {
			return true
		}
	}
	return false
}
