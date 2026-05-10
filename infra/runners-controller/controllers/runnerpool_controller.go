// Package controllers contains the reconcilers for the Tuist
// runner-pool CRDs.
package controllers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

// RunnerPoolReconciler keeps a pool's pre-bound RunnerAssignment
// count at MinWarm. Each assignment gets a Pod + ServiceAccount
// from the assignment-side reconciler; this controller only
// creates / counts assignments. Splitting MinWarm-maintenance
// from Pod-creation keeps each reconcile loop small + idempotent.
type RunnerPoolReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=tuist.dev,resources=runnerpools,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=tuist.dev,resources=runnerpools/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=tuist.dev,resources=runnerassignments,verbs=get;list;watch;create;delete

func (r *RunnerPoolReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("pool", req.NamespacedName)

	pool := &tuistv1.RunnerPool{}
	if err := r.Get(ctx, req.NamespacedName, pool); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// Count pre-bound assignments owned by this pool. Burst
	// assignments don't count toward MinWarm — they're transient
	// responses to a queued workflow_job and should expire with
	// the Pod, not constrain pool sizing.
	list := &tuistv1.RunnerAssignmentList{}
	if err := r.List(ctx, list, client.InNamespace(pool.Namespace)); err != nil {
		return ctrl.Result{}, fmt.Errorf("list assignments: %w", err)
	}

	alive := 0
	for _, a := range list.Items {
		if a.Spec.PoolRef.Name != pool.Name {
			continue
		}
		if a.Spec.Trigger != tuistv1.TriggerPreBound {
			continue
		}
		if a.Status.Phase == tuistv1.PhaseTerminated {
			continue
		}
		if !a.DeletionTimestamp.IsZero() {
			continue
		}
		alive++
	}

	gap := int(pool.Spec.MinWarm) - alive
	if gap < 0 {
		gap = 0
	}

	logger.Info("reconcile",
		"target", pool.Spec.MinWarm,
		"observed", alive,
		"gap", gap,
	)

	for i := 0; i < gap; i++ {
		if err := r.createAssignment(ctx, pool); err != nil {
			logger.Error(err, "create assignment; will retry")
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
	}

	pool.Status.ObservedReplicas = int32(alive + gap)
	pool.Status.LastReconcile = metav1.Now()
	if err := r.Status().Update(ctx, pool); err != nil {
		// Conflict / not-found are normal during rapid churn;
		// the next reconcile picks up where we left off.
		if !apierrors.IsConflict(err) && !apierrors.IsNotFound(err) {
			return ctrl.Result{}, fmt.Errorf("status update: %w", err)
		}
	}

	// Steady-state requeue: re-run every 60 s as a safety net for
	// missed events (assignment delete watch glitches, status
	// drift, etc.). Pod-event-driven reconcile via the GC watcher
	// is the primary trigger; this is the catch-all.
	return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
}

func (r *RunnerPoolReconciler) createAssignment(ctx context.Context, pool *tuistv1.RunnerPool) error {
	suffix, err := randHex(4)
	if err != nil {
		return fmt.Errorf("generate suffix: %w", err)
	}
	assignment := &tuistv1.RunnerAssignment{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:    pool.Namespace,
			GenerateName: fmt.Sprintf("%s-prebound-", pool.Name),
			Labels: map[string]string{
				"tuist.dev/runner-pool":       pool.Name,
				"tuist.dev/runner-pool-owner": pool.Spec.Owner,
			},
			Annotations: map[string]string{
				// Suffix as an annotation so we can recognise the
				// assignment later when filing names against logs.
				"tuist.dev/assignment-suffix": suffix,
			},
		},
		Spec: tuistv1.RunnerAssignmentSpec{
			PoolRef: corev1LocalRef(pool.Name),
			Trigger: tuistv1.TriggerPreBound,
		},
	}

	// OwnerReference: pool owns the assignment, so deleting the
	// pool cascades. The assignment in turn owns its Pod + SA
	// (set by the assignment reconciler), so deleting the pool
	// reaps everything.
	if err := controllerutil.SetControllerReference(pool, assignment, r.Scheme); err != nil {
		return fmt.Errorf("set owner ref: %w", err)
	}
	return r.Create(ctx, assignment)
}

func (r *RunnerPoolReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&tuistv1.RunnerPool{}).
		Owns(&tuistv1.RunnerAssignment{}, builder.MatchEveryOwner).
		Complete(r)
}

func randHex(n int) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}
