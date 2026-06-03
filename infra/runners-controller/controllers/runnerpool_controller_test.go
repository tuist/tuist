package controllers

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

func nn(ns, name string) types.NamespacedName {
	return types.NamespacedName{Namespace: ns, Name: name}
}

func mustScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	s := runtime.NewScheme()
	if err := corev1.AddToScheme(s); err != nil {
		t.Fatalf("add corev1: %v", err)
	}
	if err := tuistv1.AddToScheme(s); err != nil {
		t.Fatalf("add tuistv1: %v", err)
	}
	return s
}

func newPool(name, image string, replicas int32) *tuistv1.RunnerPool {
	return &tuistv1.RunnerPool{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist-runners"},
		Spec: tuistv1.RunnerPoolSpec{
			Replicas:      replicas,
			Image:         image,
			FleetSelector: "tuist-runners-fleet",
			DispatchLabel: "tuist-macos",
			PodCPUMilli:   8000,
			PodMemoryMB:   14336,
		},
	}
}

func newRunnerPod(name, image string, phase corev1.PodPhase, poolName string) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: "tuist-runners",
			Labels: map[string]string{
				"tuist.dev/runner":      "true",
				"tuist.dev/runner-pool": poolName,
			},
		},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{{Name: "runner", Image: image}},
		},
		Status: corev1.PodStatus{Phase: phase},
	}
}

func TestIsStaleImage(t *testing.T) {
	pool := newPool("p", "ghcr.io/tuist/tuist-runner@sha256:new", 1)

	cases := []struct {
		name      string
		podImage  string
		wantStale bool
	}{
		{"matching digest", "ghcr.io/tuist/tuist-runner@sha256:new", false},
		{"different digest", "ghcr.io/tuist/tuist-runner@sha256:old", true},
		{"tag vs digest", "ghcr.io/tuist/tuist-runner:1.0.0", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			pod := newRunnerPod("p-runner-x", tc.podImage, corev1.PodPending, "p")
			if got := isStaleImage(pod, pool); got != tc.wantStale {
				t.Fatalf("isStaleImage(%q vs %q) = %v, want %v",
					tc.podImage, pool.Spec.Image, got, tc.wantStale)
			}
		})
	}
}

func TestIsStaleImage_EmptyContainers(t *testing.T) {
	// Defensive: a Pod that somehow has no containers shouldn't be
	// classified as stale (it isn't a runner Pod we'd want to delete).
	pool := newPool("p", "ghcr.io/tuist/tuist-runner@sha256:new", 1)
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: "p-runner-x", Namespace: "tuist-runners"},
		Spec:       corev1.PodSpec{Containers: nil},
	}
	if isStaleImage(pod, pool) {
		t.Fatalf("expected isStaleImage to be false for empty-containers pod")
	}
}

// TestReconcile_DeletesStalePendingPodAndCreatesReplacement is the
// behaviour that fixes the operator-side dance we hit while rolling
// out runner-image bumps: when the chart rewrites the digest pin,
// stale Pending Pods previously had to be deleted by hand or they
// sat forever on the old image. The controller now drops them on
// the next reconcile, and the gap-fill creates a current-image Pod.
func TestReconcile_DeletesStalePendingPodAndCreatesReplacement(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("p", "ghcr.io/tuist/tuist-runner@sha256:new", 1)
	stalePod := newRunnerPod("p-runner-stale", "ghcr.io/tuist/tuist-runner@sha256:old", corev1.PodPending, "p")
	// Pod + SA are created as siblings by `createRunner`; if the
	// recycle path forgot to delete the SA, every image roll would
	// leak runner SAs into the namespace and tart-kubelet's
	// projected-token cache would keep re-validating SAs whose
	// Pods are already gone. Seed the sibling SA so the test
	// catches that regression.
	staleSA := &corev1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "p-runner-stale",
			Namespace: "tuist-runners",
		},
	}

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, stalePod, staleSA).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	_, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	})
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	// Stale Pending Pod should be deleted.
	pods := &corev1.PodList{}
	if err := c.List(context.Background(), pods); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	for _, p := range pods.Items {
		if p.Name == "p-runner-stale" {
			t.Fatalf("expected stale pending pod to be deleted, still present")
		}
	}

	// Exactly one replacement Pod should be created, on the current image.
	if len(pods.Items) != 1 {
		t.Fatalf("expected 1 replacement pod, got %d: %+v", len(pods.Items), podNames(pods.Items))
	}
	if got := pods.Items[0].Spec.Containers[0].Image; got != pool.Spec.Image {
		t.Fatalf("replacement pod image = %q, want %q", got, pool.Spec.Image)
	}

	// Sibling SA must be deleted alongside the Pod; the replacement
	// flow recreates a fresh SA with the same name as the new Pod.
	sa := &corev1.ServiceAccount{}
	err = c.Get(context.Background(), nn("tuist-runners", "p-runner-stale"), sa)
	if err == nil {
		t.Fatalf("expected stale SA p-runner-stale to be deleted, still present")
	}
}

// TestReconcile_LeavesStalePendingClaimedPodAlone covers the
// isIdle guard on the stale-Pending reap. With the Linux
// token-isolation Pod shape the poller runs as an init container, so
// a Pod that has just claimed a job is briefly Pending (poller init
// exiting, runner main starting). The server stamps
// `runner-pool-owner` at claim time; the reap must skip such Pods or
// an image roll racing a claim would kill the job mid-flight.
func TestReconcile_LeavesStalePendingClaimedPodAlone(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("p", "ghcr.io/tuist/tuist-runner@sha256:new", 1)
	claimed := newRunnerPod("p-runner-claimed", "ghcr.io/tuist/tuist-runner@sha256:old", corev1.PodPending, "p")
	claimed.Labels["tuist.dev/runner-pool-owner"] = "acme"

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, claimed).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	pods := &corev1.PodList{}
	if err := c.List(context.Background(), pods); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	var survived bool
	for _, p := range pods.Items {
		if p.Name == "p-runner-claimed" {
			survived = true
		}
	}
	if !survived {
		t.Fatalf("claimed stale pending pod was reaped; the isIdle guard should protect a just-claimed Pod")
	}
	// alive=1 (the claimed pod counts), gap=0 — no replacement.
	if len(pods.Items) != 1 {
		t.Fatalf("expected no replacement while claimed pod is alive, got %d: %+v", len(pods.Items), podNames(pods.Items))
	}
}

// TestReconcile_LeavesStaleRunningPodAlone documents the deliberate
// asymmetry between Pending and Running stale Pods. A Running stale
// Pod may be mid-customer-job; deleting it would kill the workload
// and is more disruptive than waiting for the single-shot lifecycle
// to turn it over to Succeeded, where the existing reap path
// replaces it with a current-image Pod.
func TestReconcile_LeavesStaleRunningPodAlone(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("p", "ghcr.io/tuist/tuist-runner@sha256:new", 1)
	stalePod := newRunnerPod("p-runner-running", "ghcr.io/tuist/tuist-runner@sha256:old", corev1.PodRunning, "p")

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, stalePod).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	pods := &corev1.PodList{}
	if err := c.List(context.Background(), pods); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	found := false
	for _, p := range pods.Items {
		if p.Name == "p-runner-running" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("expected running stale pod to survive reconcile")
	}
	// Replicas=1, alive=1 (the running stale pod), gap=0 — no replacement created.
	if len(pods.Items) != 1 {
		t.Fatalf("expected no replacement while running stale pod is alive, got %d", len(pods.Items))
	}
}

// TestReconcile_NoDeletionWhenImageMatches is the regression test
// for the obvious worry: the new stale-image branch should be a
// no-op when the Pod's image already matches the pool's image.
func TestReconcile_NoDeletionWhenImageMatches(t *testing.T) {
	scheme := mustScheme(t)
	image := "ghcr.io/tuist/tuist-runner@sha256:current"
	pool := newPool("p", image, 1)
	pendingPod := newRunnerPod("p-runner-current", image, corev1.PodPending, "p")

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, pendingPod).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	pods := &corev1.PodList{}
	if err := c.List(context.Background(), pods); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	if len(pods.Items) != 1 || pods.Items[0].Name != "p-runner-current" {
		t.Fatalf("expected current-image pod to survive reconcile untouched, got %v", podNames(pods.Items))
	}
}

// TestReconcile_StampsImageRolledAtOnFirstReconcile establishes
// the baseline the server-side drain endpoint reads. Without this
// stamp, the server can't compute a per-Pod drain slot — every
// stale Pod would either drain immediately (thundering herd) or
// never (depending on the fallback). The first reconcile of a
// fresh pool must set both `ObservedImage` and `ImageRolledAt`.
func TestReconcile_StampsImageRolledAtOnFirstReconcile(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("p", "ghcr.io/tuist/tuist-runner@sha256:initial", 0)

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	updated := &tuistv1.RunnerPool{}
	if err := c.Get(context.Background(), nn(pool.Namespace, pool.Name), updated); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	if updated.Status.ObservedImage != pool.Spec.Image {
		t.Fatalf("ObservedImage = %q, want %q", updated.Status.ObservedImage, pool.Spec.Image)
	}
	if updated.Status.ImageRolledAt.IsZero() {
		t.Fatalf("ImageRolledAt is zero, expected stamp on first reconcile")
	}
}

// TestReconcile_BumpsImageRolledAtOnSpecImageChange covers the
// digest-pin bump path. When `spec.image` flips to a new value,
// the controller must overwrite `ObservedImage` and reset
// `ImageRolledAt` to the moment of observation — that timestamp is
// the t=0 the server uses to compute per-Pod drain slots, so a
// stale ImageRolledAt would cause Pods to drain at the wrong
// moment relative to the actual roll.
func TestReconcile_BumpsImageRolledAtOnSpecImageChange(t *testing.T) {
	scheme := mustScheme(t)
	oldImage := "ghcr.io/tuist/tuist-runner@sha256:old"
	newImage := "ghcr.io/tuist/tuist-runner@sha256:new"

	previousRoll := metav1.NewTime(metav1.Now().Add(-time.Hour))
	pool := newPool("p", newImage, 0)
	pool.Status.ObservedImage = oldImage
	pool.Status.ImageRolledAt = previousRoll

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	updated := &tuistv1.RunnerPool{}
	if err := c.Get(context.Background(), nn(pool.Namespace, pool.Name), updated); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	if updated.Status.ObservedImage != newImage {
		t.Fatalf("ObservedImage = %q, want %q", updated.Status.ObservedImage, newImage)
	}
	if !updated.Status.ImageRolledAt.After(previousRoll.Time) {
		t.Fatalf("ImageRolledAt = %v, expected to be after previous %v", updated.Status.ImageRolledAt, previousRoll)
	}
}

// TestReconcile_LeavesImageRolledAtAloneWhenImageUnchanged is the
// regression test: a steady-state reconcile (no image change) must
// not bump the timestamp, or the staggered drain schedule would
// keep resetting and stale Pods would never become slot-eligible.
func TestReconcile_LeavesImageRolledAtAloneWhenImageUnchanged(t *testing.T) {
	scheme := mustScheme(t)
	image := "ghcr.io/tuist/tuist-runner@sha256:steady"
	// JSON round-trip truncates to second precision; mint the
	// fixture at second precision so the equality assert is stable.
	priorRoll := metav1.NewTime(metav1.Now().Add(-10 * time.Minute).Truncate(time.Second))

	pool := newPool("p", image, 0)
	pool.Status.ObservedImage = image
	pool.Status.ImageRolledAt = priorRoll

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	updated := &tuistv1.RunnerPool{}
	if err := c.Get(context.Background(), nn(pool.Namespace, pool.Name), updated); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	if !updated.Status.ImageRolledAt.Equal(&priorRoll) {
		t.Fatalf("ImageRolledAt = %v, expected unchanged %v", updated.Status.ImageRolledAt, priorRoll)
	}
}

// TestReconcile_DrainsPoolOnDeleteWithoutKillingRunningPod is the
// regression test for the cascade-GC kill: a helm upgrade that drops
// or renames a RunnerPool deletes the CR, and because Pods carry an
// owner reference to it, Kubernetes GC would otherwise cascade-delete
// every Pod the pool owns — including runners mid-job. The drain
// finalizer must hold the CR Terminating while a mid-job Pod is still
// running, reap only the idle Pods, and release the CR once the last
// in-flight runner has exited.
func TestReconcile_DrainsPoolOnDeleteWithoutKillingRunningPod(t *testing.T) {
	scheme := mustScheme(t)
	image := "ghcr.io/tuist/tuist-runner@sha256:current"
	pool := newPool("p", image, 2)

	// Idle pod: warm-polling, no owner label — safe to reap on drain.
	idle := newRunnerPod("p-runner-idle", image, corev1.PodRunning, "p")
	idleSA := &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Name: "p-runner-idle", Namespace: "tuist-runners"}}
	// Mid-job pod: the server stamped the owner label at claim time —
	// must survive the drain.
	busy := newRunnerPod("p-runner-busy", image, corev1.PodRunning, "p")
	busy.Labels["tuist.dev/runner-pool-owner"] = "acme"
	busySA := &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Name: "p-runner-busy", Namespace: "tuist-runners"}}

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, idle, idleSA, busy, busySA).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	ctx := context.Background()

	// First reconcile installs the drain finalizer.
	if _, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: nn(pool.Namespace, pool.Name)}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	got := &tuistv1.RunnerPool{}
	if err := c.Get(ctx, nn(pool.Namespace, pool.Name), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	if !controllerutil.ContainsFinalizer(got, runnerPoolFinalizer) {
		t.Fatalf("expected drain finalizer to be installed")
	}

	// helm-style delete: the finalizer holds the CR Terminating.
	if err := c.Delete(ctx, got); err != nil {
		t.Fatalf("delete pool: %v", err)
	}

	// Drain reconcile: idle pod reaped, mid-job pod survives, CR remains.
	if _, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: nn(pool.Namespace, pool.Name)}); err != nil {
		t.Fatalf("drain reconcile: %v", err)
	}
	if err := c.Get(ctx, nn("tuist-runners", "p-runner-busy"), &corev1.Pod{}); err != nil {
		t.Fatalf("expected mid-job pod to survive drain: %v", err)
	}
	if err := c.Get(ctx, nn("tuist-runners", "p-runner-idle"), &corev1.Pod{}); err == nil {
		t.Fatalf("expected idle pod to be reaped during drain")
	}
	if err := c.Get(ctx, nn(pool.Namespace, pool.Name), got); err != nil {
		t.Fatalf("expected pool to remain Terminating while a runner is mid-job: %v", err)
	}

	// The job finishes: the single-shot pod exits and goes away. With
	// no live runner left, the next reconcile finds running == 0 and
	// releases the finalizer, so the CR (and the now-unblocked GC) can
	// finalize.
	busyLive := &corev1.Pod{}
	if err := c.Get(ctx, nn("tuist-runners", "p-runner-busy"), busyLive); err != nil {
		t.Fatalf("get busy pod: %v", err)
	}
	if err := c.Delete(ctx, busyLive); err != nil {
		t.Fatalf("remove finished busy pod: %v", err)
	}

	if _, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: nn(pool.Namespace, pool.Name)}); err != nil {
		t.Fatalf("final drain reconcile: %v", err)
	}
	// The controller's contract is to release the finalizer once the
	// pool is drained; the apiserver then GCs the CR. Assert the
	// finalizer is gone (the CR is either deleted or no longer holds
	// it) rather than the fake client's GC behaviour.
	drained := &tuistv1.RunnerPool{}
	switch err := c.Get(ctx, nn(pool.Namespace, pool.Name), drained); {
	case apierrors.IsNotFound(err):
		// CR collected — fully drained.
	case err != nil:
		t.Fatalf("get pool after drain: %v", err)
	case controllerutil.ContainsFinalizer(drained, runnerPoolFinalizer):
		t.Fatalf("expected drain finalizer to be released after the drain completed")
	}
}

func podNames(pods []corev1.Pod) []string {
	out := make([]string, len(pods))
	for i, p := range pods {
		out[i] = p.Name
	}
	return out
}
