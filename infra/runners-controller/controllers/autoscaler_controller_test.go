package controllers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
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
			Replicas:      replicas,
			Image:         "ghcr.io/tuist/tuist-linux-runner:test",
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
		MinWarmPoolFloor:         1,
		MaxReplicas:              30,
		ScaleDownCooldownSeconds: 300,
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
		MinWarmPoolFloor:         1,
		MaxReplicas:              30,
		ScaleDownCooldownSeconds: 60,
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
		MinWarmPoolFloor:         1,
		MaxReplicas:              30,
		ScaleDownCooldownSeconds: 300,
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
		MinWarmPoolFloor:         1,
		MaxReplicas:              30,
		ScaleDownCooldownSeconds: 300,
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
		MinWarmPoolFloor:         1,
		MaxReplicas:              30,
		ScaleDownCooldownSeconds: 300,
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
				MinWarmPoolFloor:         floor,
				MaxReplicas:              maxRepl,
				ScaleDownCooldownSeconds: 0,
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
			Allocatable: corev1.ResourceList{
				corev1.ResourceMemory: *resource.NewQuantity(allocatableGiB*1024*1024*1024, resource.BinarySI),
			},
		},
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
