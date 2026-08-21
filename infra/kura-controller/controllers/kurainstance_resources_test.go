package controllers

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// Kura derives its admission pools from the cgroup limit at startup, so the
// memory limit is what governs how large a client burst a pod can absorb, while
// the request is only what the scheduler reserves on a shared bare-metal box.
// They are intentionally different, and a well-meaning "make QoS Guaranteed"
// change that equalises them would either shrink the burst headroom or exhaust
// a box's schedulable memory.
func TestDefaultResourcesMemoryLimitExceedsRequest(t *testing.T) {
	r := defaultResources(&kurav1alpha1.KuraInstance{}, false)

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
	if got := limit.String(); got != "4Gi" {
		t.Fatalf("memory limit = %q, want 4Gi", got)
	}

	if limit.Cmp(request) <= 0 {
		t.Fatalf("memory limit %q must exceed the request %q", limit.String(), request.String())
	}
}

// A region that sizes the instance drives both sides of the profile.
func TestDefaultResourcesHonoursMemoryProfile(t *testing.T) {
	r := defaultResources(&kurav1alpha1.KuraInstance{
		Spec: kurav1alpha1.KuraInstanceSpec{MemoryFloorMib: 512, MemoryCeilingMib: 1536},
	}, false)

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
	}, true)

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
	}, false)

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
	}, true)

	if got := r.Limits.Memory().String(); got != "2Gi" {
		t.Fatalf("memory limit = %q, want it clamped up to the 2Gi floor", got)
	}
	if lim := r.Limits[memoryCeilingResource]; lim.Value() != 2048 {
		t.Fatalf("ceiling resource = %d, want the clamped 2048", lim.Value())
	}
}

// The server flips memory_ceiling_bin_packed on its own deploy cadence, while
// the CAPI provider that advertises tuist.dev/memory-ceiling-mib rolls to the
// management cluster on another. A pod requesting an extended resource no node
// advertises stays Pending forever, so the controller resolves the spec flag
// against live node state instead of trusting it, and recovers on its own in
// both directions.
func TestCeilingBudgetAdvertisedGatesOnLiveNodeCapacity(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	selector := map[string]string{"node.cluster.x-k8s.io/pool": "kura-us-east"}
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-acme", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			NodeSelector: selector, MemoryCeilingBinPacked: true,
		},
	}

	node := func(name string, labels map[string]string, advertise bool) *corev1.Node {
		n := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: name, Labels: labels}}
		n.Status.Allocatable = corev1.ResourceList{corev1.ResourceMemory: resource.MustParse("32Gi")}
		if advertise {
			n.Status.Allocatable[memoryCeilingResource] = *resource.NewQuantity(56116, resource.DecimalSI)
		}
		return n
	}
	advertised := func(objs ...client.Object) bool {
		r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()}
		got, err := r.ceilingBudgetAdvertised(context.Background(), instance)
		if err != nil {
			t.Fatal(err)
		}
		return got
	}

	if advertised(node("bare", selector, false)) {
		t.Fatal("a node without the budget must not gate the request open; the pod would stay Pending")
	}
	if !advertised(node("ready", selector, true)) {
		t.Fatal("a node advertising the budget must let the request through")
	}
	// Another pool's node advertising it says nothing about where this instance lands.
	if advertised(node("bare", selector, false), node("elsewhere", map[string]string{"node.cluster.x-k8s.io/pool": "kura-dedibox"}, true)) {
		t.Fatal("the budget must be looked for behind the instance's own nodeSelector")
	}

	// The spec flag off short-circuits, so an ungoverned region never pays for a List.
	off := &kurav1alpha1.KuraInstance{Spec: kurav1alpha1.KuraInstanceSpec{NodeSelector: selector}}
	r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(node("ready", selector, true)).Build()}
	if got, err := r.ceilingBudgetAdvertised(context.Background(), off); err != nil || got {
		t.Fatalf("spec flag off must stay off regardless of node state, got %v (err %v)", got, err)
	}
}

// The data volume is a local-path PV -- a directory on the node's
// ephemeral-storage filesystem -- so the claim's size bounds nothing and the
// scheduler would otherwise place cache pods onto a node until it filled and
// kubelet evicted the whole region. The ephemeral-storage request is the only
// thing that reserves that disk, so a change that drops it silently restores
// the overcommit.
func TestDefaultResourcesReservesDeclaredStorage(t *testing.T) {
	r := defaultResources(&kurav1alpha1.KuraInstance{
		Spec: kurav1alpha1.KuraInstanceSpec{StorageSize: "50Gi"},
	}, false)

	request, ok := r.Requests[corev1.ResourceEphemeralStorage]
	if !ok {
		t.Fatal("expected an ephemeral-storage request")
	}
	if got := request.String(); got != "50Gi" {
		t.Fatalf("ephemeral-storage request = %q, want 50Gi", got)
	}

	// A limit is enforced against the pod's writable layer, logs and emptyDir,
	// none of which is where the cache lives, so it would evict on the wrong
	// signal while leaving the real consumption unbounded.
	if _, ok := r.Limits[corev1.ResourceEphemeralStorage]; ok {
		t.Fatal("expected no ephemeral-storage limit")
	}
}

// An instance that declares no size still reserves the controller's fallback
// claim, so an unset field cannot quietly reserve nothing.
func TestDefaultResourcesReservesFallbackStorage(t *testing.T) {
	r := defaultResources(&kurav1alpha1.KuraInstance{}, false)

	request, ok := r.Requests[corev1.ResourceEphemeralStorage]
	if !ok {
		t.Fatal("expected an ephemeral-storage request")
	}
	if got := request.String(); got != "200Gi" {
		t.Fatalf("ephemeral-storage request = %q, want 200Gi", got)
	}
}

// Kura opens its store before it binds the listener that answers /up, so a
// slow recovery (RocksDB WAL replay after an unclean shutdown) is spent
// against the startup budget rather than the liveness one. The kubelet's
// default failureThreshold of 3 would cap that budget at ~30 seconds and
// restart the container mid-recovery, leaving a dirtier write-ahead log for
// the next attempt. The budget must stay at the 300 seconds the in-tree Helm
// chart grants chart-managed pods for the same probe.
func TestStartupProbeGrantsChartRecoveryBudget(t *testing.T) {
	container := podTemplate(&kurav1alpha1.KuraInstance{}, "", "production", "", false, "").Spec.Containers[0]

	probe := container.StartupProbe
	if probe == nil {
		t.Fatal("expected a startup probe")
	}
	if probe.FailureThreshold != 30 {
		t.Fatalf("startup failureThreshold = %d, want 30", probe.FailureThreshold)
	}
	if budget := probe.FailureThreshold * probe.PeriodSeconds; budget < 300 {
		t.Fatalf("startup budget = %ds, want at least 300s", budget)
	}
}

// The startup threshold is deliberately set at the call site: httpProbe backs
// the readiness probe and livenessProbe too, and widening it there would turn
// a wedged pod's liveness restart into a ten-times-slower recovery.
func TestSteadyStateProbesKeepDefaultFailureThreshold(t *testing.T) {
	container := podTemplate(&kurav1alpha1.KuraInstance{}, "", "production", "", false, "").Spec.Containers[0]

	if got := container.LivenessProbe.FailureThreshold; got != 0 {
		t.Fatalf("liveness failureThreshold = %d, want 0 so it defaults to 3", got)
	}
	if got := container.ReadinessProbe.FailureThreshold; got != 0 {
		t.Fatalf("readiness failureThreshold = %d, want 0 so it defaults to 3", got)
	}
}
