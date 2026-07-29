package shared

import (
	"context"
	"fmt"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// TuistClusterReconciler reconciles TuistCluster objects.
//
// CAPI's contract: an InfrastructureCluster's Status.Ready must flip
// to true before the parent Cluster will accept Machines for it. We
// have nothing real to do at the cluster level (Mac minis join an
// already-running Hetzner-backed control plane), so this reconciler
// flips Ready=true once the resource exists.
//
// We also flip the parent Cluster's ControlPlaneInitialized condition
// to True. Without a managed control plane (no `controlPlaneRef` on
// the Cluster) CAPI core's Machine controller would otherwise wait
// forever for a control plane Machine to acquire `status.nodeRef` —
// that condition is the gate for creating the infrastructure side of
// every Machine (i.e. ScalewayAppleSiliconMachine). Marking the
// condition True here is the standard "externally-managed control
// plane" pattern: our cluster's control plane isn't CAPI-managed, so
// the only authority that can declare it initialized is us.
type TuistClusterReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=tuistclusters,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=tuistclusters/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=clusters,verbs=get;list;watch
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=clusters/status,verbs=get;update;patch

func (r *TuistClusterReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	infraCluster := &infrav1.TuistCluster{}
	if err := r.Get(ctx, req.NamespacedName, infraCluster); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	patchHelper, err := patch.NewHelper(infraCluster, r.Client)
	if err != nil {
		return ctrl.Result{}, err
	}
	defer func() { _ = patchHelper.Patch(ctx, infraCluster) }()

	infraCluster.Status.Ready = true

	// Find the owning Cluster and declare its control plane initialized.
	// `util.GetOwnerCluster` walks the InfrastructureRef OwnerRefs chain
	// CAPI core stamps on this resource. If the parent isn't created yet
	// (first reconcile races with the Cluster controller) we just return
	// and pick it up on the next tick — controller-runtime watches the
	// CR so we'll requeue when CAPI stamps the OwnerRef.
	ownerCluster, err := util.GetOwnerCluster(ctx, r.Client, infraCluster.ObjectMeta)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("get owner Cluster: %w", err)
	}
	if ownerCluster == nil {
		return ctrl.Result{}, nil
	}

	clusterPatchHelper, err := patch.NewHelper(ownerCluster, r.Client)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("patch helper for Cluster: %w", err)
	}
	conditions.MarkTrue(ownerCluster, clusterv1.ControlPlaneInitializedCondition)
	if err := clusterPatchHelper.Patch(ctx, ownerCluster); err != nil {
		return ctrl.Result{}, fmt.Errorf("patch Cluster status: %w", err)
	}

	return ctrl.Result{}, nil
}

func (r *TuistClusterReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.TuistCluster{}).
		// Also reconcile when the parent Cluster changes (e.g. CAPI
		// core stamps the InfrastructureRef OwnerRef on its first
		// reconcile). Without this, the SASC reconcile that flips
		// `ControlPlaneInitialized=True` would only fire on SASC
		// CR mutations + the controller-runtime resync tick (~10
		// min), leaving a window where MachineSet sees
		// `InfrastructureReady=true` but the control-plane gate is
		// still False — and on the very first deploy that window
		// is where Machine/SASM creation has historically gone
		// out of sync (Machines created, SASMs missing).
		Watches(
			&clusterv1.Cluster{},
			handler.EnqueueRequestsFromMapFunc(r.clusterToInfraCluster),
		).
		Complete(r)
}

// clusterToInfraCluster maps a Cluster event to a reconcile request
// for the SASC it references. Returns nothing if the Cluster's
// InfrastructureRef points at a different infrastructure kind.
func (r *TuistClusterReconciler) clusterToInfraCluster(_ context.Context, obj client.Object) []reconcile.Request {
	cluster, ok := obj.(*clusterv1.Cluster)
	if !ok {
		return nil
	}
	if cluster.Spec.InfrastructureRef == nil ||
		cluster.Spec.InfrastructureRef.Kind != "TuistCluster" {
		return nil
	}
	return []reconcile.Request{
		{
			NamespacedName: client.ObjectKey{
				Namespace: cluster.Spec.InfrastructureRef.Namespace,
				Name:      cluster.Spec.InfrastructureRef.Name,
			},
		},
	}
}
