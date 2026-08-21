package controllers

import (
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// A region with a guaranteed egress floor reserves it as the
// tuist.dev/egress-mbps extended resource, request == limit (extended resources
// are integer and non-overcommittable), so the scheduler bin-packs cache pods
// against the node's advertised budget.
func TestDefaultResourcesEgressFloor(t *testing.T) {
	withFloor := defaultResources(&kurav1alpha1.KuraInstance{
		Spec: kurav1alpha1.KuraInstanceSpec{EgressGuaranteedMbps: 750},
	}, false)
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
	r := defaultResources(&kurav1alpha1.KuraInstance{}, false)
	if _, ok := r.Requests[egressMbpsResource]; ok {
		t.Fatalf("did not expect an egress request when EgressGuaranteedMbps is 0")
	}
	if _, ok := r.Limits[egressMbpsResource]; ok {
		t.Fatalf("did not expect an egress limit when EgressGuaranteedMbps is 0")
	}
}

// The per-pod ceiling annotation alone is bypassed on the node-local read path
// (tuist/tuist#12363), so whenever an instance carries it the pod template
// must also carry the egress-qdisc init container that shapes inside the pod
// netns. The env value is the annotation's integer Mbit/s.
func TestPodTemplateEgressQdiscInitContainer(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{
		Spec: kurav1alpha1.KuraInstanceSpec{
			PodAnnotations: map[string]string{"kubernetes.io/egress-bandwidth": "1500M"},
		},
	}
	template := podTemplate(instance, "", "production", "", false, "ghcr.io/tuist/egress-qdisc-init@sha256:test")
	if len(template.Spec.InitContainers) != 1 {
		t.Fatalf("expected exactly one init container, got %+v", template.Spec.InitContainers)
	}
	init := template.Spec.InitContainers[0]
	if init.Name != egressQdiscInitContainerName {
		t.Fatalf("init container name = %q, want %q", init.Name, egressQdiscInitContainerName)
	}
	if init.Image != "ghcr.io/tuist/egress-qdisc-init@sha256:test" {
		t.Fatalf("init container image = %q", init.Image)
	}
	if len(init.Env) != 1 || init.Env[0].Name != "EGRESS_BURST_MBPS" || init.Env[0].Value != "1500" {
		t.Fatalf("expected EGRESS_BURST_MBPS=1500, got %+v", init.Env)
	}
	sc := init.SecurityContext
	if sc == nil || sc.Capabilities == nil {
		t.Fatalf("expected a security context with capabilities, got %+v", sc)
	}
	if len(sc.Capabilities.Add) != 1 || sc.Capabilities.Add[0] != "NET_ADMIN" {
		t.Fatalf("expected only NET_ADMIN added, got %+v", sc.Capabilities.Add)
	}
	if len(sc.Capabilities.Drop) != 1 || sc.Capabilities.Drop[0] != "ALL" {
		t.Fatalf("expected ALL capabilities dropped, got %+v", sc.Capabilities.Drop)
	}
	if sc.AllowPrivilegeEscalation == nil || *sc.AllowPrivilegeEscalation {
		t.Fatalf("expected allowPrivilegeEscalation=false")
	}
	if sc.ReadOnlyRootFilesystem == nil || !*sc.ReadOnlyRootFilesystem {
		t.Fatalf("expected readOnlyRootFilesystem=true")
	}
}

// Instances without the annotation (cloud regions, runner-cache pools without
// a burst value) must not get the init container: NET_ADMIN and the qdisc are
// shared-NIC bare-metal concerns only. Mirrors the annotation condition
// exactly.
func TestPodTemplateNoEgressQdiscInitContainerWithoutAnnotation(t *testing.T) {
	template := podTemplate(&kurav1alpha1.KuraInstance{}, "", "production", "", false, "ghcr.io/tuist/egress-qdisc-init@sha256:test")
	if len(template.Spec.InitContainers) != 0 {
		t.Fatalf("expected no init containers without the annotation, got %+v", template.Spec.InitContainers)
	}
}

// A malformed annotation value must flow through verbatim so the init
// container's entrypoint rejects it and the pod fails closed, instead of the
// controller guessing a rate or silently skipping the shaper.
func TestEgressBurstMbpsMalformedValuePassesThroughVerbatim(t *testing.T) {
	for annotation, want := range map[string]string{
		"750M":   "750",
		"1500M":  "1500",
		"1.5G":   "1.5G",
		"750":    "750",
		"M":      "M",
		"750Mib": "750Mib",
	} {
		instance := &kurav1alpha1.KuraInstance{
			Spec: kurav1alpha1.KuraInstanceSpec{
				PodAnnotations: map[string]string{"kubernetes.io/egress-bandwidth": annotation},
			},
		}
		got, ok := egressBurstMbps(instance)
		if !ok {
			t.Fatalf("annotation %q: expected presence", annotation)
		}
		if got != want {
			t.Fatalf("annotation %q: got %q, want %q", annotation, got, want)
		}
	}
}
