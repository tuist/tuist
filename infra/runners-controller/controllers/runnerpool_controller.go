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
	// --dispatch-url flag.
	DispatchURL string
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
	for i := range pods.Items {
		p := &pods.Items[i]
		switch {
		case isAlive(p):
			alive++
		case p.DeletionTimestamp.IsZero():
			// Terminal Pod (Succeeded/Failed) with no deletion in
			// flight. Reap the Pod and its sibling ServiceAccount —
			// both are owned by this RunnerPool, but they're
			// siblings (not parent/child), so Pod deletion does not
			// cascade to the SA. Without explicit cleanup the
			// namespace fills with stopped Pods + orphaned SAs,
			// and the projected-token cache in tart-kubelet keeps
			// re-validating SAs whose Pods are already gone.
			if err := r.reapTerminalRunner(ctx, p); err != nil {
				logger.Error(err, "reap terminal runner; will retry", "pod", p.Name)
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			reaped++
		}
	}

	gap := int(pool.Spec.Replicas) - alive
	if gap < 0 {
		gap = 0
	}

	logger.Info("reconcile",
		"target", pool.Spec.Replicas,
		"observed", alive,
		"reaped", reaped,
		"gap", gap,
	)

	for i := 0; i < gap; i++ {
		if err := r.createRunner(ctx, pool); err != nil {
			logger.Error(err, "create runner; will retry")
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
	}

	pool.Status.ObservedReplicas = int32(alive + gap)
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

	pod := podtemplate.Build(pool, name, name, r.DispatchURL)
	if err := controllerutil.SetControllerReference(pool, pod, r.Scheme); err != nil {
		return fmt.Errorf("pod owner ref: %w", err)
	}
	if err := r.Create(ctx, pod); err != nil && !apierrors.IsAlreadyExists(err) {
		return fmt.Errorf("create pod: %w", err)
	}

	return nil
}

// reapTerminalRunner deletes a terminal Pod and its same-named
// ServiceAccount. Both are owned by the RunnerPool as siblings —
// deleting the Pod alone leaves the SA behind. Pod and SA share a
// name by construction (see createRunner), so we issue both
// deletes by name. NotFound on either is treated as success: the
// goal is "nothing left," not "I'm the one that deleted it."
func (r *RunnerPoolReconciler) reapTerminalRunner(ctx context.Context, pod *corev1.Pod) error {
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
