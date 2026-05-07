package controllers

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"sort"
	"strings"

	appsv1 "k8s.io/api/apps/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
)

// FleetHashAnnotation is stamped on the target Deployment's pod
// template whenever the set of Ready Mac minis changes. K8s sees the
// new annotation, mints a new ReplicaSet, and the rolling update
// re-evaluates topologySpreadConstraints — which is the only way to
// rebalance Pods after a fleet-shape change, since the scheduler
// doesn't reconsider placement of running Pods on its own.
const FleetHashAnnotation = "tuist.dev/fleet-hash"

// FleetSpreadReconciler watches ScalewayAppleSiliconMachine and patches
// a target Deployment's pod-template annotation with a hash of the
// Ready fleet members. When fleet-1 transitions Ready, the hash
// changes from `{fleet-0}` to `{fleet-0,fleet-1}` and the Deployment
// rolls — pods then spread one-per-host via the Deployment's existing
// topologySpreadConstraints. Without this, fleet additions don't
// rebalance Pods and operators have to `kubectl rollout restart`
// every time a Mac mini is added or replaced.
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

	// Namespace is where DeploymentName lives. The reconciler also
	// scopes ScalewayAppleSiliconMachine listing to this namespace —
	// fleets are namespace-local in practice (chart deploys both the
	// CRs and the workload into the same release namespace).
	Namespace string
}

// Reconcile ignores req.NamespacedName: any machine event fires the
// same idempotent "list Ready machines, hash, patch deployment" pass.
// Cheap because patches that don't change the value are k8s no-ops,
// and steady state is one List + one Get per machine event.
func (r *FleetSpreadReconciler) Reconcile(ctx context.Context, _ ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("deployment", r.DeploymentName, "namespace", r.Namespace)

	var machines infrav1.ScalewayAppleSiliconMachineList
	if err := r.List(ctx, &machines, client.InNamespace(r.Namespace)); err != nil {
		return ctrl.Result{}, err
	}
	hash := readyFleetHash(machines.Items)

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

	if dep.Spec.Template.Annotations[FleetHashAnnotation] == hash {
		return ctrl.Result{}, nil
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

// readyFleetHash is a stable, order-independent hash of the Ready
// fleet members. Includes only Ready, non-deleting machines: a
// machine flapping through transient phases (Provisioning,
// Bootstrapping) won't roll the workload until the host actually
// comes Ready, and a machine being torn down stops counting the
// moment it's marked for deletion (rather than when its finalizer
// finally clears, which can be minutes later).
func readyFleetHash(machines []infrav1.ScalewayAppleSiliconMachine) string {
	names := make([]string, 0, len(machines))
	for _, m := range machines {
		if !m.DeletionTimestamp.IsZero() {
			continue
		}
		if m.Status.Phase != "Ready" {
			continue
		}
		names = append(names, m.Name)
	}
	sort.Strings(names)
	sum := sha256.Sum256([]byte(strings.Join(names, ",")))
	return hex.EncodeToString(sum[:8])
}

// SetupWithManager wires the controller's only watch:
// ScalewayAppleSiliconMachine. Reconciles ignore the request key
// (we always operate on the configured Deployment), so every
// machine event triggers the same idempotent pass — no Watches()
// gymnastics needed.
func (r *FleetSpreadReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		Named("fleet-spread").
		For(&infrav1.ScalewayAppleSiliconMachine{}).
		Complete(r)
}
