// Package controllers holds the stable-egress failover reconciler.
package controllers

import (
	"context"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
)

// FloatingIPManager assigns a Hetzner Cloud Floating IP to a server. Kept as an
// interface so the reconciler is testable without the Hetzner API.
type FloatingIPManager interface {
	// CurrentServerID returns the server id the Floating IP is currently
	// assigned to, or 0 if it is unassigned.
	CurrentServerID(ctx context.Context, floatingIPName string) (int64, error)
	// Assign assigns the Floating IP to the given server id and waits for the
	// assignment to take effect.
	Assign(ctx context.Context, floatingIPName string, serverID int64) error
}

// FailoverReconciler keeps a single healthy candidate node designated as the
// stable-egress gateway: it carries the active label (which the
// CiliumEgressGatewayPolicy + host-configurer select on) and holds the Hetzner
// Floating IP. On loss of the active node it re-elects another Ready candidate
// and moves both together.
type FailoverReconciler struct {
	client.Client
	FIP FloatingIPManager

	FloatingIPName string

	CandidateLabelKey   string
	CandidateLabelValue string
	ActiveLabelKey      string
	ActiveLabelValue    string

	ResyncInterval time.Duration
}

// reconcileKey funnels every Node event to one serialized reconcile of the
// cluster-global gateway state (the controller runs single-concurrency).
const reconcileName = "stable-egress"

func (r *FailoverReconciler) Reconcile(ctx context.Context, _ reconcile.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	var nodes corev1.NodeList
	if err := r.List(ctx, &nodes, client.MatchingLabels{r.CandidateLabelKey: r.CandidateLabelValue}); err != nil {
		return ctrl.Result{}, fmt.Errorf("listing candidate nodes: %w", err)
	}

	ready := readyCandidateNames(nodes.Items)
	current := r.activeNodeName(nodes.Items)
	desired := selectActive(ready, current)

	if desired == "" {
		// Nothing healthy to fail over to — leave the (stale) label/IP as-is
		// so the active node recovering in place needs no action, and surface
		// the gap. A monitoring alert on "no active gateway" belongs here.
		logger.Error(nil, "no Ready stable-egress candidate node available; egress has no healthy gateway",
			"candidateLabel", r.CandidateLabelKey+"="+r.CandidateLabelValue)
		return ctrl.Result{RequeueAfter: r.ResyncInterval}, nil
	}

	desiredNode := nodeByName(nodes.Items, desired)
	serverID, err := parseHCloudServerID(desiredNode.Spec.ProviderID)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("resolving server id for node %q: %w", desired, err)
	}

	// 1) Make the Floating IP follow the elected node (idempotent).
	currentServer, err := r.FIP.CurrentServerID(ctx, r.FloatingIPName)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("reading Floating IP assignment: %w", err)
	}
	if currentServer != serverID {
		logger.Info("reassigning Floating IP", "floatingIP", r.FloatingIPName,
			"fromServer", currentServer, "toServer", serverID, "node", desired)
		if err := r.FIP.Assign(ctx, r.FloatingIPName, serverID); err != nil {
			return ctrl.Result{}, fmt.Errorf("assigning Floating IP to server %d: %w", serverID, err)
		}
	}

	// 2) Make the active label track the elected node: add to it, strip from any
	// other node still carrying it. Cilium re-selects the gateway on the next
	// reconciliation (datapath trigger interval is 1s).
	if err := r.reconcileActiveLabel(ctx, nodes.Items, desired); err != nil {
		return ctrl.Result{}, err
	}

	return ctrl.Result{RequeueAfter: r.ResyncInterval}, nil
}

func (r *FailoverReconciler) reconcileActiveLabel(ctx context.Context, nodes []corev1.Node, desired string) error {
	for i := range nodes {
		n := &nodes[i]
		hasLabel := n.Labels[r.ActiveLabelKey] == r.ActiveLabelValue
		shouldHave := n.Name == desired
		if hasLabel == shouldHave {
			continue
		}
		patch := client.MergeFrom(n.DeepCopy())
		if shouldHave {
			if n.Labels == nil {
				n.Labels = map[string]string{}
			}
			n.Labels[r.ActiveLabelKey] = r.ActiveLabelValue
		} else {
			delete(n.Labels, r.ActiveLabelKey)
		}
		if err := r.Patch(ctx, n, patch); err != nil {
			return fmt.Errorf("patching active label on node %q: %w", n.Name, err)
		}
	}
	return nil
}

func (r *FailoverReconciler) activeNodeName(nodes []corev1.Node) string {
	for i := range nodes {
		if nodes[i].Labels[r.ActiveLabelKey] == r.ActiveLabelValue {
			return nodes[i].Name
		}
	}
	return ""
}

func (r *FailoverReconciler) SetupWithManager(mgr ctrl.Manager) error {
	mapToSingleton := func(context.Context, client.Object) []reconcile.Request {
		return []reconcile.Request{{NamespacedName: types.NamespacedName{Name: reconcileName}}}
	}
	return ctrl.NewControllerManagedBy(mgr).
		Named("stable-egress-failover").
		Watches(&corev1.Node{}, handler.EnqueueRequestsFromMapFunc(mapToSingleton)).
		Complete(r)
}

// selectActive picks the gateway node: keep the current one if it is still a
// Ready candidate (avoids needless Floating IP churn), otherwise the
// lexically-lowest Ready candidate. Returns "" when nothing is eligible.
func selectActive(readyCandidates []string, current string) string {
	for _, n := range readyCandidates {
		if n == current {
			return current
		}
	}
	if len(readyCandidates) == 0 {
		return ""
	}
	sorted := append([]string(nil), readyCandidates...)
	sort.Strings(sorted)
	return sorted[0]
}

func readyCandidateNames(nodes []corev1.Node) []string {
	var out []string
	for i := range nodes {
		n := &nodes[i]
		if n.DeletionTimestamp != nil {
			continue
		}
		if isNodeReady(n) {
			out = append(out, n.Name)
		}
	}
	return out
}

func isNodeReady(n *corev1.Node) bool {
	for _, c := range n.Status.Conditions {
		if c.Type == corev1.NodeReady {
			return c.Status == corev1.ConditionTrue
		}
	}
	return false
}

func nodeByName(nodes []corev1.Node, name string) *corev1.Node {
	for i := range nodes {
		if nodes[i].Name == name {
			return &nodes[i]
		}
	}
	return nil
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
