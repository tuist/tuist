package controllers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	nodev1 "k8s.io/api/node/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/utils/ptr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

// setupReconciler returns a reconciler wired to a fake K8s client
// preloaded with `pool`, plus an httptest.Server that returns
// `signals` on every request. The token-file path is overridden
// to a temp file so the in-cluster `/var/run/secrets/...` mount
// isn't required.
func setupReconciler(t *testing.T, pool *tuistv1.RunnerPool, signals scaling.Signals) (*AutoscalerReconciler, *httptest.Server) {
	t.Helper()

	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatalf("add clientgo scheme: %v", err)
	}
	if err := tuistv1.AddToScheme(scheme); err != nil {
		t.Fatalf("add tuistv1 scheme: %v", err)
	}

	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(signals)
	}))

	tokenPath := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(tokenPath, []byte("test-token"), 0o600); err != nil {
		t.Fatalf("write token: %v", err)
	}

	scalingClient := scaling.NewClient(server.URL)
	scalingClient.TokenPath = tokenPath

	return &AutoscalerReconciler{
		Client:        fakeClient,
		Scheme:        scheme,
		SignalsClient: scalingClient,
		PollInterval:  time.Millisecond,
	}, server
}

func newAutoscalerPool(name string, replicas int32, autoscaling *tuistv1.RunnerPoolAutoscaling) *tuistv1.RunnerPool {
	return &tuistv1.RunnerPool{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: "tuist-runners",
		},
		Spec: tuistv1.RunnerPoolSpec{
			Replicas: replicas,
			Image:    "ghcr.io/tuist/tuist-linux-runner:test",
			// The apiserver defaults podMemoryMB (see the CRD marker on
			// RunnerPoolSpec); the fake client used here does not apply
			// CRD defaults, so the fixture has to. A pool that genuinely
			// declares no memory request is refused by perPodCost rather
			// than allocated at zero cost.
			PodMemoryMB:   14336,
			FleetSelector: name + "-fleet",
			DispatchLabel: name + "-label",
			Autoscaling:   autoscaling,
		},
	}
}

func reconcileOnce(t *testing.T, r *AutoscalerReconciler, name string) ctrl.Result {
	t.Helper()
	res, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{Name: name, Namespace: "tuist-runners"},
	})
	if err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	return res
}

func TestAutoscaler_DisabledPoolIsNoOp(t *testing.T) {
	pool := newAutoscalerPool("linux", 3, nil)
	r, server := setupReconciler(t, pool, scaling.Signals{})
	defer server.Close()

	reconcileOnce(t, r, "linux")

	got := &tuistv1.RunnerPool{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(pool), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	if got.Spec.Replicas != 3 {
		t.Errorf("Replicas = %d, want 3 (disabled pool unchanged)", got.Spec.Replicas)
	}
}

func TestAutoscaler_ScalesUp(t *testing.T) {
	pool := newAutoscalerPool("linux", 1, &tuistv1.RunnerPoolAutoscaling{
		Enabled:                  true,
		MinWarmPoolFloor:         ptr.To[int32](1),
		MaxReplicas:              30,
		ScaleDownCooldownSeconds: ptr.To[int32](300),
	})
	r, server := setupReconciler(t, pool, scaling.Signals{
		Fleet:                 "linux",
		Claimed:               5,
		Queued:                3,
		P95ConcurrentLastHour: 5,
	})
	defer server.Close()

	reconcileOnce(t, r, "linux")

	got := &tuistv1.RunnerPool{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(pool), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	// DesiredReplicas: floor=max(1,5)=5, target=max(5+3,5)=8, desired=8+1=9
	if got.Spec.Replicas != 9 {
		t.Errorf("Replicas = %d, want 9", got.Spec.Replicas)
	}
	// No scale-down → lastScaleDownAt unchanged
	if got.Status.LastScaleDownAt != nil {
		t.Errorf("LastScaleDownAt = %v, want nil on scale-up", got.Status.LastScaleDownAt)
	}
}

func TestAutoscaler_ScalesDownAfterCooldown(t *testing.T) {
	pool := newAutoscalerPool("linux", 10, &tuistv1.RunnerPoolAutoscaling{
		Enabled:                  true,
		MinWarmPoolFloor:         ptr.To[int32](1),
		MaxReplicas:              30,
		ScaleDownCooldownSeconds: ptr.To[int32](60),
	})
	r, server := setupReconciler(t, pool, scaling.Signals{
		Fleet:                 "linux",
		Claimed:               1,
		Queued:                0,
		P95ConcurrentLastHour: 1,
	})
	defer server.Close()

	now := time.Date(2026, 5, 14, 12, 0, 0, 0, time.UTC)
	r.Now = func() time.Time { return now }

	reconcileOnce(t, r, "linux")

	got := &tuistv1.RunnerPool{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(pool), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	// Desired: floor=1, target=max(1,1)=1, desired=1+1=2 → scale down from 10
	if got.Spec.Replicas != 2 {
		t.Errorf("Replicas = %d, want 2", got.Spec.Replicas)
	}
	if got.Status.LastScaleDownAt == nil || !got.Status.LastScaleDownAt.Time.Equal(now) {
		t.Errorf("LastScaleDownAt = %v, want %v", got.Status.LastScaleDownAt, now)
	}
}

func TestAutoscaler_DefersScaleDownDuringCooldown(t *testing.T) {
	tenSecondsAgo := metav1.NewTime(time.Date(2026, 5, 14, 11, 59, 50, 0, time.UTC))
	pool := newAutoscalerPool("linux", 10, &tuistv1.RunnerPoolAutoscaling{
		Enabled:                  true,
		MinWarmPoolFloor:         ptr.To[int32](1),
		MaxReplicas:              30,
		ScaleDownCooldownSeconds: ptr.To[int32](300),
	})
	pool.Status.LastScaleDownAt = &tenSecondsAgo

	r, server := setupReconciler(t, pool, scaling.Signals{
		Fleet:                 "linux",
		Claimed:               1,
		Queued:                0,
		P95ConcurrentLastHour: 1,
	})
	defer server.Close()

	r.Now = func() time.Time { return time.Date(2026, 5, 14, 12, 0, 0, 0, time.UTC) }

	reconcileOnce(t, r, "linux")

	got := &tuistv1.RunnerPool{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(pool), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	// Cooldown not elapsed (10s < 300s) — replicas must NOT change.
	if got.Spec.Replicas != 10 {
		t.Errorf("Replicas = %d, want 10 (cooldown blocks scale-down)", got.Spec.Replicas)
	}
}

func TestAutoscaler_NoOpAtTarget(t *testing.T) {
	pool := newAutoscalerPool("linux", 6, &tuistv1.RunnerPoolAutoscaling{
		Enabled:                  true,
		MinWarmPoolFloor:         ptr.To[int32](1),
		MaxReplicas:              30,
		ScaleDownCooldownSeconds: ptr.To[int32](300),
	})
	r, server := setupReconciler(t, pool, scaling.Signals{
		Fleet:                 "linux",
		Claimed:               0,
		Queued:                0,
		P95ConcurrentLastHour: 5,
	})
	defer server.Close()

	reconcileOnce(t, r, "linux")

	got := &tuistv1.RunnerPool{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(pool), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	// Desired = floor=5, target=max(0,5)=5, desired=5+1=6 == current. No patch.
	if got.Spec.Replicas != 6 {
		t.Errorf("Replicas = %d, want 6 (no-op)", got.Spec.Replicas)
	}
}

func TestAutoscaler_ServerErrorLeavesReplicasUnchanged(t *testing.T) {
	pool := newAutoscalerPool("linux", 5, &tuistv1.RunnerPoolAutoscaling{
		Enabled:                  true,
		MinWarmPoolFloor:         ptr.To[int32](1),
		MaxReplicas:              30,
		ScaleDownCooldownSeconds: ptr.To[int32](300),
	})

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	// Server always 500s.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "boom", http.StatusInternalServerError)
	}))
	defer server.Close()

	tokenPath := filepath.Join(t.TempDir(), "token")
	_ = os.WriteFile(tokenPath, []byte("test-token"), 0o600)

	sc := scaling.NewClient(server.URL)
	sc.TokenPath = tokenPath

	r := &AutoscalerReconciler{
		Client:        fakeClient,
		Scheme:        scheme,
		SignalsClient: sc,
		PollInterval:  time.Millisecond,
	}

	reconcileOnce(t, r, "linux")

	got := &tuistv1.RunnerPool{}
	if err := fakeClient.Get(context.Background(), client.ObjectKeyFromObject(pool), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	if got.Spec.Replicas != 5 {
		t.Errorf("Replicas = %d, want 5 (server error must not change replicas)", got.Spec.Replicas)
	}
}

func linuxFleetPool(name string, replicas int32, podMemMB int32, floor, maxRepl int32) *tuistv1.RunnerPool {
	return &tuistv1.RunnerPool{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist-runners"},
		Spec: tuistv1.RunnerPoolSpec{
			Replicas:      replicas,
			Image:         "ghcr.io/tuist/tuist-linux-runner:test",
			OS:            "linux",
			FleetSelector: "runners-linux",
			DispatchLabel: name + "-label",
			PodMemoryMB:   podMemMB,
			Autoscaling: &tuistv1.RunnerPoolAutoscaling{
				Enabled:                  true,
				MinWarmPoolFloor:         ptr.To(floor),
				MaxReplicas:              maxRepl,
				ScaleDownCooldownSeconds: ptr.To[int32](0),
			},
		},
	}
}

func linuxNode(name string, allocatableGiB int64) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Name:   name,
			Labels: map[string]string{"node.cluster.x-k8s.io/pool": "runners-linux"},
		},
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{{
				Type:   corev1.NodeReady,
				Status: corev1.ConditionTrue,
			}},
			Allocatable: corev1.ResourceList{
				corev1.ResourceMemory: *resource.NewQuantity(allocatableGiB*1024*1024*1024, resource.BinarySI),
			},
		},
	}
}

func TestAutoscaler_PerPodCostIncludesRuntimeClassOverhead(t *testing.T) {
	pool := linuxFleetPool("linux", 1, 8192, 1, 30)
	pool.Spec.RuntimeClass = "kata-qemu"
	runtimeClass := &nodev1.RuntimeClass{
		ObjectMeta: metav1.ObjectMeta{Name: "kata-qemu"},
		Overhead: &nodev1.Overhead{
			PodFixed: corev1.ResourceList{
				corev1.ResourceMemory: resource.MustParse("2560Mi"),
			},
		},
	}

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(runtimeClass).
		Build()
	r := &AutoscalerReconciler{Client: fakeClient}

	got, err := r.perPodCost(context.Background(), pool)
	if err != nil {
		t.Fatalf("perPodCost returned error: %v", err)
	}
	want := int64(10752 * 1024 * 1024)
	if got != want {
		t.Errorf("perPodCost = %d, want %d", got, want)
	}
}

func TestAutoscaler_PerPodCostFailsClosedWhenRuntimeClassIsMissing(t *testing.T) {
	pool := linuxFleetPool("linux", 1, 8192, 1, 30)
	pool.Spec.RuntimeClass = "kata-qemu"

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	r := &AutoscalerReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).Build(),
	}

	if _, err := r.perPodCost(context.Background(), pool); err == nil {
		t.Fatal("perPodCost returned nil error for a missing RuntimeClass")
	}
}

func TestAutoscaler_RuntimeClassCostFailureLeavesReplicasUnchanged(t *testing.T) {
	pool := linuxFleetPool("linux", 7, 8192, 1, 30)
	pool.Spec.RuntimeClass = "kata-qemu"
	r, server := setupReconciler(t, pool, scaling.Signals{
		Fleet:                 pool.Name,
		P95ConcurrentLastHour: 1,
	})
	defer server.Close()
	r.MemReserveFraction = 1
	if err := r.Create(context.Background(), linuxNode("bm-1", 256)); err != nil {
		t.Fatalf("create node: %v", err)
	}

	reconcileOnce(t, r, pool.Name)

	got := &tuistv1.RunnerPool{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(pool), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	if got.Spec.Replicas != 7 {
		t.Errorf("Replicas = %d, want 7 when RuntimeClass cost is unavailable", got.Spec.Replicas)
	}
	if got.Status.LastScaleDownAt != nil {
		t.Errorf("LastScaleDownAt = %v, want nil when replicas are unchanged", got.Status.LastScaleDownAt)
	}
}

func TestAutoscaler_SiblingSignalsFailureFallsBackToPerPoolTarget(t *testing.T) {
	pool := linuxFleetPool("linux", 7, 8192, 1, 30)
	pool.Spec.RuntimeClass = "kata-qemu"
	sibling := linuxFleetPool("linux-large", 1, 16_384, 1, 30)
	sibling.Spec.RuntimeClass = "kata-qemu"
	runtimeClass := &nodev1.RuntimeClass{
		ObjectMeta: metav1.ObjectMeta{Name: "kata-qemu"},
		Overhead: &nodev1.Overhead{
			PodFixed: corev1.ResourceList{
				corev1.ResourceMemory: resource.MustParse("2560Mi"),
			},
		},
	}
	node := linuxNode("bm-1", 256)

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, sibling, runtimeClass, node).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("fleet") == sibling.Name {
			http.Error(w, "boom", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(scaling.Signals{
			Fleet:                 pool.Name,
			P95ConcurrentLastHour: 1,
		})
	}))
	defer server.Close()

	tokenPath := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(tokenPath, []byte("test-token"), 0o600); err != nil {
		t.Fatalf("write token: %v", err)
	}
	scalingClient := scaling.NewClient(server.URL)
	scalingClient.TokenPath = tokenPath

	r := &AutoscalerReconciler{
		Client:             fakeClient,
		Scheme:             scheme,
		SignalsClient:      scalingClient,
		PollInterval:       time.Millisecond,
		MemReserveFraction: 1,
	}

	reconcileOnce(t, r, pool.Name)

	got := &tuistv1.RunnerPool{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(pool), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	if got.Spec.Replicas != 2 {
		t.Errorf("Replicas = %d, want per-pool fallback 2 when sibling signals fail", got.Spec.Replicas)
	}
}

// TestAutoscaler_FleetReclaimsIdleHeadroomForRealLoad is the
// cross-pool reclaim case: two Linux shapes share one bare-metal node
// pool sized so real load + floors fit, but an idle shape's speculative
// p95 warm buffer does not. The busy shape keeps its real load; the
// idle shape is held at its floor instead of scaling up to its
// per-pool target.
func TestAutoscaler_FleetReclaimsIdleHeadroomForRealLoad(t *testing.T) {
	// 8 GiB pods, 64 GiB node = 8 schedulable slots.
	busy := linuxFleetPool("busy", 1, 8192, 1, 30)
	idle := linuxFleetPool("idle", 1, 8192, 1, 30)
	node := linuxNode("bm-1", 64)

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(busy, idle, node).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	// Per-fleet signals: busy has real load (6), idle only a p95 buffer.
	signalsByFleet := map[string]scaling.Signals{
		"busy": {Fleet: "busy", Claimed: 5, Queued: 1, P95ConcurrentLastHour: 6},
		"idle": {Fleet: "idle", Claimed: 0, Queued: 0, P95ConcurrentLastHour: 5},
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(signalsByFleet[r.URL.Query().Get("fleet")])
	}))
	defer server.Close()

	tokenPath := filepath.Join(t.TempDir(), "token")
	_ = os.WriteFile(tokenPath, []byte("test-token"), 0o600)
	sc := scaling.NewClient(server.URL)
	sc.TokenPath = tokenPath

	r := &AutoscalerReconciler{
		Client:             fakeClient,
		Scheme:             scheme,
		SignalsClient:      sc,
		PollInterval:       time.Millisecond,
		MemReserveFraction: 1.0, // full allocatable in the test for clean math
	}

	reconcileOnce(t, r, "busy")
	reconcileOnce(t, r, "idle")

	gotBusy := &tuistv1.RunnerPool{}
	_ = fakeClient.Get(context.Background(), client.ObjectKey{Name: "busy", Namespace: "tuist-runners"}, gotBusy)
	gotIdle := &tuistv1.RunnerPool{}
	_ = fakeClient.Get(context.Background(), client.ObjectKey{Name: "idle", Namespace: "tuist-runners"}, gotIdle)

	// busy keeps its real load (6). Its per-pool target would be 7
	// (load 6 + floor 1) — the +1 speculative slot is squeezed because
	// the fleet is tight, but real work is intact.
	if gotBusy.Spec.Replicas != 6 {
		t.Errorf("busy Replicas = %d, want 6 (real load protected)", gotBusy.Spec.Replicas)
	}
	// idle is held at floor 1. Per-pool it would scale to 6 (p95 5 +
	// floor 1); the fleet allocator denies the speculative warm buffer.
	if gotIdle.Spec.Replicas != 1 {
		t.Errorf("idle Replicas = %d, want 1 (speculative headroom reclaimed)", gotIdle.Spec.Replicas)
	}
}

// macosGuestMemoryMB is the fleet's macOS Pod shape (6 vCPU / 14 GB).
// A Mac mini host admits allocatable/this many guests, which is what
// the allocator charges per Pod.
const macosGuestMemoryMB = 14336

func macosFleetPool(name, fleetSelector string, replicas, floor, maxRepl int32) *tuistv1.RunnerPool {
	return &tuistv1.RunnerPool{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist-runners"},
		Spec: tuistv1.RunnerPoolSpec{
			Replicas:      replicas,
			Image:         "ghcr.io/tuist/tuist-runner:" + name,
			OS:            "darwin",
			FleetSelector: fleetSelector,
			DispatchLabel: name + "-label",
			PodMemoryMB:   macosGuestMemoryMB,
			Autoscaling: &tuistv1.RunnerPoolAutoscaling{
				Enabled:                  true,
				MinWarmPoolFloor:         ptr.To(floor),
				MaxReplicas:              maxRepl,
				ScaleDownCooldownSeconds: ptr.To[int32](0),
			},
		},
	}
}

// macosNode is a Mac mini advertising room for exactly one guest — the
// M2-L shape. macosNodeWithGuests builds the multi-guest SKUs.
func macosNode(name, fleetSelector string) *corev1.Node {
	return macosNodeWithGuests(name, fleetSelector, 1)
}

// macosNodeWithGuests is a Mac mini advertising allocatable memory for
// `guests` Pods of the fleet's shape: 1 for an M2-L, 2 for an M4-XL.
func macosNodeWithGuests(name, fleetSelector string, guests int64) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Name: name,
			Labels: map[string]string{
				macosFleetLabel: fleetSelector,
				nodeOSLabel:     macosNodeOSDarwin,
			},
		},
		Status: corev1.NodeStatus{
			Allocatable: corev1.ResourceList{
				corev1.ResourceMemory: *resource.NewQuantity(
					guests*macosGuestMemoryMB*1024*1024, resource.BinarySI),
			},
			Conditions: []corev1.NodeCondition{{
				Type:   corev1.NodeReady,
				Status: corev1.ConditionTrue,
			}},
		},
	}
}

func TestAutoscaler_FleetCapacityExcludesUnhealthyNodes(t *testing.T) {
	pool := linuxFleetPool("linux", 1, 8192, 1, 30)
	ready := linuxNode("ready", 64)
	notReady := linuxNode("not-ready", 64)
	notReady.Status.Conditions[0].Status = corev1.ConditionFalse
	unschedulable := linuxNode("unschedulable", 64)
	unschedulable.Spec.Unschedulable = true
	pressured := linuxNode("pressured", 64)
	pressured.Status.Conditions = append(pressured.Status.Conditions, corev1.NodeCondition{
		Type:   corev1.NodeMemoryPressure,
		Status: corev1.ConditionTrue,
	})

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, ready, notReady, unschedulable, pressured).
		Build()
	r := &AutoscalerReconciler{Client: fakeClient, Scheme: scheme, MemReserveFraction: 1}

	got, err := r.fleetAllocatableMemory(context.Background(), pool.Spec.FleetSelector)
	if err != nil {
		t.Fatalf("fleetAllocatableMemory: %v", err)
	}
	want := int64(64 * 1024 * 1024 * 1024)
	if got != want {
		t.Fatalf("fleetAllocatableMemory = %d, want only Ready node memory %d", got, want)
	}
}

func TestAutoscaler_MacosFleetCapacityExcludesUnhealthyNodes(t *testing.T) {
	const fleet = "runners-macos"
	ready := macosNode("ready", fleet)
	notReady := macosNode("not-ready", fleet)
	notReady.Status.Conditions[0].Status = corev1.ConditionUnknown
	pressured := macosNode("pressured", fleet)
	pressured.Status.Conditions = append(pressured.Status.Conditions, corev1.NodeCondition{
		Type:   corev1.NodeDiskPressure,
		Status: corev1.ConditionTrue,
	})

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(ready, notReady, pressured).
		Build()
	r := &AutoscalerReconciler{Client: fakeClient, Scheme: scheme}

	got, err := r.macosFleetAllocatableMemory(context.Background(), fleet)
	if err != nil {
		t.Fatalf("macosFleetAllocatableMemory: %v", err)
	}
	want := int64(macosGuestMemoryMB) * 1024 * 1024
	if got != want {
		t.Fatalf("macosFleetAllocatableMemory = %d, want only the Ready node's memory %d", got, want)
	}
}

// TestAutoscaler_MacosFleetCapacityCountsGuestsNotHosts is the
// mixed-SKU case the byte-based budget exists for: one fleet label
// spanning a single-guest M2-L and a dual-guest M4-XL. Counting hosts
// would report 2 and leave the M4's second guest slot permanently
// unreachable to the allocator.
func TestAutoscaler_MacosFleetCapacityCountsGuestsNotHosts(t *testing.T) {
	const fleet = "runners-macos"
	m2 := macosNodeWithGuests("mac-m2", fleet, 1)
	m4 := macosNodeWithGuests("mac-m4", fleet, 2)

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(m2, m4).
		Build()
	r := &AutoscalerReconciler{Client: fakeClient, Scheme: scheme}

	got, err := r.macosFleetAllocatableMemory(context.Background(), fleet)
	if err != nil {
		t.Fatalf("macosFleetAllocatableMemory: %v", err)
	}

	perGuest := int64(macosGuestMemoryMB) * 1024 * 1024
	if slots := got / perGuest; slots != 3 {
		t.Fatalf("guest slots = %d, want 3 (1 from the M2-L + 2 from the M4-XL)", slots)
	}
}

func TestAutoscaler_FilteredZeroCapacityFallsBackToPerPoolTarget(t *testing.T) {
	pool := linuxFleetPool("linux", 5, 8192, 1, 30)
	node := linuxNode("not-ready", 64)
	node.Status.Conditions[0].Status = corev1.ConditionFalse

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, node).
		Build()
	r := &AutoscalerReconciler{Client: fakeClient, Scheme: scheme, MemReserveFraction: 1}
	signals := scaling.Signals{Fleet: pool.Name, Claimed: 7}
	knobs := scaling.PolicyKnobs{MinWarmPoolFloor: 1, MaxReplicas: 30}

	got := r.allocate(context.Background(), pool, signals, knobs, 8, logr.Discard())
	if got != 8 {
		t.Fatalf("allocate with every node filtered = %d, want per-pool fallback 8", got)
	}
}

// TestAutoscaler_MacosFleetSqueezesIdleHeadroomAgainstHostBudget is
// the macOS analog of TestAutoscaler_FleetReclaimsIdleHeadroomForRealLoad:
// two Xcode pools share a Mac mini fleet, each Pod charging one guest
// slot's worth of memory. With a 3-slot fleet the busy pool's real
// load is honored in full and the idle pool's speculative p95 warm
// buffer is reclaimed against the budget.
func TestAutoscaler_MacosFleetSqueezesIdleHeadroomAgainstHostBudget(t *testing.T) {
	const fleet = "runners-macos"
	busy := macosFleetPool("macos-busy", fleet, 1, 1, 5)
	idle := macosFleetPool("macos-idle", fleet, 1, 1, 5)
	// 3 single-guest Mac minis = 3 slots. Floors sum to 2; busy load =
	// 2 needs 2 more; that leaves 0 slots for speculative headroom —
	// idle's p95 buffer is fully reclaimed.
	host1 := macosNode("mac-1", fleet)
	host2 := macosNode("mac-2", fleet)
	host3 := macosNode("mac-3", fleet)

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(busy, idle, host1, host2, host3).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	signalsByFleet := map[string]scaling.Signals{
		"macos-busy": {Fleet: "macos-busy", Claimed: 1, Queued: 1, P95ConcurrentLastHour: 2},
		"macos-idle": {Fleet: "macos-idle", Claimed: 0, Queued: 0, P95ConcurrentLastHour: 4},
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(signalsByFleet[r.URL.Query().Get("fleet")])
	}))
	defer server.Close()

	tokenPath := filepath.Join(t.TempDir(), "token")
	_ = os.WriteFile(tokenPath, []byte("test-token"), 0o600)
	sc := scaling.NewClient(server.URL)
	sc.TokenPath = tokenPath

	r := &AutoscalerReconciler{
		Client:        fakeClient,
		Scheme:        scheme,
		SignalsClient: sc,
		PollInterval:  time.Millisecond,
	}

	reconcileOnce(t, r, "macos-busy")
	reconcileOnce(t, r, "macos-idle")

	gotBusy := &tuistv1.RunnerPool{}
	_ = fakeClient.Get(context.Background(), client.ObjectKey{Name: "macos-busy", Namespace: "tuist-runners"}, gotBusy)
	gotIdle := &tuistv1.RunnerPool{}
	_ = fakeClient.Get(context.Background(), client.ObjectKey{Name: "macos-idle", Namespace: "tuist-runners"}, gotIdle)

	// busy gets its real load (2). Per-pool target would be 3 (load 2
	// + floor 1); the +1 speculative slot is squeezed because the
	// fleet is tight.
	if gotBusy.Spec.Replicas != 2 {
		t.Errorf("busy Replicas = %d, want 2 (real load protected)", gotBusy.Spec.Replicas)
	}
	// idle is held at floor 1. Per-pool it would scale to 5 (p95 4 +
	// floor 1); the allocator denies the speculative buffer.
	if gotIdle.Spec.Replicas != 1 {
		t.Errorf("idle Replicas = %d, want 1 (speculative headroom reclaimed)", gotIdle.Spec.Replicas)
	}
}

// TestAutoscaler_MacosFleetGrantsHeadroomWhenSlotsAvailable verifies
// the uncontended path: with idle siblings and slack hosts, an
// autoscaling macOS pool gets its full speculative warm buffer.
func TestAutoscaler_MacosFleetGrantsHeadroomWhenSlotsAvailable(t *testing.T) {
	const fleet = "runners-macos"
	a := macosFleetPool("macos-a", fleet, 1, 1, 9)
	b := macosFleetPool("macos-b", fleet, 1, 0, 9)
	// 9 single-guest hosts = 9 slots, floors sum to 1, no queued load
	// anywhere — plenty of headroom for `a`'s speculative warm.
	var nodes []client.Object
	for i := 1; i <= 9; i++ {
		nodes = append(nodes, macosNode(fmt.Sprintf("mac-%d", i), fleet))
	}

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
	objs := []client.Object{a, b}
	objs = append(objs, nodes...)
	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(objs...).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	signalsByFleet := map[string]scaling.Signals{
		"macos-a": {Fleet: "macos-a", Claimed: 0, Queued: 0, P95ConcurrentLastHour: 4},
		"macos-b": {Fleet: "macos-b", Claimed: 0, Queued: 0, P95ConcurrentLastHour: 0},
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(signalsByFleet[r.URL.Query().Get("fleet")])
	}))
	defer server.Close()

	tokenPath := filepath.Join(t.TempDir(), "token")
	_ = os.WriteFile(tokenPath, []byte("test-token"), 0o600)
	sc := scaling.NewClient(server.URL)
	sc.TokenPath = tokenPath

	r := &AutoscalerReconciler{
		Client:        fakeClient,
		Scheme:        scheme,
		SignalsClient: sc,
		PollInterval:  time.Millisecond,
	}

	reconcileOnce(t, r, "macos-a")

	gotA := &tuistv1.RunnerPool{}
	_ = fakeClient.Get(context.Background(), client.ObjectKey{Name: "macos-a", Namespace: "tuist-runners"}, gotA)

	// floor 1 + p95 4 = target 5; budget = 9 slots, sibling reserves
	// only its floor (0). Full target granted.
	if gotA.Spec.Replicas != 5 {
		t.Errorf("a Replicas = %d, want 5 (full speculative buffer granted)", gotA.Spec.Replicas)
	}
}

// A pool with no per-Pod cost must not take its siblings down with it.
// perPodCost returning an error freezes every pool in the capacity
// domain at its current replicas — correct for an unreadable
// RuntimeClass, far too broad for one pool with a bad number in its own
// spec. The costless pool is dropped from the allocation; its siblings
// keep allocating normally.
func TestAutoscaler_CostlessPoolDoesNotFreezeItsSiblings(t *testing.T) {
	const fleet = "runners-macos"
	healthy := macosFleetPool("macos-healthy", fleet, 1, 1, 5)
	broken := macosFleetPool("macos-broken", fleet, 3, 1, 5)
	broken.Spec.PodMemoryMB = 0

	nodes := []client.Object{
		macosNodeWithGuests("mac-1", fleet, 1),
		macosNodeWithGuests("mac-2", fleet, 2),
	}

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
	objs := append([]client.Object{healthy, broken}, nodes...)
	fakeClient := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(objs...).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	signalsByFleet := map[string]scaling.Signals{
		"macos-healthy": {Fleet: "macos-healthy", Claimed: 0, Queued: 0, P95ConcurrentLastHour: 2},
		"macos-broken":  {Fleet: "macos-broken", Claimed: 0, Queued: 0, P95ConcurrentLastHour: 0},
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(signalsByFleet[r.URL.Query().Get("fleet")])
	}))
	defer server.Close()

	tokenPath := filepath.Join(t.TempDir(), "token")
	_ = os.WriteFile(tokenPath, []byte("test-token"), 0o600)
	sc := scaling.NewClient(server.URL)
	sc.TokenPath = tokenPath

	r := &AutoscalerReconciler{
		Client:        fakeClient,
		Scheme:        scheme,
		SignalsClient: sc,
		PollInterval:  time.Millisecond,
	}

	reconcileOnce(t, r, "macos-healthy")

	got := &tuistv1.RunnerPool{}
	if err := fakeClient.Get(context.Background(),
		client.ObjectKey{Name: "macos-healthy", Namespace: "tuist-runners"}, got); err != nil {
		t.Fatalf("get pool: %v", err)
	}

	// 3 slots, sibling excluded, so the healthy pool gets its full
	// per-pool target (p95 2 + floor 1 = 3). Frozen-at-current would
	// have left it on the 1 it started with.
	if got.Spec.Replicas != 3 {
		t.Fatalf("healthy pool Replicas = %d, want 3; a sibling with no podMemoryMB froze the whole capacity domain",
			got.Spec.Replicas)
	}
}

// Kata's podFixed overhead is a legitimate source of per-Pod cost, so a
// Linux pool declaring podMemoryMB: 0 alongside a RuntimeClass still has
// a real cost and must keep allocating. The zero check runs after the
// overhead is folded in for exactly this reason.
func TestAutoscaler_PerPodCostCountsRuntimeClassOverheadOnZeroRequest(t *testing.T) {
	pool := linuxFleetPool("linux", 1, 0, 1, 30)
	pool.Spec.RuntimeClass = "kata-qemu"

	rc := &nodev1.RuntimeClass{
		ObjectMeta: metav1.ObjectMeta{Name: "kata-qemu"},
		Handler:    "kata-qemu",
		Overhead: &nodev1.Overhead{
			PodFixed: corev1.ResourceList{
				corev1.ResourceMemory: *resource.NewQuantity(256*1024*1024, resource.BinarySI),
			},
		},
	}

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(pool, rc).Build()
	r := &AutoscalerReconciler{Client: fakeClient, Scheme: scheme}

	cost, err := r.perPodCost(context.Background(), pool)
	if err != nil {
		t.Fatalf("perPodCost: %v", err)
	}
	if want := int64(256 * 1024 * 1024); cost != want {
		t.Fatalf("perPodCost = %d, want the RuntimeClass overhead %d", cost, want)
	}
}

// macosNodeWithResources is a Mac mini advertising both dimensions, as
// tart-kubelet does (hostCPU / hostMemoryMB verbatim, no reserve). The
// memory-only helper above predates the shape cap, which needs CPU too.
func macosNodeWithResources(name, fleetSelector string, cpu int64, memoryMB int64) *corev1.Node {
	node := macosNodeWithGuests(name, fleetSelector, 1)
	node.Status.Allocatable = corev1.ResourceList{
		corev1.ResourceCPU:    *resource.NewQuantity(cpu, resource.DecimalSI),
		corev1.ResourceMemory: *resource.NewQuantity(memoryMB*1024*1024, resource.BinarySI),
	}
	return node
}

// The production topology: 9 M2-L (8 CPU / 14336 MB) + 2 M4-XL
// (12 CPU / 28672 MB). The 6 vCPU shape seats 13, the 12 vCPU shape
// seats 2 — and the second number is the one no fleet-wide division can
// produce, since 186368 MB / 28672 reads as 6.
func TestAutoscaler_ShapePlacementCapsCountSeatsPerNode(t *testing.T) {
	const fleet = "runners-macos"

	objects := []client.Object{}
	for i := 0; i < 9; i++ {
		objects = append(objects, macosNodeWithResources(fmt.Sprintf("m2-%d", i), fleet, 8, 14336))
	}
	for i := 0; i < 2; i++ {
		objects = append(objects, macosNodeWithResources(fmt.Sprintf("m4-%d", i), fleet, 12, 28672))
	}

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).Build()
	r := &AutoscalerReconciler{Client: fakeClient, Scheme: scheme}

	small := podShape{cpuMilli: 6000, memoryMB: 14336}
	large := podShape{cpuMilli: 12000, memoryMB: 28672}
	pool := &tuistv1.RunnerPool{Spec: tuistv1.RunnerPoolSpec{OS: "darwin", FleetSelector: fleet}}

	caps, err := r.shapePlacementCaps(context.Background(), pool, map[string]podShape{
		small.key(): small,
		large.key(): large,
	})
	if err != nil {
		t.Fatalf("shapePlacementCaps: %v", err)
	}

	if got := caps[small.key()]; got != 13 {
		t.Fatalf("6 vCPU seats = %d, want 13 (9 M2-L at one + 2 M4-XL at two)", got)
	}
	if got := caps[large.key()]; got != 2 {
		t.Fatalf("12 vCPU seats = %d, want 2 (M4-XL only, one guest each)", got)
	}
}

// CPU binds a shape whose memory-per-vCPU is richer than its host's.
// Dividing advertised memory alone would report four seats on a host
// whose twelve cores can only run two.
func TestAutoscaler_ShapePlacementCapsBindOnCPUNotOnlyMemory(t *testing.T) {
	const fleet = "runners-macos"
	node := macosNodeWithResources("m4", fleet, 12, 57344)

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(node).Build()
	r := &AutoscalerReconciler{Client: fakeClient, Scheme: scheme}

	shape := podShape{cpuMilli: 6000, memoryMB: 14336}
	pool := &tuistv1.RunnerPool{Spec: tuistv1.RunnerPoolSpec{OS: "darwin", FleetSelector: fleet}}

	caps, err := r.shapePlacementCaps(context.Background(), pool, map[string]podShape{shape.key(): shape})
	if err != nil {
		t.Fatalf("shapePlacementCaps: %v", err)
	}
	if got := caps[shape.key()]; got != 2 {
		t.Fatalf("seats = %d, want 2 (12 cores / 6), not the 4 that 57344/14336 would suggest", got)
	}
}

// Linux is capped too. It used to opt out on the grounds that kata
// oversubscribes CPU, so a CPU quotient would cap a fleet that is not
// CPU-bound. That does not hold on this fleet: podtemplate sets the
// runner container's CPU request equal to its limit equal to the shape,
// so kube-scheduler bin-packs on the full vCPU and a 16 vCPU Pod costing
// 16.25 with kata's overhead seats exactly once on a 31-vCPU RISE-L. The
// min() of the two quotients is what the scheduler does, so taking it
// here is agreement rather than pessimism.
//
// The production topology: 4 RISE-L at 31 vCPU / 117 GiB allocatable.
func TestAutoscaler_ShapePlacementCapsCountLinuxSeats(t *testing.T) {
	const fleet = "runners-linux"

	objects := []client.Object{}
	for i := 0; i < 4; i++ {
		objects = append(objects, linuxNodeWithResources(fmt.Sprintf("rise-l-%d", i), fleet, 31, 117*1024))
	}

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).Build()
	r := &AutoscalerReconciler{Client: fakeClient, Scheme: scheme}

	// Placement shapes: the advertised shape plus kata's 250m / 2560Mi.
	small := podShape{cpuMilli: 2250, memoryMB: 8*1024 + 2560}
	big := podShape{cpuMilli: 4250, memoryMB: 16*1024 + 2560}
	ceiling := podShape{cpuMilli: 16250, memoryMB: 32*1024 + 2560}
	pool := &tuistv1.RunnerPool{Spec: tuistv1.RunnerPoolSpec{OS: "linux", FleetSelector: fleet}}

	caps, err := r.shapePlacementCaps(context.Background(), pool, map[string]podShape{
		small.key(): small, big.key(): big, ceiling.key(): ceiling,
	})
	if err != nil {
		t.Fatalf("shapePlacementCaps: %v", err)
	}

	if got := caps[small.key()]; got != 44 {
		t.Fatalf("2vcpu-8gb seats = %d, want 44 (11 per box, memory-bound)", got)
	}
	// The shape that starved the fleet on 2026-09-02: the autoscaler
	// targeted 67 of these where 24 fit.
	if got := caps[big.key()]; got != 24 {
		t.Fatalf("4vcpu-16gb seats = %d, want 24 (6 per box, memory-bound)", got)
	}
	// CPU binds this one: 117 GiB would suggest three per box, but two
	// would need 32.5 of 31 vCPU.
	if got := caps[ceiling.key()]; got != 4 {
		t.Fatalf("16vcpu-32gb seats = %d, want 4 (1 per box, CPU-bound)", got)
	}
}

// An unrecognised OS is left uncapped rather than capped against the
// wrong node set: fleetNodeSelector falls through to darwin, which
// matches no node in a Linux fleet, and a zero cap would freeze the pool
// at zero replicas.
func TestAutoscaler_ShapePlacementCapsNoNodesLeavesZero(t *testing.T) {
	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().WithScheme(scheme).Build()
	r := &AutoscalerReconciler{Client: fakeClient, Scheme: scheme}

	shape := podShape{cpuMilli: 2250, memoryMB: 10752}
	pool := &tuistv1.RunnerPool{Spec: tuistv1.RunnerPoolSpec{OS: "linux", FleetSelector: "runners-linux"}}

	caps, err := r.shapePlacementCaps(context.Background(), pool, map[string]podShape{shape.key(): shape})
	if err != nil {
		t.Fatalf("shapePlacementCaps: %v", err)
	}
	if got := caps[shape.key()]; got != 0 {
		t.Fatalf("seats with no nodes = %d, want 0", got)
	}
}

// The seat cap and the byte budget must charge a Pod the same overhead,
// or the two halves of the allocator disagree about what fits.
func TestAutoscaler_PlacementShapeIncludesRuntimeClassOverhead(t *testing.T) {
	pool := linuxFleetPool("linux", 1, 16*1024, 1, 30)
	pool.Spec.PodCPUMilli = 4000
	pool.Spec.RuntimeClass = "kata-qemu"
	runtimeClass := &nodev1.RuntimeClass{
		ObjectMeta: metav1.ObjectMeta{Name: "kata-qemu"},
		Overhead: &nodev1.Overhead{
			PodFixed: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse("250m"),
				corev1.ResourceMemory: resource.MustParse("2560Mi"),
			},
		},
	}

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = nodev1.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(runtimeClass).Build()
	r := &AutoscalerReconciler{Client: fakeClient, Scheme: scheme}

	shape, err := r.placementShapeOf(context.Background(), pool)
	if err != nil {
		t.Fatalf("placementShapeOf: %v", err)
	}
	if shape.cpuMilli != 4250 {
		t.Fatalf("cpuMilli = %d, want 4250 (4000 + kata 250m)", shape.cpuMilli)
	}
	if shape.memoryMB != 16*1024+2560 {
		t.Fatalf("memoryMB = %d, want %d (16 GiB + kata 2560Mi)", shape.memoryMB, 16*1024+2560)
	}
}

// A named RuntimeClass that cannot be read freezes the pool rather than
// silently sizing it as if the sandbox were free.
func TestAutoscaler_PlacementShapeFailsOnUnreadableRuntimeClass(t *testing.T) {
	pool := linuxFleetPool("linux", 1, 8192, 1, 30)
	pool.Spec.RuntimeClass = "kata-qemu"

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = nodev1.AddToScheme(scheme)
	fakeClient := fake.NewClientBuilder().WithScheme(scheme).Build()
	r := &AutoscalerReconciler{Client: fakeClient, Scheme: scheme}

	if _, err := r.placementShapeOf(context.Background(), pool); !errors.Is(err, errPodCostUnavailable) {
		t.Fatalf("err = %v, want errPodCostUnavailable", err)
	}
}

func linuxNodeWithResources(name, fleetSelector string, cpu int64, memoryMB int64) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Name: name,
			Labels: map[string]string{
				"node.cluster.x-k8s.io/pool": fleetSelector,
				"kubernetes.io/os":           "linux",
			},
		},
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}},
			Allocatable: corev1.ResourceList{
				corev1.ResourceCPU:    *resource.NewQuantity(cpu, resource.DecimalSI),
				corev1.ResourceMemory: *resource.NewQuantity(memoryMB*1024*1024, resource.BinarySI),
			},
		},
	}
}
