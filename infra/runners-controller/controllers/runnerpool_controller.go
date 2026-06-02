// Package controllers contains the reconcilers for the Tuist
// runner-pool CRD.
package controllers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
)

// RunnerPoolReconciler maintains a fleet of runner Pods + per-Pod
// ServiceAccounts. Pods are owned directly by the RunnerPool (no
// RunnerAssignment intermediate). When a Pod hits a terminal
// phase, the reconciler creates a replacement on whichever host
// the previous Pod freed.
type RunnerPoolReconciler struct {
	client.Client
	Scheme *runtime.Scheme

	// DispatchURL is the customer-server's runner dispatch endpoint
	// threaded into every Pod via env. Set from the manager's
	// --dispatch-url flag. Used as-is for macOS pools (Tart VMs
	// bypass CNI and reach the public ingress via vmnet/NAT).
	DispatchURL string

	// DispatchInternalURL is the in-cluster (Service-based)
	// dispatch endpoint, used for Linux pools whose Pods live on
	// the cluster's CNI and can't reach the public ingress IP
	// from inside (Hetzner Cloud LB has no hairpin). Optional;
	// when empty, Linux pools fall back to DispatchURL — which
	// will silently fail to reach the server in the hairpin case.
	DispatchInternalURL string

	// DindImage is the OCI ref for the dockerd sidecar stamped on
	// Linux runner Pods. The chart pins it; Renovate keeps it
	// bumped. Empty means Linux pods skip the sidecar — fine for
	// macOS-only installs.
	DindImage string
}

// +kubebuilder:rbac:groups=tuist.dev,resources=runnerpools,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=tuist.dev,resources=runnerpools/status,verbs=get;update;patch
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch;create;delete
// +kubebuilder:rbac:groups="",resources=serviceaccounts,verbs=get;list;watch;create;delete

func (r *RunnerPoolReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("pool", req.NamespacedName)

	pool := &tuistv1.RunnerPool{}
	if err := r.Get(ctx, req.NamespacedName, pool); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// Track image rolls. The server-side drain endpoint reads
	// `status.imageRolledAt` and gates HTTP 410 on a per-Pod time
	// slot derived from the Pod name, so stale Pods halt in waves
	// rather than all on the first poll after a digest-pin bump.
	// Setting on first reconcile (when `ObservedImage` is empty) is
	// fine — there are no stale Pods yet, and the timestamp just
	// establishes the t=0 baseline for any future roll.
	if pool.Status.ObservedImage != pool.Spec.Image {
		pool.Status.ObservedImage = pool.Spec.Image
		pool.Status.ImageRolledAt = metav1.Now()
	}

	// Count Pods owned by this pool that are alive (not in a
	// terminal phase, not being deleted). Terminal Pods aren't
	// counted toward `replicas` — they're on their way out and a
	// replacement is needed.
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods,
		client.InNamespace(pool.Namespace),
		client.MatchingLabels{"tuist.dev/runner-pool": pool.Name},
	); err != nil {
		return ctrl.Result{}, fmt.Errorf("list pods: %w", err)
	}

	alive := 0
	reaped := 0
	staleDeleted := 0
	var idleAlive []*corev1.Pod
	for i := range pods.Items {
		p := &pods.Items[i]

		// Drop stale Pending Pods immediately so the gap-fill below
		// can create replacements on the current spec.image. Stale
		// here means the Pod's image differs from the RunnerPool's,
		// which happens whenever `runnerImage` in the chart rolls
		// to a new digest. Pending is the safe phase to delete: the
		// VM isn't running a customer job yet (and may never get
		// scheduled, since the controller's gap math fills replicas
		// based on alive count). Running stale Pods are left alone —
		// they may be mid-job, and single-shot lifecycle will turn
		// them over to Succeeded on exit, where the reap path below
		// replaces them with a current-image Pod.
		//
		// Idle Running stale Pods are picked up by the server-side
		// drain signal in Tuist.Runners.dispatch_for_sa: on the next
		// idle poll, the server compares the Pod's image to the
		// RunnerPool's and returns HTTP 410, which the in-VM
		// dispatch-poll script treats as a clean-exit. The reap
		// path then replaces the Pod with a current-image one.
		// In-flight customer jobs aren't disrupted because the 410
		// check fires only on idle polls (before claim).
		if isAlive(p) && p.Status.Phase == corev1.PodPending && isStaleImage(p, pool) {
			// Reuse the reap path so the sibling SA goes with the
			// Pod. Pod and SA are owned by the RunnerPool as
			// siblings (not parent/child), so deleting the Pod
			// alone leaves the SA behind to accumulate on every
			// image roll.
			if err := r.reapRunner(ctx, p); err != nil {
				logger.Error(err, "delete stale pending pod; will retry", "pod", p.Name)
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			staleDeleted++
			continue
		}

		switch {
		case isAlive(p):
			alive++
			if isIdle(p) {
				idleAlive = append(idleAlive, p)
			}
		case p.DeletionTimestamp.IsZero():
			// Terminal Pod (Succeeded/Failed) with no deletion in
			// flight. Reap the Pod and its sibling ServiceAccount.
			// Without explicit cleanup the namespace fills with
			// stopped Pods + orphaned SAs, and the projected-token
			// cache in tart-kubelet keeps re-validating SAs whose
			// Pods are already gone.
			if err := r.reapRunner(ctx, p); err != nil {
				logger.Error(err, "reap terminal runner; will retry", "pod", p.Name)
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			reaped++
		}
	}

	gap := int(pool.Spec.Replicas) - alive
	overflow := 0
	if gap < 0 {
		overflow = -gap
		gap = 0
	}

	logger.Info("reconcile",
		"target", pool.Spec.Replicas,
		"observed", alive,
		"reaped", reaped,
		"staleDeleted", staleDeleted,
		"gap", gap,
		"overflow", overflow,
		"idleAlive", len(idleAlive),
	)

	for i := 0; i < gap; i++ {
		if err := r.createRunner(ctx, pool); err != nil {
			logger.Error(err, "create runner; will retry")
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
	}

	// Scale-down: alive > target. Delete IDLE Pods first — those
	// without `tuist.dev/runner-pool-owner` are warm-polling and
	// not currently running a customer job, so terminating them is
	// safe. Owned Pods (currently running a job) are never deleted
	// by the reconciler; the autoscaler's targets must be reached
	// over time, as owned Pods finish their jobs and exit.
	scaledDown := 0
	for i := 0; i < overflow && i < len(idleAlive); i++ {
		p := idleAlive[i]
		if err := r.reapAlivePod(ctx, p); err != nil {
			logger.Error(err, "scale-down delete; will retry", "pod", p.Name)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		scaledDown++
	}

	observed := alive - scaledDown + gap
	pool.Status.ObservedReplicas = int32(observed)
	pool.Status.LastReconcile = metav1.Now()
	if err := r.Status().Update(ctx, pool); err != nil {
		if !apierrors.IsConflict(err) && !apierrors.IsNotFound(err) {
			return ctrl.Result{}, fmt.Errorf("status update: %w", err)
		}
	}

	// Steady-state requeue: re-run every 60 s as a safety net for
	// missed events. Pod-event-driven reconcile via Owns() is the
	// primary trigger; this is the catch-all.
	return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
}

// createRunner provisions one Pod + per-Pod ServiceAccount pair,
// both owned by the RunnerPool. Pod and SA share the same name so
// the dispatch endpoint can look up "which Pod is this SA mounted
// on" from the validated SA name alone.
func (r *RunnerPoolReconciler) createRunner(ctx context.Context, pool *tuistv1.RunnerPool) error {
	suffix, err := randHex(4)
	if err != nil {
		return fmt.Errorf("generate suffix: %w", err)
	}
	name := fmt.Sprintf("%s-runner-%s", pool.Name, suffix)

	sa := podtemplate.BuildServiceAccount(pool, name)
	if err := controllerutil.SetControllerReference(pool, sa, r.Scheme); err != nil {
		return fmt.Errorf("sa owner ref: %w", err)
	}
	if err := r.Create(ctx, sa); err != nil && !apierrors.IsAlreadyExists(err) {
		return fmt.Errorf("create sa: %w", err)
	}

	pod, err := podtemplate.Build(pool, name, name, r.DispatchURL, r.DispatchInternalURL, r.DindImage)
	if err != nil {
		return fmt.Errorf("build pod: %w", err)
	}
	if err := controllerutil.SetControllerReference(pool, pod, r.Scheme); err != nil {
		return fmt.Errorf("pod owner ref: %w", err)
	}
	if err := r.Create(ctx, pod); err != nil && !apierrors.IsAlreadyExists(err) {
		return fmt.Errorf("create pod: %w", err)
	}

	return nil
}

// reapRunner deletes a Pod and its same-named ServiceAccount.
// Both are owned by the RunnerPool as siblings — deleting the
// Pod alone leaves the SA behind. Pod and SA share a name by
// construction (see createRunner), so we issue both deletes by
// name. NotFound on either is treated as success: the goal is
// "nothing left," not "I'm the one that deleted it."
//
// Called for both terminal Pods (Succeeded/Failed → natural
// turnover) and stale Pending Pods (image roll → recycle on
// current image). The cleanup contract is the same.
func (r *RunnerPoolReconciler) reapRunner(ctx context.Context, pod *corev1.Pod) error {
	if err := r.Delete(ctx, pod); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete pod %s: %w", pod.Name, err)
	}
	sa := &corev1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: pod.Namespace,
			Name:      pod.Name,
		},
	}
	if err := r.Delete(ctx, sa); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete sa %s: %w", pod.Name, err)
	}
	return nil
}

// reapAlivePod is the scale-down path. Same shape as
// reapRunner (delete Pod + sibling SA) but we hit it from
// the autoscaler-driven branch where the Pod is still alive and
// merely idle. kubelet handles graceful container shutdown for us
// once Pod.DeletionTimestamp is set.
func (r *RunnerPoolReconciler) reapAlivePod(ctx context.Context, pod *corev1.Pod) error {
	return r.reapRunner(ctx, pod)
}

// isAlive returns true for Pods that should count toward `replicas`:
// not in a terminal phase, not pending deletion.
func isAlive(pod *corev1.Pod) bool {
	if !pod.DeletionTimestamp.IsZero() {
		return false
	}
	switch pod.Status.Phase {
	case corev1.PodSucceeded, corev1.PodFailed:
		return false
	default:
		return true
	}
}

// isIdle returns true for alive Pods that have NOT yet claimed a
// customer's workflow_job. The Tuist server stamps
// `tuist.dev/runner-pool-owner=<account>` on the Pod at the
// moment it claims a queue entry; absent label means the Pod is
// warm-polling. Scale-down deletes idle Pods first so we never
// kill a runner mid-job.
func isIdle(pod *corev1.Pod) bool {
	v, ok := pod.Labels["tuist.dev/runner-pool-owner"]
	return !ok || v == ""
}

// isStaleImage returns true when the Pod's runner container image
// no longer matches the RunnerPool's spec.image — i.e., the chart
// has rolled the image pin since this Pod was created. Used to
// recycle Pending Pods on the next reconcile so a fresh image rolls
// out without an operator-driven `kubectl delete pod` dance.
func isStaleImage(pod *corev1.Pod, pool *tuistv1.RunnerPool) bool {
	if len(pod.Spec.Containers) == 0 {
		return false
	}
	return pod.Spec.Containers[0].Image != pool.Spec.Image
}

// runnerLabelPredicate filters the Pod watch down to Pods carrying
// `tuist.dev/runner=true` so the reconciler isn't woken by
// unrelated Pods that might land in the namespace.
func runnerLabelPredicate() predicate.Predicate {
	return predicate.NewPredicateFuncs(func(obj client.Object) bool {
		v, ok := obj.GetLabels()["tuist.dev/runner"]
		return ok && v == "true"
	})
}

func (r *RunnerPoolReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&tuistv1.RunnerPool{}).
		Owns(&corev1.Pod{}, builder.WithPredicates(runnerLabelPredicate())).
		Owns(&corev1.ServiceAccount{}).
		Complete(r)
}

func randHex(n int) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}
