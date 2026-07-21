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
	ctrlmetrics "sigs.k8s.io/controller-runtime/pkg/metrics"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/metrics"
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

func TestPodPhaseReplicaCounts(t *testing.T) {
	pending := newRunnerPod("p-pending", "img", corev1.PodPending, "p")
	running := newRunnerPod("p-running", "img", corev1.PodRunning, "p")
	unknown := newRunnerPod("p-unknown", "img", corev1.PodUnknown, "p")

	counts := podPhaseReplicaCounts{}
	counts.add(pending)
	counts.add(running)
	counts.add(unknown)

	if counts.pending != 1 || counts.running != 1 || counts.unknown != 1 {
		t.Fatalf("counts after add = %+v, want pending=1 running=1 unknown=1", counts)
	}

	counts.remove(pending)
	counts.remove(pending)
	counts.remove(running)

	if counts.pending != 0 || counts.running != 0 || counts.unknown != 1 {
		t.Fatalf("counts after remove = %+v, want pending=0 running=0 unknown=1", counts)
	}
}

func TestIsIdle(t *testing.T) {
	withPoller := func(name string, state corev1.ContainerState) *corev1.Pod {
		p := newRunnerPod(name, "img", corev1.PodPending, "p")
		p.Status.InitContainerStatuses = []corev1.ContainerStatus{
			{Name: "dind", State: corev1.ContainerState{Running: &corev1.ContainerStateRunning{}}},
			{Name: "poller", State: state},
		}
		return p
	}
	owner := newRunnerPod("p-owner", "img", corev1.PodPending, "p")
	owner.Labels["tuist.dev/runner-pool-owner"] = "acme"

	cases := []struct {
		name string
		pod  *corev1.Pod
		want bool
	}{
		{"warm, no label, no init status", newRunnerPod("p-warm", "img", corev1.PodPending, "p"), true},
		{"owner label set", owner, false},
		// The poller exits the moment it stages a claim, so a
		// terminated poller means "claimed" even without the
		// best-effort owner label.
		{"poller terminated, no label", withPoller("p-claimed", corev1.ContainerState{Terminated: &corev1.ContainerStateTerminated{ExitCode: 0}}), false},
		{"poller still running, no label", withPoller("p-polling", corev1.ContainerState{Running: &corev1.ContainerStateRunning{}}), true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isIdle(tc.pod); got != tc.want {
				t.Fatalf("isIdle = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestRunnerTerminated(t *testing.T) {
	withRunner := func(state corev1.ContainerState) *corev1.Pod {
		p := newRunnerPod("p", "img", corev1.PodFailed, "p")
		p.Status.ContainerStatuses = []corev1.ContainerStatus{
			{Name: "dind", State: corev1.ContainerState{Terminated: &corev1.ContainerStateTerminated{ExitCode: 0}}},
			{Name: "runner", State: state},
		}
		return p
	}

	t.Run("guest-OOM fingerprint (137/Error) is captured", func(t *testing.T) {
		got := runnerTerminated(withRunner(corev1.ContainerState{
			Terminated: &corev1.ContainerStateTerminated{ExitCode: 137, Signal: 9, Reason: "Error"},
		}))
		if got == nil || got.ExitCode != 137 || got.Reason != "Error" {
			t.Fatalf("runnerTerminated = %+v, want exitCode=137 reason=Error", got)
		}
	})

	t.Run("falls back to LastTerminationState", func(t *testing.T) {
		p := newRunnerPod("p", "img", corev1.PodRunning, "p")
		p.Status.ContainerStatuses = []corev1.ContainerStatus{
			{Name: "runner", LastTerminationState: corev1.ContainerState{
				Terminated: &corev1.ContainerStateTerminated{ExitCode: 1},
			}},
		}
		if got := runnerTerminated(p); got == nil || got.ExitCode != 1 {
			t.Fatalf("runnerTerminated = %+v, want exitCode=1 from LastTerminationState", got)
		}
	})

	t.Run("no runner container returns nil", func(t *testing.T) {
		p := newRunnerPod("p", "img", corev1.PodRunning, "p")
		p.Status.ContainerStatuses = []corev1.ContainerStatus{
			{Name: "dind", State: corev1.ContainerState{Running: &corev1.ContainerStateRunning{}}},
		}
		if got := runnerTerminated(p); got != nil {
			t.Fatalf("runnerTerminated = %+v, want nil", got)
		}
	})

	t.Run("running runner returns nil", func(t *testing.T) {
		if got := runnerTerminated(withRunner(corev1.ContainerState{Running: &corev1.ContainerStateRunning{}})); got != nil {
			t.Fatalf("runnerTerminated = %+v, want nil", got)
		}
	})
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

// TestReconcile_ThrottlesStalePendingReapToRollCap guards the roll
// concurrency cap on the stale-Pending reap path. Before, every stale
// Pending Pod was reaped in a single reconcile, so a digest roll made
// the whole fleet `tart pull` the new image at once. Now the reap shares
// the roll budget: with 5 replicas and a 40% cap (floor = 2), only 2
// stale Pods retire per reconcile and the rest keep serving the old
// image until the budget frees.
func TestReconcile_ThrottlesStalePendingReapToRollCap(t *testing.T) {
	scheme := mustScheme(t)
	const (
		oldImage = "ghcr.io/tuist/tuist-runner@sha256:old"
		newImage = "ghcr.io/tuist/tuist-runner@sha256:new"
	)
	pool := newPool("p", newImage, 5)
	pool.Spec.Rollout = &tuistv1.RunnerPoolRollout{MaxConcurrentPercent: 40}
	p0 := newRunnerPod("p-runner-s0", oldImage, corev1.PodPending, "p")
	p1 := newRunnerPod("p-runner-s1", oldImage, corev1.PodPending, "p")
	p2 := newRunnerPod("p-runner-s2", oldImage, corev1.PodPending, "p")
	p3 := newRunnerPod("p-runner-s3", oldImage, corev1.PodPending, "p")
	p4 := newRunnerPod("p-runner-s4", oldImage, corev1.PodPending, "p")

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, p0, p1, p2, p3, p4).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn(pool.Namespace, pool.Name)}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	pods := &corev1.PodList{}
	if err := c.List(context.Background(), pods); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	oldCount, newCount := 0, 0
	for i := range pods.Items {
		if pods.Items[i].Spec.Containers[0].Image == oldImage {
			oldCount++
		} else {
			newCount++
		}
	}
	// cap = floor(40% * 5) = 2: exactly 2 stale Pods retired + replaced
	// this tick; the other 3 keep serving the old image.
	if oldCount != 3 {
		t.Fatalf("expected 3 stale pods remaining (cap=2 reaped), got %d", oldCount)
	}
	if newCount != 2 {
		t.Fatalf("expected 2 current-image replacements, got %d", newCount)
	}
	if len(pods.Items) != 5 {
		t.Fatalf("expected pool to stay at 5 pods, got %d", len(pods.Items))
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

// TestReconcile_LeavesStalePendingPollerExitedPodAlone covers the
// label-independent half of the stale-Pending guard. The server's
// owner-label stamp is best-effort (it degrades to "running without
// the label" if the apiserver patch keeps failing), so a genuinely
// claimed Pod can be Pending with no owner label while the poller
// exits and the runner starts. The terminated poller is the reliable
// "claimed" signal, and the reap must honor it.
func TestReconcile_LeavesStalePendingPollerExitedPodAlone(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("p", "ghcr.io/tuist/tuist-runner@sha256:new", 1)
	claiming := newRunnerPod("p-runner-claiming", "ghcr.io/tuist/tuist-runner@sha256:old", corev1.PodPending, "p")
	// No owner label (stamp failed), but the poller has staged the JIT
	// and exited.
	claiming.Status.InitContainerStatuses = []corev1.ContainerStatus{
		{Name: "poller", State: corev1.ContainerState{Terminated: &corev1.ContainerStateTerminated{ExitCode: 0}}},
	}

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, claiming).
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
		if p.Name == "p-runner-claiming" {
			survived = true
		}
	}
	if !survived {
		t.Fatalf("stale Pending pod with an exited poller was reaped; the poller-terminated signal should protect a just-claimed Pod even without the owner label")
	}
	if len(pods.Items) != 1 {
		t.Fatalf("expected no replacement while the claiming pod is alive, got %d: %+v", len(pods.Items), podNames(pods.Items))
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

// newNode returns a registered cluster Node. Tests that exercise the
// orphan sweep need at least one, because an empty Node view is
// deliberately treated as unusable rather than as "every Pod is
// orphaned" (see liveNodeNames).
func newNode(name string) *corev1.Node {
	return &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: name}}
}

// wedgedOrphanPod builds a runner Pod in the exact shape that survived
// in production: terminal, bound to a Node that no longer exists, and
// already carrying both tart-kubelet's node-local finalizer and the
// deletionTimestamp left by a reap that could never complete.
func wedgedOrphanPod(name, image, poolName, nodeName string) *corev1.Pod {
	pod := newRunnerPod(name, image, corev1.PodFailed, poolName)
	pod.Spec.NodeName = nodeName
	pod.Finalizers = []string{tartKubeletVMCleanupFinalizer}
	deleted := metav1.NewTime(time.Now().Add(-22 * time.Hour))
	pod.DeletionTimestamp = &deleted
	return pod
}

// TestReconcile_ReleasesRunnerOrphanedOnDeletedNode is the regression for
// runner Pods outliving the Mac minis they ran on. tart-kubelet's
// `vm-cleanup` finalizer is removed only by the podagent on the Pod's own
// host, so once the CAPI provider released the mini and deleted its Node
// object, the Pod became immortal: the reap's Delete set a
// deletionTimestamp, the finalizer blocked collection, and every later
// reconcile skipped the Pod because it was neither alive nor
// DeletionTimestamp-free. Upstream PodGC can't help either — it only
// issues a Delete, which the same finalizer blocks. Four such Pods
// accumulated in production, two of them on deleted Nodes, and Pods
// orphaned this way have wedged `helm --wait` before.
func TestReconcile_ReleasesRunnerOrphanedOnDeletedNode(t *testing.T) {
	scheme := mustScheme(t)
	const image = "ghcr.io/tuist/tuist-runner@sha256:new"
	pool := newPool("p", image, 1)
	orphan := wedgedOrphanPod("p-runner-orphan", image, "p", "mini-released")
	orphanSA := &corev1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{Name: "p-runner-orphan", Namespace: "tuist-runners"},
	}

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, newNode("mini-live"), orphan, orphanSA).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, APIReader: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	pods := &corev1.PodList{}
	if err := c.List(context.Background(), pods); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	for _, p := range pods.Items {
		if p.Name == "p-runner-orphan" {
			t.Fatalf("expected orphaned pod to be released, still present with finalizers %v", p.Finalizers)
		}
	}

	// The orphan never counted as alive, so the pool refills the gap it
	// left rather than sitting a replica short behind a dead host.
	if len(pods.Items) != 1 {
		t.Fatalf("expected 1 replacement pod, got %d: %+v", len(pods.Items), podNames(pods.Items))
	}

	sa := &corev1.ServiceAccount{}
	if err := c.Get(context.Background(), nn("tuist-runners", "p-runner-orphan"), sa); err == nil {
		t.Fatalf("expected orphaned pod's sibling SA to be deleted, still present")
	}
}

// TestReconcile_SkipsOrphanSweepWhenNodeViewUnusable guards the sweep's
// blast radius. An unsynced Node informer reads as zero Nodes rather than
// as an error, and every Pod would then look orphaned — so an unusable
// view must delete nothing at all. The Pod here is in the wedged shape,
// which no other branch touches, so the sweep is the only thing that could
// remove it.
func TestReconcile_SkipsOrphanSweepWhenNodeViewUnusable(t *testing.T) {
	scheme := mustScheme(t)
	const image = "ghcr.io/tuist/tuist-runner@sha256:new"
	pool := newPool("p", image, 1)
	orphan := wedgedOrphanPod("p-runner-orphan", image, "p", "mini-released")

	// No Node objects at all: the view is unusable.
	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, orphan).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, APIReader: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := &corev1.Pod{}
	if err := c.Get(context.Background(), nn("tuist-runners", "p-runner-orphan"), got); err != nil {
		t.Fatalf("expected pod to survive an unusable node view, got: %v", err)
	}
	if !controllerutil.ContainsFinalizer(got, tartKubeletVMCleanupFinalizer) {
		t.Fatalf("expected vm-cleanup finalizer to be left intact when the node view is unusable")
	}
}

// TestReconcile_OrphanSweepPreservesForeignFinalizers pins the sweep to
// tart-kubelet's own finalizer. Stripping it is only safe because the host
// that would honour it is gone; a finalizer belonging to anything else has
// an owner that may well still be alive, so the sweep must leave it (and
// therefore the Pod) alone.
func TestReconcile_OrphanSweepPreservesForeignFinalizers(t *testing.T) {
	scheme := mustScheme(t)
	const foreign = "example.com/some-other-controller"
	const image = "ghcr.io/tuist/tuist-runner@sha256:new"
	pool := newPool("p", image, 1)
	orphan := newRunnerPod("p-runner-orphan", image, corev1.PodRunning, "p")
	orphan.Spec.NodeName = "mini-released"
	orphan.Finalizers = []string{tartKubeletVMCleanupFinalizer, foreign}

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, newNode("mini-live"), orphan).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, APIReader: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := &corev1.Pod{}
	if err := c.Get(context.Background(), nn("tuist-runners", "p-runner-orphan"), got); err != nil {
		t.Fatalf("expected pod held open by a foreign finalizer to still exist, got: %v", err)
	}
	if controllerutil.ContainsFinalizer(got, tartKubeletVMCleanupFinalizer) {
		t.Fatalf("expected vm-cleanup finalizer to be stripped, finalizers = %v", got.Finalizers)
	}
	if !controllerutil.ContainsFinalizer(got, foreign) {
		t.Fatalf("expected foreign finalizer %q to be preserved, finalizers = %v", foreign, got.Finalizers)
	}
}

// TestReconcileDelete_ReleasesOrphansWedgingTerminatingPool is the
// regression for the drain path skipping the orphan sweep. Reconcile
// returns through reconcileDelete before ever reaching the steady-state
// sweep, and neither of the drain's own branches can handle an orphan: the
// busy-looking one below counts as `running` forever, holding the CR in
// Terminating so the `helm --wait` behind a pool rename never returns, and
// the terminal one is left to a GC that its held finalizer blocks. This is
// the motivating scenario for the whole fix, so it has to work on the exact
// path a helm pool-topology change takes.
func TestReconcileDelete_ReleasesOrphansWedgingTerminatingPool(t *testing.T) {
	scheme := mustScheme(t)
	const image = "ghcr.io/tuist/tuist-runner@sha256:current"
	pool := newPool("p", image, 1)

	// Mid-job runner: the server stamped the owner label at claim time, so
	// the drain waits for it rather than killing it. Its host is still alive
	// at this point.
	busy := newRunnerPod("p-runner-busy", image, corev1.PodRunning, "p")
	busy.Labels["tuist.dev/runner-pool-owner"] = "acme"
	busy.Spec.NodeName = "mini-doomed"
	busy.Finalizers = []string{tartKubeletVMCleanupFinalizer}
	busySA := &corev1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{Name: "p-runner-busy", Namespace: "tuist-runners"},
	}

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, newNode("mini-live"), newNode("mini-doomed"), busy, busySA).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, APIReader: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	ctx := context.Background()

	if _, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: nn(pool.Namespace, pool.Name)}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	got := &tuistv1.RunnerPool{}
	if err := c.Get(ctx, nn(pool.Namespace, pool.Name), got); err != nil {
		t.Fatalf("get pool: %v", err)
	}

	// helm-style delete: the drain finalizer holds the CR Terminating while
	// the mid-job runner finishes.
	if err := c.Delete(ctx, got); err != nil {
		t.Fatalf("delete pool: %v", err)
	}

	// The mini is released mid-drain, taking the VM with it. Everything the
	// orphan sweep reacts to happens strictly AFTER the pool went
	// Terminating, so only reconcileDelete can clean this up — the
	// steady-state sweep is never reached again for this pool.
	if err := c.Delete(ctx, newNode("mini-doomed")); err != nil {
		t.Fatalf("delete node: %v", err)
	}

	if _, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: nn(pool.Namespace, pool.Name)}); err != nil {
		t.Fatalf("drain reconcile: %v", err)
	}

	p := &corev1.Pod{}
	if err := c.Get(ctx, nn("tuist-runners", "p-runner-busy"), p); err == nil {
		t.Fatalf("expected orphan to be released during drain, still present with finalizers %v", p.Finalizers)
	}
	if err := c.Get(ctx, nn("tuist-runners", "p-runner-busy"), &corev1.ServiceAccount{}); err == nil {
		t.Fatalf("expected released orphan's sibling SA to be deleted, still present")
	}

	// Nothing live is left, so the drain must complete rather than block on
	// a runner that no longer has a host to run on. A held finalizer here is
	// what wedges `helm --wait`.
	if err := c.Get(ctx, nn(pool.Namespace, pool.Name), got); err == nil &&
		controllerutil.ContainsFinalizer(got, runnerPoolFinalizer) {
		t.Fatalf("expected drain finalizer to be released once only orphans remained")
	}
}

// TestReconcile_KeepsRunnerWhenNodeMissingOnlyFromCache guards the sweep's
// blast radius against informer skew. Pod and Node informers are separate
// watch streams with no atomic cross-type view, so a Node that exists can be
// briefly absent from the Node cache while a Pod already bound to it is
// visible — routine on a fleet where minis join and are released constantly.
// Believing the cache there deletes a healthy runner mid-job: the Pod below
// is busy and carries the vm-cleanup finalizer, which is exactly what every
// live macOS runner looks like, so nothing but the Node read distinguishes it
// from a wedged orphan. The authoritative Get is the only thing standing
// between a stale cache and a killed job.
func TestReconcile_KeepsRunnerWhenNodeMissingOnlyFromCache(t *testing.T) {
	scheme := mustScheme(t)
	const image = "ghcr.io/tuist/tuist-runner@sha256:current"
	pool := newPool("p", image, 1)

	busy := newRunnerPod("p-runner-busy", image, corev1.PodRunning, "p")
	busy.Labels["tuist.dev/runner-pool-owner"] = "acme"
	busy.Spec.NodeName = "mini-joining"
	busy.Finalizers = []string{tartKubeletVMCleanupFinalizer}
	busySA := &corev1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{Name: "p-runner-busy", Namespace: "tuist-runners"},
	}

	// Cached view: synced enough to be usable (it has a Node), but the Pod's
	// own Node hasn't been delivered yet.
	cached := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, newNode("mini-live"), busy, busySA).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()
	// The apiserver knows better: mini-joining is real.
	authoritative := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(newNode("mini-live"), newNode("mini-joining")).
		Build()

	r := &RunnerPoolReconciler{Client: cached, APIReader: authoritative, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := &corev1.Pod{}
	if err := cached.Get(context.Background(), nn("tuist-runners", "p-runner-busy"), got); err != nil {
		t.Fatalf("expected mid-job pod on a cache-missing but live node to survive, got: %v", err)
	}
	if !controllerutil.ContainsFinalizer(got, tartKubeletVMCleanupFinalizer) {
		t.Fatalf("expected vm-cleanup finalizer to be left intact on a live node's pod")
	}
	if err := cached.Get(context.Background(), nn("tuist-runners", "p-runner-busy"), &corev1.ServiceAccount{}); err != nil {
		t.Fatalf("expected mid-job pod's sibling SA to survive, got: %v", err)
	}
}

// TestReconcile_SkipsOrphanSweepWithoutAPIReader pins the fail-closed
// default. Without an authoritative reader the sweep cannot tell a released
// mini from an unsynced cache, and it must then do nothing: unwired plumbing
// should cost cleanup, never jobs.
func TestReconcile_SkipsOrphanSweepWithoutAPIReader(t *testing.T) {
	scheme := mustScheme(t)
	const image = "ghcr.io/tuist/tuist-runner@sha256:new"
	pool := newPool("p", image, 1)
	orphan := wedgedOrphanPod("p-runner-orphan", image, "p", "mini-released")

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, newNode("mini-live"), orphan).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	if err := c.Get(context.Background(), nn("tuist-runners", "p-runner-orphan"), &corev1.Pod{}); err != nil {
		t.Fatalf("expected pod to survive a reconciler with no APIReader, got: %v", err)
	}
}

func TestIsOrphaned(t *testing.T) {
	live := map[string]struct{}{"mini-live": {}}

	cases := []struct {
		name     string
		nodeName string
		want     bool
	}{
		{"bound to a live node", "mini-live", false},
		{"bound to a deleted node", "mini-released", true},
		// A Pod the scheduler hasn't placed yet is the normal Pending
		// state for a warm poller, not an orphan.
		{"not yet scheduled", "", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			pod := newRunnerPod("p-runner-x", "img", corev1.PodPending, "p")
			pod.Spec.NodeName = tc.nodeName
			if got := isOrphaned(pod, live); got != tc.want {
				t.Fatalf("isOrphaned(nodeName=%q) = %v, want %v", tc.nodeName, got, tc.want)
			}
		})
	}
}

func podNames(pods []corev1.Pod) []string {
	out := make([]string, len(pods))
	for i, p := range pods {
		out[i] = p.Name
	}
	return out
}

func TestOldestPendingAgeTracksTheOldest(t *testing.T) {
	now := time.Date(2026, 7, 17, 3, 0, 0, 0, time.UTC)

	newest := newRunnerPod("p-newest", "img", corev1.PodPending, "p")
	newest.CreationTimestamp = metav1.NewTime(now.Add(-30 * time.Second))
	oldest := newRunnerPod("p-oldest", "img", corev1.PodPending, "p")
	oldest.CreationTimestamp = metav1.NewTime(now.Add(-4 * time.Hour))
	running := newRunnerPod("p-running", "img", corev1.PodRunning, "p")
	running.CreationTimestamp = metav1.NewTime(now.Add(-8 * time.Hour))

	counts := podPhaseReplicaCounts{}
	counts.add(newest)
	counts.add(oldest)
	// A Pod that booted long ago is not waiting on anything, so its age
	// must not leak into the gauge.
	counts.add(running)

	if got := counts.oldestPendingAge(now); got != 4*time.Hour {
		t.Fatalf("oldest pending age = %v, want 4h", got)
	}

	// Reaping the oldest has to reveal the next-oldest. A running max
	// would keep reporting 4h here.
	counts.remove(oldest)
	if got := counts.oldestPendingAge(now); got != 30*time.Second {
		t.Fatalf("oldest pending age after reaping the oldest = %v, want 30s", got)
	}

	counts.remove(newest)
	if got := counts.oldestPendingAge(now); got != 0 {
		t.Fatalf("oldest pending age with nothing pending = %v, want 0", got)
	}
}

func TestOldestPendingAgeEmpty(t *testing.T) {
	counts := podPhaseReplicaCounts{}
	if got := counts.oldestPendingAge(time.Now()); got != 0 {
		t.Fatalf("oldest pending age on an empty pool = %v, want 0", got)
	}
}

// oldestPendingGauge reads the published gauge out of the shared
// controller-runtime registry: the metric is unexported in its own
// package, and the registry is the same surface Prometheus scrapes.
// Returns the value for `pool` and the total number of series.
func oldestPendingGauge(t *testing.T, pool string) (float64, int) {
	t.Helper()
	families, err := ctrlmetrics.Registry.Gather()
	if err != nil {
		t.Fatalf("gather: %v", err)
	}
	var value float64
	var series int
	for _, f := range families {
		if f.GetName() != "tuist_runners_pool_oldest_pending_pod_age_seconds" {
			continue
		}
		series = len(f.GetMetric())
		for _, m := range f.GetMetric() {
			for _, l := range m.GetLabel() {
				if l.GetName() == "pool" && l.GetValue() == pool {
					value = m.GetGauge().GetValue()
				}
			}
		}
	}
	return value, series
}

// A Linux warm-standby Pod runs its dispatch poller as an init container,
// and kubelet holds a Pod in Pending for as long as any init container
// runs — so an idle Linux runner reports Pending for hours by design.
// Publishing the un-booted age for Linux would peg every idle pool at its
// warm-pool age and read as wedged. Tart pools have no such state.
func TestOldestPendingPodAgeIsDarwinOnly(t *testing.T) {
	now := time.Date(2026, 7, 17, 3, 0, 0, 0, time.UTC)

	for _, tc := range []struct {
		os         string
		pool       string
		wantAge    float64
		wantSeries int
	}{
		{os: "darwin", pool: "p-darwin", wantAge: 3600, wantSeries: 1},
		{os: "linux", pool: "p-linux", wantAge: 0, wantSeries: 0},
	} {
		t.Run(tc.os, func(t *testing.T) {
			metrics.ClearRunnerPool(tc.pool)
			t.Cleanup(func() { metrics.ClearRunnerPool(tc.pool) })

			scheme := mustScheme(t)
			pool := newPool(tc.pool, "img", 1)
			pool.Spec.OS = tc.os

			pending := newRunnerPod(tc.pool+"-runner-a", "img", corev1.PodPending, tc.pool)
			pending.CreationTimestamp = metav1.NewTime(now.Add(-time.Hour))

			c := fake.NewClientBuilder().
				WithScheme(scheme).
				WithObjects(pool, pending).
				WithStatusSubresource(&tuistv1.RunnerPool{}).
				Build()

			r := &RunnerPoolReconciler{
				Client:      c,
				Scheme:      scheme,
				DispatchURL: "http://dispatch",
				Now:         func() time.Time { return now },
			}
			if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn(pool.Namespace, pool.Name)}); err != nil {
				t.Fatalf("reconcile: %v", err)
			}

			gotAge, gotSeries := oldestPendingGauge(t, tc.pool)
			if gotAge != tc.wantAge {
				t.Errorf("%s pool oldest pending age = %v, want %v", tc.os, gotAge, tc.wantAge)
			}
			if gotSeries != tc.wantSeries {
				t.Errorf("%s pool published %d series, want %d", tc.os, gotSeries, tc.wantSeries)
			}
		})
	}
}
