package shared

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/dedibox"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
)

const defaultFailoverIPResync = 5 * time.Minute

// FailoverIPMover routes a vendor failover IP to a box and reports where it
// currently points, so the reconciler only moves it when it is not already on
// the elected box. Target strings are vendor-opaque (OVH service name; Dedibox
// "zone/server-id") and round-trip through TargetForNode / CurrentTarget / Move.
type FailoverIPMover interface {
	// CurrentTarget returns where ip routes now, or "" if unassigned.
	CurrentTarget(ctx context.Context, ip string) (string, error)
	// TargetForNode derives the opaque target for routing ip to node.
	TargetForNode(node *corev1.Node) (string, error)
	// Move routes ip to target (a value previously returned by TargetForNode).
	Move(ctx context.Context, ip, target string) error
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=failoverips,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=failoverips/status,verbs=get;update;patch
// +kubebuilder:rbac:groups="",resources=nodes;pods,verbs=get;list;watch

// FailoverIPReconciler keeps each FailoverIP routed to a healthy box of its pool.
// It adopts the box the IP is already on when that box is still eligible (no
// needless move, no peer-plane blip), and only fails over to another eligible
// box when the current one is gone or its demux is not ready (drain-on-roll).
type FailoverIPReconciler struct {
	client.Client
	Scheme *runtime.Scheme

	// Movers maps a FailoverIP vendor to its IP mover. A vendor missing here
	// (its creds unset in this environment) makes its FailoverIPs a no-op with a
	// surfaced status message rather than an error.
	Movers map[string]FailoverIPMover

	ResyncInterval time.Duration
}

func (r *FailoverIPReconciler) resync() time.Duration {
	if r.ResyncInterval > 0 {
		return r.ResyncInterval
	}
	return defaultFailoverIPResync
}

func (r *FailoverIPReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("failoverip", req.Name)

	fip := &infrav1.FailoverIP{}
	if err := r.Get(ctx, req.NamespacedName, fip); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	mover := r.Movers[fip.Spec.Vendor]
	if mover == nil {
		return r.finish(ctx, fip, "", "", fmt.Sprintf("no mover for vendor %q (creds unset in this environment)", fip.Spec.Vendor))
	}

	var nodes corev1.NodeList
	if err := r.List(ctx, &nodes, client.MatchingLabels(fip.Spec.NodePoolSelector)); err != nil {
		return ctrl.Result{}, fmt.Errorf("listing pool nodes: %w", err)
	}

	ready, err := r.demuxReadyNodes(ctx, fip)
	if err != nil {
		return ctrl.Result{}, err
	}

	eligible := eligibleFailoverNodes(nodes.Items, ready)

	current, err := mover.CurrentTarget(ctx, fip.Spec.IP)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("reading current target of %s: %w", fip.Spec.IP, err)
	}

	desired := selectFailoverNode(eligible, current, mover)
	if desired == nil {
		// Leave the IP where it is and surface the gap: an active box recovering
		// in place then needs no move, and "no eligible box" is alert-worthy.
		logger.Error(nil, "no eligible box for failover IP", "ip", fip.Spec.IP, "pool", fip.Spec.NodePoolSelector)
		return ctrl.Result{RequeueAfter: r.resync()}, r.setStatus(ctx, fip, fip.Status.ActiveNode, current, "no eligible box in pool")
	}

	target, err := mover.TargetForNode(desired)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("resolving target for node %q: %w", desired.Name, err)
	}

	if current != target {
		logger.Info("routing failover IP", "ip", fip.Spec.IP, "from", current, "to", target, "node", desired.Name)
		if err := mover.Move(ctx, fip.Spec.IP, target); err != nil {
			return ctrl.Result{}, fmt.Errorf("routing %s to %s: %w", fip.Spec.IP, target, err)
		}
	}

	return r.finish(ctx, fip, desired.Name, target, "routed")
}

func (r *FailoverIPReconciler) finish(ctx context.Context, fip *infrav1.FailoverIP, node, target, message string) (ctrl.Result, error) {
	return ctrl.Result{RequeueAfter: r.resync()}, r.setStatus(ctx, fip, node, target, message)
}

func (r *FailoverIPReconciler) setStatus(ctx context.Context, fip *infrav1.FailoverIP, node, target, message string) error {
	now := metav1.NewTime(time.Now().UTC())
	patch := client.MergeFrom(fip.DeepCopy())
	fip.Status.ActiveNode = node
	fip.Status.Target = target
	fip.Status.Message = message
	fip.Status.LastReconciledAt = &now
	return r.Status().Patch(ctx, fip, patch)
}

// demuxReadyNodes returns the set of node names that currently run a Ready demux
// pod for this FailoverIP. nil when no DemuxSelector is configured (node
// Readiness alone gates eligibility then).
func (r *FailoverIPReconciler) demuxReadyNodes(ctx context.Context, fip *infrav1.FailoverIP) (map[string]bool, error) {
	if len(fip.Spec.DemuxSelector) == 0 {
		return nil, nil
	}
	namespace := fip.Spec.DemuxNamespace
	if namespace == "" {
		namespace = "kura"
	}
	var pods corev1.PodList
	if err := r.List(ctx, &pods, client.InNamespace(namespace), client.MatchingLabels(fip.Spec.DemuxSelector)); err != nil {
		return nil, fmt.Errorf("listing demux pods: %w", err)
	}
	ready := map[string]bool{}
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Spec.NodeName != "" && isPodReady(pod) {
			ready[pod.Spec.NodeName] = true
		}
	}
	return ready, nil
}

// eligibleFailoverNodes is the Ready, non-terminating pool nodes, further
// restricted to those running a Ready demux pod when demuxReady is non-nil.
func eligibleFailoverNodes(nodes []corev1.Node, demuxReady map[string]bool) []*corev1.Node {
	var eligible []*corev1.Node
	for i := range nodes {
		n := &nodes[i]
		if n.DeletionTimestamp != nil || !isNodeReady(n) {
			continue
		}
		if demuxReady != nil && !demuxReady[n.Name] {
			continue
		}
		eligible = append(eligible, n)
	}
	return eligible
}

// selectFailoverNode adopts the box the IP is already on when it is still
// eligible (no move), else picks the lexically-lowest eligible box.
func selectFailoverNode(eligible []*corev1.Node, current string, mover FailoverIPMover) *corev1.Node {
	var lowest *corev1.Node
	for _, n := range eligible {
		if current != "" {
			if t, err := mover.TargetForNode(n); err == nil && t == current {
				return n
			}
		}
		if lowest == nil || n.Name < lowest.Name {
			lowest = n
		}
	}
	return lowest
}

func isNodeReady(n *corev1.Node) bool {
	for _, c := range n.Status.Conditions {
		if c.Type == corev1.NodeReady {
			return c.Status == corev1.ConditionTrue
		}
	}
	return false
}

func isPodReady(p *corev1.Pod) bool {
	if p.DeletionTimestamp != nil {
		return false
	}
	for _, c := range p.Status.Conditions {
		if c.Type == corev1.PodReady {
			return c.Status == corev1.ConditionTrue
		}
	}
	return false
}

func (r *FailoverIPReconciler) SetupWithManager(mgr ctrl.Manager) error {
	toAll := func(ctx context.Context, _ client.Object) []reconcile.Request {
		var list infrav1.FailoverIPList
		if err := r.List(ctx, &list); err != nil {
			return nil
		}
		reqs := make([]reconcile.Request, 0, len(list.Items))
		for i := range list.Items {
			reqs = append(reqs, reconcile.Request{NamespacedName: types.NamespacedName{Name: list.Items[i].Name}})
		}
		return reqs
	}
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.FailoverIP{}).
		Watches(&corev1.Node{}, handler.EnqueueRequestsFromMapFunc(toAll), builder.WithPredicates(nodeFailoverPredicate())).
		Watches(&corev1.Pod{}, handler.EnqueueRequestsFromMapFunc(toAll), builder.WithPredicates(demuxPodPredicate())).
		Complete(r)
}

// nodeFailoverPredicate keeps reconciles to the node transitions that change
// eligibility — Ready flips and entering termination — dropping the per-second
// kubelet heartbeats.
func nodeFailoverPredicate() predicate.Predicate {
	return predicate.Funcs{
		UpdateFunc: func(e event.UpdateEvent) bool {
			oldNode, ok1 := e.ObjectOld.(*corev1.Node)
			newNode, ok2 := e.ObjectNew.(*corev1.Node)
			if !ok1 || !ok2 {
				return true
			}
			return isNodeReady(oldNode) != isNodeReady(newNode) ||
				(oldNode.DeletionTimestamp == nil) != (newNode.DeletionTimestamp == nil)
		},
	}
}

// demuxPodPredicate restricts the Pod watch to peer-demux pods and to readiness
// transitions, so the IP drains off a box whose demux is rolling.
func demuxPodPredicate() predicate.Predicate {
	isDemux := func(o client.Object) bool {
		return o.GetLabels()["app.kubernetes.io/component"] == "peer-demux"
	}
	return predicate.Funcs{
		CreateFunc:  func(e event.CreateEvent) bool { return isDemux(e.Object) },
		DeleteFunc:  func(e event.DeleteEvent) bool { return isDemux(e.Object) },
		GenericFunc: func(e event.GenericEvent) bool { return isDemux(e.Object) },
		UpdateFunc: func(e event.UpdateEvent) bool {
			if !isDemux(e.ObjectNew) {
				return false
			}
			oldPod, ok1 := e.ObjectOld.(*corev1.Pod)
			newPod, ok2 := e.ObjectNew.(*corev1.Pod)
			if !ok1 || !ok2 {
				return true
			}
			return isPodReady(oldPod) != isPodReady(newPod)
		},
	}
}

// OVHFailoverMover routes an OVH failover IP block to a dedicated server.
type OVHFailoverMover struct {
	Client *ovh.Client
}

func (m OVHFailoverMover) CurrentTarget(ctx context.Context, ip string) (string, error) {
	return m.Client.IPRoutedTo(ctx, ip)
}

func (m OVHFailoverMover) TargetForNode(node *corev1.Node) (string, error) {
	return ovhServiceNameFromProviderID(node.Spec.ProviderID)
}

func (m OVHFailoverMover) Move(ctx context.Context, ip, target string) error {
	return m.Client.MoveIP(ctx, ip, target)
}

// ovhServiceNameFromProviderID extracts the service name from "ovh://<dc>/<svc>".
func ovhServiceNameFromProviderID(providerID string) (string, error) {
	rest, ok := strings.CutPrefix(providerID, "ovh://")
	if !ok {
		return "", fmt.Errorf("providerID %q is not an OVH id", providerID)
	}
	_, svc, ok := strings.Cut(rest, "/")
	if !ok || svc == "" {
		return "", fmt.Errorf("providerID %q has no service name", providerID)
	}
	return svc, nil
}

// DediboxFailoverMover routes a Scaleway Dedibox failover IP to a server by
// re-attaching it. The target is "zone/server-id" parsed from the node
// providerID.
type DediboxFailoverMover struct {
	Client *dedibox.Client
	Zones  []string
}

func (m DediboxFailoverMover) CurrentTarget(ctx context.Context, ip string) (string, error) {
	fip, _, err := m.Client.FailoverIPByAddress(ctx, m.Zones, ip)
	if err != nil {
		return "", err
	}
	if fip.ServerID == nil || fip.ServerZone == nil {
		return "", nil
	}
	return fmt.Sprintf("%s/%d", *fip.ServerZone, *fip.ServerID), nil
}

func (m DediboxFailoverMover) TargetForNode(node *corev1.Node) (string, error) {
	rest, ok := strings.CutPrefix(node.Spec.ProviderID, "dedibox://")
	if !ok || rest == "" {
		return "", fmt.Errorf("providerID %q is not a Dedibox id", node.Spec.ProviderID)
	}
	return rest, nil
}

func (m DediboxFailoverMover) Move(ctx context.Context, ip, target string) error {
	zone, serverID, err := parseDediboxTarget(target)
	if err != nil {
		return err
	}
	fip, _, err := m.Client.FailoverIPByAddress(ctx, m.Zones, ip)
	if err != nil {
		return err
	}
	return m.Client.AttachFailoverIP(ctx, zone, serverID, fip.ID)
}

func parseDediboxTarget(target string) (string, uint64, error) {
	zone, idStr, ok := strings.Cut(target, "/")
	if !ok || zone == "" || idStr == "" {
		return "", 0, fmt.Errorf("dedibox target %q is not zone/server-id", target)
	}
	id, err := strconv.ParseUint(idStr, 10, 64)
	if err != nil {
		return "", 0, fmt.Errorf("parsing dedibox server id from %q: %w", target, err)
	}
	return zone, id, nil
}
