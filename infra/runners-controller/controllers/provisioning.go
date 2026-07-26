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

	observed := make(map[string]struct{}, len(pods.Items))
	pendingForFleet := 0
	pendingForPool := 0
	for i := range pods.Items {
		pod := &pods.Items[i]
		observed[pod.Namespace+"/"+pod.Name] = struct{}{}
		if _, ok := poolNames[pod.Labels["tuist.dev/runner-pool"]]; !ok || !isLinuxProvisioningPod(pod) {
			continue
		}
		pendingForFleet++
		if pod.Labels["tuist.dev/runner-pool"] == pool.Name {
			pendingForPool++
		}
	}

	reserved, reservedByPool := r.creationReservations.reconcile(
		pool.Namespace,
		pool.Spec.FleetSelector,
		observed,
		r.now(),
	)
	pendingForFleet += reserved
	pendingForPool += reservedByPool[pool.Name]

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
	admission.available = capN - pendingForFleet
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
