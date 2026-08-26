package controllers

import (
	"context"
	"fmt"
	"sort"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
)

// Node reservation: draining one host to fit a Pod that no host can seat.
//
// A macOS fleet mixes guest shapes on the same hosts, and the large ones
// need more than one guest slot on a single host. An M4-XL seats two
// 6 vCPU guests or one 12 vCPU guest, so a 12 vCPU Pod needs BOTH of a
// host's slots free at the same instant. Nothing in Kubernetes arranges
// that on its own:
//
//   - kube-scheduler does not hold a queue on an unschedulable Pod. The
//     large Pod is attempted, fails the CPU filter, and is set aside;
//     the next 6 vCPU Pod is attempted and binds into the slot that just
//     freed. Being queued longer earns a first attempt, not the seat.
//   - The fleet allocator's cross-pool reclaim cannot help either. It
//     reclaims speculative warm capacity, and the Pod winning the race
//     here is backed by real queued work, which is the one tier that
//     never yields.
//
// So under a steady trickle of small jobs the large Pod waits for a
// coincidence that may not arrive. The fix is to stop the leak: take one
// eligible host out of circulation for everyone else, let its running
// jobs finish, retire only its idle Pods, and hand the accumulated seats
// to the pool that was starved.
//
// Preemption cannot do this. The scheduler chooses victims by priority,
// `spec.priority` is immutable after admission, and a runner Pod becomes
// job-owning in place — so a priority high enough to evict for the large
// Pod would also evict Pods running customer builds. The signal that
// separates them, `isIdle`, reads init-container status the scheduler
// never sees. The controller is the only component that can tell the
// difference, which is why the reservation lives here.
const (
	// reservationAtAnnotation records when a reservation started, so it
	// can be released on a timeout. Taint objects only carry a timestamp
	// for NoExecute, and this taint is deliberately NoSchedule.
	reservationAtAnnotation = "tuist.dev/reserved-at"

	// reservationGrace is how long a Pod must sit unscheduled before it
	// is treated as starved rather than merely waiting for the scheduler.
	// Draining a host is expensive, and the ordinary case (a seat is free
	// somewhere) resolves in well under a second.
	reservationGrace = 2 * time.Minute

	// reservationTimeout bounds how long one host stays held. The Pods a
	// reservation waits on are customer jobs, which can legitimately run
	// for hours; past this point the seats already cleared are worth more
	// back in general circulation than spent waiting.
	reservationTimeout = 15 * time.Minute

	// reservationCooldownAnnotation is when a timed-out host may be
	// reserved again, and reservationCooldown is how long that is.
	//
	// Without it the timeout above does nothing. `starvedPod` measures a
	// Pod's own age, so the Pod that triggered a reservation is still
	// long past the grace period the instant the reservation releases —
	// the next reconcile would re-reserve the same host immediately and
	// the small shapes would never actually get it back. The timeout
	// would read as a safety valve and behave like an indefinite hold.
	//
	// It is stamped on the NODE rather than the pool, because that is
	// the resource being rested: a pool blocked on one host should still
	// be free to reserve a different eligible one. Only a timed-out
	// release sets it. A reservation that ended because the Pod landed
	// achieved what it was for, and a later starved Pod deserves a fresh
	// attempt with no penalty.
	reservationCooldownAnnotation = "tuist.dev/reservation-cooldown-until"
	reservationCooldown           = 15 * time.Minute

	// maxFleetReservations is how many hosts may be held across the whole
	// fleet at once. Every reservation is capacity withdrawn from the
	// small shapes while it converges, so this stays at one: a second
	// concurrent drain would take a quarter of an 11-slot fleet offline
	// to serve two large jobs.
	maxFleetReservations = 1
)

// reconcileReservation drives the reservation state machine for one
// pool. It is called from the RunnerPool reconciler, which runs with
// MaxConcurrentReconciles 1 — that serialization is what makes the
// fleet-wide reservation count safe to read and act on without a lease.
//
// `pods` are this pool's Pods, already fetched by the caller.
func (r *RunnerPoolReconciler) reconcileReservation(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	pods []corev1.Pod,
) error {
	// darwin only. Linux runner Pods are kata sandboxes on homogeneous
	// bare-metal hosts an order of magnitude larger than any shape, so a
	// shape never needs a host drained to fit.
	if pool.Spec.OS != macosNodeOSDarwin {
		return nil
	}

	logger := log.FromContext(ctx)
	now := r.now()

	nodes, err := r.fleetNodes(ctx, pool)
	if err != nil {
		return err
	}

	// Orphan sweep first. A reservation is discoverable only by the pool
	// named in its taint, so once that pool's CR is gone nothing can
	// release it: the host stays tainted out of the fleet forever AND
	// its reservation keeps counting against maxFleetReservations, which
	// blocks every future one. Deleting or renaming a pool in a helm
	// upgrade is enough to reach this, because a deleting pool returns
	// through reconcileDelete before it ever gets here.
	if err := r.releaseOrphanedReservations(ctx, pool, nodes); err != nil {
		return err
	}

	value := podtemplate.ReservationValue(pool.Name)
	held := reservedNode(nodes, value)
	starved := starvedPod(pods, now)

	if held != nil {
		switch {
		case starved == nil:
			logger.Info("releasing node reservation; pool is served", "node", held.Name, "pool", pool.Name)
			return r.releaseReservation(ctx, held, time.Time{})
		case reservationAge(held, now) > reservationTimeout:
			logger.Info("releasing node reservation; timed out waiting for jobs to finish",
				"node", held.Name, "pool", pool.Name, "timeout", reservationTimeout,
				"cooldown", reservationCooldown)
			return r.releaseReservation(ctx, held, now.Add(reservationCooldown))
		default:
			return r.retireIdlePodsOnReservedNode(ctx, held, pool)
		}
	}

	if starved == nil {
		return nil
	}
	if reservationCount(nodes) >= maxFleetReservations {
		return nil
	}

	// About to take the fleet's one reservation, so re-read the nodes
	// straight from the apiserver. MaxConcurrentReconciles 1 serializes
	// the workers but not their reads: the List above is served from the
	// informer cache, which can still be missing a taint another pool's
	// reconcile wrote moments ago. Confirming against the cache would
	// hand out a second reservation and drain two hosts at once.
	fresh, err := r.fleetNodesFrom(ctx, r.apiReader(), pool)
	if err != nil {
		return err
	}
	if reservationCount(fresh) >= maxFleetReservations {
		return nil
	}

	target, err := r.pickReservationTarget(ctx, pool, fresh, now)
	if err != nil {
		return err
	}
	if target == nil {
		// No host in the fleet could seat this shape even empty. That is
		// a capacity or catalog problem, not something a drain can fix,
		// and the pool's queue-age metric already carries the signal.
		return nil
	}

	logger.Info("reserving node to fit a starved runner",
		"node", target.Name, "pool", pool.Name, "pod", starved.Name)
	return r.reserveNode(ctx, target, value, now)
}

// starvedPod returns a Pod that has waited past the grace period with no
// node assigned. Phase is not the test on its own — an unscheduled Pod
// and a Pod whose VM is still booting are both Pending — so this asks
// for an empty `spec.nodeName`, which only an unplaced Pod has.
func starvedPod(pods []corev1.Pod, now time.Time) *corev1.Pod {
	var oldest *corev1.Pod
	for i := range pods {
		pod := &pods[i]
		if pod.Spec.NodeName != "" || !pod.DeletionTimestamp.IsZero() {
			continue
		}
		if pod.Status.Phase != corev1.PodPending {
			continue
		}
		if now.Sub(pod.CreationTimestamp.Time) < reservationGrace {
			continue
		}
		if oldest == nil || pod.CreationTimestamp.Time.Before(oldest.CreationTimestamp.Time) {
			oldest = pod
		}
	}
	return oldest
}

// pickReservationTarget chooses the host to drain: one that could seat
// this pool's shape if it were empty, is not already reserved, and is
// otherwise healthy.
//
// Preference is the host that will converge soonest — fewest Pods
// running customer jobs, since those are the ones a reservation can only
// wait for. Idle Pods are not counted; retiring them is immediate. Ties
// break on name so a reservation does not wander between reconciles.
func (r *RunnerPoolReconciler) pickReservationTarget(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	nodes []corev1.Node,
	now time.Time,
) (*corev1.Node, error) {
	shape := podShape{cpuMilli: pool.Spec.PodCPUMilli, memoryMB: pool.Spec.PodMemoryMB}
	if shape.cpuMilli <= 0 || shape.memoryMB <= 0 {
		return nil, nil
	}

	siblings, err := r.fleetShapes(ctx, pool)
	if err != nil {
		return nil, err
	}

	var fleetPods corev1.PodList
	if err := r.List(ctx, &fleetPods, client.InNamespace(pool.Namespace)); err != nil {
		return nil, fmt.Errorf("list pods for reservation target: %w", err)
	}

	owned := map[string]int{}
	ownPool := map[string]int32{}
	for i := range fleetPods.Items {
		pod := &fleetPods.Items[i]
		if pod.Spec.NodeName == "" || !pod.DeletionTimestamp.IsZero() {
			continue
		}
		// This pool's own Pods are never retired by the reaper, so for
		// the purposes of this reservation they are permanent occupants
		// and have to come off the candidate's usable seats. Other
		// pools' Pods do not: idle ones are retired immediately and
		// running ones are waited out.
		if pod.Labels["tuist.dev/runner-pool"] == pool.Name {
			ownPool[pod.Spec.NodeName]++
			continue
		}
		if !isIdle(pod) {
			owned[pod.Spec.NodeName]++
		}
	}

	candidates := make([]*corev1.Node, 0, len(nodes))
	for i := range nodes {
		node := &nodes[i]
		if nodeFilterReason(node) != "" || isReserved(node) {
			continue
		}
		if inReservationCooldown(node, now) {
			continue
		}
		seats := nodeSeatsForShape(node, shape)
		// Seats this reservation could actually end up with. A host
		// already holding one of this pool's own Pods cannot be cleared
		// for a second one, and ranking on occupancy alone would make it
		// look like the BEST candidate — its own idle Pod counts as zero
		// occupancy — so the reservation would settle on a host it can
		// never clear and burn the fleet's one slot until the timeout.
		seats -= ownPool[node.Name]
		if seats < 1 {
			continue
		}
		// Reserve only where a reservation can actually achieve
		// something: this shape must occupy more of the host than the
		// fleet's most granular shape does, which is precisely the case
		// where the seats it needs are the ones smaller Pods keep taking.
		//
		// Without this a homogeneous single-slot fleet would reserve for
		// an ordinary Pod that is merely queued behind one other Pod.
		// Nothing accumulates (the shape already fits one seat), and on a
		// one-host fleet the taint takes every pool out of service until
		// the reservation clears. Waiting for the seat is the correct
		// behaviour there, and it is what the allocator's cross-pool
		// reclaim already arranges.
		if seats >= maxSeatsOnNode(node, siblings) {
			continue
		}
		candidates = append(candidates, node)
	}
	if len(candidates) == 0 {
		return nil, nil
	}

	sort.Slice(candidates, func(a, b int) bool {
		if owned[candidates[a].Name] != owned[candidates[b].Name] {
			return owned[candidates[a].Name] < owned[candidates[b].Name]
		}
		return candidates[a].Name < candidates[b].Name
	})
	return candidates[0], nil
}

// retireIdlePodsOnReservedNode clears the seats a reservation can clear
// straight away: idle Pods belonging to OTHER pools. Retiring them costs
// a cold start and nothing else.
//
// This pool's own Pods are left alone — an idle one here is the seat the
// reservation was taken to produce. Pods running customer jobs are never
// touched; the reservation waits them out, or times out.
//
// Idleness is read through `isIdle`, matching the node-drain path: the
// owner label alone is best-effort and can be missing on a Pod that is
// running a job.
func (r *RunnerPoolReconciler) retireIdlePodsOnReservedNode(
	ctx context.Context,
	node *corev1.Node,
	pool *tuistv1.RunnerPool,
) error {
	logger := log.FromContext(ctx)

	var pods corev1.PodList
	if err := r.List(ctx, &pods, client.InNamespace(pool.Namespace)); err != nil {
		return fmt.Errorf("list pods on reserved node %s: %w", node.Name, err)
	}

	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Spec.NodeName != node.Name || !pod.DeletionTimestamp.IsZero() {
			continue
		}
		if pod.Labels["tuist.dev/runner-pool"] == pool.Name {
			continue
		}
		if !isIdle(pod) {
			continue
		}
		if err := r.reapRunner(ctx, pod); err != nil {
			return fmt.Errorf("retire idle pod %s on reserved node %s: %w", pod.Name, node.Name, err)
		}
		logger.Info("retired idle pod to clear a reserved node", "pod", pod.Name, "node", node.Name)
	}
	return nil
}

func (r *RunnerPoolReconciler) reserveNode(
	ctx context.Context,
	node *corev1.Node,
	value string,
	now time.Time,
) error {
	patched := node.DeepCopy()
	patched.Spec.Taints = append(patched.Spec.Taints, corev1.Taint{
		Key:    podtemplate.ReservationTaintKey,
		Value:  value,
		Effect: corev1.TaintEffectNoSchedule,
	})
	if patched.Annotations == nil {
		patched.Annotations = map[string]string{}
	}
	patched.Annotations[reservationAtAnnotation] = now.UTC().Format(time.RFC3339)

	if err := r.Patch(ctx, patched, optimisticPatch(node)); err != nil {
		return fmt.Errorf("reserve node %s: %w", node.Name, err)
	}
	return nil
}

// releaseReservation lifts the taint. A non-zero `cooldownUntil` rests
// the host until that time, which is what a timed-out release wants; the
// zero value releases it straight back into circulation.
func (r *RunnerPoolReconciler) releaseReservation(
	ctx context.Context,
	node *corev1.Node,
	cooldownUntil time.Time,
) error {
	patched := node.DeepCopy()
	taints := make([]corev1.Taint, 0, len(patched.Spec.Taints))
	for _, taint := range patched.Spec.Taints {
		if taint.Key == podtemplate.ReservationTaintKey {
			continue
		}
		taints = append(taints, taint)
	}
	patched.Spec.Taints = taints
	delete(patched.Annotations, reservationAtAnnotation)
	if !cooldownUntil.IsZero() {
		if patched.Annotations == nil {
			patched.Annotations = map[string]string{}
		}
		patched.Annotations[reservationCooldownAnnotation] = cooldownUntil.UTC().Format(time.RFC3339)
	}

	if err := r.Patch(ctx, patched, optimisticPatch(node)); err != nil {
		return fmt.Errorf("release reservation on node %s: %w", node.Name, err)
	}
	return nil
}

// fleetNodes lists the macOS hosts behind a pool's fleet selector, the
// same set the autoscaler sizes its budget from. Cached read: fine for
// deciding whether this pool already holds a reservation, and for
// releasing one.
func (r *RunnerPoolReconciler) fleetNodes(ctx context.Context, pool *tuistv1.RunnerPool) ([]corev1.Node, error) {
	return r.fleetNodesFrom(ctx, r.Client, pool)
}

func (r *RunnerPoolReconciler) fleetNodesFrom(
	ctx context.Context,
	reader client.Reader,
	pool *tuistv1.RunnerPool,
) ([]corev1.Node, error) {
	var nodes corev1.NodeList
	if err := reader.List(ctx, &nodes, client.MatchingLabels{
		macosFleetLabel:  pool.Spec.FleetSelector,
		macosNodeOSLabel: macosNodeOSDarwin,
	}); err != nil {
		return nil, fmt.Errorf("list fleet nodes: %w", err)
	}
	return nodes.Items, nil
}

// apiReader is the uncached client, used on the one path where a stale
// read is not survivable. Falls back to the cached client when unset so
// tests (and any caller that has not wired one) still work.
func (r *RunnerPoolReconciler) apiReader() client.Reader {
	if r.APIReader != nil {
		return r.APIReader
	}
	return r.Client
}

// releaseOrphanedReservations lifts reservation taints that name a pool
// which no longer exists, or is on its way out. Both the per-pool
// release in reconcileDelete and this sweep are needed: the release
// handles the ordinary delete promptly, and the sweep is the backstop
// for a controller that died mid-reservation, a pool force-deleted past
// its finalizer, or a taint left by an earlier version.
//
// Deliberately no cooldown on these: an orphan was never a considered
// decision about this host, so there is nothing to back off from.
func (r *RunnerPoolReconciler) releaseOrphanedReservations(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	nodes []corev1.Node,
) error {
	logger := log.FromContext(ctx)

	var pools tuistv1.RunnerPoolList
	if err := r.List(ctx, &pools, client.InNamespace(pool.Namespace)); err != nil {
		return fmt.Errorf("list runner pools for orphan sweep: %w", err)
	}

	live := map[string]bool{}
	for i := range pools.Items {
		if !pools.Items[i].DeletionTimestamp.IsZero() {
			continue
		}
		live[podtemplate.ReservationValue(pools.Items[i].Name)] = true
	}

	for i := range nodes {
		node := &nodes[i]
		for _, taint := range node.Spec.Taints {
			if taint.Key != podtemplate.ReservationTaintKey || live[taint.Value] {
				continue
			}
			logger.Info("releasing orphaned node reservation; owning pool is gone",
				"node", node.Name, "reservedFor", taint.Value)
			if err := r.releaseReservation(ctx, node, time.Time{}); err != nil {
				return err
			}
			break
		}
	}
	return nil
}

// ReleaseReservationsForPool lifts any reservation this pool holds. Called
// from the delete path, which returns before the ordinary reservation
// reconciliation and would otherwise strand the taint.
func (r *RunnerPoolReconciler) ReleaseReservationsForPool(ctx context.Context, pool *tuistv1.RunnerPool) error {
	if pool.Spec.OS != macosNodeOSDarwin {
		return nil
	}

	nodes, err := r.fleetNodes(ctx, pool)
	if err != nil {
		return err
	}
	held := reservedNode(nodes, podtemplate.ReservationValue(pool.Name))
	if held == nil {
		return nil
	}

	log.FromContext(ctx).Info("releasing node reservation; owning pool is being deleted",
		"node", held.Name, "pool", pool.Name)
	return r.releaseReservation(ctx, held, time.Time{})
}

// fleetShapes is every Pod footprint in play on this pool's fleet. The
// reservation needs it to know what "large" means here: a shape is only
// large relative to the smallest thing competing for the same hosts.
func (r *RunnerPoolReconciler) fleetShapes(ctx context.Context, pool *tuistv1.RunnerPool) ([]podShape, error) {
	var pools tuistv1.RunnerPoolList
	if err := r.List(ctx, &pools, client.InNamespace(pool.Namespace)); err != nil {
		return nil, fmt.Errorf("list runner pools for fleet shapes: %w", err)
	}

	shapes := make([]podShape, 0, len(pools.Items))
	for i := range pools.Items {
		sibling := &pools.Items[i]
		if sibling.Spec.OS != pool.Spec.OS || sibling.Spec.FleetSelector != pool.Spec.FleetSelector {
			continue
		}
		if sibling.Spec.PodCPUMilli <= 0 || sibling.Spec.PodMemoryMB <= 0 {
			continue
		}
		shapes = append(shapes, podShape{
			cpuMilli: sibling.Spec.PodCPUMilli,
			memoryMB: sibling.Spec.PodMemoryMB,
		})
	}
	return shapes, nil
}

// maxSeatsOnNode is how many Pods the most granular shape on the fleet
// would get from this node — the yardstick a reservation candidate is
// measured against.
func maxSeatsOnNode(node *corev1.Node, shapes []podShape) int32 {
	var most int32
	for _, shape := range shapes {
		if seats := nodeSeatsForShape(node, shape); seats > most {
			most = seats
		}
	}
	return most
}

// inReservationCooldown reports whether a host is resting after a
// timed-out reservation. An unparseable stamp reads as expired: a
// malformed annotation must not take a host out of the pool forever.
func inReservationCooldown(node *corev1.Node, now time.Time) bool {
	stamp, ok := node.Annotations[reservationCooldownAnnotation]
	if !ok {
		return false
	}
	until, err := time.Parse(time.RFC3339, stamp)
	if err != nil {
		return false
	}
	return now.Before(until)
}

func isReserved(node *corev1.Node) bool {
	for _, taint := range node.Spec.Taints {
		if taint.Key == podtemplate.ReservationTaintKey {
			return true
		}
	}
	return false
}

func reservedNode(nodes []corev1.Node, value string) *corev1.Node {
	for i := range nodes {
		for _, taint := range nodes[i].Spec.Taints {
			if taint.Key == podtemplate.ReservationTaintKey && taint.Value == value {
				return &nodes[i]
			}
		}
	}
	return nil
}

func reservationCount(nodes []corev1.Node) int {
	count := 0
	for i := range nodes {
		if isReserved(&nodes[i]) {
			count++
		}
	}
	return count
}

// reservationAge reports how long a node has been held. A missing or
// unparseable stamp reads as freshly reserved rather than expired, so a
// hand-applied taint is not torn down on the next tick.
func reservationAge(node *corev1.Node, now time.Time) time.Duration {
	stamp, ok := node.Annotations[reservationAtAnnotation]
	if !ok {
		return 0
	}
	at, err := time.Parse(time.RFC3339, stamp)
	if err != nil {
		return 0
	}
	return now.Sub(at)
}

// optimisticPatch carries the base object's resourceVersion as a
// precondition. Taints are a plain list, so a merge patch REPLACES the
// whole array with the one computed from our copy of the node. Without
// the precondition a taint another actor added since we read it — a
// kubelet pressure taint, Cluster API's cordon, a sibling reservation —
// would be silently dropped on write. With it the write fails on
// conflict instead, and the next reconcile recomputes from fresh state.
func optimisticPatch(base client.Object) client.Patch {
	return client.MergeFromWithOptions(base, client.MergeFromWithOptimisticLock{})
}
