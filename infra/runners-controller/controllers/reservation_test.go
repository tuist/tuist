package controllers

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
)

const reservationFleet = "runners-macos"

var reservationNow = time.Date(2026, 8, 26, 12, 0, 0, 0, time.UTC)

// largePool is the 12 vCPU shape: it needs both of an M4-XL's guest
// slots, so no host running two 6 vCPU guests can seat it.
func largePool() *tuistv1.RunnerPool {
	return &tuistv1.RunnerPool{
		ObjectMeta: metav1.ObjectMeta{Name: "macos-26-6-12vcpu-28gb", Namespace: "runners"},
		Spec: tuistv1.RunnerPoolSpec{
			OS:            "darwin",
			FleetSelector: reservationFleet,
			PodCPUMilli:   12000,
			PodMemoryMB:   28672,
		},
	}
}

func m4Node(name string) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Name: name,
			Labels: map[string]string{
				macosFleetLabel: reservationFleet,
				nodeOSLabel:     macosNodeOSDarwin,
			},
		},
		Status: corev1.NodeStatus{
			Allocatable: corev1.ResourceList{
				corev1.ResourceCPU:    *resource.NewQuantity(12, resource.DecimalSI),
				corev1.ResourceMemory: *resource.NewQuantity(28672*1024*1024, resource.BinarySI),
			},
			Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}},
		},
	}
}

// m2Node cannot seat the large shape on either dimension.
func m2Node(name string) *corev1.Node {
	node := m4Node(name)
	node.Status.Allocatable = corev1.ResourceList{
		corev1.ResourceCPU:    *resource.NewQuantity(8, resource.DecimalSI),
		corev1.ResourceMemory: *resource.NewQuantity(14336*1024*1024, resource.BinarySI),
	}
	return node
}

func pendingPod(name, pool string, age time.Duration) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:              name,
			Namespace:         "runners",
			Labels:            map[string]string{"tuist.dev/runner-pool": pool},
			CreationTimestamp: metav1.NewTime(reservationNow.Add(-age)),
		},
		Status: corev1.PodStatus{Phase: corev1.PodPending},
	}
}

func placedPod(name, pool, node string, owner string) *corev1.Pod {
	pod := pendingPod(name, pool, time.Hour)
	pod.Spec.NodeName = node
	pod.Status.Phase = corev1.PodRunning
	if owner != "" {
		pod.Labels["tuist.dev/runner-pool-owner"] = owner
	}
	return pod
}

// smallPool is the 6 vCPU shape the large one competes with. A
// reservation is only taken for a shape that is large RELATIVE to what
// else runs on the fleet, so the sibling has to exist for the large
// shape to qualify.
func smallPool() *tuistv1.RunnerPool {
	return &tuistv1.RunnerPool{
		ObjectMeta: metav1.ObjectMeta{Name: "macos-26-6", Namespace: "runners"},
		Spec: tuistv1.RunnerPoolSpec{
			OS:            "darwin",
			FleetSelector: reservationFleet,
			PodCPUMilli:   6000,
			PodMemoryMB:   14336,
		},
	}
}

const (
	linuxReservationFleet = "runners-linux"
	linuxSmallPoolName    = "runner-pool-linux-2vcpu-8gb"
)

// linuxLargePool is the 64 GB ceiling shape. It costs a third of an
// AX162-R, which is what makes it starvable behind smaller Pods.
func linuxLargePool() *tuistv1.RunnerPool {
	return &tuistv1.RunnerPool{
		ObjectMeta: metav1.ObjectMeta{Name: "runner-pool-linux-16vcpu-64gb", Namespace: "runners"},
		Spec: tuistv1.RunnerPoolSpec{
			OS:            "linux",
			FleetSelector: linuxReservationFleet,
			PodCPUMilli:   16000,
			PodMemoryMB:   65536,
		},
	}
}

// linuxSmallPool is the default 2 vCPU / 8 GB shape the large one
// competes with for the same hosts.
func linuxSmallPool() *tuistv1.RunnerPool {
	return &tuistv1.RunnerPool{
		ObjectMeta: metav1.ObjectMeta{Name: linuxSmallPoolName, Namespace: "runners"},
		Spec: tuistv1.RunnerPoolSpec{
			OS:            "linux",
			FleetSelector: linuxReservationFleet,
			PodCPUMilli:   2000,
			PodMemoryMB:   8192,
		},
	}
}

// ax162Node carries the production AX162-R's allocatable, which is well
// short of its 256 GB of installed memory once kube and system
// reservations come off.
func ax162Node(name string) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Name: name,
			Labels: map[string]string{
				fleetNodePoolLabel: linuxReservationFleet,
				nodeOSLabel:        "linux",
			},
		},
		Status: corev1.NodeStatus{
			Allocatable: corev1.ResourceList{
				corev1.ResourceCPU:    *resource.NewQuantity(94, resource.DecimalSI),
				corev1.ResourceMemory: *resource.NewQuantity(227571*1024*1024, resource.BinarySI),
			},
			Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}},
		},
	}
}

func reservationReconciler(objects ...client.Object) *RunnerPoolReconciler {
	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
	return &RunnerPoolReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).Build(),
		Scheme: scheme,
		Now:    func() time.Time { return reservationNow },
	}
}

func nodeByName(t *testing.T, r *RunnerPoolReconciler, name string) *corev1.Node {
	t.Helper()
	node := &corev1.Node{}
	if err := r.Get(context.Background(), client.ObjectKey{Name: name}, node); err != nil {
		t.Fatalf("get node %s: %v", name, err)
	}
	return node
}

// The scenario the reservation exists for: both M4 guest slots are held
// by 6 vCPU jobs, a 12 vCPU Pod has waited past the grace period, and no
// coincidence of two simultaneously-free slots is going to arrive on its
// own while small jobs keep landing.
func TestReservation_HoldsAHostForAStarvedShape(t *testing.T) {
	pool := largePool()
	node := m4Node("m4-0")
	starved := pendingPod("large-0", pool.Name, 5*time.Minute)

	r := reservationReconciler(pool, smallPool(), node, starved,
		placedPod("small-0", "macos-26-6", "m4-0", "acme"),
		placedPod("small-1", "macos-26-6", "m4-0", "acme"),
	)

	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	got := nodeByName(t, r, "m4-0")
	if !isReserved(got) {
		t.Fatalf("node was not reserved: %+v", got.Spec.Taints)
	}
	for _, taint := range got.Spec.Taints {
		if taint.Key == podtemplate.ReservationTaintKey {
			if taint.Value != podtemplate.ReservationValue(pool.Name) {
				t.Errorf("taint value = %q, want the starved pool", taint.Value)
			}
			if taint.Effect != corev1.TaintEffectNoSchedule {
				t.Errorf("taint effect = %q, want NoSchedule so running jobs survive", taint.Effect)
			}
		}
	}
	if got.Annotations[reservationAtAnnotation] == "" {
		t.Error("reservation must be stamped so it can time out")
	}
}

// A Pod that has only just been created is waiting for the scheduler,
// not starved. Draining a host for it would be expensive and wrong.
func TestReservation_WaitsOutTheGracePeriod(t *testing.T) {
	pool := largePool()
	node := m4Node("m4-0")
	fresh := pendingPod("large-0", pool.Name, 10*time.Second)

	r := reservationReconciler(pool, smallPool(), node, fresh)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*fresh}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if isReserved(nodeByName(t, r, "m4-0")) {
		t.Fatal("a Pod inside the grace period must not trigger a drain")
	}
}

// Only idle Pods are retired, and only those belonging to other pools.
// A Pod running a customer job is waited out, never evicted.
func TestReservation_RetiresIdlePodsButNeverRunningJobs(t *testing.T) {
	pool := largePool()
	node := m4Node("m4-0")
	node.Spec.Taints = []corev1.Taint{{
		Key:    podtemplate.ReservationTaintKey,
		Value:  podtemplate.ReservationValue(pool.Name),
		Effect: corev1.TaintEffectNoSchedule,
	}}
	node.Annotations = map[string]string{reservationAtAnnotation: reservationNow.Format(time.RFC3339)}

	starved := pendingPod("large-0", pool.Name, 5*time.Minute)
	idle := placedPod("small-idle", "macos-26-6", "m4-0", "")
	owned := placedPod("small-owned", "macos-26-6", "m4-0", "acme")

	r := reservationReconciler(pool, smallPool(), node, starved, idle, owned)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	remaining := &corev1.PodList{}
	if err := r.List(context.Background(), remaining, client.InNamespace("runners")); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	names := map[string]bool{}
	for i := range remaining.Items {
		names[remaining.Items[i].Name] = true
	}

	if names["small-idle"] {
		t.Error("an idle Pod of another pool should have been retired to clear the seat")
	}
	if !names["small-owned"] {
		t.Error("a Pod running a customer job must never be evicted by a reservation")
	}
}

// Once the pool is served the host goes back into general circulation.
func TestReservation_ReleasesWhenThePoolIsServed(t *testing.T) {
	pool := largePool()
	node := m4Node("m4-0")
	node.Spec.Taints = []corev1.Taint{{
		Key:    podtemplate.ReservationTaintKey,
		Value:  podtemplate.ReservationValue(pool.Name),
		Effect: corev1.TaintEffectNoSchedule,
	}}
	node.Annotations = map[string]string{reservationAtAnnotation: reservationNow.Format(time.RFC3339)}

	placed := placedPod("large-0", pool.Name, "m4-0", "acme")

	r := reservationReconciler(pool, smallPool(), node, placed)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*placed}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if isReserved(nodeByName(t, r, "m4-0")) {
		t.Fatal("reservation should be released once the pool has its seat")
	}
}

// A reservation waiting on a six-hour job must not hold the host
// forever; the seats already cleared are worth more back in circulation.
func TestReservation_ReleasesOnTimeout(t *testing.T) {
	pool := largePool()
	node := m4Node("m4-0")
	node.Spec.Taints = []corev1.Taint{{
		Key:    podtemplate.ReservationTaintKey,
		Value:  podtemplate.ReservationValue(pool.Name),
		Effect: corev1.TaintEffectNoSchedule,
	}}
	node.Annotations = map[string]string{
		reservationAtAnnotation: reservationNow.Add(-reservationTimeout - time.Minute).Format(time.RFC3339),
	}
	starved := pendingPod("large-0", pool.Name, time.Hour)

	r := reservationReconciler(pool, smallPool(), node, starved)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if isReserved(nodeByName(t, r, "m4-0")) {
		t.Fatal("an expired reservation should have been released")
	}
}

// Hosts too small to ever seat the shape are not drained: no amount of
// waiting makes an M2-L fit a 12 vCPU guest.
func TestReservation_SkipsHostsThatCouldNeverSeatTheShape(t *testing.T) {
	pool := largePool()
	starved := pendingPod("large-0", pool.Name, 5*time.Minute)

	r := reservationReconciler(pool, smallPool(), m2Node("m2-0"), m2Node("m2-1"), starved)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	for _, name := range []string{"m2-0", "m2-1"} {
		if isReserved(nodeByName(t, r, name)) {
			t.Fatalf("%s cannot seat the shape and must not be drained", name)
		}
	}
}

// Every reservation is capacity withdrawn from the small shapes, so only
// one host is held at a time across the whole fleet.
func TestReservation_HoldsAtMostOneHostFleetWide(t *testing.T) {
	pool := largePool()
	held := m4Node("m4-0")
	held.Spec.Taints = []corev1.Taint{{
		Key:    podtemplate.ReservationTaintKey,
		Value:  "some-other-pool",
		Effect: corev1.TaintEffectNoSchedule,
	}}
	free := m4Node("m4-1")
	starved := pendingPod("large-0", pool.Name, 5*time.Minute)

	r := reservationReconciler(pool, smallPool(), held, free, starved)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if isReserved(nodeByName(t, r, "m4-1")) {
		t.Fatal("a second concurrent reservation would take a quarter of the fleet offline")
	}
}

// The host that converges soonest is the one with fewest customer jobs
// to wait out; ties break on name so a reservation does not wander.
func TestReservation_PrefersTheHostThatConvergesSoonest(t *testing.T) {
	pool := largePool()
	starved := pendingPod("large-0", pool.Name, 5*time.Minute)

	r := reservationReconciler(pool, smallPool(), m4Node("m4-busy"), m4Node("m4-quiet"), starved,
		placedPod("job-0", "macos-26-6", "m4-busy", "acme"),
		placedPod("job-1", "macos-26-6", "m4-busy", "acme"),
		placedPod("idle-0", "macos-26-6", "m4-quiet", ""),
	)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if !isReserved(nodeByName(t, r, "m4-quiet")) {
		t.Error("should reserve the host whose seats are only held by idle Pods")
	}
	if isReserved(nodeByName(t, r, "m4-busy")) {
		t.Error("should not reserve the host with two customer jobs to wait out")
	}
}

// Linux fleets opt out: those hosts are far larger than any shape, so a
// shape never needs one drained to fit.
// The Linux equivalent of the scenario above. A 64 GiB shape costs a
// third of an AX162-R, so it needs a contiguous third of a host that a
// trickle of 8 GiB Pods keeps carving up — the same starvation the macOS
// 12 vCPU shape hits, at a different granularity.
func TestReservation_HoldsALinuxHostForAStarvedShape(t *testing.T) {
	pool := linuxLargePool()
	node := ax162Node("bm-0")
	starved := pendingPod("large-0", pool.Name, 5*time.Minute)

	r := reservationReconciler(pool, linuxSmallPool(), node, starved,
		placedPod("small-0", linuxSmallPoolName, "bm-0", "acme"),
	)

	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	got := nodeByName(t, r, "bm-0")
	if !isReserved(got) {
		t.Fatalf("node was not reserved: %+v", got.Spec.Taints)
	}
	for _, taint := range got.Spec.Taints {
		if taint.Key != podtemplate.ReservationTaintKey {
			continue
		}
		if taint.Value != podtemplate.ReservationValue(pool.Name) {
			t.Errorf("taint value = %q, want the starved pool", taint.Value)
		}
		// NoSchedule and not NoExecute: the drain is progressive. Jobs
		// already running on the host finish and free their memory, and
		// the starved Pod lands as soon as its shape fits.
		if taint.Effect != corev1.TaintEffectNoSchedule {
			t.Errorf("taint effect = %q, want NoSchedule so running jobs survive", taint.Effect)
		}
	}
}

// A pool addresses its fleet by the labels its own Pods select on:
// `tuist.dev/fleet` on darwin, `node.cluster.x-k8s.io/pool` on linux.
// Both fleets live in one cluster and nothing stops an operator naming
// them alike, so the two hosts here carry the SAME fleet value under
// their respective labels. A selector keyed on the fleet name alone
// would hand each platform the other's host to drain.
func TestFleetNodes_AddressEachPlatformsHostsSeparately(t *testing.T) {
	mac := m4Node("m4-0")
	mac.Labels[macosFleetLabel] = linuxReservationFleet
	bare := ax162Node("bm-0")

	macPool := largePool()
	macPool.Spec.FleetSelector = linuxReservationFleet

	r := reservationReconciler(macPool, linuxLargePool(), mac, bare)

	linuxNodes, err := r.fleetNodes(context.Background(), linuxLargePool())
	if err != nil {
		t.Fatalf("fleetNodes(linux): %v", err)
	}
	if got := nodeNames(linuxNodes); len(got) != 1 || got[0] != "bm-0" {
		t.Errorf("linux fleet = %v, want just the bare-metal host", got)
	}

	macNodes, err := r.fleetNodes(context.Background(), macPool)
	if err != nil {
		t.Fatalf("fleetNodes(darwin): %v", err)
	}
	if got := nodeNames(macNodes); len(got) != 1 || got[0] != "m4-0" {
		t.Errorf("darwin fleet = %v, want just the Mac mini", got)
	}
}

func nodeNames(nodes []corev1.Node) []string {
	names := make([]string, 0, len(nodes))
	for i := range nodes {
		names = append(names, nodes[i].Name)
	}
	return names
}

// The drain is what makes the reservation useful on Linux, where a host
// carries many small Pods rather than two. `isIdle` reads the poller's
// exit, so an unclaimed Pod is retired and a claimed one is waited out.
func TestReservation_RetiresIdleLinuxPodsButNeverRunningJobs(t *testing.T) {
	pool := linuxLargePool()
	node := ax162Node("bm-0")
	node.Spec.Taints = []corev1.Taint{{
		Key:    podtemplate.ReservationTaintKey,
		Value:  podtemplate.ReservationValue(pool.Name),
		Effect: corev1.TaintEffectNoSchedule,
	}}
	node.Annotations = map[string]string{reservationAtAnnotation: reservationNow.Format(time.RFC3339)}

	starved := pendingPod("large-0", pool.Name, 5*time.Minute)
	idle := placedPod("small-idle", linuxSmallPoolName, "bm-0", "")
	owned := placedPod("small-owned", linuxSmallPoolName, "bm-0", "acme")

	r := reservationReconciler(pool, linuxSmallPool(), node, starved, idle, owned)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	remaining := &corev1.PodList{}
	if err := r.List(context.Background(), remaining, client.InNamespace("runners")); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	names := map[string]bool{}
	for i := range remaining.Items {
		names[remaining.Items[i].Name] = true
	}

	if names["small-idle"] {
		t.Error("an idle Pod of another pool should have been retired to clear memory")
	}
	if !names["small-owned"] {
		t.Error("a Pod running a customer job must never be evicted by a reservation")
	}
}

// The "large relative to the fleet" guard is platform-neutral. The
// default 2 vCPU / 8 GiB shape gets as many seats on a host as anything
// else does, so queueing behind other Pods is ordinary contention and
// draining a host for it would take a third of the Linux fleet out of
// service to no end.
func TestReservation_SkipsLinuxShapesThatAreNotLarge(t *testing.T) {
	pool := linuxSmallPool()
	node := ax162Node("bm-0")
	starved := pendingPod("small-0", pool.Name, 5*time.Minute)

	r := reservationReconciler(pool, linuxLargePool(), node, starved)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if isReserved(nodeByName(t, r, "bm-0")) {
		t.Fatal("the fleet's most granular shape must not reserve")
	}
}

// A deleted Linux pool has to hand its host back on the delete path.
// The orphan sweep is only a backstop, and it runs from OTHER pools'
// reconciles — on a fleet whose remaining pools are all scaled to zero
// it may not run promptly.
func TestReservation_ReleasedWhenTheOwningLinuxPoolIsDeleted(t *testing.T) {
	pool := linuxLargePool()
	node := ax162Node("bm-0")
	node.Spec.Taints = []corev1.Taint{{
		Key:    podtemplate.ReservationTaintKey,
		Value:  podtemplate.ReservationValue(pool.Name),
		Effect: corev1.TaintEffectNoSchedule,
	}}

	r := reservationReconciler(pool, node)
	if err := r.ReleaseReservationsForPool(context.Background(), pool); err != nil {
		t.Fatalf("ReleaseReservationsForPool: %v", err)
	}

	if isReserved(nodeByName(t, r, "bm-0")) {
		t.Fatal("a deleting Linux pool must release the host it held")
	}
}

// A homogeneous fleet whose hosts hold exactly one guest has nothing to
// accumulate: the shape already fits a single seat, so waiting for it is
// correct. Reserving there would take a one-host fleet entirely out of
// service for every other pool until the reservation cleared.
func TestReservation_SkipsFleetsWhereTheShapeIsNotLarge(t *testing.T) {
	pool := smallPool()
	node := m2Node("m2-0")
	starved := pendingPod("small-0", pool.Name, 5*time.Minute)

	r := reservationReconciler(pool, node, starved,
		placedPod("other-0", "macos-26-5", "m2-0", "acme"),
	)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if isReserved(nodeByName(t, r, "m2-0")) {
		t.Fatal("a single-seat shape on a single-seat host must not reserve; it should just wait")
	}
}

// The 6 vCPU shape is not large on an M4-XL either — it fits any free
// seat, so it never needs a host drained for it.
func TestReservation_SkipsTheSmallShapeOnADualSeatHost(t *testing.T) {
	pool := smallPool()
	node := m4Node("m4-0")
	starved := pendingPod("small-0", pool.Name, 5*time.Minute)

	r := reservationReconciler(pool, largePool(), node, starved)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if isReserved(nodeByName(t, r, "m4-0")) {
		t.Fatal("the fleet's most granular shape must never trigger a reservation")
	}
}

// The timeout is only a safety valve if the host actually goes back
// into circulation. `starvedPod` measures the Pod's own age, so the Pod
// that triggered the reservation is still long past the grace period the
// instant the taint lifts — without a cooldown the next reconcile
// re-reserves the same host and the small shapes never get it back.
func TestReservation_TimedOutHostRestsBeforeBeingReservedAgain(t *testing.T) {
	pool := largePool()
	node := m4Node("m4-0")
	node.Spec.Taints = []corev1.Taint{{
		Key:    podtemplate.ReservationTaintKey,
		Value:  podtemplate.ReservationValue(pool.Name),
		Effect: corev1.TaintEffectNoSchedule,
	}}
	node.Annotations = map[string]string{
		reservationAtAnnotation: reservationNow.Add(-reservationTimeout - time.Minute).Format(time.RFC3339),
	}
	// Pending since well before the grace period, as it would be after
	// fifteen minutes of waiting.
	starved := pendingPod("large-0", pool.Name, time.Hour)

	r := reservationReconciler(pool, smallPool(), node, starved)
	ctx := context.Background()

	// First pass times out and releases.
	if err := r.reconcileReservation(ctx, pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation (release): %v", err)
	}
	released := nodeByName(t, r, "m4-0")
	if isReserved(released) {
		t.Fatal("an expired reservation should have been released")
	}
	if released.Annotations[reservationCooldownAnnotation] == "" {
		t.Fatal("a timed-out release must rest the host")
	}

	// Second pass, same tick: the host must not be taken straight back.
	if err := r.reconcileReservation(ctx, pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation (retry): %v", err)
	}
	if isReserved(nodeByName(t, r, "m4-0")) {
		t.Fatal("host was re-reserved during its cooldown; the timeout is then a no-op")
	}
}

// Once the cooldown expires the pool may try again — the job is still
// queued and the host may since have freed up.
func TestReservation_ResumesAfterTheCooldownExpires(t *testing.T) {
	pool := largePool()
	node := m4Node("m4-0")
	node.Annotations = map[string]string{
		reservationCooldownAnnotation: reservationNow.Add(-time.Minute).Format(time.RFC3339),
	}
	starved := pendingPod("large-0", pool.Name, time.Hour)

	r := reservationReconciler(pool, smallPool(), node, starved)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if !isReserved(nodeByName(t, r, "m4-0")) {
		t.Fatal("an expired cooldown must not keep blocking the host")
	}
}

// A reservation that ended because the Pod landed achieved what it was
// for, so the host is handed straight back with no penalty.
func TestReservation_SuccessfulReleaseSetsNoCooldown(t *testing.T) {
	pool := largePool()
	node := m4Node("m4-0")
	node.Spec.Taints = []corev1.Taint{{
		Key:    podtemplate.ReservationTaintKey,
		Value:  podtemplate.ReservationValue(pool.Name),
		Effect: corev1.TaintEffectNoSchedule,
	}}
	node.Annotations = map[string]string{reservationAtAnnotation: reservationNow.Format(time.RFC3339)}
	placed := placedPod("large-0", pool.Name, "m4-0", "acme")

	r := reservationReconciler(pool, smallPool(), node, placed)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*placed}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if got := nodeByName(t, r, "m4-0"); got.Annotations[reservationCooldownAnnotation] != "" {
		t.Fatal("a successful reservation must not penalise the host")
	}
}

// A pool blocked on a resting host is still free to reserve a different
// eligible one, which is why the cooldown lives on the node.
func TestReservation_CooldownIsPerHostNotPerPool(t *testing.T) {
	pool := largePool()
	resting := m4Node("m4-0")
	resting.Annotations = map[string]string{
		reservationCooldownAnnotation: reservationNow.Add(time.Minute).Format(time.RFC3339),
	}
	fresh := m4Node("m4-1")
	starved := pendingPod("large-0", pool.Name, time.Hour)

	r := reservationReconciler(pool, smallPool(), resting, fresh, starved)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if isReserved(nodeByName(t, r, "m4-0")) {
		t.Error("the resting host must stay out of the running")
	}
	if !isReserved(nodeByName(t, r, "m4-1")) {
		t.Error("a sibling host with no cooldown should have been reserved instead")
	}
}

// A reservation names its owning pool, so only that pool can find and
// release it. Once the pool's CR is gone the taint is unreachable: the
// host is out of the fleet permanently AND its reservation keeps
// counting against the fleet-wide limit, blocking every future one.
func TestReservation_SweepsReservationsWhoseOwningPoolIsGone(t *testing.T) {
	pool := largePool()
	orphaned := m4Node("m4-0")
	orphaned.Spec.Taints = []corev1.Taint{{
		Key:    podtemplate.ReservationTaintKey,
		Value:  podtemplate.ReservationValue("macos-26-1-12vcpu-28gb"),
		Effect: corev1.TaintEffectNoSchedule,
	}}

	// No Pod is starved, so nothing but the sweep can act here.
	r := reservationReconciler(pool, smallPool(), orphaned)
	if err := r.reconcileReservation(context.Background(), pool, nil); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if isReserved(nodeByName(t, r, "m4-0")) {
		t.Fatal("a reservation whose pool no longer exists must be swept")
	}
}

// An orphaned reservation must not keep the fleet's one slot spoken for.
func TestReservation_OrphanDoesNotBlockANewReservation(t *testing.T) {
	pool := largePool()
	orphaned := m4Node("m4-0")
	orphaned.Spec.Taints = []corev1.Taint{{
		Key:    podtemplate.ReservationTaintKey,
		Value:  podtemplate.ReservationValue("long-gone-pool"),
		Effect: corev1.TaintEffectNoSchedule,
	}}
	starved := pendingPod("large-0", pool.Name, 5*time.Minute)

	r := reservationReconciler(pool, smallPool(), orphaned, starved)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	node := nodeByName(t, r, "m4-0")
	for _, taint := range node.Spec.Taints {
		if taint.Key == podtemplate.ReservationTaintKey &&
			taint.Value != podtemplate.ReservationValue(pool.Name) {
			t.Fatal("the orphan still holds the host; the starved pool is blocked behind it")
		}
	}
}

// A pool being deleted returns through reconcileDelete without reaching
// reservation reconciliation, so the delete path has to hand the host
// back itself.
func TestReservation_ReleasedWhenTheOwningPoolIsDeleted(t *testing.T) {
	pool := largePool()
	node := m4Node("m4-0")
	node.Spec.Taints = []corev1.Taint{{
		Key:    podtemplate.ReservationTaintKey,
		Value:  podtemplate.ReservationValue(pool.Name),
		Effect: corev1.TaintEffectNoSchedule,
	}}

	r := reservationReconciler(pool, smallPool(), node)
	if err := r.ReleaseReservationsForPool(context.Background(), pool); err != nil {
		t.Fatalf("ReleaseReservationsForPool: %v", err)
	}

	if isReserved(nodeByName(t, r, "m4-0")) {
		t.Fatal("a deleting pool must hand its host back")
	}
}

// A host already holding one of this pool's own Pods cannot be cleared
// for a second: the reaper never retires own-pool Pods. Ranking on
// occupancy alone made that host look ideal, because its own idle Pod
// counts as zero occupancy.
func TestReservation_SkipsHostsItsOwnPodAlreadyFills(t *testing.T) {
	pool := largePool()
	occupied := m4Node("m4-a") // holds this pool's own idle Pod
	free := m4Node("m4-b")     // holds two other-pool jobs
	starved := pendingPod("large-1", pool.Name, 5*time.Minute)

	r := reservationReconciler(pool, smallPool(), occupied, free, starved,
		placedPod("large-0", pool.Name, "m4-a", ""),
		placedPod("small-0", "macos-26-6", "m4-b", "acme"),
		placedPod("small-1", "macos-26-6", "m4-b", "acme"),
	)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if isReserved(nodeByName(t, r, "m4-a")) {
		t.Fatal("reserved a host its own Pod fills; that host can never seat the second Pod")
	}
	if !isReserved(nodeByName(t, r, "m4-b")) {
		t.Fatal("should have reserved the host whose occupants can actually be cleared")
	}
}
