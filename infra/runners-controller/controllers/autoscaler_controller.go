package controllers

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	nodev1 "k8s.io/api/node/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/metrics"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

// fleetNodePoolLabel is the node label Linux runner Pods select on
// (`node.cluster.x-k8s.io/pool=<FleetSelector>`). Summing allocatable
// memory across nodes carrying this label for a pool's FleetSelector
// gives the memory budget the pool's shapes compete for.
const fleetNodePoolLabel = "node.cluster.x-k8s.io/pool"

// macosFleetLabel + nodeOSLabel identify the Mac mini hosts
// claimed by a macOS RunnerPool's fleetSelector. tuist.dev/fleet is
// stamped by the runners-fleet's MachineDeployment (and matched by
// the macOS runner Pods' nodeSelector); kubernetes.io/os=darwin
// filters out any cross-OS noise. Summing what these nodes can
// actually admit gives the slot budget the macOS Xcode pools compete
// for.
//
// nodeOSLabel is not macOS-only: the reservation path pairs it with
// fleetNodePoolLabel to address the Linux fleet's bare-metal hosts.
//
// One fleet label can span several MachineDeployments — that is how a
// mixed-SKU fleet is expressed (M2-L at one guest per host next to
// M4-XL at two), so the node set behind a fleetSelector is NOT
// homogeneous and its capacity is not its cardinality.
const (
	macosFleetLabel   = "tuist.dev/fleet"
	nodeOSLabel       = "kubernetes.io/os"
	macosNodeOSDarwin = "darwin"
)

// defaultMemReserveFraction is the share of a node pool's allocatable
// memory kept usable for runner Pods. The remainder is slack for
// system DaemonSets (Cilium, kube-proxy replacement, node-exporter)
// and kata per-sandbox overhead that doesn't show up in Pod requests.
const defaultMemReserveFraction = 0.90

var errPodCostUnavailable = errors.New("per-Pod cost unavailable")

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
// +kubebuilder:rbac:groups=node.k8s.io,resources=runtimeclasses,verbs=get;list;watch

func (r *AutoscalerReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("autoscaler", req.NamespacedName)

	pool := &tuistv1.RunnerPool{}
	if err := r.Get(ctx, req.NamespacedName, pool); err != nil {
		if apierrors.IsNotFound(err) {
			// Pool is gone — drop its allocation series so the
			// dashboard doesn't keep charting a stale warm deficit.
			metrics.ClearAutoscaler(req.Name)
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	if !pool.DeletionTimestamp.IsZero() {
		// Pool is being drained by the RunnerPoolReconciler's
		// finalizer. Don't patch replicas on a Terminating CR, and
		// don't requeue — the drain owns its lifecycle from here.
		metrics.ClearAutoscaler(pool.Name)
		return ctrl.Result{}, nil
	}

	if pool.Spec.Autoscaling == nil || !pool.Spec.Autoscaling.Enabled {
		// Pool opted out (or never opted in) — don't requeue.
		// A future patch that flips `enabled` true will trigger
		// a fresh reconcile via the For() watch.
		metrics.ClearAutoscaler(pool.Name)
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
		MinWarmPoolFloor: pool.Spec.Autoscaling.MinWarmPoolFloorOrDefault(),
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
		cooldown := time.Duration(pool.Spec.Autoscaling.ScaleDownCooldownSecondsOrDefault()) * time.Second
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
//     fleet's nodes, scaled by a reserve fraction for DaemonSets and
//     kata sandbox overhead.
//   - macOS pools share a Mac mini fleet and contend for the same
//     unit; budget = sum of allocatable memory bytes, unscaled. A
//     Pod's cost is its memory request, so the quotient is the guest
//     count each host admits — 1 on an M2-L, 2 on an M4-XL — which is
//     the same division kube-scheduler performs when it places the
//     Pod.
//
// Fleet-capacity, pool-list, and sibling-signal read failures fall
// back to the per-pool target, preserving the existing anti-thrash
// behavior and allowing queued work to scale up. A RuntimeClass cost
// failure leaves replicas unchanged because scaling without that
// scheduling overhead could overcommit the fleet.
func (r *AutoscalerReconciler) desiredForPool(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	signals scaling.Signals,
	knobs scaling.PolicyKnobs,
	logger logr.Logger,
) int32 {
	perPool := scaling.DesiredReplicas(signals, knobs)
	allocated := r.allocate(ctx, pool, signals, knobs, perPool, logger)

	// Publish the allocation outcome so the warm-pool squeeze (target
	// reaped down to `allocated` under fleet contention) is observable
	// on its own series, not inferred from alive-vs-desired.
	metrics.RecordAllocation(pool.Name, signals.Load(), knobs.MinWarmPoolFloor, perPool, allocated)

	// Publish the demand signals unsummed as well. The allocator only
	// needs occupied+queued, but the split shows both dispatch progress
	// (queued -> claimed) and the post-job tail (claimed -> occupied).
	metrics.RecordDemand(pool.Name, signals.Claimed, signals.CurrentOccupancy(), signals.Queued)

	return allocated
}

// allocate runs the shared-capacity fleet allocator for `pool`,
// returning the (possibly squeezed) replica target. Fleet-view read
// failures fall back to the per-pool target, while an unavailable
// per-Pod scheduling cost leaves replicas unchanged.
func (r *AutoscalerReconciler) allocate(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	signals scaling.Signals,
	knobs scaling.PolicyKnobs,
	perPool int32,
	logger logr.Logger,
) int32 {
	if knobs.MaxReplicas <= 0 {
		return perPool
	}

	demands, shapes, err := r.gatherFleetDemands(ctx, pool, signals, knobs)
	if err != nil {
		if errors.Is(err, errPodCostUnavailable) {
			logger.Error(err, "per-Pod scheduling cost unknown; leaving replicas unchanged",
				"fleetSelector", pool.Spec.FleetSelector)
			return pool.Spec.Replicas
		}
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

	// A cap read failure degrades to the byte budget alone rather than
	// freezing the pool: the budget is never LOWER than the true
	// placeable count, so the worst case is the over-scheduling this cap
	// exists to prevent — which is where the fleet already was.
	shapeCaps, err := r.shapePlacementCaps(ctx, pool, shapes)
	if err != nil {
		logger.Error(err, "read shape placement caps; allocating on the byte budget alone",
			"fleetSelector", pool.Spec.FleetSelector)
	}

	alloc := scaling.AllocateFleet(demands, capacity, shapeCaps)
	if v, ok := alloc[pool.Name]; ok {
		return v
	}
	return perPool
}

// podShape is the placement footprint of one pool's Pod. Two pools with
// the same footprint compete for the same node slots regardless of which
// runner image they carry, which is what makes it the right grouping key
// for a placement cap.
type podShape struct {
	cpuMilli int32
	memoryMB int32
}

func podShapeOf(pool *tuistv1.RunnerPool) podShape {
	return podShape{cpuMilli: pool.Spec.PodCPUMilli, memoryMB: pool.Spec.PodMemoryMB}
}

// placementShapeOf is podShapeOf plus the RuntimeClass overhead the
// scheduler adds at admission, which is the footprint a node is actually
// asked to seat. Under kata a 16 GiB shape costs 18.5 GiB and a 4 vCPU
// shape costs 4.25, so dividing a node's allocatable by the bare shape
// reports seats that do not exist: 117 GiB / 16 GiB is seven where the
// truth is six. Runtimes without overhead (macOS Tart guests) return the
// bare shape unchanged, so both platforms use one definition.
//
// This is also the right grouping key for capByShape: two pools whose
// Pods request the same resources but run under different RuntimeClasses
// do not compete for the same node slots.
func (r *AutoscalerReconciler) placementShapeOf(ctx context.Context, pool *tuistv1.RunnerPool) (podShape, error) {
	shape := podShapeOf(pool)

	overheadCPU, overheadMemory, err := r.runtimeClassOverhead(ctx, pool)
	if err != nil {
		return podShape{}, err
	}
	shape.cpuMilli += int32(overheadCPU)
	shape.memoryMB += int32(overheadMemory / (1024 * 1024))
	return shape, nil
}

// runtimeClassOverhead reads the pool's RuntimeClass podFixed overhead as
// (CPU milli, memory bytes). No RuntimeClass, or one without overhead,
// is zero rather than an error. A RuntimeClass that is named but cannot
// be read IS an error: scaling without known admission overhead
// overcommits the fleet.
func (r *AutoscalerReconciler) runtimeClassOverhead(ctx context.Context, pool *tuistv1.RunnerPool) (int64, int64, error) {
	if pool.Spec.RuntimeClass == "" {
		return 0, 0, nil
	}

	runtimeClass := &nodev1.RuntimeClass{}
	if err := r.Get(ctx, client.ObjectKey{Name: pool.Spec.RuntimeClass}, runtimeClass); err != nil {
		return 0, 0, fmt.Errorf("%w: get RuntimeClass %q: %w", errPodCostUnavailable, pool.Spec.RuntimeClass, err)
	}
	if runtimeClass.Overhead == nil {
		return 0, 0, nil
	}

	var cpuMilli, memoryBytes int64
	if cpu := runtimeClass.Overhead.PodFixed.Cpu(); cpu != nil {
		cpuMilli = cpu.MilliValue()
	}
	if memory := runtimeClass.Overhead.PodFixed.Memory(); memory != nil {
		memoryBytes = memory.Value()
	}
	return cpuMilli, memoryBytes, nil
}

func (s podShape) key() string {
	return fmt.Sprintf("%dm-%dMi", s.cpuMilli, s.memoryMB)
}

// shapePlacementCaps returns, per shape, how many Pods of that shape the
// fleet's Ready nodes can actually seat — summing each node's own
// `min(cpu, memory)` quotient rather than dividing a fleet-wide total.
//
// The distinction is the whole point. Summing first and dividing after
// answers "how much fleet is there", which over-counts twice over on a
// mixed fleet: it pools memory from hosts too small to seat the shape at
// all, and it ignores CPU, which is what actually binds a guest whose
// memory-per-vCPU is richer than its host's. Per-node `min` answers the
// question kube-scheduler will actually be asked.
//
// darwin only, deliberately. Linux runner Pods are kata microVMs that
// pin memory per sandbox while CPU is intentionally oversubscribed, so a
// CPU quotient there would cap a fleet that is not CPU-bound; and those
// hosts are homogeneous, so the byte budget is already exact.
//
// An empty result (no nodes, or a non-darwin pool) disables the cap.
func (r *AutoscalerReconciler) shapePlacementCaps(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	shapes map[string]podShape,
) (map[string]int32, error) {
	if len(shapes) == 0 {
		return nil, nil
	}

	// fleetNodeSelector mirrors the nodeSelector podtemplate stamps on
	// these Pods, so the cap counts exactly the nodes the scheduler will
	// consider.
	var nodes corev1.NodeList
	if err := r.List(ctx, &nodes, fleetNodeSelector(pool)); err != nil {
		return nil, fmt.Errorf("list %s fleet nodes for shape caps: %w", pool.Spec.OS, err)
	}

	caps := make(map[string]int32, len(shapes))
	for key, shape := range shapes {
		if shape.cpuMilli <= 0 || shape.memoryMB <= 0 {
			continue
		}
		var seats int32
		for i := range nodes.Items {
			if nodeFilterReason(&nodes.Items[i]) != "" {
				continue
			}
			seats += nodeSeatsForShape(&nodes.Items[i], shape)
		}
		caps[key] = seats
	}
	return caps, nil
}

// nodeSeatsForShape is how many Pods of `shape` one node could hold if
// it were empty: the smaller of its CPU and memory quotients. Current
// occupancy is deliberately not subtracted — the allocator sizes a
// steady-state target, and the Pods already running are themselves part
// of that target.
func nodeSeatsForShape(node *corev1.Node, shape podShape) int32 {
	cpu := node.Status.Allocatable.Cpu()
	memory := node.Status.Allocatable.Memory()
	if cpu == nil || memory == nil {
		return 0
	}

	byCPU := cpu.MilliValue() / int64(shape.cpuMilli)
	byMemory := memory.Value() / (int64(shape.memoryMB) * 1024 * 1024)
	if byMemory < byCPU {
		byCPU = byMemory
	}
	if byCPU < 0 {
		return 0
	}
	return int32(byCPU)
}

// fleetCapacity returns the shared budget `pool` competes for with
// its siblings, in the same unit AllocateFleet expects PerPodCost to
// be expressed in — allocatable memory bytes, for both OSes. An
// unrecognised OS returns (0, nil), which trips the per-pool fallback
// in desiredForPool without an error log — pools without a known OS
// quietly skip the allocator.
//
// macOS used to have its own unit ("host slots", one per Ready Mac
// mini, PerPodCost fixed at 1). That was exactly right while every
// host ran exactly one guest and exactly wrong the moment one did not:
// a host advertising room for two VMs still contributed 1, so half of
// a dual-guest host's capacity was invisible to the allocator and the
// pools it feeds would never scale into it.
//
// Counting bytes instead of hosts is not a new mechanism, it is the
// removal of a special case. tart-kubelet advertises hostMemoryMB as
// the Node's allocatable memory and the macOS runner Pod requests
// podMemoryMB, so kube-scheduler ALREADY decides how many guests fit
// by exactly this division. Doing the same arithmetic here makes the
// allocator agree with the scheduler by construction, instead of via
// a second number an operator has to remember to keep in sync — which
// is what a per-SKU fleet would otherwise require.
func (r *AutoscalerReconciler) fleetCapacity(ctx context.Context, pool *tuistv1.RunnerPool) (int64, error) {
	switch pool.Spec.OS {
	case "linux":
		return r.fleetAllocatableMemory(ctx, pool.Spec.FleetSelector)
	case "darwin":
		return r.macosFleetAllocatableMemory(ctx, pool.Spec.FleetSelector)
	default:
		return 0, nil
	}
}

// perPodCost is one Pod's claim on the shared fleet budget, in the
// same unit as fleetCapacity returns above. Linux RuntimeClass
// overhead is admission-time scheduling cost, so include the live
// podFixed memory instead of duplicating that value in RunnerPool.
//
// macOS has no RuntimeClass (the guest is a Tart VM, not a sandboxed
// container), so its cost is the Pod's memory request and nothing
// else — the same request kube-scheduler bin-packs against the Node's
// allocatable.
// A zero cost is NOT an error here. It is reported to the caller, which
// drops that one pool from the allocation instead of failing the whole
// call — see gatherFleetDemands. An error from this function freezes
// every pool in the capacity domain, which is the right response to an
// unreadable RuntimeClass (scaling without known admission overhead
// could overcommit the fleet) and much too broad for one pool with a
// bad number in its own spec.
func (r *AutoscalerReconciler) perPodCost(ctx context.Context, pool *tuistv1.RunnerPool) (int64, error) {
	cost := int64(pool.Spec.PodMemoryMB) * 1024 * 1024

	_, overheadMemory, err := r.runtimeClassOverhead(ctx, pool)
	if err != nil {
		return 0, err
	}
	return cost + overheadMemory, nil
}

// gatherFleetDemands builds the allocator input for every
// autoscaling-enabled sibling pool sharing `pool`'s OS and
// FleetSelector (the set contending for the same capacity domain).
// Pools of a different OS are excluded — the unit is bytes on both
// sides now, but the fleets are different physical machines, so
// pooling them would let a Linux pool's demand squeeze a macOS pool's
// warm floor against capacity it could never schedule onto. The
// reconciled pool reuses the signals
// already fetched this tick; siblings get a fresh fetch.
func (r *AutoscalerReconciler) gatherFleetDemands(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	signals scaling.Signals,
	knobs scaling.PolicyKnobs,
) ([]scaling.PoolDemand, map[string]podShape, error) {
	var pools tuistv1.RunnerPoolList
	if err := r.List(ctx, &pools, client.InNamespace(pool.Namespace)); err != nil {
		return nil, nil, fmt.Errorf("list runner pools: %w", err)
	}

	var demands []scaling.PoolDemand
	shapes := map[string]podShape{}
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
				return nil, nil, fmt.Errorf("signals for sibling %q: %w", p.Name, err)
			}
			sig = *fetched
			k = scaling.PolicyKnobs{
				MinWarmPoolFloor: p.Spec.Autoscaling.MinWarmPoolFloorOrDefault(),
				MaxReplicas:      p.Spec.Autoscaling.MaxReplicas,
			}
		}

		cost, err := r.perPodCost(ctx, p)
		if err != nil {
			return nil, nil, fmt.Errorf("calculate per-Pod cost for %q: %w", p.Name, err)
		}

		// A costless Pod would consume none of the shared budget, so
		// the allocator would grant this pool its whole target while
		// still believing the fleet empty, and its siblings would then
		// be squeezed against capacity that is already spoken for.
		//
		// Drop just this pool rather than failing the batch. Returning
		// an error here would take the errPodCostUnavailable path in
		// allocate and freeze EVERY pool sharing the OS + fleetSelector
		// at its current replica count, visible only as a log line — one
		// mis-set pool would quietly stop the whole fleet responding to
		// queue depth. A dropped pool falls back to its own per-pool
		// target (desiredForPool finds no allocation for it), which is
		// the same treatment a pool with autoscaling off already gets.
		//
		// The cost is checked after RuntimeClass overhead is folded in,
		// so a Linux pool that legitimately derives its whole cost from
		// kata's podFixed memory is unaffected. Reaching zero means both
		// are absent, which the CRD's podMemoryMB default makes hard to
		// do by accident.
		if cost <= 0 {
			logger := log.FromContext(ctx)
			logger.Error(errPodCostUnavailable,
				"pool declares no per-Pod cost; excluding it from fleet allocation and leaving it on its per-pool target",
				"pool", p.Name, "podMemoryMB", p.Spec.PodMemoryMB, "runtimeClass", p.Spec.RuntimeClass)
			continue
		}

		shape, err := r.placementShapeOf(ctx, p)
		if err != nil {
			return nil, nil, fmt.Errorf("placement shape for %q: %w", p.Name, err)
		}
		shapes[shape.key()] = shape

		demands = append(demands, scaling.PoolDemand{
			Name:       p.Name,
			PerPodCost: cost,
			Floor:      k.MinWarmPoolFloor,
			Load:       sig.Load(),
			Target:     scaling.DesiredReplicas(sig, k),
			ShapeKey:   shape.key(),
		})
	}

	return demands, shapes, nil
}

// fleetAllocatableMemory sums allocatable memory across nodes in the
// `fleetSelector` bare-metal pool, scaled by the reserve fraction.
func (r *AutoscalerReconciler) fleetAllocatableMemory(ctx context.Context, fleetSelector string) (int64, error) {
	var nodes corev1.NodeList
	if err := r.List(ctx, &nodes, client.MatchingLabels{fleetNodePoolLabel: fleetSelector}); err != nil {
		return 0, fmt.Errorf("list fleet nodes: %w", err)
	}

	var total int64
	ready, filtered := summarizeFleetNodes(nodes.Items)
	metrics.RecordFleetNodes(fleetSelector, "linux", ready, filtered)
	for i := range nodes.Items {
		if nodeFilterReason(&nodes.Items[i]) != "" {
			continue
		}
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

// macosFleetAllocatableMemory sums allocatable memory across the Mac
// mini nodes claimed by `fleetSelector`. Divided by a pool's
// podMemoryMB (perPodCost) this is the fleet's guest-slot budget, and
// it is correct for a mixed-SKU fleet without anything having to know
// which SKU a given host is: a 14336 MB M2-L contributes one 14 GB
// slot, a 28672 MB M4-XL contributes two.
//
// Tracks the actually-Ready hosts — a host being CAPI-rolled drops out
// of the sum, and the per-pool fallback in desiredForPool keeps the
// pool at its current size through the blip.
//
// No reserve fraction, unlike the Linux path. There is nothing here
// for a reserve to cover: hostMemoryMB is a number the operator picks
// for tart-kubelet to advertise, already net of the ~2 GB Apple's
// Virtualization.framework holds back from the host, and macOS runs no
// memory-requesting DaemonSets on these Nodes. Scaling it down again
// would double-count that reserve and strand a whole guest slot on a
// dual-guest host.
func (r *AutoscalerReconciler) macosFleetAllocatableMemory(ctx context.Context, fleetSelector string) (int64, error) {
	var nodes corev1.NodeList
	if err := r.List(ctx, &nodes, client.MatchingLabels{
		macosFleetLabel: fleetSelector,
		nodeOSLabel:     macosNodeOSDarwin,
	}); err != nil {
		return 0, fmt.Errorf("list macOS fleet nodes: %w", err)
	}
	ready, filtered := summarizeFleetNodes(nodes.Items)
	metrics.RecordFleetNodes(fleetSelector, "darwin", ready, filtered)

	var total int64
	for i := range nodes.Items {
		if nodeFilterReason(&nodes.Items[i]) != "" {
			continue
		}
		if mem := nodes.Items[i].Status.Allocatable.Memory(); mem != nil {
			total += mem.Value()
		}
	}
	return total, nil
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
