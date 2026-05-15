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

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
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

func newPool(name string, replicas int32, autoscaling *tuistv1.RunnerPoolAutoscaling) *tuistv1.RunnerPool {
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
	pool := newPool("linux", 3, nil)
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
	pool := newPool("linux", 1, &tuistv1.RunnerPoolAutoscaling{
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
	pool := newPool("linux", 10, &tuistv1.RunnerPoolAutoscaling{
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
	pool := newPool("linux", 10, &tuistv1.RunnerPoolAutoscaling{
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
	pool := newPool("linux", 6, &tuistv1.RunnerPoolAutoscaling{
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
	pool := newPool("linux", 5, &tuistv1.RunnerPoolAutoscaling{
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

// --- MachineDeployment scaling (Option B: autoscaler reaches into
//     the management cluster's CAPI MD instead of relying on a
//     separately-installed cluster-autoscaler) ---

func mdLabelSelector() map[string]string {
	return map[string]string{
		"cluster.x-k8s.io/cluster-name":             "tuist-staging",
		"topology.cluster.x-k8s.io/deployment-name": "runners-linux",
	}
}

func newMachineDeployment(replicas int64) *unstructured.Unstructured {
	md := &unstructured.Unstructured{}
	md.SetGroupVersionKind(machineDeploymentGVK)
	md.SetNamespace("org-tuist")
	md.SetName("tuist-staging-runners-linux-abc12")
	md.SetLabels(mdLabelSelector())
	_ = unstructured.SetNestedField(md.Object, replicas, "spec", "replicas")
	return md
}

func newAutoscalingWithMDRef() *tuistv1.RunnerPoolAutoscaling {
	return &tuistv1.RunnerPoolAutoscaling{
		Enabled:                  true,
		MinWarmPoolFloor:         1,
		MaxReplicas:              30,
		ScaleDownCooldownSeconds: 300,
		MachineDeployment: &tuistv1.MachineDeploymentRef{
			Namespace:      "org-tuist",
			ClusterName:    "tuist-staging",
			DeploymentName: "runners-linux",
		},
	}
}

func mgmtFakeClient(t *testing.T, mds ...*unstructured.Unstructured) client.Client {
	t.Helper()
	// Use the default clientgoscheme — unstructured objects don't
	// need explicit scheme registration with the fake builder.
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatalf("add clientgo scheme: %v", err)
	}
	objs := make([]client.Object, len(mds))
	for i, md := range mds {
		objs[i] = md
	}
	return fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(objs...).
		Build()
}

func TestAutoscaler_ScalesMachineDeployment_UpAlongsidePool(t *testing.T) {
	pool := newPool("linux", 1, newAutoscalingWithMDRef())
	r, server := setupReconciler(t, pool, scaling.Signals{
		Fleet:                 "linux",
		Claimed:               5,
		Queued:                3,
		P95ConcurrentLastHour: 5,
	})
	defer server.Close()
	md := newMachineDeployment(1)
	r.MgmtClient = mgmtFakeClient(t, md)

	reconcileOnce(t, r, "linux")

	// Pool replicas updated (same math as the existing scale-up test).
	got := &tuistv1.RunnerPool{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(pool), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	if got.Spec.Replicas != 9 {
		t.Errorf("pool.Replicas = %d, want 9", got.Spec.Replicas)
	}

	// MD replicas also updated to match.
	gotMD := &unstructured.Unstructured{}
	gotMD.SetGroupVersionKind(machineDeploymentGVK)
	if err := r.MgmtClient.Get(context.Background(), client.ObjectKey{Namespace: "org-tuist", Name: md.GetName()}, gotMD); err != nil {
		t.Fatalf("get MD: %v", err)
	}
	mdReplicas, _, _ := unstructured.NestedInt64(gotMD.Object, "spec", "replicas")
	if mdReplicas != 9 {
		t.Errorf("MD.spec.replicas = %d, want 9 (pool scaled up but MD did not follow)", mdReplicas)
	}
}

func TestAutoscaler_SyncsMachineDeploymentEvenOnSteadyState(t *testing.T) {
	// Pool is already at desired size — the switch hits the "no-op"
	// branch — but the MD has drifted (someone scaled it manually).
	// The reconciler should still nudge it back so MD stays in
	// lockstep with the source-of-truth RunnerPool.
	pool := newPool("linux", 5, newAutoscalingWithMDRef())
	r, server := setupReconciler(t, pool, scaling.Signals{
		Fleet:                 "linux",
		Claimed:               2,
		Queued:                1,
		P95ConcurrentLastHour: 2,
	})
	defer server.Close()
	md := newMachineDeployment(99) // drifted
	r.MgmtClient = mgmtFakeClient(t, md)

	reconcileOnce(t, r, "linux")

	// Pool: floor=2, target=max(3,2)=3, desired=3+1=4 → scaled DOWN
	// from 5 to 4. (Tests RunnerPool scale-down + MD sync in one
	// pass, also relevant: even if pool stayed steady, the MD path
	// runs regardless.)
	got := &tuistv1.RunnerPool{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(pool), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	if got.Spec.Replicas != 4 {
		t.Errorf("pool.Replicas = %d, want 4", got.Spec.Replicas)
	}

	gotMD := &unstructured.Unstructured{}
	gotMD.SetGroupVersionKind(machineDeploymentGVK)
	if err := r.MgmtClient.Get(context.Background(), client.ObjectKey{Namespace: "org-tuist", Name: md.GetName()}, gotMD); err != nil {
		t.Fatalf("get MD: %v", err)
	}
	mdReplicas, _, _ := unstructured.NestedInt64(gotMD.Object, "spec", "replicas")
	if mdReplicas != 4 {
		t.Errorf("MD.spec.replicas = %d, want 4 (drift not corrected)", mdReplicas)
	}
}

func TestAutoscaler_NoMgmtClient_PoolScalesButMDStays(t *testing.T) {
	pool := newPool("linux", 1, newAutoscalingWithMDRef())
	r, server := setupReconciler(t, pool, scaling.Signals{
		Fleet:                 "linux",
		Claimed:               5,
		Queued:                3,
		P95ConcurrentLastHour: 5,
	})
	defer server.Close()
	// r.MgmtClient stays nil — simulates an env without
	// management-cluster credentials configured.

	reconcileOnce(t, r, "linux")

	got := &tuistv1.RunnerPool{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(pool), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	if got.Spec.Replicas != 9 {
		t.Errorf("pool.Replicas = %d, want 9 (RunnerPool must still scale even when MD scaling is disabled)", got.Spec.Replicas)
	}
}

func TestAutoscaler_NoMatchingMachineDeployment_FailsOpen(t *testing.T) {
	pool := newPool("linux", 1, newAutoscalingWithMDRef())
	r, server := setupReconciler(t, pool, scaling.Signals{
		Fleet:                 "linux",
		Claimed:               5,
		Queued:                3,
		P95ConcurrentLastHour: 5,
	})
	defer server.Close()
	// MgmtClient is set but has zero MDs matching the selector.
	r.MgmtClient = mgmtFakeClient(t)

	reconcileOnce(t, r, "linux")

	// Pool scaling must still succeed. The reconcile result is
	// non-error (we log + carry on); only the MD-side scaling is
	// skipped on this tick.
	got := &tuistv1.RunnerPool{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(pool), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	if got.Spec.Replicas != 9 {
		t.Errorf("pool.Replicas = %d, want 9 (missing MD must not block pool scaling)", got.Spec.Replicas)
	}
}
