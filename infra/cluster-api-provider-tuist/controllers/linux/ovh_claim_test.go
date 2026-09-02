package linux

import (
	"context"
	"testing"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

func ovhScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	return scheme
}

func ovhMachine(name string, uid string, created time.Time, serviceName string) *infrav1.OVHDedicatedMachine {
	return &infrav1.OVHDedicatedMachine{
		ObjectMeta: metav1.ObjectMeta{
			Name:              name,
			Namespace:         "tuist",
			UID:               types.UID(uid),
			CreationTimestamp: metav1.NewTime(created),
		},
		Status: infrav1.OVHDedicatedMachineStatus{ServiceName: serviceName},
	}
}

// A sibling's claim must be visible the moment it is persisted. The manager's
// client reads from the informer cache, which trailed the claim write by the ~2s
// between two adoptions and reported an already-claimed box as free: two
// Machines took ovh://gra1/ns3048220, each joined it under its own node name,
// and the fleet never reached Ready. Claim reads go through the uncached reader,
// so a stale cache cannot resurface a claimed box.
func TestOVHClaimedServiceNamesReadsThroughUncachedReader(t *testing.T) {
	scheme := ovhScheme(t)
	created := time.Date(2026, 9, 2, 16, 9, 37, 0, time.UTC)

	self := ovhMachine("fleet-6sdk4", "uid-6sdk4", created, "")
	// The cache still holds the sibling as it was before it claimed the box.
	staleSibling := ovhMachine("fleet-g7jgl", "uid-g7jgl", created, "")
	// The API server already holds the persisted claim.
	freshSibling := ovhMachine("fleet-g7jgl", "uid-g7jgl", created, "ns3048220.ip-51-255-75.eu")

	r := &OVHDedicatedMachineReconciler{
		Client:    fake.NewClientBuilder().WithScheme(scheme).WithObjects(self, staleSibling).Build(),
		APIReader: fake.NewClientBuilder().WithScheme(scheme).WithObjects(self, freshSibling).Build(),
	}

	state, err := r.claimedServiceNames(context.Background(), self)
	if err != nil {
		t.Fatal(err)
	}
	if !state.claimed["ns3048220.ip-51-255-75.eu"] {
		t.Fatalf("sibling claim on ns3048220 not observed; claimed=%v", state.claimed)
	}
}

// A Machine that already persisted a claim must not re-enter adoption because
// its own status read came from a stale cache. The 9sfwk Machine logged "adopted
// OVH server" twice 2s apart for this reason; it took the same free box both
// times only because nothing else was competing for it.
func TestOVHClaimedServiceNamesReportsOwnPersistedClaim(t *testing.T) {
	scheme := ovhScheme(t)
	created := time.Date(2026, 9, 2, 16, 58, 51, 0, time.UTC)

	stale := ovhMachine("fleet-9sfwk", "uid-9sfwk", created, "")
	fresh := ovhMachine("fleet-9sfwk", "uid-9sfwk", created, "ns3049612.ip-51-255-75.eu")

	r := &OVHDedicatedMachineReconciler{
		Client:    fake.NewClientBuilder().WithScheme(scheme).WithObjects(stale).Build(),
		APIReader: fake.NewClientBuilder().WithScheme(scheme).WithObjects(fresh).Build(),
	}

	state, err := r.claimedServiceNames(context.Background(), stale)
	if err != nil {
		t.Fatal(err)
	}
	if state.self != "ns3049612.ip-51-255-75.eu" {
		t.Fatalf("own persisted claim not reported, got %q", state.self)
	}
}

// The claim snapshot must name the Machine holding each box, so the
// pre-bootstrap check can identify the other claimant without a second read,
// and must not report the asking Machine as its own duplicate.
func TestOVHClaimSnapshotNamesTheOtherHolder(t *testing.T) {
	scheme := ovhScheme(t)
	created := time.Date(2026, 9, 2, 16, 9, 37, 0, time.UTC)
	const box = "ns3048220.ip-51-255-75.eu"

	self := ovhMachine("fleet-6sdk4", "uid-6sdk4", created, box)
	other := ovhMachine("fleet-g7jgl", "uid-g7jgl", created, box)
	unrelated := ovhMachine("fleet-2f6gf", "uid-2f6gf", created, "ns3048201.ip-51-255-75.eu")

	r := &OVHDedicatedMachineReconciler{
		APIReader: fake.NewClientBuilder().WithScheme(scheme).WithObjects(self, other, unrelated).Build(),
	}

	state, err := r.claimedServiceNames(context.Background(), self)
	if err != nil {
		t.Fatal(err)
	}
	if holder := state.holders[box]; holder == nil || holder.Name != "fleet-g7jgl" {
		t.Fatalf("expected fleet-g7jgl as the other holder of %s, got %v", box, holder)
	}

	state, err = r.claimedServiceNames(context.Background(), unrelated)
	if err != nil {
		t.Fatal(err)
	}
	if holder := state.holders[unrelated.Status.ServiceName]; holder != nil {
		t.Fatalf("a uniquely-held box must have no other holder, got %s", holder.Name)
	}
}

// Both sides evaluate the tie-break, so exactly one must yield: a rule where
// both yield returns two Machines to adoption and leaves the box unclaimed,
// and a rule where neither yields double-joins the host.
func TestYieldsDuplicateClaimPicksExactlyOneLoser(t *testing.T) {
	older := ovhMachine("older", "uid-aaa", time.Date(2026, 9, 2, 16, 9, 37, 0, time.UTC), "box")
	newer := ovhMachine("newer", "uid-bbb", time.Date(2026, 9, 2, 16, 9, 41, 0, time.UTC), "box")

	if yieldsDuplicateClaim(older, newer) {
		t.Fatal("the older Machine must keep the box")
	}
	if !yieldsDuplicateClaim(newer, older) {
		t.Fatal("the newer Machine must yield")
	}

	// Same creationTimestamp is the common case: a MachineSet scale-up stamps
	// every Machine it creates in the same instant, which is exactly the shape
	// that raced. UID breaks the tie.
	sameA := ovhMachine("a", "uid-aaa", time.Date(2026, 9, 2, 16, 9, 37, 0, time.UTC), "box")
	sameB := ovhMachine("b", "uid-bbb", time.Date(2026, 9, 2, 16, 9, 37, 0, time.UTC), "box")
	if yieldsDuplicateClaim(sameA, sameB) == yieldsDuplicateClaim(sameB, sameA) {
		t.Fatal("exactly one of the two Machines must yield")
	}
}
