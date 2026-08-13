package controllers

import (
	"sort"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
)

const (
	// Failures needed inside nodeQuarantineWindow before a node stops
	// receiving runner Pods. One timeout is ordinary noise — a slow
	// image pull, a sandbox that lost a race. A node that cannot start
	// this many consecutive sandboxes is broken in a way that recreating
	// the Pod does not fix.
	nodeQuarantineThreshold = 3

	// Failures older than this stop counting toward the threshold.
	nodeQuarantineWindow = 15 * time.Minute

	// How long a quarantine holds. The breaker is half-open by
	// construction: on expiry the node takes a fresh batch, and if it is
	// still broken those Pods time out and re-quarantine it. Long enough
	// that a churn loop cannot outpace it, short enough that a repaired
	// host rejoins without operator action.
	nodeQuarantineDuration = 30 * time.Minute
)

// nodeQuarantineStore is the fleet's circuit breaker against a node that
// accepts Pods it can never start.
//
// A node can be Ready, schedulable, and free of every pressure condition
// while still failing to create pod cgroups — kubelet reports the failure
// per Pod, not as a node condition, so nodeFilterReason sees nothing wrong.
// Such a node is also the emptiest one in the fleet (nothing it admits ever
// runs), which makes the scheduler actively prefer it. Every Pod it takes
// occupies a slot in the fleet-wide provisioning ceiling until the start
// timeout reaps it, and the replacement lands on the same node: the ceiling
// stays saturated, sibling shapes are refused admission, and the queue
// drains at zero while the fleet reports healthy.
//
// Counting those timeouts per node and steering new Pods away breaks that
// loop using only the Pod create the reconciler already performs — the
// controller holds read-only access to nodes and cannot cordon or taint.
//
// One instance is shared by the RunnerPool and Autoscaler reconcilers: the
// former observes the timeouts, the latter must agree that the node is not
// capacity, and both publish the same fleet-node gauges. A nil *NodeQuarantine
// is a working no-op breaker, so tests and any future caller that does not
// wire one up behave exactly as before.
type NodeQuarantine struct {
	mu       sync.Mutex
	failures map[string][]time.Time
	until    map[string]time.Time
}

func NewNodeQuarantine() *NodeQuarantine {
	return &NodeQuarantine{}
}

// recordStartFailure attributes one pod-start timeout to node. It reports
// whether this failure is the one that tripped the breaker, so the caller
// can log the transition rather than every failure. Pods that never bound
// carry no node name and are ignored.
func (s *NodeQuarantine) recordStartFailure(node string, now time.Time) bool {
	if s == nil || node == "" {
		return false
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.failures == nil {
		s.failures = map[string][]time.Time{}
	}
	if s.until == nil {
		s.until = map[string]time.Time{}
	}

	if quarantinedUntil, ok := s.until[node]; ok && now.Before(quarantinedUntil) {
		return false
	}

	cutoff := now.Add(-nodeQuarantineWindow)
	recent := s.failures[node][:0]
	for _, at := range s.failures[node] {
		if at.After(cutoff) {
			recent = append(recent, at)
		}
	}
	recent = append(recent, now)
	s.failures[node] = recent

	if len(recent) < nodeQuarantineThreshold {
		return false
	}
	// Clearing the counter is what makes expiry half-open: the probe
	// batch after a quarantine starts from zero and has to fail the full
	// threshold again to re-trip.
	delete(s.failures, node)
	s.until[node] = now.Add(nodeQuarantineDuration)
	return true
}

func (s *NodeQuarantine) isQuarantined(node string, now time.Time) bool {
	if s == nil {
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	quarantinedUntil, ok := s.until[node]
	return ok && now.Before(quarantinedUntil)
}

// quarantined returns the nodes currently held out of the fleet, sorted so
// the Pod specs built from it stay byte-stable across reconciles.
func (s *NodeQuarantine) quarantined(now time.Time) []string {
	if s == nil {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	var nodes []string
	for node, quarantinedUntil := range s.until {
		if now.Before(quarantinedUntil) {
			nodes = append(nodes, node)
			continue
		}
		delete(s.until, node)
	}
	sort.Strings(nodes)
	return nodes
}

// sortedKeys renders a quarantine set as the deterministic slice Pod
// specs are built from, so the affinity stays byte-stable across
// reconciles.
func sortedKeys(set map[string]struct{}) []string {
	if len(set) == 0 {
		return nil
	}
	keys := make([]string, 0, len(set))
	for key := range set {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

// quarantinedSet is the membership view summarizeFleetNodes wants.
func (s *NodeQuarantine) quarantinedSet(now time.Time) map[string]struct{} {
	nodes := s.quarantined(now)
	set := make(map[string]struct{}, len(nodes))
	for _, node := range nodes {
		set[node] = struct{}{}
	}
	return set
}

// effectiveQuarantine bounds the breaker to a minority of the fleet.
//
// Holding out every usable node converts a partial fault into a total
// stall: provisioningAdmission blocks on no_healthy_node and the required
// affinity leaves any Pod that is created unschedulable, so the pool
// creates nothing at all for the quarantine's duration. That is strictly
// worse than the behaviour this breaker replaces, where a bad node at
// least churned while its siblings kept working.
//
// The floor matters most on a small fleet, which is exactly where this
// runs: the Linux fleet is two nodes, so a false positive on both would
// take everything down. False positives are plausible because
// startTimedOut measures from bind, so it counts image-pull time — three
// slow pulls inside the window look identical to a broken node.
//
// Releasing every quarantine (rather than keeping an arbitrary one) is
// the honest degradation: if no node can start Pods, containment has
// nothing left to protect, and the operator is told either way by the
// quarantine alert.
func effectiveQuarantine(nodes []corev1.Node, quarantined map[string]struct{}) map[string]struct{} {
	if len(quarantined) == 0 {
		return quarantined
	}

	for i := range nodes {
		if nodeFilterReason(&nodes[i]) != "" {
			continue
		}
		if _, held := quarantined[nodes[i].Name]; !held {
			return quarantined
		}
	}
	return map[string]struct{}{}
}

// applyNodeQuarantine keeps a Pod off quarantined nodes. The requirement is
// hard: a preference would still place the Pod on a broken node once it is
// the emptiest option, which is exactly the state a quarantined node is in.
// Any existing preferred affinity is left intact.
func applyNodeQuarantine(pod *corev1.Pod, quarantined []string) {
	if len(quarantined) == 0 {
		return
	}

	if pod.Spec.Affinity == nil {
		pod.Spec.Affinity = &corev1.Affinity{}
	}
	if pod.Spec.Affinity.NodeAffinity == nil {
		pod.Spec.Affinity.NodeAffinity = &corev1.NodeAffinity{}
	}

	requirement := corev1.NodeSelectorRequirement{
		Key:      corev1.LabelHostname,
		Operator: corev1.NodeSelectorOpNotIn,
		Values:   quarantined,
	}

	required := pod.Spec.Affinity.NodeAffinity.RequiredDuringSchedulingIgnoredDuringExecution
	if required == nil || len(required.NodeSelectorTerms) == 0 {
		pod.Spec.Affinity.NodeAffinity.RequiredDuringSchedulingIgnoredDuringExecution = &corev1.NodeSelector{
			NodeSelectorTerms: []corev1.NodeSelectorTerm{{
				MatchExpressions: []corev1.NodeSelectorRequirement{requirement},
			}},
		}
		return
	}

	// NodeSelectorTerms are ORed, so the exclusion has to join every term
	// to hold. MatchExpressions within a term are ANDed.
	for i := range required.NodeSelectorTerms {
		required.NodeSelectorTerms[i].MatchExpressions = append(
			required.NodeSelectorTerms[i].MatchExpressions, requirement)
	}
}
