package controllers

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/metrics"
)

const (
	provisioningRequeueAfter      = 5 * time.Second
	creationReservationLifetime   = 30 * time.Second
	pollerNotStartedTimeoutReason = "poller_not_started"
	unschedulableTimeoutReason    = "unschedulable"
)

type creationReservation struct {
	namespace     string
	pool          string
	fleetSelector string
	expiresAt     time.Time
}

// creationReservationStore closes the informer-cache window after a Pod
// create. Without it, an immediate reconcile can observe the old Pod list and
// admit another full batch before the watch event for the first batch lands.
// Reservations disappear as soon as the cache observes the Pod, or after a
// short fail-safe lifetime if a watch event is lost.
type creationReservationStore struct {
	mu     sync.Mutex
	byName map[string]creationReservation
}

func (s *creationReservationStore) add(namespace, name, pool, fleetSelector string, now time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.byName == nil {
		s.byName = map[string]creationReservation{}
	}
	s.byName[namespace+"/"+name] = creationReservation{
		namespace:     namespace,
		pool:          pool,
		fleetSelector: fleetSelector,
		expiresAt:     now.Add(creationReservationLifetime),
	}
}

func (s *creationReservationStore) reconcile(
	namespace string,
	fleetSelector string,
	observed map[string]struct{},
	now time.Time,
) (int, map[string]int) {
	s.mu.Lock()
	defer s.mu.Unlock()

	total := 0
	byPool := map[string]int{}
	for key, reservation := range s.byName {
		if _, ok := observed[key]; ok || !now.Before(reservation.expiresAt) {
			delete(s.byName, key)
			continue
		}
		if reservation.namespace != namespace || reservation.fleetSelector != fleetSelector {
			continue
		}
		total++
		byPool[reservation.pool]++
	}
	return total, byPool
}

type provisioningAdmission struct {
	available       int
	pendingForPool  int
	pendingForFleet int
	cap             int
	poolCap         int
	healthyNodes    int
	blockedReason   string
}

func isLinuxKataPool(pool *tuistv1.RunnerPool) bool {
	return pool.Spec.OS == "linux" && pool.Spec.RuntimeClass == "kata-qemu"
}

// isLinuxProvisioningPod is true until the dispatch poller starts. A
// terminated poller has already claimed or drained, and isIdle deliberately
// excludes it. Deleting and terminal Pods are excluded by isAlive.
func isLinuxProvisioningPod(pod *corev1.Pod) bool {
	return isAlive(pod) && isIdle(pod) && !pollerRunning(pod)
}

// unschedulableSince reports when the scheduler last rejected the Pod. Only an
// explicit Unschedulable condition counts: a freshly created Pod carries no
// PodScheduled condition at all and is merely waiting its turn.
func unschedulableSince(pod *corev1.Pod) (time.Time, bool) {
	if pod.Spec.NodeName != "" {
		return time.Time{}, false
	}
	for _, condition := range pod.Status.Conditions {
		if condition.Type != corev1.PodScheduled {
			continue
		}
		if condition.Status != corev1.ConditionFalse ||
			condition.Reason != corev1.PodReasonUnschedulable ||
			condition.LastTransitionTime.IsZero() {
			return time.Time{}, false
		}
		return condition.LastTransitionTime.Time, true
	}
	return time.Time{}, false
}

func (r *RunnerPoolReconciler) provisioningAdmission(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
) (provisioningAdmission, error) {
	var pools tuistv1.RunnerPoolList
	if err := r.List(ctx, &pools, client.InNamespace(pool.Namespace)); err != nil {
		return provisioningAdmission{}, fmt.Errorf("list sibling runner pools: %w", err)
	}

	poolNames := map[string]struct{}{pool.Name: {}}
	capN := int(pool.Spec.Provisioning.MaxConcurrentPerFleetSelectorOrDefault())
	for i := range pools.Items {
		sibling := &pools.Items[i]
		if !isLinuxKataPool(sibling) || sibling.Spec.FleetSelector != pool.Spec.FleetSelector {
			continue
		}
		poolNames[sibling.Name] = struct{}{}
		if siblingCap := int(sibling.Spec.Provisioning.MaxConcurrentPerFleetSelectorOrDefault()); siblingCap < capN {
			capN = siblingCap
		}
	}

	var pods corev1.PodList
	if err := r.List(ctx, &pods,
		client.InNamespace(pool.Namespace),
		client.MatchingLabels{"tuist.dev/runner": "true"},
	); err != nil {
		return provisioningAdmission{}, fmt.Errorf("list fleet runner pods: %w", err)
	}

	// Every provisioning Pod counts, bound or not. An unbound Pod is one
	// the scheduler may bind at any moment, with no further admission
	// check in between, so excluding it would let a backlog accumulate and
	// then start together the instant capacity returns — exactly the
	// simultaneous-sandbox-start burst this ceiling exists to prevent.
	// Pods that can never bind are released by unschedulableTimedOut
	// rather than by being discounted here.
	observed := make(map[string]struct{}, len(pods.Items))
	pendingForFleet := 0
	pendingByPool := make(map[string]int, len(poolNames))
	aliveByPool := make(map[string]int, len(poolNames))
	for i := range pods.Items {
		pod := &pods.Items[i]
		observed[pod.Namespace+"/"+pod.Name] = struct{}{}
		owner := pod.Labels["tuist.dev/runner-pool"]
		if _, ok := poolNames[owner]; !ok {
			continue
		}
		if isAlive(pod) {
			aliveByPool[owner]++
		}
		if !isLinuxProvisioningPod(pod) {
			continue
		}
		pendingForFleet++
		pendingByPool[owner]++
	}

	reserved, reservedByPool := r.creationReservations.reconcile(
		pool.Namespace,
		pool.Spec.FleetSelector,
		observed,
		r.now(),
	)
	pendingForFleet += reserved
	for name, count := range reservedByPool {
		pendingByPool[name] += count
	}
	pendingForPool := pendingByPool[pool.Name]

	// The ceiling is shared, so one pool can hold all of it. Four Pods of a
	// shape no node can seat sit Unschedulable until unschedulableTimedOut
	// reaps them, the pool recreates them at once, and every sibling shape
	// is refused creation for as long as the shortfall lasts: the default
	// shape stayed at zero Pods for an hour with a full queue while a
	// larger shape held the whole budget with Pods that could never bind.
	//
	// So a pool's own share of the ceiling shrinks by one for each sibling
	// that has a replica gap and nothing provisioning. The fleet count is
	// untouched (the burst guarantee is that at most cap sandboxes can start
	// together, and that still holds); what changes is who may top the count
	// back up after a reap. A hog at its share cannot recreate the Pod the
	// timeout released, so the slot goes to the sibling that had none.
	siblingsNeedingSlot := 0
	for i := range pools.Items {
		sibling := &pools.Items[i]
		if _, ok := poolNames[sibling.Name]; !ok || sibling.Name == pool.Name {
			continue
		}
		if int(sibling.Spec.Replicas) > aliveByPool[sibling.Name] && pendingByPool[sibling.Name] == 0 {
			siblingsNeedingSlot++
		}
	}
	poolCap := capN - siblingsNeedingSlot
	if poolCap < 1 {
		poolCap = 1
	}

	var nodes corev1.NodeList
	if err := r.List(ctx, &nodes, client.MatchingLabels{
		fleetNodePoolLabel: pool.Spec.FleetSelector,
	}); err != nil {
		return provisioningAdmission{}, fmt.Errorf("list Linux fleet nodes: %w", err)
	}
	healthyNodes, filtered := summarizeFleetNodes(nodes.Items)
	metrics.RecordFleetNodes(pool.Spec.FleetSelector, pool.Spec.OS, healthyNodes, filtered)
	metrics.RecordPendingProvisioningPods(pool.Name, pendingForPool)

	admission := provisioningAdmission{
		pendingForPool:  pendingForPool,
		pendingForFleet: pendingForFleet,
		cap:             capN,
		poolCap:         poolCap,
		healthyNodes:    healthyNodes,
	}
	if healthyNodes == 0 {
		admission.blockedReason = "no_healthy_node"
		return admission, nil
	}
	if pendingForFleet >= capN {
		admission.blockedReason = "fleet_cap"
		return admission, nil
	}
	if pendingForPool >= poolCap {
		admission.blockedReason = "pool_share"
		return admission, nil
	}
	admission.available = capN - pendingForFleet
	if share := poolCap - pendingForPool; share < admission.available {
		admission.available = share
	}
	return admission, nil
}

func (r *RunnerPoolReconciler) reserveCreatedRunner(pool *tuistv1.RunnerPool, name string) {
	r.creationReservations.add(pool.Namespace, name, pool.Name, pool.Spec.FleetSelector, r.now())
}

func startTimedOut(pod *corev1.Pod, pool *tuistv1.RunnerPool, now time.Time) bool {
	if !isLinuxKataPool(pool) || !isLinuxProvisioningPod(pod) {
		return false
	}
	timeoutSeconds := pool.Spec.Provisioning.StartTimeoutSecondsOrDefault()
	if timeoutSeconds <= 0 {
		return false
	}
	startedAt, ok := linuxProvisioningStartedAt(pod)
	return ok && now.Sub(startedAt) >= time.Duration(timeoutSeconds)*time.Second
}

// unschedulableTimedOut is true once the scheduler has been rejecting a Pod for
// longer than the start timeout. Recreating it cannot conjure capacity, so the
// point is not recovery: an unschedulable Pod holds a slot in the fleet-wide
// provisioning ceiling that it will never convert into a running sandbox, and
// nothing else ever releases it (the bound-Pod start timeout cannot fire on a
// Pod with no node). Left in place it starves every sibling shape sharing the
// FleetSelector of creations. Reaping hands the slot back; the pool's replica
// gap is untouched, so it retries and simply goes unschedulable again while the
// shortfall lasts, at a rate the timeout bounds.
func unschedulableTimedOut(pod *corev1.Pod, pool *tuistv1.RunnerPool, now time.Time) bool {
	if !isLinuxKataPool(pool) || !isLinuxProvisioningPod(pod) {
		return false
	}
	timeoutSeconds := pool.Spec.Provisioning.StartTimeoutSecondsOrDefault()
	if timeoutSeconds <= 0 {
		return false
	}
	rejectedAt, ok := unschedulableSince(pod)
	return ok && now.Sub(rejectedAt) >= time.Duration(timeoutSeconds)*time.Second
}

// linuxProvisioningStartedAt uses the scheduler's transition timestamp rather
// than Pod creation time. A Pod may legitimately wait unscheduled for much
// longer than the sandbox-start timeout; starting the clock earlier would reap
// it immediately after it finally binds.
func linuxProvisioningStartedAt(pod *corev1.Pod) (time.Time, bool) {
	if pod.Spec.NodeName == "" {
		return time.Time{}, false
	}
	for _, condition := range pod.Status.Conditions {
		if condition.Type == corev1.PodScheduled && condition.Status == corev1.ConditionTrue && !condition.LastTransitionTime.IsZero() {
			return condition.LastTransitionTime.Time, true
		}
	}
	return time.Time{}, false
}

func (r *RunnerPoolReconciler) nodeConditionSummary(ctx context.Context, nodeName string) string {
	node := &corev1.Node{}
	if err := r.Get(ctx, client.ObjectKey{Name: nodeName}, node); err != nil {
		return "unavailable: " + err.Error()
	}
	conditions := make([]string, 0, len(node.Status.Conditions))
	for _, condition := range node.Status.Conditions {
		conditions = append(conditions, string(condition.Type)+"="+string(condition.Status))
	}
	return strings.Join(conditions, ",")
}
