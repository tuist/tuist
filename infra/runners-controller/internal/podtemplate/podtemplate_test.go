package podtemplate

import (
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

const testDindImage = "docker:28-dind"

func basePool(os string) *tuistv1.RunnerPool {
	return &tuistv1.RunnerPool{
		ObjectMeta: metav1.ObjectMeta{Name: "pool-1", Namespace: "tuist-runners"},
		Spec: tuistv1.RunnerPoolSpec{
			OS:            os,
			Image:         "ghcr.io/tuist/tuist-runner:test",
			FleetSelector: "fleet-x",
			DispatchLabel: "tuist-test",
			PodCPUMilli:   4000,
			PodMemoryMB:   16384,
		},
	}
}

func build(p *tuistv1.RunnerPool) *corev1.Pod {
	return Build(p, "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch", testDindImage)
}

func TestBuild_MacOSScheduling(t *testing.T) {
	pod := build(basePool(""))

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

func TestBuild_LinuxScheduling(t *testing.T) {
	pod := build(basePool("linux"))
	// Linux pools must use the in-cluster URL — the public path
	// hits Hetzner Cloud LB hairpin and silently times out.
	for _, env := range pod.Spec.Containers[0].Env {
		if env.Name == "TUIST_RUNNER_DISPATCH_URL" {
			if env.Value != "http://internal-dispatch" {
				t.Errorf("Linux dispatch URL = %q, want http://internal-dispatch", env.Value)
			}
		}
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

func TestBuild_UnknownOSFallsBackToMacOS(t *testing.T) {
	// A misconfigured OS field should still produce a schedulable
	// Pod against the macOS fleet rather than fail open.
	pod := build(basePool("solaris"))
	if got, want := pod.Spec.NodeSelector["kubernetes.io/os"], "darwin"; got != want {
		t.Errorf("nodeSelector os = %q, want darwin fallback", got)
	}
}

func TestBuild_RuntimeClassNameStampedWhenSet(t *testing.T) {
	pool := basePool("linux")
	pool.Spec.RuntimeClass = "kata-qemu"
	pod := build(pool)
	if pod.Spec.RuntimeClassName == nil {
		t.Fatalf("RuntimeClassName = nil, want \"kata-qemu\"")
	}
	if got := *pod.Spec.RuntimeClassName; got != "kata-qemu" {
		t.Errorf("RuntimeClassName = %q, want \"kata-qemu\"", got)
	}
}

func TestBuild_RuntimeClassNameNilWhenUnset(t *testing.T) {
	pool := basePool("linux")
	pod := build(pool)
	if pod.Spec.RuntimeClassName != nil {
		t.Errorf("RuntimeClassName = %v, want nil for default runtime", *pod.Spec.RuntimeClassName)
	}
}

func TestBuild_LinuxPodGetsDindSidecar(t *testing.T) {
	// Linux pods get a dind native sidecar (initContainer with
	// restartPolicy=Always) instead of running dockerd in the
	// runner container. Mirrors the ARC pattern.
	pod := build(basePool("linux"))

	if len(pod.Spec.InitContainers) != 1 {
		t.Fatalf("InitContainers = %d, want 1 (dind sidecar)", len(pod.Spec.InitContainers))
	}
	dind := pod.Spec.InitContainers[0]
	if dind.Name != "dind" {
		t.Errorf("sidecar Name = %q, want \"dind\"", dind.Name)
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
	// /var/lib/docker only on the sidecar (the runner has no
	// business writing to dockerd's image store).
	dindStorage := corev1.VolumeMount{Name: "dind-storage", MountPath: "/var/lib/docker"}
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

	// dind-storage must be a plain node-disk emptyDir — overlay2's
	// xattr requirement is satisfied by the kata virtiofsd --xattr
	// annotation (asserted below), not by switching the medium to
	// tmpfs. Tmpfs medium would silently eat pod memory.
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

func TestBuild_LinuxPodCarriesKataXattrAnnotation(t *testing.T) {
	// kata's virtiofsd defaults xattr passthrough OFF; without the
	// annotation, overlay2 inside the microVM falls back to vfs and
	// any docker-using workflow that works on cloud-VM GitHub
	// runners breaks here. The annotation flips passthrough on
	// per-Pod (kata's enable_annotations whitelist permits it).
	//
	// --xattr enables xattr methods at all; --xattrmap remaps
	// every guest xattr to user.virtiofs.* on the host so
	// trusted.overlay.* writes from privileged dind don't trip
	// the host kernel's CAP_SYS_ADMIN gate on trusted.*. Without
	// the remap, dockerd silently rejects overlay2 (the probe
	// setxattr returns EPERM) and falls back to vfs.
	pod := build(basePool("linux"))
	got, ok := pod.Annotations["io.katacontainers.config.hypervisor.virtio_fs_extra_args"]
	if !ok {
		t.Fatalf("Linux pod missing virtio_fs_extra_args annotation; got %+v", pod.Annotations)
	}
	// kata's shim json-unmarshals this into []string; raw "--xattr"
	// trips json.Unmarshal and the pod sandbox never starts.
	want := `["--xattr","--xattrmap=:map::user.virtiofs.::"]`
	if got != want {
		t.Errorf("virtio_fs_extra_args = %q, want %q (JSON-encoded array)", got, want)
	}
}

func TestBuild_MacOSPodHasNoKataXattrAnnotation(t *testing.T) {
	pod := build(basePool(""))
	if _, ok := pod.Annotations["io.katacontainers.config.hypervisor.virtio_fs_extra_args"]; ok {
		t.Errorf("macOS pod should not carry kata virtiofsd annotations; got %+v", pod.Annotations)
	}
}

func TestBuild_LinuxPodWithoutDindImageSkipsSidecar(t *testing.T) {
	// Empty dindImage (macOS-only install) must not produce a
	// sidecar or DOCKER_HOST env even on a Linux pool.
	pod := Build(basePool("linux"), "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch", "")
	if len(pod.Spec.InitContainers) != 0 {
		t.Errorf("InitContainers = %d, want 0 when dindImage is empty", len(pod.Spec.InitContainers))
	}
	for _, env := range pod.Spec.Containers[0].Env {
		if env.Name == "DOCKER_HOST" {
			t.Errorf("runner should not carry DOCKER_HOST when sidecar is absent; got %q", env.Value)
		}
	}
}

func TestBuild_MacOSPodHasNoDindSidecar(t *testing.T) {
	pod := build(basePool(""))
	if len(pod.Spec.InitContainers) != 0 {
		t.Errorf("macOS pods must not get the dind sidecar; got %d initContainers", len(pod.Spec.InitContainers))
	}
	for _, env := range pod.Spec.Containers[0].Env {
		if env.Name == "DOCKER_HOST" {
			t.Errorf("macOS pods should not carry DOCKER_HOST; got %q", env.Value)
		}
	}
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
