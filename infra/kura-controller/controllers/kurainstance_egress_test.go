package controllers

import (
	"context"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

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

// The classid is deterministic per account (hash candidate + linear probe),
// stays inside the tenant minor range, and probing skips already-claimed ids
// so no two accounts share a class.
func TestAllocateEgressClassID(t *testing.T) {
	first, err := allocateEgressClassID("acme", map[uint16]bool{})
	if err != nil {
		t.Fatal(err)
	}
	if first < egressClassIDMinorMin || first > egressClassIDMinorMax {
		t.Fatalf("allocated %#x outside the tenant range", first)
	}
	if again, _ := allocateEgressClassID("acme", map[uint16]bool{}); again != first {
		t.Fatalf("allocation is not deterministic: %#x vs %#x", again, first)
	}
	probed, err := allocateEgressClassID("acme", map[uint16]bool{first: true})
	if err != nil {
		t.Fatal(err)
	}
	if probed == first {
		t.Fatalf("probe did not skip the claimed id %#x", first)
	}
}

// All instances of an account share one id (it keys the tenant's class on
// every node), so a second region must adopt the first region's claim, while
// a different account must get a different id.
func TestReconcileEgressClassIDSharedPerAccount(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	shaped := func(name, account string) *kurav1alpha1.KuraInstance {
		return &kurav1alpha1.KuraInstance{
			ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "kura"},
			Spec: kurav1alpha1.KuraInstanceSpec{
				AccountHandle:  account,
				PodAnnotations: map[string]string{"kubernetes.io/egress-bandwidth": "1500M"},
			},
		}
	}
	regionOne := shaped("kura-acme-eu", "acme")
	regionTwo := shaped("kura-acme-us", "acme")
	other := shaped("kura-other-eu", "other")
	fakeClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(regionOne, regionTwo, other).Build()
	r := &KuraInstanceReconciler{
		Client:    fakeClient,
		APIReader: fakeClient,
		Scheme:    scheme,
	}

	for _, instance := range []*kurav1alpha1.KuraInstance{regionOne, regionTwo, other} {
		if err := r.reconcileEgressClassID(ctx, instance); err != nil {
			t.Fatal(err)
		}
	}

	one, ok := parseEgressClassID(regionOne.Annotations[egressClassIDAnnotation])
	if !ok {
		t.Fatalf("region one got no classid: %v", regionOne.Annotations)
	}
	two, _ := parseEgressClassID(regionTwo.Annotations[egressClassIDAnnotation])
	if two != one {
		t.Fatalf("same account got different ids: %#x vs %#x", one, two)
	}
	third, ok := parseEgressClassID(other.Annotations[egressClassIDAnnotation])
	if !ok || third == one {
		t.Fatalf("other account id = %#x (ok=%v), must differ from %#x", third, ok, one)
	}

	// Idempotent: a second pass must not rewrite anything.
	before := regionOne.Annotations[egressClassIDAnnotation]
	if err := r.reconcileEgressClassID(ctx, regionOne); err != nil {
		t.Fatal(err)
	}
	if regionOne.Annotations[egressClassIDAnnotation] != before {
		t.Fatalf("id changed on re-reconcile: %v", regionOne.Annotations)
	}
}

// Unshaped instances (no ceiling annotation, no floor) never allocate an id:
// the class space is for tenants on shared-NIC pools only.
func TestReconcileEgressClassIDSkipsUnshaped(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-cloud", Namespace: "kura"},
		Spec:       kurav1alpha1.KuraInstanceSpec{AccountHandle: "acme"},
	}
	fakeClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).Build()
	r := &KuraInstanceReconciler{
		Client:    fakeClient,
		APIReader: fakeClient,
		Scheme:    scheme,
	}
	if err := r.reconcileEgressClassID(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if _, ok := instance.Annotations[egressClassIDAnnotation]; ok {
		t.Fatalf("unshaped instance got a classid: %v", instance.Annotations)
	}
}

// The pod annotation is the agent's whole input: classid + floor + burst as
// JSON. It renders only once the id is allocated, and a burst that does not
// parse renders as 0 — no per-tenant ceiling, the class caps at the node
// budget only.
func TestEgressClassPodAnnotation(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{
			Annotations: map[string]string{egressClassIDAnnotation: "1:2a7"},
		},
		Spec: kurav1alpha1.KuraInstanceSpec{
			EgressGuaranteedMbps: 750,
			PodAnnotations:       map[string]string{"kubernetes.io/egress-bandwidth": "1500M"},
		},
	}
	value, ok := egressClassPodAnnotation(instance)
	if !ok {
		t.Fatal("expected a rendered annotation")
	}
	want := `{"classid":"1:2a7","floor_mbps":750,"burst_mbps":1500}`
	if value != want {
		t.Fatalf("annotation = %s, want %s", value, want)
	}

	annotations := podAnnotations(instance, "")
	if annotations[egressClassAnnotation] != want {
		t.Fatalf("podAnnotations did not carry the egress class: %v", annotations)
	}

	unallocated := instance.DeepCopy()
	delete(unallocated.Annotations, egressClassIDAnnotation)
	if _, ok := egressClassPodAnnotation(unallocated); ok {
		t.Fatal("must not render before the id is allocated")
	}

	malformed := instance.DeepCopy()
	malformed.Spec.PodAnnotations["kubernetes.io/egress-bandwidth"] = "1.5G"
	got, ok := egressClassPodAnnotation(malformed)
	if !ok || got != `{"classid":"1:2a7","floor_mbps":750,"burst_mbps":0}` {
		t.Fatalf("malformed burst rendered %q (ok=%v)", got, ok)
	}

	unshaped := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{
			Annotations: map[string]string{egressClassIDAnnotation: "1:2a7"},
		},
	}
	if _, ok := egressClassPodAnnotation(unshaped); ok {
		t.Fatal("must not render for unshaped instances")
	}
}
