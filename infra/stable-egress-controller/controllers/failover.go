// Package controllers holds the stable-egress failover reconciler.
package controllers

import (
	"context"
	"fmt"
	"net/netip"
	"sort"
	"strconv"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
)

// FloatingIPManager assigns a Hetzner Cloud Floating IP to a server. Kept as an
// interface so the reconciler is testable without the Hetzner API.
type FloatingIPManager interface {
	// Get returns the Floating IP's address (e.g. "116.202.0.10") and the
	// server id it is currently assigned to (0 if unassigned), read together in
	// a single Hetzner API call. The reconciler runs on every relevant node
	// event against a rate-limited token shared with cluster-api, so collapsing
	// the per-reconcile reads to one call keeps it well under the budget.
	Get(ctx context.Context, floatingIPName string) (address string, serverID int64, err error)
	// Assign assigns the Floating IP to the given server id and waits for the
	// assignment to take effect.
	Assign(ctx context.Context, floatingIPName string, serverID int64) error
}

// FailoverReconciler keeps a single healthy node designated as the stable-egress
// gateway: it carries the active label (which the CiliumEgressGatewayPolicy +
// host-configurer coordinate around) and holds the Hetzner Floating IP. It
// adopts a prepared, directly healthy node that already holds the active label,
// so steady state never moves the Floating IP needlessly. Only when there is no
// healthy active node does it fail over to a prepared, directly reachable
// candidate.
type FailoverReconciler struct {
	client.Client
	FIP FloatingIPManager

	FloatingIPName string

	CandidateLabelKey   string
	CandidateLabelValue string
	ActiveLabelKey      string
	ActiveLabelValue    string

	// PreparedPodNamespace and PreparedPod labels identify the host-configurer
	// Pods whose Ready condition proves a candidate has the outbound address
	// before Cilium is allowed to select it.
	PreparedPodNamespace  string
	PreparedPodLabelKey   string
	PreparedPodLabelValue string

	// EgressIPAllowlist, when non-empty, is the documented set of CIDRs
	// customers allowlist. The controller refuses to operate a Floating IP
	// whose address falls outside it — failing closed so we never activate an
	// egress IP customers have not allowlisted.
	EgressIPAllowlist []netip.Prefix

	NodeHealthChecker     NodeHealthChecker
	UnhealthyGracePeriod  time.Duration
	UnpreparedGracePeriod time.Duration
	ResyncInterval        time.Duration
	Now                   func() time.Time

	unhealthySince  map[string]time.Time
	unpreparedSince map[string]time.Time
}

// reconcileKey funnels every Node event to one serialized reconcile of the
// cluster-global gateway state (the controller runs single-concurrency).
const reconcileName = "stable-egress"

func (r *FailoverReconciler) Reconcile(ctx context.Context, _ reconcile.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	var candidates corev1.NodeList
	if err := r.List(ctx, &candidates, client.MatchingLabels{r.CandidateLabelKey: r.CandidateLabelValue}); err != nil {
		return ctrl.Result{}, fmt.Errorf("listing candidate nodes: %w", err)
	}
	var labeled corev1.NodeList
	if err := r.List(ctx, &labeled, client.MatchingLabels{r.ActiveLabelKey: r.ActiveLabelValue}); err != nil {
		return ctrl.Result{}, fmt.Errorf("listing active-labelled nodes: %w", err)
	}

	prepared, err := r.preparedCandidates(ctx, candidates.Items, labeled.Items)
	if err != nil {
		return ctrl.Result{}, err
	}
	nodeHealth := r.probeNodeHealth(ctx, candidates.Items, labeled.Items)
	gatewayPrepared.Reset()
	preparedCandidates := make([]corev1.Node, 0, len(candidates.Items))
	for i := range candidates.Items {
		node := &candidates.Items[i]
		isPrepared := prepared[node.Name]
		gatewayPrepared.WithLabelValues(node.Name).Set(boolFloat(isPrepared))
		if isPrepared && nodeHealth[node.Name] && isPromotionReady(node) {
			preparedCandidates = append(preparedCandidates, *node)
		}
	}

	now := time.Now()
	if r.Now != nil {
		now = r.Now()
	}
	healthyActive, holdFor := r.eligibleActiveNodes(labeled.Items, prepared, nodeHealth, now)
	if len(healthyActive) == 0 && holdFor > 0 {
		gatewayAvailable.Set(0)
		// Keep gatewayActive unchanged so responders retain the identity of the
		// selected gateway while its health is being evaluated.
		logger.Info("holding stable-egress gateway during direct health grace period",
			"remaining", holdFor)
		return ctrl.Result{RequeueAfter: min(holdFor, r.ResyncInterval)}, nil
	}
	desiredNode := selectGateway(preparedCandidates, healthyActive)
	if desiredNode == nil {
		// No healthy active node and no prepared candidate: leave any stale
		// label/IP as-is so an active node recovering in place needs no action,
		// and surface the gap (a monitoring alert on "no active gateway" belongs
		// here).
		gatewayAvailable.Set(0)
		gatewayActive.Reset()
		logger.Error(nil, "no healthy stable-egress gateway: no directly reachable active node and no prepared candidate",
			"candidateLabel", r.CandidateLabelKey+"="+r.CandidateLabelValue)
		return ctrl.Result{RequeueAfter: r.ResyncInterval}, nil
	}
	gatewayAvailable.Set(boolFloat(nodeHealth[desiredNode.Name]))

	serverID, err := parseHCloudServerID(desiredNode.Spec.ProviderID)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("resolving server id for node %q: %w", desiredNode.Name, err)
	}

	// Read the Floating IP's address and current assignment in one API call:
	// both the allowlist gate and the assignment check need it, and this read is
	// the controller's hot path against a rate-limited, shared Hetzner token.
	addr, currentServer, err := r.FIP.Get(ctx, r.FloatingIPName)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("reading Floating IP: %w", err)
	}

	// Fail closed if the Floating IP is not within the documented egress set —
	// activating an un-allowlisted source IP would silently break customers
	// who allowlist our egress. Better a gap than a leak.
	if len(r.EgressIPAllowlist) > 0 {
		ok, err := ipInAllowlist(addr, r.EgressIPAllowlist)
		if err != nil {
			return ctrl.Result{}, err
		}
		if !ok {
			logger.Error(nil, "Floating IP address is outside the documented egress allowlist; refusing to manage it",
				"floatingIP", r.FloatingIPName, "address", addr, "allowlist", prefixesString(r.EgressIPAllowlist))
			return ctrl.Result{RequeueAfter: r.ResyncInterval}, nil
		}
		logger.Info("active egress IP", "address", addr, "node", desiredNode.Name)
	}

	// 1) When moving the Floating IP, first remove every active selector so
	// Cilium never selects a gateway after the provider has routed the address
	// away from it. A temporary absence is safer than two selected gateways.
	if currentServer != serverID {
		if err := r.stripActiveLabels(ctx, ""); err != nil {
			return ctrl.Result{}, err
		}
		logger.Info("reassigning Floating IP", "floatingIP", r.FloatingIPName,
			"fromServer", currentServer, "toServer", serverID, "node", desiredNode.Name)
		if err := r.FIP.Assign(ctx, r.FloatingIPName, serverID); err != nil {
			recoveryErr := r.recoverActiveLabelAfterAssignError(
				ctx,
				desiredNode,
				candidates.Items,
				labeled.Items,
			)
			if recoveryErr != nil {
				return ctrl.Result{}, fmt.Errorf(
					"assigning Floating IP to server %d: %w; recovering active label: %v",
					serverID,
					err,
					recoveryErr,
				)
			}
			return ctrl.Result{}, fmt.Errorf("assigning Floating IP to server %d: %w", serverID, err)
		}
		gatewayFailovers.Inc()
	}

	// 2) Normalize any externally introduced duplicate labels, then select the
	// elected node. Cilium re-selects the gateway on its next reconciliation.
	if err := r.reconcileActiveLabel(ctx, desiredNode); err != nil {
		return ctrl.Result{}, err
	}
	gatewayActive.Reset()
	gatewayActive.WithLabelValues(desiredNode.Name, addr).Set(1)

	return ctrl.Result{RequeueAfter: r.ResyncInterval}, nil
}

func (r *FailoverReconciler) probeNodeHealth(
	ctx context.Context,
	nodeSets ...[]corev1.Node,
) map[string]bool {
	health := map[string]bool{}
	gatewayNodeHealthy.Reset()
	for _, nodes := range nodeSets {
		for i := range nodes {
			node := &nodes[i]
			if _, checked := health[node.Name]; checked {
				continue
			}
			if node.DeletionTimestamp != nil {
				health[node.Name] = false
				gatewayNodeHealthy.WithLabelValues(node.Name).Set(0)
				continue
			}

			healthy, err := r.NodeHealthChecker.Healthy(ctx, node)
			health[node.Name] = healthy
			gatewayNodeHealthy.WithLabelValues(node.Name).Set(boolFloat(healthy))
			if !healthy {
				gatewayHealthCheckFailures.WithLabelValues(node.Name).Inc()
				log.FromContext(ctx).Info("direct gateway node health check failed",
					"node", node.Name, "error", err)
			}
		}
	}
	return health
}

func (r *FailoverReconciler) eligibleActiveNodes(
	labeled []corev1.Node,
	prepared map[string]bool,
	nodeHealth map[string]bool,
	now time.Time,
) ([]corev1.Node, time.Duration) {
	if r.unhealthySince == nil {
		r.unhealthySince = map[string]time.Time{}
	}
	if r.unpreparedSince == nil {
		r.unpreparedSince = map[string]time.Time{}
	}

	activeNames := make(map[string]struct{}, len(labeled))
	eligible := make([]corev1.Node, 0, len(labeled))
	holdFor := time.Duration(0)
	for i := range labeled {
		node := &labeled[i]
		activeNames[node.Name] = struct{}{}
		if node.DeletionTimestamp != nil || node.Spec.Unschedulable {
			delete(r.unhealthySince, node.Name)
			delete(r.unpreparedSince, node.Name)
			continue
		}

		if nodeHealth[node.Name] && prepared[node.Name] {
			delete(r.unhealthySince, node.Name)
			delete(r.unpreparedSince, node.Name)
			eligible = append(eligible, *node)
			continue
		}

		var remaining time.Duration
		if !nodeHealth[node.Name] {
			delete(r.unpreparedSince, node.Name)
			remaining = remainingGrace(r.unhealthySince, node.Name, now, r.UnhealthyGracePeriod)
		} else {
			delete(r.unhealthySince, node.Name)
			remaining = remainingGrace(r.unpreparedSince, node.Name, now, r.UnpreparedGracePeriod)
		}
		if remaining > holdFor {
			holdFor = remaining
		}
	}

	for nodeName := range r.unhealthySince {
		if _, active := activeNames[nodeName]; !active {
			delete(r.unhealthySince, nodeName)
		}
	}
	for nodeName := range r.unpreparedSince {
		if _, active := activeNames[nodeName]; !active {
			delete(r.unpreparedSince, nodeName)
		}
	}
	if len(eligible) > 0 {
		holdFor = 0
	}
	return eligible, holdFor
}

func remainingGrace(
	failures map[string]time.Time,
	nodeName string,
	now time.Time,
	gracePeriod time.Duration,
) time.Duration {
	since, exists := failures[nodeName]
	if !exists {
		since = now
		failures[nodeName] = since
	}
	return gracePeriod - now.Sub(since)
}

func (r *FailoverReconciler) preparedCandidates(
	ctx context.Context,
	nodeSets ...[]corev1.Node,
) (map[string]bool, error) {
	prepared := map[string]bool{}
	if r.PreparedPodNamespace == "" || r.PreparedPodLabelKey == "" {
		for _, nodes := range nodeSets {
			for i := range nodes {
				prepared[nodes[i].Name] = true
			}
		}
		return prepared, nil
	}

	var pods corev1.PodList
	if err := r.List(
		ctx,
		&pods,
		client.InNamespace(r.PreparedPodNamespace),
		client.MatchingLabels{r.PreparedPodLabelKey: r.PreparedPodLabelValue},
	); err != nil {
		return nil, fmt.Errorf("listing host-configurer pods: %w", err)
	}
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Spec.NodeName == "" || pod.DeletionTimestamp != nil {
			continue
		}
		for _, condition := range pod.Status.Conditions {
			if condition.Type == corev1.PodReady && condition.Status == corev1.ConditionTrue {
				prepared[pod.Spec.NodeName] = true
				break
			}
		}
	}
	return prepared, nil
}

func boolFloat(value bool) float64 {
	if value {
		return 1
	}
	return 0
}

// reconcileActiveLabel ensures the active label is present on exactly the
// desired node, cluster-wide. It removes every other selector before adding
// the desired one so Cilium never observes two eligible gateways.
func (r *FailoverReconciler) reconcileActiveLabel(ctx context.Context, desired *corev1.Node) error {
	if err := r.stripActiveLabels(ctx, desired.Name); err != nil {
		return err
	}
	var current corev1.Node
	if err := r.Get(ctx, client.ObjectKey{Name: desired.Name}, &current); err != nil {
		return fmt.Errorf("reading desired active node %q: %w", desired.Name, err)
	}
	if current.Labels[r.ActiveLabelKey] == r.ActiveLabelValue {
		return nil
	}
	patch := client.MergeFrom(current.DeepCopy())
	if current.Labels == nil {
		current.Labels = map[string]string{}
	}
	current.Labels[r.ActiveLabelKey] = r.ActiveLabelValue
	if err := r.Patch(ctx, &current, patch); err != nil {
		return fmt.Errorf("setting active label on node %q: %w", desired.Name, err)
	}
	return nil
}

func (r *FailoverReconciler) stripActiveLabels(ctx context.Context, keepNodeName string) error {
	var labeled corev1.NodeList
	if err := r.List(ctx, &labeled, client.MatchingLabels{r.ActiveLabelKey: r.ActiveLabelValue}); err != nil {
		return fmt.Errorf("listing active-labelled nodes: %w", err)
	}
	for i := range labeled.Items {
		n := &labeled.Items[i]
		if n.Name == keepNodeName {
			continue
		}
		patch := client.MergeFrom(n.DeepCopy())
		delete(n.Labels, r.ActiveLabelKey)
		if err := r.Patch(ctx, n, patch); err != nil {
			return fmt.Errorf("stripping active label from node %q: %w", n.Name, err)
		}
	}
	return nil
}

func (r *FailoverReconciler) recoverActiveLabelAfterAssignError(
	ctx context.Context,
	desired *corev1.Node,
	candidates []corev1.Node,
	previouslyLabeled []corev1.Node,
) error {
	_, observedServer, err := r.FIP.Get(ctx, r.FloatingIPName)
	if err != nil {
		return fmt.Errorf("reading Floating IP after failed assignment: %w", err)
	}
	if observedServer == 0 {
		return nil
	}

	nodes := append([]corev1.Node{*desired}, candidates...)
	nodes = append(nodes, previouslyLabeled...)
	for i := range nodes {
		node := &nodes[i]
		serverID, err := parseHCloudServerID(node.Spec.ProviderID)
		if err == nil && serverID == observedServer {
			return r.reconcileActiveLabel(ctx, node)
		}
	}
	return fmt.Errorf("no Kubernetes node matches observed Hetzner server %d", observedServer)
}

func (r *FailoverReconciler) SetupWithManager(mgr ctrl.Manager) error {
	if r.PreparedPodNamespace == "" || r.PreparedPodLabelKey == "" {
		return fmt.Errorf("prepared Pod namespace and label are required")
	}
	if r.NodeHealthChecker == nil {
		return fmt.Errorf("node health checker is required")
	}
	mapToSingleton := func(context.Context, client.Object) []reconcile.Request {
		return []reconcile.Request{{NamespacedName: types.NamespacedName{Name: reconcileName}}}
	}
	return ctrl.NewControllerManagedBy(mgr).
		Named("stable-egress-failover").
		Watches(&corev1.Node{},
			handler.EnqueueRequestsFromMapFunc(mapToSingleton),
			builder.WithPredicates(r.nodeEventPredicate())).
		Watches(&corev1.Pod{},
			handler.EnqueueRequestsFromMapFunc(mapToSingleton),
			builder.WithPredicates(r.preparedPodEventPredicate())).
		Complete(r)
}

// nodeEventPredicate drops the Node updates the reconciler does not key on —
// chiefly the kubelet status heartbeats and lease renewals that fire every few
// seconds per node — so a reconcile (and its Hetzner API read against a shared,
// rate-limited token) only runs when gateway eligibility can actually change: a
// Ready transition, a candidate/active label change, an address change, or the
// node entering termination. NodeReady only triggers an immediate direct health
// check; it never determines gateway eligibility.
func (r *FailoverReconciler) nodeEventPredicate() predicate.Predicate {
	return predicate.Funcs{
		UpdateFunc: func(e event.UpdateEvent) bool {
			oldNode, ok1 := e.ObjectOld.(*corev1.Node)
			newNode, ok2 := e.ObjectNew.(*corev1.Node)
			if !ok1 || !ok2 {
				return true
			}
			return isNodeReady(oldNode) != isNodeReady(newNode) ||
				oldNode.Labels[r.CandidateLabelKey] != newNode.Labels[r.CandidateLabelKey] ||
				oldNode.Labels[r.ActiveLabelKey] != newNode.Labels[r.ActiveLabelKey] ||
				nodeAddressKey(oldNode) != nodeAddressKey(newNode) ||
				(oldNode.DeletionTimestamp == nil) != (newNode.DeletionTimestamp == nil)
		},
	}
}

// preparedPodEventPredicate wakes the controller as soon as a host-configurer
// Pod becomes Ready, rather than waiting for the periodic resync. Updates that
// add or remove the identifying label are included so preparedness cannot get
// stuck if a Pod is relabelled.
func (r *FailoverReconciler) preparedPodEventPredicate() predicate.Predicate {
	matches := func(object client.Object) bool {
		if object == nil || object.GetNamespace() != r.PreparedPodNamespace {
			return false
		}
		return object.GetLabels()[r.PreparedPodLabelKey] == r.PreparedPodLabelValue
	}
	return predicate.Funcs{
		CreateFunc:  func(e event.CreateEvent) bool { return matches(e.Object) },
		DeleteFunc:  func(e event.DeleteEvent) bool { return matches(e.Object) },
		GenericFunc: func(e event.GenericEvent) bool { return matches(e.Object) },
		UpdateFunc: func(e event.UpdateEvent) bool {
			return matches(e.ObjectOld) || matches(e.ObjectNew)
		},
	}
}

// selectGateway picks the node that should hold the egress gateway. It adopts an
// eligible node that already carries the active label — even one outside the
// candidate pool — so a working gateway is never disturbed (no Floating IP
// churn, no Cilium reconvergence, no egress blip). Only when there is no healthy
// active node does it fail over to the lexically-lowest prepared candidate.
// Returns nil when nothing is eligible.
func selectGateway(candidates, labeled []corev1.Node) *corev1.Node {
	if n := lowestEligible(labeled); n != nil {
		return n
	}
	return lowestEligible(candidates)
}

// lowestEligible returns the lexically-lowest non-terminating node, or nil.
func lowestEligible(nodes []corev1.Node) *corev1.Node {
	var best *corev1.Node
	for i := range nodes {
		n := &nodes[i]
		if n.DeletionTimestamp != nil {
			continue
		}
		if best == nil || n.Name < best.Name {
			best = n
		}
	}
	return best
}

func isNodeReady(n *corev1.Node) bool {
	for _, c := range n.Status.Conditions {
		if c.Type == corev1.NodeReady {
			return c.Status == corev1.ConditionTrue
		}
	}
	return false
}

func nodeAddressKey(node *corev1.Node) string {
	addresses := nodeAddresses(node)
	sort.Strings(addresses)
	return strings.Join(addresses, ",")
}

func isPromotionReady(node *corev1.Node) bool {
	return node.DeletionTimestamp == nil && !node.Spec.Unschedulable && isNodeReady(node)
}

// ipInAllowlist reports whether addr falls within any of the allowed prefixes.
func ipInAllowlist(addr string, allow []netip.Prefix) (bool, error) {
	ip, err := netip.ParseAddr(addr)
	if err != nil {
		return false, fmt.Errorf("parsing Floating IP address %q: %w", addr, err)
	}
	for _, p := range allow {
		if p.Contains(ip) {
			return true, nil
		}
	}
	return false, nil
}

func prefixesString(prefixes []netip.Prefix) string {
	parts := make([]string, len(prefixes))
	for i, p := range prefixes {
		parts[i] = p.String()
	}
	return strings.Join(parts, ",")
}

// parseHCloudServerID extracts the numeric server id from a Hetzner Cloud
// providerID of the form "hcloud://<id>".
func parseHCloudServerID(providerID string) (int64, error) {
	const prefix = "hcloud://"
	if !strings.HasPrefix(providerID, prefix) {
		return 0, fmt.Errorf("providerID %q is not a Hetzner Cloud id", providerID)
	}
	id, err := strconv.ParseInt(strings.TrimPrefix(providerID, prefix), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parsing server id from %q: %w", providerID, err)
	}
	return id, nil
}
