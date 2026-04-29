// Package controllers contains the reconcilers for the Scaleway Apple
// Silicon CAPI provider's CRDs.
package controllers

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/bootstrap"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/scaleway"
)

const (
	// MachineFinalizer prevents the CR from being garbage-collected
	// before we've released the underlying Scaleway server (Apple's
	// 24h floor means leaks cost money — this matters).
	MachineFinalizer = "scalewayapplesilicon.cluster.x-k8s.io/finalizer"

	// Conditions surfaced on the CR for operator visibility.
	ProvisionedCondition  clusterv1.ConditionType = "Provisioned"
	BootstrappedCondition clusterv1.ConditionType = "Bootstrapped"
	NodeReadyCondition    clusterv1.ConditionType = "NodeReady"
)

// ScalewayAppleSiliconMachineReconciler reconciles ScalewayAppleSiliconMachine objects.
type ScalewayAppleSiliconMachineReconciler struct {
	client.Client
	Scheme              *runtime.Scheme
	ScalewayClient      *scaleway.Client
	CredentialsManager  *credentials.Manager
	DefaultKubeletVersion string
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconmachines/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconmachines/finalizers,verbs=update
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=machines,verbs=get;list;watch
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=clusters,verbs=get;list;watch
// +kubebuilder:rbac:groups="",resources=secrets,verbs=get;list;watch;create;update
// +kubebuilder:rbac:groups="",resources=nodes,verbs=get;list;watch

func (r *ScalewayAppleSiliconMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	machine := &infrav1.ScalewayAppleSiliconMachine{}
	if err := r.Get(ctx, req.NamespacedName, machine); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// Resolve the parent CAPI Machine (label set by the MachineSet
	// controller). Without it we can't read the cluster the Machine
	// belongs to or its bootstrap data.
	parent, err := util.GetOwnerMachine(ctx, r.Client, machine.ObjectMeta)
	if err != nil {
		return ctrl.Result{}, err
	}
	if parent == nil {
		logger.Info("waiting for owner Machine to be set")
		return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
	}

	patchHelper, err := patch.NewHelper(machine, r.Client)
	if err != nil {
		return ctrl.Result{}, err
	}
	defer func() {
		if perr := patchHelper.Patch(ctx, machine); perr != nil && err == nil {
			err = perr
		}
	}()

	// Handle deletion.
	if !machine.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, machine)
	}

	// Make sure we have a finalizer so we always get a chance to
	// release the Scaleway server before the CR disappears.
	if !controllerutil.ContainsFinalizer(machine, MachineFinalizer) {
		controllerutil.AddFinalizer(machine, MachineFinalizer)
	}

	return r.reconcileNormal(ctx, machine, parent)
}

func (r *ScalewayAppleSiliconMachineReconciler) reconcileNormal(
	ctx context.Context,
	machine *infrav1.ScalewayAppleSiliconMachine,
	parent *clusterv1.Machine,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	// Stage 0: ensure the per-fleet SSH key is registered with Scaleway
	// BEFORE we order the Mac mini. Scaleway only injects project SSH
	// keys at first-boot — keys registered after CreateServer are not
	// auto-installed on the host, leaving us locked out of SSH and
	// unable to bootstrap kubelet. Doing this first means the Mac mini
	// comes up with our pubkey already in ~/.ssh/authorized_keys.
	fleet := machine.Spec.FleetName
	if fleet == "" {
		fleet = machine.Namespace + "-" + machine.Name
	}
	sshKey, err := r.CredentialsManager.EnsureFleetSSHKey(ctx, fleet)
	if err != nil {
		conditions.MarkFalse(machine, BootstrappedCondition, "SSHKeyUnavailable",
			clusterv1.ConditionSeverityError, "%v", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Stage 1: ensure the Scaleway server exists.
	if machine.Status.ServerID == "" {
		machine.Status.Phase = "Provisioning"
		srv, err := r.ScalewayClient.CreateServer(
			ctx,
			machine.Name,
			machine.Spec.Zone,
			machine.Spec.Type,
			machine.Spec.OS,
		)
		if err != nil {
			conditions.MarkFalse(machine, ProvisionedCondition, "ScalewayCreateFailed",
				clusterv1.ConditionSeverityError, "%v", err)
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		}

		machine.Status.ServerID = srv.ID
		machine.Status.Addresses = []clusterv1.MachineAddress{{
			Type:    clusterv1.MachineExternalIP,
			Address: srv.IP,
		}}
		providerID := fmt.Sprintf("scw-applesilicon://%s/%s", machine.Spec.Zone, srv.ID)
		machine.Spec.ProviderID = &providerID

		// Stash the sudo password on the machine resource as an
		// annotation; the bootstrap step needs it but it doesn't
		// belong in spec or status.
		if machine.Annotations == nil {
			machine.Annotations = map[string]string{}
		}
		machine.Annotations["scaleway.tuist.dev/sudo-password"] = srv.SudoPassword
		machine.Annotations["scaleway.tuist.dev/ssh-username"] = srv.SSHUsername
		conditions.MarkTrue(machine, ProvisionedCondition)
		logger.Info("provisioned Scaleway Mac mini", "id", srv.ID, "ip", srv.IP)
	}

	// Stage 2: bootstrap (idempotent — re-running picks up where it
	// left off).
	if !conditions.IsTrue(machine, BootstrappedCondition) {
		machine.Status.Phase = "Bootstrapping"

		ip := machineIP(machine)
		if ip == "" {
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}

		kubeletVersion := machine.Spec.KubeletVersion
		if kubeletVersion == "" {
			kubeletVersion = r.DefaultKubeletVersion
		}
		bootstrapData, err := r.CredentialsManager.MintBootstrap(ctx, kubeletVersion)
		if err != nil {
			conditions.MarkFalse(machine, BootstrappedCondition, "BootstrapMintFailed",
				clusterv1.ConditionSeverityError, "%v", err)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}

		if err := bootstrap.Run(ctx, bootstrap.Config{
			IP:             ip,
			SSHUser:        machine.Annotations["scaleway.tuist.dev/ssh-username"],
			SudoPassword:   machine.Annotations["scaleway.tuist.dev/sudo-password"],
			SSHPrivateKey:  sshKey,
			Hostname:       machine.Name,
			PodCIDR:        machine.Spec.PodCIDR,
			KubeletVersion: bootstrapData.KubeletVersion,
			BootstrapToken: bootstrapData.BootstrapToken,
			APIServer:      bootstrapData.APIServerURL,
			CACertData:     bootstrapData.CACertData,
		}); err != nil {
			conditions.MarkFalse(machine, BootstrappedCondition, "BootstrapFailed",
				clusterv1.ConditionSeverityWarning, "%v", err)
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		}

		conditions.MarkTrue(machine, BootstrappedCondition)
		logger.Info("bootstrap complete", "host", ip)
	}

	// Stage 3: wait for the Node object to report Ready.
	machine.Status.Phase = "WaitingForNode"
	node, err := r.findNode(ctx, machine.Name)
	if err != nil || node == nil {
		conditions.MarkFalse(machine, NodeReadyCondition, "NodeNotRegistered",
			clusterv1.ConditionSeverityInfo, "kubelet hasn't registered with the API server yet")
		return ctrl.Result{RequeueAfter: 15 * time.Second}, nil
	}

	if !nodeReady(node) {
		conditions.MarkFalse(machine, NodeReadyCondition, "NodeNotReady",
			clusterv1.ConditionSeverityInfo, "kubelet registered but Node.Ready=false")
		return ctrl.Result{RequeueAfter: 15 * time.Second}, nil
	}

	conditions.MarkTrue(machine, NodeReadyCondition)
	machine.Status.Ready = true
	machine.Status.Phase = "Ready"
	_ = parent // kept for future: write back addresses, etc.
	return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
}

func (r *ScalewayAppleSiliconMachineReconciler) reconcileDelete(
	ctx context.Context,
	machine *infrav1.ScalewayAppleSiliconMachine,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	machine.Status.Phase = "Deleting"

	if machine.Status.ServerID != "" {
		if err := r.ScalewayClient.DeleteServer(ctx, machine.Status.ServerID, machine.Spec.Zone); err != nil {
			logger.Error(err, "Scaleway delete failed; will retry")
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		}
		machine.Status.ServerID = ""
	}

	controllerutil.RemoveFinalizer(machine, MachineFinalizer)
	return ctrl.Result{}, nil
}

// === helpers ================================================================

func (r *ScalewayAppleSiliconMachineReconciler) findNode(ctx context.Context, hostname string) (*corev1.Node, error) {
	node := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: hostname}, node); err != nil {
		if apierrors.IsNotFound(err) {
			return nil, nil
		}
		return nil, err
	}
	return node, nil
}

func machineIP(m *infrav1.ScalewayAppleSiliconMachine) string {
	for _, a := range m.Status.Addresses {
		if a.Type == clusterv1.MachineExternalIP {
			return a.Address
		}
	}
	return ""
}

func nodeReady(node *corev1.Node) bool {
	for _, c := range node.Status.Conditions {
		if c.Type == corev1.NodeReady {
			return c.Status == corev1.ConditionTrue
		}
	}
	return false
}

func (r *ScalewayAppleSiliconMachineReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.ScalewayAppleSiliconMachine{}).
		Watches(
			&corev1.Node{},
			handler.EnqueueRequestsFromMapFunc(r.nodeToMachine),
			builder.WithPredicates(),
		).
		Watches(
			&clusterv1.Machine{},
			handler.EnqueueRequestsFromMapFunc(r.parentMachineToMachine),
		).
		Complete(r)
}

func (r *ScalewayAppleSiliconMachineReconciler) nodeToMachine(_ context.Context, obj client.Object) []reconcile.Request {
	node, ok := obj.(*corev1.Node)
	if !ok {
		return nil
	}
	// Node name == Machine name (we --hostname-override at kubelet
	// boot to enforce this).
	return []reconcile.Request{{NamespacedName: types.NamespacedName{Name: node.Name}}}
}

func (r *ScalewayAppleSiliconMachineReconciler) parentMachineToMachine(_ context.Context, obj client.Object) []reconcile.Request {
	parent, ok := obj.(*clusterv1.Machine)
	if !ok {
		return nil
	}
	if parent.Spec.InfrastructureRef.Kind != "ScalewayAppleSiliconMachine" {
		return nil
	}
	return []reconcile.Request{{NamespacedName: types.NamespacedName{
		Namespace: parent.Spec.InfrastructureRef.Namespace,
		Name:      parent.Spec.InfrastructureRef.Name,
	}}}
}
