package controllers

import (
	"testing"

	corev1 "k8s.io/api/core/v1"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// Kura derives its admission pools from the cgroup limit at startup, so the
// memory limit is what governs how large a client burst a pod can absorb, while
// the request is only what the scheduler reserves on a shared bare-metal box.
// They are intentionally different, and a well-meaning "make QoS Guaranteed"
// change that equalises them would either shrink the burst headroom or exhaust
// a box's schedulable memory.
func TestDefaultResourcesMemoryLimitExceedsRequest(t *testing.T) {
	r := defaultResources(&kurav1alpha1.KuraInstance{})

	request, ok := r.Requests[corev1.ResourceMemory]
	if !ok {
		t.Fatal("expected a memory request")
	}
	if got := request.String(); got != "2Gi" {
		t.Fatalf("memory request = %q, want 2Gi", got)
	}

	limit, ok := r.Limits[corev1.ResourceMemory]
	if !ok {
		t.Fatal("expected a memory limit")
	}
	if got := limit.String(); got != "3Gi" {
		t.Fatalf("memory limit = %q, want 3Gi", got)
	}

	if limit.Cmp(request) <= 0 {
		t.Fatalf("memory limit %q must exceed the request %q", limit.String(), request.String())
	}
}
