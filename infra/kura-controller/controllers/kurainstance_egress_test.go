package controllers

import (
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// WS5: a region with a guaranteed egress floor reserves it as the
// tuist.dev/egress-mbps extended resource, request == limit (extended resources
// are integer and non-overcommittable), so the scheduler bin-packs cache pods
// against the node's advertised budget.
func TestDefaultResourcesEgressFloor(t *testing.T) {
	withFloor := defaultResources(&kurav1alpha1.KuraInstance{
		Spec: kurav1alpha1.KuraInstanceSpec{EgressGuaranteedMbps: 750},
	})
	req, ok := withFloor.Requests[egressMbpsResource]
	if !ok {
		t.Fatalf("expected a request for %s", egressMbpsResource)
	}
	if req.Value() != 750 {
		t.Fatalf("egress request = %d, want 750", req.Value())
	}
	lim, ok := withFloor.Limits[egressMbpsResource]
	if !ok || lim.Value() != 750 {
		t.Fatalf("egress limit = %v (present=%v), want 750 (request must equal limit)", lim.Value(), ok)
	}
}

// Cloud regions (no shared NIC) leave EgressGuaranteedMbps zero and must not
// request the extended resource, or every cache pod would be unschedulable on a
// node that advertises no egress capacity.
func TestDefaultResourcesNoEgressFloorWhenZero(t *testing.T) {
	r := defaultResources(&kurav1alpha1.KuraInstance{})
	if _, ok := r.Requests[egressMbpsResource]; ok {
		t.Fatalf("did not expect an egress request when EgressGuaranteedMbps is 0")
	}
	if _, ok := r.Limits[egressMbpsResource]; ok {
		t.Fatalf("did not expect an egress limit when EgressGuaranteedMbps is 0")
	}
}
