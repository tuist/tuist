// Package controllers holds the stable-egress failover reconciler.
package controllers

import (
	"context"
	"fmt"
	"net/netip"
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
// host-configurer select on) and holds the Hetzner Floating IP. It ADOPTS a
// healthy node that already holds the active label — even one outside the
// candidate pool — so enabling the controller over an existing gateway, or any
// steady state, never moves the Floating IP needlessly (no Cilium
// reconvergence, no egress blip). Only when there is no healthy active node
// does it fail over to a Ready candidate, moving the IP + label together.
type FailoverReconciler struct {
	client.Client
	FIP FloatingIPManager

	FloatingIPName string

	CandidateLabelKey   string
	CandidateLabelValue string
	ActiveLabelKey      string
	ActiveLabelValue    string

	// EgressIPAllowlist, when non-empty, is the documented set of CIDRs
	// customers allowlist. The controller refuses to operate a Floating IP
	// whose address falls outside it — failing closed so we never activate an
	// egress IP customers have not allowlisted.
	EgressIPAllowlist []netip.Prefix

	ResyncInterval time.Duration
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

	desiredNode := selectGateway(candidates.Items, labeled.Items)
	if desiredNode == nil {
		// No healthy active node and no Ready candidate — leave any stale
		// label/IP as-is so an active node recovering in place needs no action,
		// and surface the gap (a monitoring alert on "no active gateway" belongs
		// here).
		logger.Error(nil, "no healthy stable-egress gateway: no healthy active node and no Ready candidate",
			"candidateLabel", r.CandidateLabelKey+"="+r.CandidateLabelValue)
		return ctrl.Result{RequeueAfter: r.ResyncInterval}, nil
	}

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

	// 1) Make the Floating IP follow the elected node (idempotent).
	if currentServer != serverID {
		logger.Info("reassigning Floating IP", "floatingIP", r.FloatingIPName,
			"fromServer", currentServer, "toServer", serverID, "node", desiredNode.Name)
		if err := r.FIP.Assign(ctx, r.FloatingIPName, serverID); err != nil {
			return ctrl.Result{}, fmt.Errorf("assigning Floating IP to server %d: %w", serverID, err)
		}
	}

	// 2) Make the active label track the elected node: add to it, strip from any
	// other node still carrying it. Cilium re-selects the gateway on the next
	// reconciliation (datapath trigger interval is 1s).
	if err := r.reconcileActiveLabel(ctx, desiredNode); err != nil {
		return ctrl.Result{}, err
	}

	return ctrl.Result{RequeueAfter: r.ResyncInterval}, nil
}

// reconcileActiveLabel ensures the active label is present on exactly the
// desired node, cluster-wide. It strips the label from ANY other node that
// carries it — not just candidates — so a stale label (e.g. a manual failover
// on a non-candidate node, or a previous gateway) can't shadow the elected
// node in Cilium's selector and black-hole egress.
func (r *FailoverReconciler) reconcileActiveLabel(ctx context.Context, desired *corev1.Node) error {
	var labeled corev1.NodeList
	if err := r.List(ctx, &labeled, client.MatchingLabels{r.ActiveLabelKey: r.ActiveLabelValue}); err != nil {
		return fmt.Errorf("listing active-labelled nodes: %w", err)
	}
	desiredHasLabel := false
	for i := range labeled.Items {
		n := &labeled.Items[i]
		if n.Name == desired.Name {
			desiredHasLabel = true
			continue
		}
		patch := client.MergeFrom(n.DeepCopy())
		delete(n.Labels, r.ActiveLabelKey)
		if err := r.Patch(ctx, n, patch); err != nil {
			return fmt.Errorf("stripping active label from node %q: %w", n.Name, err)
		}
	}
	if !desiredHasLabel {
		patch := client.MergeFrom(desired.DeepCopy())
		if desired.Labels == nil {
			desired.Labels = map[string]string{}
		}
		desired.Labels[r.ActiveLabelKey] = r.ActiveLabelValue
		if err := r.Patch(ctx, desired, patch); err != nil {
			return fmt.Errorf("setting active label on node %q: %w", desired.Name, err)
		}
	}
	return nil
}

func (r *FailoverReconciler) SetupWithManager(mgr ctrl.Manager) error {
	mapToSingleton := func(context.Context, client.Object) []reconcile.Request {
		return []reconcile.Request{{NamespacedName: types.NamespacedName{Name: reconcileName}}}
	}
	return ctrl.NewControllerManagedBy(mgr).
		Named("stable-egress-failover").
		Watches(&corev1.Node{},
			handler.EnqueueRequestsFromMapFunc(mapToSingleton),
			builder.WithPredicates(r.nodeEventPredicate())).
		Complete(r)
}

// nodeEventPredicate drops the Node updates the reconciler does not key on —
// chiefly the kubelet status heartbeats and lease renewals that fire every few
// seconds per node — so a reconcile (and its Hetzner API read against a shared,
// rate-limited token) only runs when gateway eligibility can actually change: a
// Ready transition, a candidate/active label change, or the node entering
// termination. Create, Delete, and Generic events always reconcile.
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
				(oldNode.DeletionTimestamp == nil) != (newNode.DeletionTimestamp == nil)
		},
	}
}

// selectGateway picks the node that should hold the egress gateway. It adopts a
// healthy node that already carries the active label — even one outside the
// candidate pool — so a working gateway is never disturbed (no Floating IP
// churn, no Cilium reconvergence, no egress blip). Only when there is no healthy
// active node does it fail over to the lexically-lowest Ready candidate.
// Returns nil when nothing is eligible.
func selectGateway(candidates, labeled []corev1.Node) *corev1.Node {
	if n := lowestReady(labeled); n != nil {
		return n
	}
	return lowestReady(candidates)
}

// lowestReady returns the lexically-lowest Ready, non-terminating node, or nil.
func lowestReady(nodes []corev1.Node) *corev1.Node {
	var best *corev1.Node
	for i := range nodes {
		n := &nodes[i]
		if n.DeletionTimestamp != nil || !isNodeReady(n) {
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
