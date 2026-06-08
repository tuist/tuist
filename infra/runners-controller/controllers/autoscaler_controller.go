package controllers

import (
	"context"
	"fmt"
	"time"

	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

// fleetNodePoolLabel is the node label Linux runner Pods select on
// (`node.cluster.x-k8s.io/pool=<FleetSelector>`). Summing allocatable
// memory across nodes carrying this label for a pool's FleetSelector
// gives the memory budget the pool's shapes compete for.
const fleetNodePoolLabel = "node.cluster.x-k8s.io/pool"

// macosFleetLabel + macosNodeOSLabel identify the Mac mini hosts
// claimed by a macOS RunnerPool's fleetSelector. tuist.dev/fleet is
// stamped by the runners-fleet's MachineDeployment (and matched by
// the macOS runner Pods' nodeSelector); kubernetes.io/os=darwin
// filters out any cross-OS noise. Counting these nodes gives the
// host-slot budget the macOS Xcode pools compete for — one VM per
// Mac mini under the Virtualization.framework SLA.
const (
	macosFleetLabel   = "tuist.dev/fleet"
	macosNodeOSLabel  = "kubernetes.io/os"
	macosNodeOSDarwin = "darwin"
)

// defaultMemReserveFraction is the share of a node pool's allocatable
// memory kept usable for runner Pods. The remainder is slack for
// system DaemonSets (Cilium, kube-proxy replacement, node-exporter)
// and kata per-sandbox overhead that doesn't show up in Pod requests.
const defaultMemReserveFraction = 0.90

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
//
// Pod-level only. Bare-metal Host count (the CAPI MachineDeployment
// replicas) stays operator-managed via the cluster topology because
// Hetzner Robot hosts are monthly-billed and can't be auto-ordered.
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

	// MemReserveFraction is the share of a Linux node pool's
	// allocatable memory the fleet allocator may hand to runner Pods.
	// Defaults to defaultMemReserveFraction. 0 (unset) uses the
	// default; set explicitly in tests.
	MemReserveFraction float64
}

// +kubebuilder:rbac:groups=tuist.dev,resources=runnerpools,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=tuist.dev,resources=runnerpools/status,verbs=get;update;patch
// +kubebuilder:rbac:groups="",resources=nodes,verbs=get;list;watch

func (r *AutoscalerReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("autoscaler", req.NamespacedName)

	pool := &tuistv1.RunnerPool{}
	if err := r.Get(ctx, req.NamespacedName, pool); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	if !pool.DeletionTimestamp.IsZero() {
		// Pool is being drained by the RunnerPoolReconciler's
		// finalizer. Don't patch replicas on a Terminating CR, and
		// don't requeue — the drain owns its lifecycle from here.
		return ctrl.Result{}, nil
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
	desired := r.desiredForPool(ctx, pool, *signals, knobs, logger)

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

// desiredForPool computes the target replica count for `pool`.
//
// Pools with autoscaling-disabled `maxReplicas` keep the simple
// per-pool policy. Everything else runs through the fleet allocator,
// which apportions a shared capacity budget across sibling pools and
// squeezes idle pools' speculative warm buffers before another pool's
// real queued work. The budget unit depends on OS:
//
//   - Linux pools share a bare-metal node pool, contending for
//     memory; budget = sum of allocatable memory bytes across the
//     fleet's nodes.
//   - macOS pools share a Mac mini fleet; each Pod claims a whole
//     host (Apple's Virtualization.framework SLA caps at 2 VMs/host
//     and we run 1 today), so budget = host count.
//
// Any failure gathering the fleet view falls back to the per-pool
// target — a node-read blip must never trigger a mass scale-down.
func (r *AutoscalerReconciler) desiredForPool(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	signals scaling.Signals,
	knobs scaling.PolicyKnobs,
	logger logr.Logger,
) int32 {
	perPool := scaling.DesiredReplicas(signals, knobs)

	if knobs.MaxReplicas <= 0 {
		return perPool
	}

	demands, err := r.gatherFleetDemands(ctx, pool, signals, knobs)
	if err != nil {
		logger.Error(err, "gather fleet demands; falling back to per-pool target",
			"fleetSelector", pool.Spec.FleetSelector)
		return perPool
	}

	// capacity <= 0 is treated like an error on purpose. A zero sum is
	// almost always a transient empty node-list read (informer cache
	// blip, or no Ready nodes mid-roll), not a genuine "fleet has no
	// capacity" state. Routing it into AllocateFleet would squeeze every
	// pool's floor to zero and reap their warm Pods fleet-wide, the exact
	// blip-driven mass scale-down this per-pool fallback exists to
	// prevent. AllocateFleet's own zero-capacity contract (see its unit
	// test) is therefore never exercised from here.
	capacity, err := r.fleetCapacity(ctx, pool)
	if err != nil || capacity <= 0 {
		logger.Error(err, "read fleet capacity; falling back to per-pool target",
			"fleetSelector", pool.Spec.FleetSelector, "os", pool.Spec.OS)
		return perPool
	}

	alloc := scaling.AllocateFleet(demands, capacity)
	if v, ok := alloc[pool.Name]; ok {
		return v
	}
	return perPool
}

// fleetCapacity returns the shared budget `pool` competes for with
// its siblings, in the same unit AllocateFleet expects PerPodCost
// to be expressed in (memory bytes for Linux, host slots for macOS).
// An unrecognised OS returns (0, nil), which trips the per-pool
// fallback in desiredForPool without an error log — pools without a
// known OS quietly skip the allocator.
func (r *AutoscalerReconciler) fleetCapacity(ctx context.Context, pool *tuistv1.RunnerPool) (int64, error) {
	switch pool.Spec.OS {
	case "linux":
		return r.fleetAllocatableMemory(ctx, pool.Spec.FleetSelector)
	case "darwin":
		return r.fleetHostCount(ctx, pool.Spec.FleetSelector)
	default:
		return 0, nil
	}
}

// perPodCost is one Pod's claim on the shared fleet budget, in the
// same unit as fleetCapacity returns above.
func perPodCost(pool *tuistv1.RunnerPool) int64 {
	if pool.Spec.OS == "darwin" {
		// One Mac mini = one slot = one VM.
		return 1
	}
	return int64(pool.Spec.PodMemoryMB) * 1024 * 1024
}

// gatherFleetDemands builds the allocator input for every
// autoscaling-enabled sibling pool sharing `pool`'s OS and
// FleetSelector (the set contending for the same capacity domain).
// Pools of a different OS are excluded — Linux memory bytes and
// macOS host slots aren't commensurable units in one
// AllocateFleet call. The reconciled pool reuses the signals
// already fetched this tick; siblings get a fresh fetch.
func (r *AutoscalerReconciler) gatherFleetDemands(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	signals scaling.Signals,
	knobs scaling.PolicyKnobs,
) ([]scaling.PoolDemand, error) {
	var pools tuistv1.RunnerPoolList
	if err := r.List(ctx, &pools, client.InNamespace(pool.Namespace)); err != nil {
		return nil, fmt.Errorf("list runner pools: %w", err)
	}

	var demands []scaling.PoolDemand
	for i := range pools.Items {
		p := &pools.Items[i]
		if p.Spec.OS != pool.Spec.OS || p.Spec.FleetSelector != pool.Spec.FleetSelector {
			continue
		}
		if p.Spec.Autoscaling == nil || !p.Spec.Autoscaling.Enabled || p.Spec.Autoscaling.MaxReplicas <= 0 {
			continue
		}

		sig := signals
		k := knobs
		if p.Name != pool.Name {
			fetched, err := r.SignalsClient.Signals(ctx, p.Name)
			if err != nil {
				return nil, fmt.Errorf("signals for sibling %q: %w", p.Name, err)
			}
			sig = *fetched
			k = scaling.PolicyKnobs{
				MinWarmPoolFloor: p.Spec.Autoscaling.MinWarmPoolFloor,
				MaxReplicas:      p.Spec.Autoscaling.MaxReplicas,
			}
		}

		demands = append(demands, scaling.PoolDemand{
			Name:       p.Name,
			PerPodCost: perPodCost(p),
			Floor:      k.MinWarmPoolFloor,
			Load:       sig.Claimed + sig.Queued,
			Target:     scaling.DesiredReplicas(sig, k),
		})
	}

	return demands, nil
}

// fleetAllocatableMemory sums allocatable memory across nodes in the
// `fleetSelector` bare-metal pool, scaled by the reserve fraction.
func (r *AutoscalerReconciler) fleetAllocatableMemory(ctx context.Context, fleetSelector string) (int64, error) {
	var nodes corev1.NodeList
	if err := r.List(ctx, &nodes, client.MatchingLabels{fleetNodePoolLabel: fleetSelector}); err != nil {
		return 0, fmt.Errorf("list fleet nodes: %w", err)
	}

	var total int64
	for i := range nodes.Items {
		if mem := nodes.Items[i].Status.Allocatable.Memory(); mem != nil {
			total += mem.Value()
		}
	}

	reserve := r.MemReserveFraction
	if reserve <= 0 {
		reserve = defaultMemReserveFraction
	}
	return int64(float64(total) * reserve), nil
}

// fleetHostCount counts Mac mini nodes claimed by `fleetSelector`.
// Each host is one schedulable slot (one VM per Mac mini), so the
// returned int64 is the macOS pool family's slot budget. Tracks the
// actually-Ready host count — a host being CAPI-rolled drops out of
// the result, and the per-pool fallback in desiredForPool keeps the
// pool at its current size through the blip.
func (r *AutoscalerReconciler) fleetHostCount(ctx context.Context, fleetSelector string) (int64, error) {
	var nodes corev1.NodeList
	if err := r.List(ctx, &nodes, client.MatchingLabels{
		macosFleetLabel:  fleetSelector,
		macosNodeOSLabel: macosNodeOSDarwin,
	}); err != nil {
		return 0, fmt.Errorf("list macOS fleet nodes: %w", err)
	}
	return int64(len(nodes.Items)), nil
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
