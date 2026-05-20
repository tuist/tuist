package podtemplate

import (
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

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

func TestBuild_MacOSScheduling(t *testing.T) {
	pod := Build(basePool(""), "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch")

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
	pod := Build(basePool("linux"), "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch")
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
	// Hetzner Robot bare-metal hosts join the workload cluster via
	// kubeadm out-of-band (not CAPI-managed in v1), and the operator
	// labels them `node.cluster.x-k8s.io/pool=<FleetSelector>` so the
	// Pod's nodeSelector pins to the runner-tier hosts.
	if got, want := pod.Spec.NodeSelector["node.cluster.x-k8s.io/pool"], "fleet-x"; got != want {
		t.Errorf("nodeSelector pool = %q, want %q", got, want)
	}
	if _, present := pod.Spec.NodeSelector["tuist.dev/fleet"]; present {
		t.Errorf("nodeSelector should NOT carry tuist.dev/fleet on Linux pools (that's the macOS-only key)")
	}
	if _, present := pod.Spec.NodeSelector["tuist.dev/runtime"]; present {
		t.Errorf("nodeSelector should NOT carry tuist.dev/runtime on Linux pools")
	}
	// Linux bare-metal hosts are tainted `tuist.dev/runner-tier=bare-metal:NoSchedule`
	// so only runner Pods land on them; everything else (server, system
	// DaemonSets, etc.) stays on the elastic Hetzner Cloud `md-0` pool.
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
	pod := Build(basePool("solaris"), "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch")
	if got, want := pod.Spec.NodeSelector["kubernetes.io/os"], "darwin"; got != want {
		t.Errorf("nodeSelector os = %q, want darwin fallback", got)
	}
}

func TestBuild_RuntimeClassNameStampedWhenSet(t *testing.T) {
	pool := basePool("linux")
	pool.Spec.RuntimeClass = "kata-fc"
	pod := Build(pool, "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch")
	if pod.Spec.RuntimeClassName == nil {
		t.Fatalf("RuntimeClassName = nil, want \"kata-fc\"")
	}
	if got := *pod.Spec.RuntimeClassName; got != "kata-fc" {
		t.Errorf("RuntimeClassName = %q, want \"kata-fc\"", got)
	}
}

func TestBuild_RuntimeClassNameNilWhenUnset(t *testing.T) {
	// Empty `runtimeClass` must produce a nil *string, not an empty
	// pointer. kube-apiserver accepts both as "default runtime" but
	// nil is the canonical absence; some downstream tooling treats
	// the two cases differently.
	pool := basePool("linux") // no RuntimeClass set
	pod := Build(pool, "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch")
	if pod.Spec.RuntimeClassName != nil {
		t.Errorf("RuntimeClassName = %v, want nil for default runtime", *pod.Spec.RuntimeClassName)
	}
}

func TestBuild_DockerEnabledStampsPrivilegedAndEnv(t *testing.T) {
	// docker-in-runner pools must produce a container with
	// `privileged: true` + `TUIST_RUNNER_DOCKER_ENABLED=1` so the
	// image's dispatch-poll.sh launches dockerd. The privileged
	// flag is only safe when paired with `runtimeClass: kata-qemu`
	// on this fleet; the controller doesn't enforce that pairing
	// because the chart is the single source of truth — this test
	// just covers the wire shape.
	pool := basePool("linux")
	pool.Spec.RuntimeClass = "kata-qemu"
	pool.Spec.Docker = &tuistv1.RunnerPoolDocker{Enabled: true}
	pod := Build(pool, "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch")

	c := pod.Spec.Containers[0]
	if c.SecurityContext == nil || c.SecurityContext.Privileged == nil || !*c.SecurityContext.Privileged {
		t.Fatalf("SecurityContext = %+v, want privileged=true", c.SecurityContext)
	}

	var sawFlag, sawHost bool
	for _, env := range c.Env {
		if env.Name == "TUIST_RUNNER_DOCKER_ENABLED" && env.Value == "1" {
			sawFlag = true
		}
		if env.Name == "DOCKER_HOST" && env.Value == "unix:///var/run/docker.sock" {
			sawHost = true
		}
	}
	if !sawFlag {
		t.Errorf("env missing TUIST_RUNNER_DOCKER_ENABLED=1; got %+v", c.Env)
	}
	if !sawHost {
		t.Errorf("env missing DOCKER_HOST=unix:///var/run/docker.sock; got %+v", c.Env)
	}
}

func TestBuild_DockerDisabledLeavesContainerUnprivileged(t *testing.T) {
	// Default (no `docker` block) must not stamp privileged or the
	// docker env vars. Same image, env-gated behavior — the daemon
	// stays dormant in the container.
	pool := basePool("linux")
	pool.Spec.RuntimeClass = "kata-qemu"
	pod := Build(pool, "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch")

	c := pod.Spec.Containers[0]
	if c.SecurityContext != nil && c.SecurityContext.Privileged != nil && *c.SecurityContext.Privileged {
		t.Errorf("SecurityContext = %+v, want no privileged flag", c.SecurityContext)
	}
	for _, env := range c.Env {
		if env.Name == "TUIST_RUNNER_DOCKER_ENABLED" || env.Name == "DOCKER_HOST" {
			t.Errorf("env should not carry %s without docker.enabled; got value %q", env.Name, env.Value)
		}
	}
}

func TestBuild_DockerExplicitlyDisabled(t *testing.T) {
	// A non-nil Docker block with Enabled=false must behave like
	// the unset case — no privileged, no env. Protects against the
	// chart rendering `docker: {enabled: false}` and the controller
	// mistakenly treating "block present" as opt-in.
	pool := basePool("linux")
	pool.Spec.RuntimeClass = "kata-qemu"
	pool.Spec.Docker = &tuistv1.RunnerPoolDocker{Enabled: false}
	pod := Build(pool, "pod-name", "sa-name", "http://dispatch", "http://internal-dispatch")

	c := pod.Spec.Containers[0]
	if c.SecurityContext != nil && c.SecurityContext.Privileged != nil && *c.SecurityContext.Privileged {
		t.Errorf("SecurityContext = %+v, want no privileged flag when docker.enabled=false", c.SecurityContext)
	}
	for _, env := range c.Env {
		if env.Name == "TUIST_RUNNER_DOCKER_ENABLED" || env.Name == "DOCKER_HOST" {
			t.Errorf("env should not carry %s when docker.enabled=false; got value %q", env.Name, env.Value)
		}
	}
}
