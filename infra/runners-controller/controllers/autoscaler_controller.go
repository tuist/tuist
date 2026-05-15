package controllers

import (
	"context"
	"fmt"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

// AutoscalerReconciler reconciles autoscaling-enabled RunnerPools.
// On a 5-second cadence (RequeueAfter), it:
//
//  1. fetches load signals from the Tuist server for the pool's
//     fleet name,
//  2. computes the desired replicas using the pool's policy knobs
//     (`spec.autoscaling.minWarmPoolFloor` / `maxReplicas`),
//  3. patches `spec.replicas` to the new value when it changes, and
//  4. stamps `status.lastScaleDownAt` on scale-down so the
//     cooldown gate fires next time.
//
// Pod count convergence is the RunnerPoolReconciler's job — this
// reconciler only adjusts the target. Decoupling lets each handle
// what it's best at: this one polls + does policy math; the other
// one watches the cluster and converges Pods.
type AutoscalerReconciler struct {
	client.Client
	Scheme *runtime.Scheme

	// SignalsClient fetches load signals from the Tuist server.
	// Injected so tests can stand up an httptest.Server without
	// reaching for in-cluster machinery.
	SignalsClient *scaling.Client

	// PollInterval is the RequeueAfter for autoscaling-enabled
	// pools. Default 5s — fast enough that a queued workflow_job
	// lands on a freshly scaled Pod within one tick, low enough on
	// server load (one signals query per pool per tick) that it
	// disappears under the dispatch-poll traffic. Tests override
	// to milliseconds to keep them fast.
	PollInterval time.Duration

	// Now defaults to time.Now; overridable for deterministic
	// cooldown tests.
	Now func() time.Time
}

// +kubebuilder:rbac:groups=tuist.dev,resources=runnerpools,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=tuist.dev,resources=runnerpools/status,verbs=get;update;patch

func (r *AutoscalerReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("autoscaler", req.NamespacedName)

	pool := &tuistv1.RunnerPool{}
	if err := r.Get(ctx, req.NamespacedName, pool); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	if pool.Spec.Autoscaling == nil || !pool.Spec.Autoscaling.Enabled {
		// Pool opted out (or never opted in) — don't requeue.
		// A future patch that flips `enabled` true will trigger
		// a fresh reconcile via the For() watch.
		return ctrl.Result{}, nil
	}

	signals, err := r.SignalsClient.Signals(ctx, pool.Name)
	if err != nil {
		// Server unreachable or returned a non-200. Anti-thrash:
		// do NOT change replicas on a transient error — leave the
		// pool at its current size and retry on the next poll.
		// The controller's primary RunnerPoolReconciler keeps the
		// existing Pod count alive in the meantime.
		logger.Error(err, "fetch scaling signals; leaving replicas unchanged")
		return ctrl.Result{RequeueAfter: r.pollInterval()}, nil
	}

	knobs := scaling.PolicyKnobs{
		MinWarmPoolFloor: pool.Spec.Autoscaling.MinWarmPoolFloor,
		MaxReplicas:      pool.Spec.Autoscaling.MaxReplicas,
	}
	desired := scaling.DesiredReplicas(*signals, knobs)

	current := pool.Spec.Replicas
	now := r.now()

	switch {
	case desired == current:
		// Steady state — no patch needed.
	case desired > current:
		// Scale up. No cooldown — we want fresh capacity as fast
		// as possible.
		if err := r.applyReplicas(ctx, pool, desired); err != nil {
			return ctrl.Result{}, fmt.Errorf("scale up: %w", err)
		}
		logger.Info("scaled up", "from", current, "to", desired,
			"signals", signals, "minWarm", knobs.MinWarmPoolFloor)
	default:
		// desired < current — scale down candidate. Cooldown gate
		// stops us from oscillating: a single brief idle window
		// shouldn't drop warm capacity that's about to be reused.
		cooldown := time.Duration(pool.Spec.Autoscaling.ScaleDownCooldownSeconds) * time.Second
		if cooldown < 0 {
			cooldown = 0
		}
		if pool.Status.LastScaleDownAt != nil {
			elapsed := now.Sub(pool.Status.LastScaleDownAt.Time)
			if elapsed < cooldown {
				logger.V(1).Info("scale-down deferred by cooldown",
					"elapsed", elapsed.String(),
					"cooldown", cooldown.String(),
					"from", current, "to", desired)
				return ctrl.Result{RequeueAfter: r.pollInterval()}, nil
			}
		}

		if err := r.applyReplicas(ctx, pool, desired); err != nil {
			return ctrl.Result{}, fmt.Errorf("scale down: %w", err)
		}

		// Refresh after the spec patch so the status update has
		// the right resourceVersion.
		if err := r.Get(ctx, req.NamespacedName, pool); err != nil {
			return ctrl.Result{}, fmt.Errorf("get pool after scale-down patch: %w", err)
		}
		ts := metav1.NewTime(now)
		pool.Status.LastScaleDownAt = &ts
		if err := r.Status().Update(ctx, pool); err != nil {
			if !apierrors.IsConflict(err) && !apierrors.IsNotFound(err) {
				return ctrl.Result{}, fmt.Errorf("stamp lastScaleDownAt: %w", err)
			}
		}
		logger.Info("scaled down", "from", current, "to", desired,
			"signals", signals, "minWarm", knobs.MinWarmPoolFloor)
	}

	return ctrl.Result{RequeueAfter: r.pollInterval()}, nil
}

func (r *AutoscalerReconciler) applyReplicas(ctx context.Context, pool *tuistv1.RunnerPool, desired int32) error {
	original := pool.DeepCopy()
	pool.Spec.Replicas = desired
	return r.Patch(ctx, pool, client.MergeFrom(original))
}

func (r *AutoscalerReconciler) pollInterval() time.Duration {
	if r.PollInterval > 0 {
		return r.PollInterval
	}
	return 5 * time.Second
}

func (r *AutoscalerReconciler) now() time.Time {
	if r.Now != nil {
		return r.Now()
	}
	return time.Now()
}

func (r *AutoscalerReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		// Different controller name so it doesn't collide with
		// the RunnerPoolReconciler — both watch the same For()
		// type but maintain independent workqueues.
		Named("autoscaler").
		For(&tuistv1.RunnerPool{}).
		Complete(r)
}
