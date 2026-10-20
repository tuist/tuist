package controllers

import (
	"context"
	"fmt"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

func TestCreationReservationStoreReleasesObservedPod(t *testing.T) {
	now := time.Unix(1000, 0)
	store := creationReservationStore{}
	store.add("tuist-runners", "runner-a", "linux", "runners-linux", now)

	total, _ := store.reconcile("tuist-runners", "runners-linux", map[string]struct{}{
		"tuist-runners/runner-a": {},
	}, now)
	if total != 0 {
		t.Fatalf("observed reservation count = %d, want 0", total)
	}
	if len(store.byName) != 0 {
		t.Fatalf("observed reservation remained in store: %+v", store.byName)
	}
}

func TestCreationReservationStoreExpiresUnobservedPod(t *testing.T) {
	now := time.Unix(1000, 0)
	store := creationReservationStore{}
	store.add("tuist-runners", "runner-a", "linux", "runners-linux", now)

	total, _ := store.reconcile(
		"tuist-runners",
		"runners-linux",
		map[string]struct{}{},
		now.Add(creationReservationLifetime),
	)
	if total != 0 {
		t.Fatalf("expired reservation count = %d, want 0", total)
	}
	if len(store.byName) != 0 {
		t.Fatalf("expired reservation remained in store: %+v", store.byName)
	}
}

func TestProvisioningAdmissionUsesLowestSiblingCap(t *testing.T) {
	scheme := mustScheme(t)
	poolA := newLinuxKataPool("linux-a", 8, 4)
	poolB := newLinuxKataPool("linux-b", 8, 2)
	node := readyLinuxRunnerNode("runner-node", poolA.Spec.FleetSelector)
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(poolA, poolB, node).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), poolA)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	// The sibling also has a gap and nothing provisioning, so one of the two
	// slots is reserved for it: the ceiling is the sibling minimum, the share
	// is what this pool may take of it.
	if admission.cap != 2 || admission.poolCap != 1 || admission.available != 1 {
		t.Fatalf("admission = %+v, want sibling minimum cap 2 and a share of 1", admission)
	}
}

func TestProvisioningAdmissionCountsUnschedulableSiblingPodsAgainstFleetCap(t *testing.T) {
	scheme := mustScheme(t)
	poolA := newLinuxKataPool("linux-a", 8, 2)
	poolB := newLinuxKataPool("linux-b", 8, 2)
	node := readyLinuxRunnerNode("runner-node", poolA.Spec.FleetSelector)
	// Unschedulable Pods still hold the ceiling: the scheduler may bind
	// them the moment capacity returns, with no admission check between.
	stuckB1 := unschedulableRunnerPod("linux-b-runner-1", poolB.Name, time.Unix(1000, 0))
	stuckB2 := unschedulableRunnerPod("linux-b-runner-2", poolB.Name, time.Unix(1000, 0))
	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(poolA, poolB, node, stuckB1, stuckB2).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), poolA)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.blockedReason != "fleet_cap" || admission.available != 0 {
		t.Fatalf("admission = %+v, want fleet_cap with no availability", admission)
	}
}

// The starvation this guards against: an unschedulable Pod is never reaped by
// the bound-Pod start timeout, because that clock only starts at node binding.
func TestUnschedulableTimedOutReleasesSlotOnlyAfterTimeout(t *testing.T) {
	pool := newLinuxKataPool("linux-a", 8, 2)
	rejectedAt := time.Unix(1000, 0)
	pod := unschedulableRunnerPod("linux-a-runner-1", pool.Name, rejectedAt)
	timeout := time.Duration(pool.Spec.Provisioning.StartTimeoutSecondsOrDefault()) * time.Second

	if startTimedOut(pod, pool, rejectedAt.Add(timeout)) {
		t.Fatal("bound-Pod start timeout fired on a Pod with no node")
	}
	if unschedulableTimedOut(pod, pool, rejectedAt.Add(timeout-time.Second)) {
		t.Fatal("unschedulable reap fired before the timeout elapsed")
	}
	if !unschedulableTimedOut(pod, pool, rejectedAt.Add(timeout)) {
		t.Fatal("unschedulable reap did not fire after the timeout elapsed")
	}
}

// A Pod the scheduler rejected and then placed is booting a sandbox like any
// other, so it must keep its slot rather than be reaped out from under itself.
func TestUnschedulableTimedOutIgnoresPodThatLaterScheduled(t *testing.T) {
	pool := newLinuxKataPool("linux-a", 8, 2)
	rejectedAt := time.Unix(1000, 0)
	pod := unschedulableRunnerPod("linux-a-runner-1", pool.Name, rejectedAt)
	// Capacity returned: the scheduler bound it and cleared the condition.
	pod.Spec.NodeName = "runner-node"
	pod.Status.Conditions = []corev1.PodCondition{{
		Type:               corev1.PodScheduled,
		Status:             corev1.ConditionTrue,
		LastTransitionTime: metav1.NewTime(rejectedAt.Add(time.Hour)),
	}}

	if unschedulableTimedOut(pod, pool, rejectedAt.Add(2*time.Hour)) {
		t.Fatal("reaped a Pod that the scheduler subsequently placed")
	}
}

// Capacity returning must not release a burst larger than the ceiling. The
// Pods that were unschedulable are exactly the ones the scheduler binds first,
// so the count that gates creation has to include them the whole time.
func TestProvisioningAdmissionHoldsCapAsUnschedulablePodsBecomeSchedulable(t *testing.T) {
	scheme := mustScheme(t)
	poolA := newLinuxKataPool("linux-a", 8, 2)
	poolB := newLinuxKataPool("linux-b", 8, 2)
	node := readyLinuxRunnerNode("runner-node", poolB.Spec.FleetSelector)
	bound := unschedulableRunnerPod("linux-b-runner-1", poolB.Name, time.Unix(1000, 0))
	bound.Spec.NodeName = node.Name
	bound.Status.Conditions = []corev1.PodCondition{{
		Type:   corev1.PodScheduled,
		Status: corev1.ConditionTrue,
	}}
	stillStuck := unschedulableRunnerPod("linux-b-runner-2", poolB.Name, time.Unix(1000, 0))
	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(poolA, poolB, node, bound, stillStuck).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), poolA)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.pendingForFleet != 2 {
		t.Fatalf("pendingForFleet = %d, want both the newly bound and the still-stuck Pod", admission.pendingForFleet)
	}
	if admission.blockedReason != "fleet_cap" || admission.available != 0 {
		t.Fatalf("admission = %+v, want the ceiling held across the transition", admission)
	}
}

// The starvation seen on 2026-09-02: one shape holds the entire fleet ceiling
// with Pods no node can seat, and every sibling with a replica gap is refused
// creation for as long as the shortfall lasts. The fleet ceiling still holds
// (burst guarantee), but the hog's own share shrinks by one per sibling that
// has a gap and nothing provisioning, so it may not top the count back up
// after unschedulableTimedOut reaps one of its Pods.
func TestProvisioningAdmissionHogCannotRecreateAfterReapWhileSiblingStarves(t *testing.T) {
	scheme := mustScheme(t)
	hog := newLinuxKataPool("linux-big", 8, 4)
	starved := newLinuxKataPool("linux-small", 8, 4)
	node := readyLinuxRunnerNode("runner-node", hog.Spec.FleetSelector)
	// After the reap: three of the hog's four parked Pods remain, so the fleet
	// count (3) is under the ceiling (4) and the freed slot is up for grabs.
	stuck := []*corev1.Pod{
		unschedulableRunnerPod("linux-big-runner-1", hog.Name, time.Unix(1000, 0)),
		unschedulableRunnerPod("linux-big-runner-2", hog.Name, time.Unix(1000, 0)),
		unschedulableRunnerPod("linux-big-runner-3", hog.Name, time.Unix(1000, 0)),
	}
	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(hog, starved, node, stuck[0], stuck[1], stuck[2]).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	hogAdmission, err := r.provisioningAdmission(context.Background(), hog)
	if err != nil {
		t.Fatalf("provisioningAdmission(hog): %v", err)
	}
	// The reservation now comes out of the ceiling the hog is measured against,
	// so the fleet check is what withholds the slot and it reports `fleet_cap`
	// rather than `pool_share`. The outcome is the one this test is about: the
	// hog gets nothing and the starved sibling gets the freed slot.
	if hogAdmission.poolCap != 3 || hogAdmission.fleetCap != 3 || hogAdmission.available != 0 {
		t.Fatalf("hog admission = %+v, want share 3 (cap 4 minus one starved sibling) and no availability", hogAdmission)
	}

	starvedAdmission, err := r.provisioningAdmission(context.Background(), starved)
	if err != nil {
		t.Fatalf("provisioningAdmission(starved): %v", err)
	}
	if starvedAdmission.blockedReason != "" || starvedAdmission.available != 1 {
		t.Fatalf("starved admission = %+v, want the freed slot", starvedAdmission)
	}
}

// A pool's share only shrinks for siblings that actually need a slot: one with
// no replica gap, or one already provisioning something, takes nothing away.
func TestProvisioningAdmissionShareIgnoresSiblingsWithoutAGap(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 8, 4)
	satisfied := newLinuxKataPool("linux-b", 0, 4)
	provisioning := newLinuxKataPool("linux-c", 8, 4)
	node := readyLinuxRunnerNode("runner-node", pool.Spec.FleetSelector)
	cPending := unschedulableRunnerPod("linux-c-runner-1", provisioning.Name, time.Unix(1000, 0))
	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(pool, satisfied, provisioning, node, cPending).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.poolCap != 4 {
		t.Fatalf("poolCap = %d, want the full cap: no sibling both has a gap and holds nothing", admission.poolCap)
	}
	if admission.available != 3 {
		t.Fatalf("available = %d, want cap 4 minus the one sibling Pod already provisioning", admission.available)
	}
}

// The share never drops below one, so a pool surrounded by starving siblings
// can still make progress rather than deadlocking the fleet.
func TestProvisioningAdmissionShareFloorsAtOne(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 8, 2)
	objs := []client.Object{pool, readyLinuxRunnerNode("runner-node", pool.Spec.FleetSelector)}
	for _, name := range []string{"linux-b", "linux-c", "linux-d"} {
		objs = append(objs, newLinuxKataPool(name, 8, 2))
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.poolCap != 1 || admission.available != 1 {
		t.Fatalf("admission = %+v, want a share floored at one", admission)
	}
}

func unschedulableRunnerPod(name, poolName string, rejectedAt time.Time) *corev1.Pod {
	pod := newRunnerPod(name, "img", corev1.PodPending, poolName)
	pod.Status.Conditions = []corev1.PodCondition{{
		Type:               corev1.PodScheduled,
		Status:             corev1.ConditionFalse,
		Reason:             corev1.PodReasonUnschedulable,
		LastTransitionTime: metav1.NewTime(rejectedAt),
	}}
	return pod
}

// The live regression: the share bounded each pool's own Pending count, but
// nothing held a slot open under the shared ceiling. Three siblings each well
// inside their own share filled the ceiling between them, and the starved pool
// was refused by the fleet check before its reserved share was ever consulted.
// Measured in production at cap 4 with the starved shape reporting
// `pendingForPool: 0, poolCap: 4, gap: 19` and still blocked.
func TestProvisioningAdmissionHoldsFleetSlotForStarvedSibling(t *testing.T) {
	scheme := mustScheme(t)
	starved := newLinuxKataPool("linux-starved", 19, 4)
	hogs := []*tuistv1.RunnerPool{
		newLinuxKataPool("linux-hog-a", 33, 4),
		newLinuxKataPool("linux-hog-b", 8, 4),
		newLinuxKataPool("linux-hog-c", 8, 4),
	}
	objs := []client.Object{starved, readyLinuxRunnerNode("runner-node", starved.Spec.FleetSelector)}
	for _, hog := range hogs {
		objs = append(objs, hog)
		objs = append(objs, unschedulableRunnerPod(hog.Name+"-runner-1", hog.Name, time.Unix(1000, 0)))
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	// Three of the four slots are held, one per sibling, so no sibling is over
	// its own share of three. The last slot is the starved pool's.
	for _, hog := range hogs {
		admission, err := r.provisioningAdmission(context.Background(), hog)
		if err != nil {
			t.Fatalf("provisioningAdmission(%s): %v", hog.Name, err)
		}
		if admission.blockedReason != "fleet_cap" || admission.available != 0 {
			t.Fatalf("%s admission = %+v, want the last slot withheld for the starved sibling", hog.Name, admission)
		}
	}

	admission, err := r.provisioningAdmission(context.Background(), starved)
	if err != nil {
		t.Fatalf("provisioningAdmission(starved): %v", err)
	}
	if admission.blockedReason != "" || admission.available != 1 {
		t.Fatalf("starved admission = %+v, want the reserved slot", admission)
	}
}

// The reservation must not deadlock a fleet where every pool is starved: the
// ceiling a sibling measures itself against floors at one, so the first Pod to
// start frees the count for the next.
func TestProvisioningAdmissionFleetCeilingFloorsAtOneWhenAllSiblingsStarve(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 8, 2)
	objs := []client.Object{pool, readyLinuxRunnerNode("runner-node", pool.Spec.FleetSelector)}
	for _, name := range []string{"linux-b", "linux-c", "linux-d"} {
		objs = append(objs, newLinuxKataPool(name, 8, 2))
	}
	// The pool under test is provisioning, so it is not itself owed a slot and
	// measures against the reduced ceiling; its three starved siblings would
	// take it below zero without the floor.
	objs = append(objs, unschedulableRunnerPod("linux-a-runner-1", pool.Name, time.Unix(1000, 0)))
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.fleetCap != 1 {
		t.Fatalf("fleetCap = %d, want a ceiling floored at one", admission.fleetCap)
	}
	if admission.blockedReason != "fleet_cap" {
		t.Fatalf("admission = %+v, want the in-flight Pod to hold the floored ceiling", admission)
	}
}

// A pool that is itself owed a slot measures against the whole ceiling; only
// its siblings are held back. Without this the reservation would cancel itself
// out whenever more than one pool was starved.
func TestProvisioningAdmissionStarvedPoolKeepsFullFleetCeiling(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 8, 4)
	sibling := newLinuxKataPool("linux-b", 8, 4)
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(
		pool, sibling, readyLinuxRunnerNode("runner-node", pool.Spec.FleetSelector),
	).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.fleetCap != admission.cap {
		t.Fatalf("fleetCap = %d, cap = %d, want a starved pool to keep the whole ceiling", admission.fleetCap, admission.cap)
	}
}

// The ceiling is per-node arithmetic, so hardware raises start throughput.
// Under the fleet-wide constant this pool was refused at four in flight no
// matter how many machines stood idle: measured on 2026-09-03 with 62 jobs
// queued, one node at 0% CPU and 0% memory, and every pool on `fleet_cap`.
func TestProvisioningAdmissionCeilingScalesWithHealthyNodes(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 20, 4)
	objs := []client.Object{pool}
	for _, name := range []string{"node-a", "node-b", "node-c"} {
		objs = append(objs, readyLinuxRunnerNode(name, pool.Spec.FleetSelector))
	}
	for i, node := range []string{"node-a", "node-a", "node-b", "node-b", "node-c"} {
		objs = append(objs, boundRunnerPod(fmt.Sprintf("linux-a-runner-%d", i), pool.Name, node))
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.cap != 12 {
		t.Fatalf("cap = %d, want the per-node budget times three healthy nodes", admission.cap)
	}
	if admission.blockedReason != "" || admission.available != 4 {
		t.Fatalf("admission = %+v, want a full node's worth of creations, not a fleet-wide four", admission)
	}
}

// Scaling the ceiling with the fleet must not stop it being a ceiling.
func TestProvisioningAdmissionBlocksWhenTheDerivedCeilingIsFull(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 20, 2)
	objs := []client.Object{pool}
	for _, name := range []string{"node-a", "node-b", "node-c"} {
		objs = append(objs, readyLinuxRunnerNode(name, pool.Spec.FleetSelector))
	}
	for i, node := range []string{"node-a", "node-a", "node-b", "node-b", "node-c", "node-c"} {
		objs = append(objs, boundRunnerPod(fmt.Sprintf("linux-a-runner-%d", i), pool.Name, node))
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.cap != 6 || admission.blockedReason != "fleet_cap" || admission.available != 0 {
		t.Fatalf("admission = %+v, want the six-slot ceiling held by six in-flight Pods", admission)
	}
}

// A node that cannot take Pods must not lend the fleet start budget. This is
// what makes the documented remedy for a host that accepts sandboxes it cannot
// start — cordon it — shrink the ceiling rather than leave it inflated.
func TestProvisioningAdmissionCeilingExcludesUnusableNodes(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 20, 4)
	cordoned := readyLinuxRunnerNode("node-cordoned", pool.Spec.FleetSelector)
	cordoned.Spec.Unschedulable = true
	notReady := readyLinuxRunnerNode("node-down", pool.Spec.FleetSelector)
	notReady.Status.Conditions = []corev1.NodeCondition{{
		Type:   corev1.NodeReady,
		Status: corev1.ConditionFalse,
	}}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(
		pool, readyLinuxRunnerNode("node-a", pool.Spec.FleetSelector), cordoned, notReady,
	).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.healthyNodes != 1 || admission.cap != 4 {
		t.Fatalf("admission = %+v, want only the one usable node to contribute budget", admission)
	}
}

// The ceiling bounds sandboxes coming up across the fleet; it cannot bound how
// many land on one host, because the controller does not place Pods. What it
// bounds instead is how many are handed to the scheduler at once — the batch
// that can arrive on one kubelet together, since the scheduler prefers the
// least-allocated node and an idle host attracts all of them.
func TestProvisioningAdmissionLimitsSimultaneousPlacement(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 40, 4)
	objs := []client.Object{pool}
	for _, name := range []string{"node-a", "node-b", "node-c"} {
		objs = append(objs, readyLinuxRunnerNode(name, pool.Spec.FleetSelector))
	}
	for i := 0; i < 4; i++ {
		objs = append(objs, newRunnerPod(fmt.Sprintf("linux-a-runner-%d", i), "img", corev1.PodPending, pool.Name))
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.awaitingPlacement != 4 {
		t.Fatalf("awaitingPlacement = %d, want the four unbound Pods", admission.awaitingPlacement)
	}
	if admission.blockedReason != "placement_burst" || admission.available != 0 {
		t.Fatalf("admission = %+v, want the twelve-slot ceiling still gated at one node's worth of placements", admission)
	}
}

// A Pod the scheduler has already refused is not about to arrive anywhere, so
// it must not hold the burst gate. Counting it would rebuild the 2026-09-02
// starvation on the new gate: a shape no node can seat parks its Pods for a
// whole start timeout and every sibling is refused creation behind them.
func TestProvisioningAdmissionPlacementBurstIgnoresRejectedPods(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 40, 4)
	objs := []client.Object{pool}
	for _, name := range []string{"node-a", "node-b", "node-c"} {
		objs = append(objs, readyLinuxRunnerNode(name, pool.Spec.FleetSelector))
	}
	for i := 0; i < 4; i++ {
		objs = append(objs, unschedulableRunnerPod(fmt.Sprintf("linux-a-runner-%d", i), pool.Name, time.Unix(1000, 0)))
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.awaitingPlacement != 0 {
		t.Fatalf("awaitingPlacement = %d, want rejected Pods left out of the burst gate", admission.awaitingPlacement)
	}
	if admission.blockedReason != "" || admission.available != 4 {
		t.Fatalf("admission = %+v, want creations to continue under the parked Pods", admission)
	}
}

// The admission metric reports a reason whenever a replica gap survives the
// tick, including the ordinary case of a gap larger than the slots on offer.
// With three terms able to cap creations, attributing all of them to the
// ceiling would make `reason="fleet_cap"` mean nothing.
func TestProvisioningAdmissionNamesTheTermThatCappedCreations(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-a", 40, 4)
	objs := []client.Object{pool}
	for _, name := range []string{"node-a", "node-b", "node-c"} {
		objs = append(objs, readyLinuxRunnerNode(name, pool.Spec.FleetSelector))
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err := r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.available != 4 || admission.limitedBy != "placement_burst" {
		t.Fatalf("admission = %+v, want a ramp attributed to the burst gate, not the ceiling", admission)
	}

	// Nine of the twelve slots in flight: now the ceiling is what binds.
	for i, node := range []string{"node-a", "node-a", "node-a", "node-b", "node-b", "node-b", "node-c", "node-c", "node-c"} {
		objs = append(objs, boundRunnerPod(fmt.Sprintf("linux-a-runner-%d", i), pool.Name, node))
	}
	c = fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	r = &RunnerPoolReconciler{Client: c, Scheme: scheme}

	admission, err = r.provisioningAdmission(context.Background(), pool)
	if err != nil {
		t.Fatalf("provisioningAdmission: %v", err)
	}
	if admission.available != 3 || admission.limitedBy != "fleet_cap" {
		t.Fatalf("admission = %+v, want the remaining ceiling attributed to fleet_cap", admission)
	}
}

// The fair-share reservation from the fleet-slot fix has to keep working
// against a ceiling that is now derived rather than configured.
func TestProvisioningAdmissionHoldsFleetSlotForStarvedSiblingOnMultiNodeFleet(t *testing.T) {
	scheme := mustScheme(t)
	starved := newLinuxKataPool("linux-starved", 19, 2)
	hog := newLinuxKataPool("linux-hog", 33, 2)
	objs := []client.Object{starved, hog}
	for _, name := range []string{"node-a", "node-b"} {
		objs = append(objs, readyLinuxRunnerNode(name, starved.Spec.FleetSelector))
	}
	// Four of the ceiling's four slots, so only the reservation can free one.
	for i, node := range []string{"node-a", "node-a", "node-b", "node-b"} {
		objs = append(objs, boundRunnerPod(fmt.Sprintf("linux-hog-runner-%d", i), hog.Name, node))
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme}

	hogAdmission, err := r.provisioningAdmission(context.Background(), hog)
	if err != nil {
		t.Fatalf("provisioningAdmission(hog): %v", err)
	}
	if hogAdmission.cap != 4 || hogAdmission.fleetCap != 3 || hogAdmission.available != 0 {
		t.Fatalf("hog admission = %+v, want a derived ceiling of 4 with one slot withheld", hogAdmission)
	}

	starvedAdmission, err := r.provisioningAdmission(context.Background(), starved)
	if err != nil {
		t.Fatalf("provisioningAdmission(starved): %v", err)
	}
	if starvedAdmission.fleetCap != starvedAdmission.cap {
		t.Fatalf("starved admission = %+v, want the whole derived ceiling", starvedAdmission)
	}
}

func boundRunnerPod(name, poolName, nodeName string) *corev1.Pod {
	pod := newRunnerPod(name, "img", corev1.PodPending, poolName)
	pod.Spec.NodeName = nodeName
	pod.Status.Conditions = []corev1.PodCondition{{
		Type:               corev1.PodScheduled,
		Status:             corev1.ConditionTrue,
		LastTransitionTime: metav1.NewTime(time.Unix(1000, 0)),
	}}
	return pod
}

func TestTerminationTimedOutIgnoresPodThatIsNotDeleting(t *testing.T) {
	pod := newRunnerPod("runner-a", "img", corev1.PodRunning, "linux-a")
	if terminationTimedOut(pod, time.Unix(10000, 0)) {
		t.Fatal("termination reap fired on a Pod with no deletionTimestamp")
	}
}

// A sandbox that is merely slow to stop is still making progress. The reap
// waits out the grace period kubelet was given plus the slack before deciding
// the shim is stuck.
func TestTerminationTimedOutWaitsGracePeriodPlusSlack(t *testing.T) {
	deletedAt := time.Unix(1000, 0)
	pod := terminatingRunnerPod("runner-a", "linux-a", deletedAt, 30)
	deadline := deletedAt.Add(30 * time.Second).Add(terminationStuckSlack)

	if terminationTimedOut(pod, deadline.Add(-time.Second)) {
		t.Fatal("termination reap fired before the grace period and slack elapsed")
	}
	if !terminationTimedOut(pod, deadline) {
		t.Fatal("termination reap did not fire after the grace period and slack elapsed")
	}
}

// A Pod deleted with no grace period still gets the slack: kubelet needs a
// moment to tear the sandbox down even when it was told not to wait.
func TestTerminationTimedOutAppliesSlackWithoutGracePeriod(t *testing.T) {
	deletedAt := time.Unix(1000, 0)
	pod := terminatingRunnerPod("runner-a", "linux-a", deletedAt, 0)
	pod.DeletionGracePeriodSeconds = nil

	if terminationTimedOut(pod, deletedAt.Add(terminationStuckSlack-time.Second)) {
		t.Fatal("termination reap fired inside the slack")
	}
	if !terminationTimedOut(pod, deletedAt.Add(terminationStuckSlack)) {
		t.Fatal("termination reap did not fire after the slack")
	}
}

func terminatingRunnerPod(name, poolName string, deletedAt time.Time, graceSeconds int64) *corev1.Pod {
	pod := newRunnerPod(name, "img", corev1.PodRunning, poolName)
	deletion := metav1.NewTime(deletedAt)
	pod.DeletionTimestamp = &deletion
	pod.DeletionGracePeriodSeconds = &graceSeconds
	return pod
}
