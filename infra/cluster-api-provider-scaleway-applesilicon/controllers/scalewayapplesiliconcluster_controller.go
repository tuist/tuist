package controllers

import (
	"context"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
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
// flips Ready=true once the resource exists and otherwise has no
// per-tick work.
type ScalewayAppleSiliconClusterReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconclusters,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconclusters/status,verbs=get;update;patch

func (r *ScalewayAppleSiliconClusterReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	cluster := &infrav1.ScalewayAppleSiliconCluster{}
	if err := r.Get(ctx, req.NamespacedName, cluster); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	patchHelper, err := patch.NewHelper(cluster, r.Client)
	if err != nil {
		return ctrl.Result{}, err
	}
	defer func() { _ = patchHelper.Patch(ctx, cluster) }()

	cluster.Status.Ready = true
	return ctrl.Result{}, nil
}

func (r *ScalewayAppleSiliconClusterReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.ScalewayAppleSiliconCluster{}).
		Complete(r)
}
