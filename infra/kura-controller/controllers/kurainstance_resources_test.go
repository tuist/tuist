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

// A region that sizes the instance drives both sides of the profile.
func TestDefaultResourcesHonoursMemoryProfile(t *testing.T) {
	r := defaultResources(&kurav1alpha1.KuraInstance{
		Spec: kurav1alpha1.KuraInstanceSpec{MemoryFloorMib: 512, MemoryCeilingMib: 1536},
	})

	if got := r.Requests.Memory().String(); got != "512Mi" {
		t.Fatalf("memory request = %q, want 512Mi", got)
	}
	if got := r.Limits.Memory().String(); got != "1536Mi" {
		t.Fatalf("memory limit = %q, want 1536Mi", got)
	}
}

// Ceilings oversubscribe the box, so the native requests.memory bin-pack cannot
// see them. The extended resource is what bounds the oversubscription, and it
// has to mirror the limit exactly (request == limit) to be non-overcommittable.
func TestDefaultResourcesBinPacksCeilingWhenSet(t *testing.T) {
	r := defaultResources(&kurav1alpha1.KuraInstance{
		Spec: kurav1alpha1.KuraInstanceSpec{
			MemoryFloorMib: 512, MemoryCeilingMib: 1536, MemoryCeilingBinPacked: true,
		},
	})

	req, ok := r.Requests[memoryCeilingResource]
	if !ok {
		t.Fatalf("expected a request for %s", memoryCeilingResource)
	}
	if req.Value() != 1536 {
		t.Fatalf("ceiling request = %d, want 1536", req.Value())
	}
	lim, ok := r.Limits[memoryCeilingResource]
	if !ok || lim.Value() != 1536 {
		t.Fatalf("ceiling limit = %v (present=%v), want 1536 (request must equal limit)", lim.Value(), ok)
	}
}

// A node pool the CAPI provider does not patch advertises no ceiling budget, so
// requesting the extended resource there would leave every cache pod Pending
// forever. Such a region still wants a right-sized ceiling, so the value and the
// bin-packing have to be independent.
func TestDefaultResourcesSizesCeilingWithoutBinPacking(t *testing.T) {
	r := defaultResources(&kurav1alpha1.KuraInstance{
		Spec: kurav1alpha1.KuraInstanceSpec{MemoryFloorMib: 512, MemoryCeilingMib: 1536},
	})

	if got := r.Limits.Memory().String(); got != "1536Mi" {
		t.Fatalf("memory limit = %q, want the region's 1536Mi ceiling", got)
	}
	if _, ok := r.Requests[memoryCeilingResource]; ok {
		t.Fatalf("did not expect a %s request when the region does not bin-pack", memoryCeilingResource)
	}
	if _, ok := r.Limits[memoryCeilingResource]; ok {
		t.Fatalf("did not expect a %s limit when the region does not bin-pack", memoryCeilingResource)
	}
}

// A limit below its request is rejected by the API, which would make every pod
// of the instance unadmittable rather than merely mis-sized. The floor wins.
func TestDefaultResourcesClampsCeilingBelowFloor(t *testing.T) {
	r := defaultResources(&kurav1alpha1.KuraInstance{
		Spec: kurav1alpha1.KuraInstanceSpec{
			MemoryFloorMib: 2048, MemoryCeilingMib: 512, MemoryCeilingBinPacked: true,
		},
	})

	if got := r.Limits.Memory().String(); got != "2Gi" {
		t.Fatalf("memory limit = %q, want it clamped up to the 2Gi floor", got)
	}
	if lim := r.Limits[memoryCeilingResource]; lim.Value() != 2048 {
		t.Fatalf("ceiling resource = %d, want the clamped 2048", lim.Value())
	}
}
