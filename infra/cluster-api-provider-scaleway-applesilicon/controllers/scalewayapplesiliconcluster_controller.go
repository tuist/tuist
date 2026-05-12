package controllers

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

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
)

// ScalewayAppleSiliconClusterReconciler reconciles ScalewayAppleSiliconCluster objects.
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
type ScalewayAppleSiliconClusterReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconclusters,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconclusters/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=clusters,verbs=get;list;watch
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=clusters/status,verbs=get;update;patch

func (r *ScalewayAppleSiliconClusterReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	infraCluster := &infrav1.ScalewayAppleSiliconCluster{}
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

func (r *ScalewayAppleSiliconClusterReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.ScalewayAppleSiliconCluster{}).
		Complete(r)
}
