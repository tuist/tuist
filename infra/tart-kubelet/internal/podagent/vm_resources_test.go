package podagent

import (
	"testing"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
)

func TestVMResourcesFromPod_PrefersLimitsOverRequests(t *testing.T) {
	c := corev1.Container{
		Resources: corev1.ResourceRequirements{
			Requests: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse("4000m"),
				corev1.ResourceMemory: resource.MustParse("8Gi"),
			},
			Limits: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse("8000m"),
				corev1.ResourceMemory: resource.MustParse("14Gi"),
			},
		},
	}
	cpu, mem := vmResourcesFromPod(c)
	if cpu != 8 {
		t.Fatalf("expected 8 cpu (from limits), got %d", cpu)
	}
	if mem != 14*1024 {
		t.Fatalf("expected %d MB (from limits 14Gi), got %d", 14*1024, mem)
	}
}

func TestVMResourcesFromPod_FallsBackToRequests(t *testing.T) {
	c := corev1.Container{
		Resources: corev1.ResourceRequirements{
			Requests: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse("8000m"),
				corev1.ResourceMemory: resource.MustParse("14Gi"),
			},
		},
	}
	cpu, mem := vmResourcesFromPod(c)
	if cpu != 8 {
		t.Fatalf("expected 8 cpu, got %d", cpu)
	}
	if mem != 14*1024 {
		t.Fatalf("expected %d MB, got %d", 14*1024, mem)
	}
}

func TestVMResourcesFromPod_RoundsCpuMillicoresDown(t *testing.T) {
	c := corev1.Container{
		Resources: corev1.ResourceRequirements{
			Requests: corev1.ResourceList{
				corev1.ResourceCPU: resource.MustParse("3500m"),
			},
		},
	}
	cpu, _ := vmResourcesFromPod(c)
	if cpu != 3 {
		t.Fatalf("expected 3 (3500m rounded down), got %d", cpu)
	}
}

func TestVMResourcesFromPod_NoSpecMeansZeroes(t *testing.T) {
	c := corev1.Container{}
	cpu, mem := vmResourcesFromPod(c)
	if cpu != 0 || mem != 0 {
		t.Fatalf("expected (0, 0) for unspecified resources; got (%d, %d)", cpu, mem)
	}
}
