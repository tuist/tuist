package macos

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"sort"
	"strings"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
)

// FleetHashAnnotation is stamped on the target Deployment's pod
// template whenever the set of Ready Mac mini Nodes changes. K8s sees
// the new annotation, mints a new ReplicaSet, and the rolling update
// re-evaluates topologySpreadConstraints — which is the only way to
// rebalance Pods after a fleet-shape change, since the scheduler
// doesn't reconsider placement of running Pods on its own.
const FleetHashAnnotation = "tuist.dev/fleet-hash"

const rolloutRequeueAfter = 30 * time.Second

// baseFleetNodeSelector picks out Mac mini Nodes (the ones
// tart-kubelet registered) from the rest of the cluster. The
// reconciler narrows further at runtime using the target
// Deployment's own `spec.template.spec.nodeSelector` so that, e.g.,
// scaling a builders-fleet (which carries `tuist.dev/runtime=tart`
// but a different `tuist.dev/fleet` value) doesn't unnecessarily
// roll a Deployment scheduled to a different fleet. SetupWithManager
// uses this base selector for the cache-side watch predicate, where
// we don't have a per-Deployment view yet.
var baseFleetNodeSelector = labels.SelectorFromSet(labels.Set{
	"kubernetes.io/os":  "darwin",
	"tuist.dev/runtime": "tart",
})

// FleetSpreadReconciler watches Mac mini Nodes and patches a target
// Deployment's pod-template annotation with a hash of the Ready
// members. When fleet-1's Node transitions Ready, the hash changes
// from `{fleet-0}` to `{fleet-0,fleet-1}` and the Deployment rolls —
// pods then spread one-per-host via the Deployment's existing
// topologySpreadConstraints. Without this, fleet additions don't
// rebalance Pods and operators have to `kubectl rollout restart`
// every time a Mac mini is added or replaced.
//
// We hash on Node Ready, not Machine Phase=Ready, on purpose. The
// machine controller sets Phase=Ready as soon as bootstrap returns,
// but tart-kubelet's first heartbeat may not have landed yet — the
// kube Node can still be NotReady. Rolling at Phase=Ready means the
// new ReplicaSet's Pods can't schedule on the not-yet-Ready Node,
// the topology spread settles for `ScheduleAnyway` on the only
// Ready host (fleet-0 again), and the imbalance reappears.
//
// Disabled when DeploymentName is empty, so OSS deployments that
// don't run xcresult-processor aren't affected by it.
type FleetSpreadReconciler struct {
	client.Client

	// APIReader bypasses the manager's informer cache for Deployment
	// Gets. Without this, controller-runtime would build a Deployment
	// informer and need list+watch RBAC over the resource — broader
	// than the named-resource get+patch we want to grant. Reads via
	// APIReader hit the API server directly. Wired by the manager
	// binary to mgr.GetAPIReader().
	APIReader client.Reader

	// DeploymentName is the workload to patch on fleet-shape change.
	// Empty disables the controller.
	DeploymentName string

	// Namespace is where DeploymentName lives. Chart deploys both the
	// macOS fleet CRs and the workload into the same release
	// namespace; this scopes the Deployment Get/Patch to that one
	// namespace (Nodes themselves are cluster-scoped).
	Namespace string
}

// Reconcile ignores req.NamespacedName: any Node event fires the
// same idempotent "list Ready fleet Nodes, hash, patch deployment"
// pass. Cheap because patches that don't change the value are k8s
// no-ops, and steady state is one List + one Get per Node event.
func (r *FleetSpreadReconciler) Reconcile(ctx context.Context, _ ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("deployment", r.DeploymentName, "namespace", r.Namespace)

	reader := r.APIReader
	if reader == nil {
		reader = r.Client
	}
	var dep appsv1.Deployment
	depKey := types.NamespacedName{Namespace: r.Namespace, Name: r.DeploymentName}
	if err := reader.Get(ctx, depKey, &dep); err != nil {
		if apierrors.IsNotFound(err) {
			// Chart-managed Deployment may not exist yet during
			// first-time bring-up (helm orders resources by kind +
			// our CRs sort before the Deployment's kind). Trust
			// the next reconcile to find it.
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// Hash only Nodes the target Deployment can actually schedule
	// on. The Deployment's pod template carries a nodeSelector
	// (e.g. `tuist.dev/fleet=<macosFleet>` for xcresult-processor);
	// folding it into the Node list filter means scaling a sibling
	// fleet (the builders fleet shares `kubernetes.io/os=darwin` +
	// `tuist.dev/runtime=tart` but pins a different
	// `tuist.dev/fleet` value) doesn't trip a rollout of this
	// Deployment. The base selector still applies — we never want
	// to hash, say, Linux Nodes — but it's combined with whatever
	// the Deployment itself selects on.
	deploymentSelector := labels.SelectorFromSet(labels.Set(dep.Spec.Template.Spec.NodeSelector))
	combinedSelector := mergeSelectors(baseFleetNodeSelector, deploymentSelector)

	var nodes corev1.NodeList
	if err := r.List(ctx, &nodes, &client.ListOptions{LabelSelector: combinedSelector}); err != nil {
		return ctrl.Result{}, err
	}
	hash := readyNodeHash(nodes.Items)

	if dep.Spec.Template.Annotations[FleetHashAnnotation] == hash {
		return ctrl.Result{}, nil
	}
	if !deploymentRolloutSettled(dep) {
		logger.Info("deferring fleet-shape rollout while deployment is still settling", "fleet-hash", hash)
		return ctrl.Result{RequeueAfter: rolloutRequeueAfter}, nil
	}

	patch := client.MergeFrom(dep.DeepCopy())
	if dep.Spec.Template.Annotations == nil {
		dep.Spec.Template.Annotations = map[string]string{}
	}
	dep.Spec.Template.Annotations[FleetHashAnnotation] = hash
	if err := r.Patch(ctx, &dep, patch); err != nil {
		return ctrl.Result{}, err
	}
	logger.Info("rolled deployment on fleet-shape change", "fleet-hash", hash)
	return ctrl.Result{}, nil
}

func deploymentRolloutSettled(dep appsv1.Deployment) bool {
	desired := int32(1)
	if dep.Spec.Replicas != nil {
		desired = *dep.Spec.Replicas
	}

	if dep.Generation > dep.Status.ObservedGeneration {
		return false
	}
	if dep.Status.UpdatedReplicas != desired {
		return false
	}
	if dep.Status.Replicas != desired {
		return false
	}
	if dep.Status.AvailableReplicas != desired {
		return false
	}
	return dep.Status.UnavailableReplicas == 0
}

// readyNodeHash is a stable, order-independent hash of the schedulable
// Mac mini Nodes. Source of truth is `NodeReady=True`: the kube
// scheduler will only place new Pods onto a Ready Node, so anything
// else doesn't count toward the spread. A Node being drained or
// torn down (DeletionTimestamp set) drops out the moment the delete
// is observed, before its Pods get evicted — the Deployment rolls
// onto the surviving hosts ahead of time.
func readyNodeHash(nodes []corev1.Node) string {
	names := make([]string, 0, len(nodes))
	for _, n := range nodes {
		if !n.DeletionTimestamp.IsZero() {
			continue
		}
		if !isNodeReady(n) {
			continue
		}
		names = append(names, n.Name)
	}
	sort.Strings(names)
	sum := sha256.Sum256([]byte(strings.Join(names, ",")))
	return hex.EncodeToString(sum[:8])
}

func isNodeReady(n corev1.Node) bool {
	for _, c := range n.Status.Conditions {
		if c.Type == corev1.NodeReady {
			return c.Status == corev1.ConditionTrue
		}
	}
	return false
}

// mergeSelectors combines two label selectors with AND semantics:
// a Node must satisfy both to pass. The Kubernetes labels package
// exposes `Selector.Add` for this; we use the requirements form so
// the call site doesn't have to deal with label.Requirement
// construction directly.
//
// Returns Nothing() (matches no labels) if either input is nil to
// fail safe — a reconcile with a malformed selector shouldn't
// silently hash the entire Node list and trip a rollout.
func mergeSelectors(a, b labels.Selector) labels.Selector {
	if a == nil || b == nil {
		return labels.Nothing()
	}
	reqs, _ := a.Requirements()
	bReqs, _ := b.Requirements()
	return a.Add(append([]labels.Requirement{}, bReqs...)...).Add(reqs...)
}

// SetupWithManager watches Nodes filtered to the Mac mini fleet —
// that's the source of truth for "Pod can schedule here." Predicate
// trims the watch to fleet Nodes server-side via the cache's label
// selector index, so the operator doesn't churn through Linux node
// updates from the rest of the cluster.
func (r *FleetSpreadReconciler) SetupWithManager(mgr ctrl.Manager) error {
	fleetNode := predicate.NewPredicateFuncs(func(o client.Object) bool {
		return baseFleetNodeSelector.Matches(labels.Set(o.GetLabels()))
	})
	return ctrl.NewControllerManagedBy(mgr).
		Named("fleet-spread").
		For(&corev1.Node{}, builder.WithPredicates(fleetNode)).
		Complete(r)
}
