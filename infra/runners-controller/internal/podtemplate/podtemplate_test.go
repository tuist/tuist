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
	pod := Build(basePool(""), "pod-name", "sa-name", "http://dispatch")

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
	pod := Build(basePool("linux"), "pod-name", "sa-name", "http://dispatch")

	if got, want := pod.Spec.NodeSelector["kubernetes.io/os"], "linux"; got != want {
		t.Errorf("nodeSelector os = %q, want %q", got, want)
	}
	if got, want := pod.Spec.NodeSelector["kubernetes.io/arch"], "amd64"; got != want {
		t.Errorf("nodeSelector arch = %q, want %q", got, want)
	}
	// CAPI label-sync propagates the `node.cluster.x-k8s.io/pool`
	// label from the MachineDeployment to the Node; the Pod's
	// nodeSelector must use the same key to pin to the runners
	// MD. `tuist.dev/fleet=` is the macOS-only convention because
	// tart-kubelet sets it outside the standard label-sync.
	if got, want := pod.Spec.NodeSelector["node.cluster.x-k8s.io/pool"], "fleet-x"; got != want {
		t.Errorf("nodeSelector pool = %q, want %q", got, want)
	}
	if _, present := pod.Spec.NodeSelector["tuist.dev/fleet"]; present {
		t.Errorf("nodeSelector should NOT carry tuist.dev/fleet on Linux pools (label-sync prefix rejected)")
	}
	if _, present := pod.Spec.NodeSelector["tuist.dev/runtime"]; present {
		t.Errorf("nodeSelector should NOT carry tuist.dev/runtime on Linux pools")
	}
	if len(pod.Spec.Tolerations) != 0 {
		t.Errorf("Tolerations = %+v, want none on Linux pools", pod.Spec.Tolerations)
	}
}

func TestBuild_UnknownOSFallsBackToMacOS(t *testing.T) {
	// A misconfigured OS field should still produce a schedulable
	// Pod against the macOS fleet rather than fail open.
	pod := Build(basePool("solaris"), "pod-name", "sa-name", "http://dispatch")
	if got, want := pod.Spec.NodeSelector["kubernetes.io/os"], "darwin"; got != want {
		t.Errorf("nodeSelector os = %q, want darwin fallback", got)
	}
}
