package controllers

import (
	"context"
	"fmt"
	"sort"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
)

// Node reservation: draining one host to fit a Pod that no host can seat.
//
// Both fleets mix shapes on the same hosts, and the large ones need more
// of a host than any single small Pod does. An M4-XL seats two 6 vCPU
// guests or one 12 vCPU guest, so a 12 vCPU Pod needs BOTH of a host's
// slots free at the same instant. The Linux fleet is the same problem at
// a different granularity: a 64 GiB shape costs 66.5 GiB with the kata
// overhead — a third of an AX162-R, over half of the OVH RISE-L the
// fleet is moving to — so it needs a contiguous block that a steady
// trickle of 8 and 16 GiB Pods keeps carving up. Nothing in Kubernetes
// arranges either on its own:
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

	// maxFleetReservations is how many hosts may be held at once. The
	// count is taken over the pool's OWN fleet nodes, so each fleet gets
	// its own budget and a macOS reservation never blocks a Linux one.
	//
	// Every reservation is capacity withdrawn from the small shapes while
	// it converges, so this stays at one. On macOS a second concurrent
	// drain would hold two hosts, up to 4 of the 14-slot production
	// fleet, to serve two large jobs. On Linux the argument is sharper
	// still: that fleet is a handful of bare-metal boxes, so a single
	// reservation is already a large share of it out of circulation.
	// `healthyNodes` puts a floor under that — the last host is never
	// taken.
	//
	// A held Linux host is not idled, only closed to new Pods — running
	// jobs finish and free memory progressively, and the starved Pod
	// lands the moment its shape fits rather than when the host is empty.
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
	starvedFor := trackStarvation(pool, pods, now)
	starved := starvedFor >= reservationGrace

	if held != nil {
		switch {
		case starvedFor == 0:
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

	if !starved {
		return nil
	}
	if reservationCount(nodes) >= maxFleetReservations {
		return nil
	}

	// Oldest starvation goes first. Without this the fleet's single
	// reservation is handed out in reconcile order, and the shapes that
	// need it least win: a granular shape is starved often and converges
	// in seconds, so it takes the slot, releases, and takes it again,
	// while the coarse shape — the only one that genuinely cannot be
	// served without a drain — waits behind pools that were merely
	// queued. Production ran exactly that on 2026-09-04: the 16 vCPU
	// pool waited 07:23 to 08:36 while 2, 4 and 8 vCPU pools cycled
	// through the slot.
	//
	// Ordering on starvation age rather than on shape size keeps the
	// rule symmetric. The opposite failure is on record too — a big
	// pool holding the fleet-wide provisioning budget while the default
	// shape was admitted nothing and the deploy cascade queued behind
	// it — and a size-ordered rule would have made that one worse.
	ahead, err := r.longerStarvedPool(ctx, pool, nodes, now)
	if err != nil {
		return err
	}
	if ahead != "" {
		logger.V(1).Info("yielding the fleet reservation to a pool starved longer",
			"pool", pool.Name, "waitingFor", ahead, "starvedFor", starvedFor.String())
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
	// Never close the fleet. The taint is NoSchedule for every pool but
	// this one, so on a single-host fleet a reservation stops dispatch
	// outright until it clears — up to reservationTimeout, and again
	// after each cooldown.
	//
	// pickReservationTarget's granularity guard does not cover this. It
	// asks whether the shape is coarse relative to its siblings, which
	// on Linux a 64 GiB shape genuinely is even on a lone host, so it
	// passes. The guard only happens to cover the one-host macOS fleets
	// because a single-guest host gives every shape exactly one seat.
	//
	// Waiting is the right behaviour here, and it is the same conclusion
	// the one-guest fleets reach: nothing a drain produces is worth the
	// fleet being shut to everyone else, and the allocator's cross-pool
	// reclaim is the mechanism that frees room on a fleet this small.
	if healthyNodes(fresh) < 2 {
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
		"node", target.Name, "pool", pool.Name,
		"pod", unplacedPodName(pods), "starvedFor", starvedFor.String())
	return r.reserveNode(ctx, target, value, now)
}

// trackStarvation folds the pool's current placement state into
// `status.UnplaceableSince` and returns how long it has been starved.
// Zero means nothing is waiting.
//
// The caller mutates the pool in place; the reconciler's existing
// `Status().Update` at the end of the pass persists it, the same way
// `ObservedImage`/`ImageRolledAt` are handled.
//
// This replaces a per-Pod age test. Measuring starvation on a Pod's own
// `CreationTimestamp` cannot work while the reaper deletes unplaced Pods
// at `startTimeoutSeconds` and the pool recreates them: a Pod only
// counted as starved between the 2-minute grace and the 5-minute reap,
// so the moment a cohort was reaped together the replacements were all
// too young, the pool read as "served", and a reservation part-way
// through draining a host was thrown away. Production, 2026-09-04
// 08:24:24: a reap and a "pool is served" release in the same second,
// with the pool going 3 -> 2 -> 1 -> 0 Running across the window.
func trackStarvation(pool *tuistv1.RunnerPool, pods []corev1.Pod, now time.Time) time.Duration {
	if !poolUnplaceable(pool, pods) {
		pool.Status.UnplaceableSince = nil
		return 0
	}
	if pool.Status.UnplaceableSince == nil {
		// Seed from the oldest Pod still waiting rather than from now.
		// The stamp is the only durable record of the wait, so a
		// controller restart — or the first reconcile after this field
		// was introduced — would otherwise forgive every starvation in
		// flight and make a Pod that has waited an hour look brand new.
		start := now
		if oldest := oldestUnplacedCreation(pods); !oldest.IsZero() && oldest.Before(start) {
			start = oldest
		}
		stamp := metav1.NewTime(start)
		pool.Status.UnplaceableSince = &stamp
	}
	if elapsed := now.Sub(pool.Status.UnplaceableSince.Time); elapsed > 0 {
		return elapsed
	}
	// A starvation that starts this instant has lasted no time, but it
	// IS a starvation — a flat zero would read as "served" and release
	// a reservation that is still needed.
	return time.Nanosecond
}

// oldestUnplacedCreation is the creation time of the longest-waiting
// unplaced Pod, or the zero time when nothing is waiting.
func oldestUnplacedCreation(pods []corev1.Pod) time.Time {
	var oldest time.Time
	for i := range pods {
		pod := &pods[i]
		if !isAlive(pod) || pod.Spec.NodeName != "" {
			continue
		}
		created := pod.CreationTimestamp.Time
		if oldest.IsZero() || created.Before(oldest) {
			oldest = created
		}
	}
	return oldest
}

// poolUnplaceable reports whether the pool is holding demand it has not
// placed: an unscheduled Pod, or fewer bound Pods than `spec.replicas`.
//
// The second clause is what makes the signal survive the reap. Between
// the reaper deleting an unplaced Pod and the converge loop recreating
// it, the pool can momentarily own no unplaced Pod at all while being no
// better served than it was a second earlier. `spec.replicas` is set by
// the autoscaler from real demand and is untouched by the reap, so it
// still reports the gap across that window.
func poolUnplaceable(pool *tuistv1.RunnerPool, pods []corev1.Pod) bool {
	bound := 0
	unplaced := 0
	for i := range pods {
		pod := &pods[i]
		if !isAlive(pod) {
			continue
		}
		if pod.Spec.NodeName == "" {
			unplaced++
			continue
		}
		bound++
	}
	return unplaced > 0 || bound < int(pool.Spec.Replicas)
}

// unplacedPodName names an unplaced Pod for the reservation log line.
// Purely for reporting — the decision is the pool-level clock above.
func unplacedPodName(pods []corev1.Pod) string {
	for i := range pods {
		pod := &pods[i]
		if isAlive(pod) && pod.Spec.NodeName == "" {
			return pod.Name
		}
	}
	return ""
}

// longerStarvedPool names a sibling on this fleet that has been unable
// to place for longer than this pool and could still use a reservation.
// Empty when this pool is first in line.
func (r *RunnerPoolReconciler) longerStarvedPool(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	nodes []corev1.Node,
	now time.Time,
) (string, error) {
	mine := pool.Status.UnplaceableSince
	if mine == nil {
		return "", nil
	}

	var pools tuistv1.RunnerPoolList
	if err := r.List(ctx, &pools, client.InNamespace(pool.Namespace)); err != nil {
		return "", fmt.Errorf("list runner pools for reservation arbitration: %w", err)
	}

	for i := range pools.Items {
		sibling := &pools.Items[i]
		if sibling.Name == pool.Name || !sibling.DeletionTimestamp.IsZero() {
			continue
		}
		if sibling.Spec.OS != pool.Spec.OS || sibling.Spec.FleetSelector != pool.Spec.FleetSelector {
			continue
		}
		since := sibling.Status.UnplaceableSince
		if since == nil || !since.Time.Before(mine.Time) {
			continue
		}
		if now.Sub(since.Time) < reservationGrace {
			continue
		}
		// Only yield to a sibling a drain could actually serve. A shape
		// no host can seat even empty never stops being starved, so
		// yielding to it would not be waiting for a turn — it would be
		// a permanent block, trading the starvation this fix removes
		// for a worse one it introduced.
		if !shapeSeatableOnFleet(nodes, podShape{
			cpuMilli: sibling.Spec.PodCPUMilli,
			memoryMB: sibling.Spec.PodMemoryMB,
		}) {
			continue
		}
		return sibling.Name, nil
	}
	return "", nil
}

// shapeSeatableOnFleet reports whether any healthy host could seat this
// shape if it were empty.
func shapeSeatableOnFleet(nodes []corev1.Node, shape podShape) bool {
	if shape.cpuMilli <= 0 || shape.memoryMB <= 0 {
		return false
	}
	for i := range nodes {
		if nodeFilterReason(&nodes[i]) != "" {
			continue
		}
		if nodeSeatsForShape(&nodes[i], shape) >= 1 {
			return true
		}
	}
	return false
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

// fleetNodes lists the hosts behind a pool's fleet selector, the same
// set the autoscaler sizes its budget from. Cached read: fine for
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
	if err := reader.List(ctx, &nodes, fleetNodeSelector(pool)); err != nil {
		return nil, fmt.Errorf("list fleet nodes: %w", err)
	}
	return nodes.Items, nil
}

// fleetNodeSelector addresses the hosts a pool's Pods can actually land
// on. It mirrors the nodeSelector `podtemplate.schedulingFor` stamps on
// those Pods, so the reservation reasons about exactly the node set the
// scheduler considers; the two would otherwise be free to disagree about
// which hosts belong to a fleet.
//
// Anything other than linux falls through to darwin, matching that same
// function's fallback and the CRD's `os` default.
func fleetNodeSelector(pool *tuistv1.RunnerPool) client.MatchingLabels {
	switch pool.Spec.OS {
	case "linux":
		return client.MatchingLabels{
			fleetNodePoolLabel: pool.Spec.FleetSelector,
			nodeOSLabel:        "linux",
		}
	default:
		return client.MatchingLabels{
			macosFleetLabel: pool.Spec.FleetSelector,
			nodeOSLabel:     macosNodeOSDarwin,
		}
	}
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

// healthyNodes counts a fleet's hosts that could take work right now.
// Reserving is only safe while at least one other host remains to serve
// every other pool.
func healthyNodes(nodes []corev1.Node) int {
	count := 0
	for i := range nodes {
		if nodeFilterReason(&nodes[i]) == "" {
			count++
		}
	}
	return count
}
