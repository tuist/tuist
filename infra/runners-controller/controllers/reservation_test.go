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
				macosFleetLabel:  reservationFleet,
				macosNodeOSLabel: macosNodeOSDarwin,
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

	r := reservationReconciler(pool, node, starved,
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

	r := reservationReconciler(pool, node, fresh)
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

	r := reservationReconciler(pool, node, starved, idle, owned)
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

	r := reservationReconciler(pool, node, placed)
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

	r := reservationReconciler(pool, node, starved)
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

	r := reservationReconciler(pool, m2Node("m2-0"), m2Node("m2-1"), starved)
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

	r := reservationReconciler(pool, held, free, starved)
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

	r := reservationReconciler(pool, m4Node("m4-busy"), m4Node("m4-quiet"), starved,
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
func TestReservation_SkipsLinuxPools(t *testing.T) {
	pool := largePool()
	pool.Spec.OS = "linux"
	node := m4Node("m4-0")
	starved := pendingPod("large-0", pool.Name, 5*time.Minute)

	r := reservationReconciler(pool, node, starved)
	if err := r.reconcileReservation(context.Background(), pool, []corev1.Pod{*starved}); err != nil {
		t.Fatalf("reconcileReservation: %v", err)
	}

	if isReserved(nodeByName(t, r, "m4-0")) {
		t.Fatal("Linux pools must not take reservations")
	}
}
