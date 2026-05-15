package controllers

import (
	"context"
	"fmt"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

// machineDeploymentGVK is the CAPI MachineDeployment type the
// autoscaler patches in the management cluster. We use unstructured
// here rather than pulling the full `sigs.k8s.io/cluster-api` module
// (heavy) just to read/write `spec.replicas` (int32) and match on
// two labels.
var machineDeploymentGVK = schema.GroupVersionKind{
	Group:   "cluster.x-k8s.io",
	Version: "v1beta1",
	Kind:    "MachineDeployment",
}

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

	// MgmtClient, when non-nil, is a client.Client against the
	// management cluster's API (the one running CAPI controllers and
	// holding the `MachineDeployment` CRs). When a RunnerPool has
	// `spec.autoscaling.machineDeployment` set the reconciler also
	// patches the bound MD's `spec.replicas` here. nil disables the
	// MD-scaling path; pools that reference an MD log a warning and
	// the RunnerPool scaling still proceeds.
	MgmtClient client.Client

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

	// Sync the bound CAPI MachineDeployment's spec.replicas (in the
	// management cluster) to the value we just locked in on the
	// RunnerPool. Idempotent on equality, so a no-op reconcile still
	// nudges drift back. RunnerPool scaling already succeeded above;
	// MD scaling failure is non-fatal and retried on the next tick.
	//
	// Order matters on scale-down: RunnerPool first (idle Pods get
	// deleted by RunnerPoolReconciler), MD second (CAPI drains the
	// now-empty node and releases the cloud server). On scale-up the
	// order is harmless — Pods schedule Pending until the new node
	// joins.
	if pool.Spec.Autoscaling.MachineDeployment != nil {
		if r.MgmtClient == nil {
			logger.V(1).Info("MachineDeployment ref set but management-cluster kubeconfig is not configured; skipping MD scaling")
		} else if err := r.scaleMachineDeployment(ctx, pool, desired); err != nil {
			logger.Error(err, "scale MachineDeployment; leaving MD replicas unchanged",
				"clusterName", pool.Spec.Autoscaling.MachineDeployment.ClusterName,
				"deploymentName", pool.Spec.Autoscaling.MachineDeployment.DeploymentName)
		}
	}

	return ctrl.Result{RequeueAfter: r.pollInterval()}, nil
}

// scaleMachineDeployment patches the bound CAPI MachineDeployment's
// `spec.replicas` in the management cluster. Uses unstructured to
// avoid pulling the full `sigs.k8s.io/cluster-api` module (heavy)
// just to set one int field.
func (r *AutoscalerReconciler) scaleMachineDeployment(ctx context.Context, pool *tuistv1.RunnerPool, desired int32) error {
	ref := pool.Spec.Autoscaling.MachineDeployment

	mdList := &unstructured.UnstructuredList{}
	mdList.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   machineDeploymentGVK.Group,
		Version: machineDeploymentGVK.Version,
		Kind:    machineDeploymentGVK.Kind + "List",
	})
	if err := r.MgmtClient.List(ctx, mdList,
		client.InNamespace(ref.Namespace),
		client.MatchingLabels{
			"cluster.x-k8s.io/cluster-name":             ref.ClusterName,
			"topology.cluster.x-k8s.io/deployment-name": ref.DeploymentName,
		}); err != nil {
		return fmt.Errorf("list MachineDeployments: %w", err)
	}

	if len(mdList.Items) == 0 {
		return fmt.Errorf("no MachineDeployment matches cluster=%s deployment=%s in %s",
			ref.ClusterName, ref.DeploymentName, ref.Namespace)
	}
	if len(mdList.Items) > 1 {
		// Ambiguous match — refuse to act. The CAPI topology should
		// render exactly one MD per (cluster-name, deployment-name)
		// pair; more than one means a topology bug we shouldn't paper
		// over with an arbitrary pick.
		names := make([]string, 0, len(mdList.Items))
		for i := range mdList.Items {
			names = append(names, mdList.Items[i].GetName())
		}
		return fmt.Errorf("ambiguous MachineDeployment match (%d found): %v", len(mdList.Items), names)
	}

	md := &mdList.Items[0]
	currentReplicas, found, err := unstructured.NestedInt64(md.Object, "spec", "replicas")
	if err != nil {
		return fmt.Errorf("read MD spec.replicas: %w", err)
	}
	desired64 := int64(desired)
	if found && currentReplicas == desired64 {
		return nil
	}

	original := md.DeepCopy()
	if err := unstructured.SetNestedField(md.Object, desired64, "spec", "replicas"); err != nil {
		return fmt.Errorf("set MD spec.replicas: %w", err)
	}
	if err := r.MgmtClient.Patch(ctx, md, client.MergeFrom(original)); err != nil {
		return fmt.Errorf("patch MD: %w", err)
	}

	return nil
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
