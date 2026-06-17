package controllers

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util"
	"sigs.k8s.io/cluster-api/util/annotations"
	"sigs.k8s.io/cluster-api/util/patch"

	"github.com/scaleway/scaleway-sdk-go/scw"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/kubeconfig"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/scaleway"
)

const (
	// InstanceMachineFinalizer guards the Scaleway instance: it stays on
	// the CR until the underlying server is deleted, so a CR removed
	// before its instance is torn down doesn't strand a paid server.
	InstanceMachineFinalizer = "scalewayinstance.cluster.x-k8s.io/finalizer"

	// pnIPv4Label is the node label dispatch reads as the Private-Network
	// address of the runner-cache node. kubelet can't self-set tuist.dev/*
	// labels under NodeRestriction, so the controller patches it.
	pnIPv4Label = "tuist.dev/pn-ipv4"

	// linuxNodeIdentityClusterRole binds the Linux kura node's kubelet identity
	// to the built-in system:node ClusterRole — the complete, canonical kubelet
	// permission set — instead of the chart's scoped tart-kubelet role (which
	// only covers what the macOS shim exercises). A real Linux kubelet needs the
	// full set (leases, services, PVCs, CSI, ...), and discovering those one
	// forbidden error at a time is its own kind of outage.
	linuxNodeIdentityClusterRole = "system:node"
)

// ScalewayInstanceMachineReconciler reconciles a ScalewayInstanceMachine: it
// orders a regular Scaleway Instance, hands it the CAPI kubeadm cloud-init as
// user-data so it self-joins, links the resulting Node by providerID, and
// stamps the dynamic pn-ipv4 label. The provider runs in the same cluster the
// nodes join, so r.Client reaches both the CRs and the Nodes.
type ScalewayInstanceMachineReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	ScalewayClient *scaleway.InstanceClient
	Recorder       record.EventRecorder

	// CredentialsManager mints the kubelet node identity (token + CA), and
	// Kubeconfig renders it into a kubelet kubeconfig — the same machinery
	// the Apple Silicon reconciler uses. The node self-registers with that
	// kubeconfig; no CAPI kubeadm bootstrap is involved.
	CredentialsManager *credentials.Manager
	Kubeconfig         *kubeconfig.Builder

	// KubernetesMinor is the pkgs.k8s.io channel the cloud-init installs
	// kubelet from (e.g. "v1.34"); keep in step with the control plane.
	KubernetesMinor string

	// DefaultImage / DefaultZone fill in a Machine spec that left them
	// empty (the kubebuilder defaults cover the common path; these guard
	// standalone CRs and older templates).
	DefaultImage string
	DefaultZone  string
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayinstancemachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayinstancemachines/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayinstancemachines/finalizers,verbs=update
// +kubebuilder:rbac:groups="",resources=nodes,verbs=get;list;watch;patch
// +kubebuilder:rbac:groups="",resources=secrets,verbs=get;list;watch

func (r *ScalewayInstanceMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	machine := &infrav1.ScalewayInstanceMachine{}
	if getErr := r.Get(ctx, req.NamespacedName, machine); getErr != nil {
		if apierrors.IsNotFound(getErr) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, getErr
	}

	patchHelper, helperErr := patch.NewHelper(machine, r.Client)
	if helperErr != nil {
		return ctrl.Result{}, helperErr
	}
	defer func() {
		if patchErr := patchHelper.Patch(ctx, machine); patchErr != nil && err == nil {
			err = patchErr
		}
	}()

	ownerMachine, ownerErr := util.GetOwnerMachine(ctx, r.Client, machine.ObjectMeta)
	if ownerErr != nil {
		return ctrl.Result{}, fmt.Errorf("get owner Machine: %w", ownerErr)
	}

	if !machine.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, machine)
	}

	if !controllerutil.ContainsFinalizer(machine, InstanceMachineFinalizer) {
		controllerutil.AddFinalizer(machine, InstanceMachineFinalizer)
	}

	var cluster *clusterv1.Cluster
	if ownerMachine != nil && ownerMachine.Spec.ClusterName != "" {
		cluster = &clusterv1.Cluster{}
		if err := r.Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: ownerMachine.Spec.ClusterName}, cluster); err != nil {
			if apierrors.IsNotFound(err) {
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			return ctrl.Result{}, err
		}
	}

	if cluster != nil && cluster.Spec.Paused {
		return ctrl.Result{}, nil
	}
	if annotations.HasPaused(machine) {
		return ctrl.Result{}, nil
	}
	if cluster != nil && !cluster.Status.InfrastructureReady {
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	return r.reconcileNormal(ctx, machine, ownerMachine)
}

func (r *ScalewayInstanceMachineReconciler) reconcileNormal(
	ctx context.Context,
	machine *infrav1.ScalewayInstanceMachine,
	ownerMachine *clusterv1.Machine,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	zone, err := scw.ParseZone(firstNonEmpty(machine.Spec.Zone, r.DefaultZone))
	if err != nil {
		return r.fail(machine, "InvalidZone", fmt.Sprintf("zone %q: %v", machine.Spec.Zone, err))
	}

	// Provision: find-or-create the server named after this Machine, then run
	// the post-create steps (set user-data, attach PN, power on) idempotently.
	// The kubelet identity + cloud-init are (re)computed every pass, and
	// user-data is set before power-on, so a server created but not yet
	// configured (a partial-create failure) is finished on the next reconcile
	// instead of booting blank. ServerID is recorded as soon as the server
	// exists, so a mid-provision failure leaves a cleanable instance; providerID
	// is set only once every step succeeds, so a transient failure retries
	// instead of stranding a half-configured node.
	if machine.Spec.ProviderID == nil || *machine.Spec.ProviderID == "" {
		server, findErr := r.ScalewayClient.FindServerByName(ctx, zone, machine.Name)
		if findErr != nil {
			return ctrl.Result{}, findErr
		}

		identity, idErr := r.CredentialsManager.EnsureNodeIdentity(ctx, machine.Name, linuxNodeIdentityClusterRole)
		if idErr != nil {
			machine.Status.Phase = "Pending"
			return ctrl.Result{RequeueAfter: 20 * time.Second}, fmt.Errorf("mint node identity: %w", idErr)
		}
		kubeconfigYAML, kcErr := r.Kubeconfig.Render(ctx, machine.Name, identity.Token, identity.CA)
		if kcErr != nil {
			return ctrl.Result{}, fmt.Errorf("render kubelet kubeconfig: %w", kcErr)
		}
		cloudInit := renderLinuxCloudInitWithOptions(linuxCloudInitOptions{
			NodeName:       machine.Name,
			KubeconfigYAML: kubeconfigYAML,
			K8sMinor:       firstNonEmpty(r.KubernetesMinor, "v1.34"),
			Taints:         machine.Spec.NodeTaints,
			ClusterDNS:     discoverClusterDNS(ctx, r.Client),
		})

		if server == nil {
			created, createErr := r.ScalewayClient.CreateInstance(ctx, scaleway.CreateInstanceParams{
				Name:             machine.Name,
				Zone:             zone,
				CommercialType:   machine.Spec.CommercialType,
				ImageLabel:       firstNonEmpty(machine.Spec.Image, r.DefaultImage),
				RootVolumeGB:     machine.Spec.RootVolumeGB,
				PrivateNetworkID: machine.Spec.PrivateNetworkID,
				Tags:             []string{"capi", "scalewayinstancemachine=" + machine.Name},
			})
			if createErr != nil {
				return ctrl.Result{}, createErr
			}
			server = created
			logger.Info("provisioned Scaleway instance", "id", server.ID)
			r.event(machine, "Provisioned", "Ordered Scaleway instance %s", server.ID)
		}
		machine.Status.ServerID = server.ID

		if err := r.ScalewayClient.EnsureUserData(ctx, zone, server, []byte(cloudInit)); err != nil {
			return ctrl.Result{}, err
		}
		if err := r.ScalewayClient.EnsurePrivateNIC(ctx, zone, server, machine.Spec.PrivateNetworkID); err != nil {
			return ctrl.Result{}, err
		}
		if err := r.ScalewayClient.EnsurePoweredOn(ctx, zone, server); err != nil {
			return ctrl.Result{}, err
		}

		providerID := scaleway.ProviderID(zone, server.ID)
		machine.Spec.ProviderID = &providerID
		machine.Status.Phase = "Provisioning"
		return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
	}

	// Provisioned: link + finish once the kubeadm-joined Node appears.
	node := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: machine.Name}, node); err != nil {
		if apierrors.IsNotFound(err) {
			machine.Status.Phase = "Bootstrapping"
			return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
		}
		return ctrl.Result{}, err
	}

	if err := r.reconcileNode(ctx, machine, node); err != nil {
		return ctrl.Result{}, err
	}

	// The PN IPAM address can lag the node going Ready, so keep reconciling
	// until the pn-ipv4 label is stamped — otherwise a node that becomes Ready
	// before its address resolves would never get labelled (dispatch needs it
	// to route runner cache traffic over the Private Network).
	pnLabelPending := machine.Spec.PrivateNetworkID != "" && node.Labels[pnIPv4Label] == ""

	if nodeReady(node) {
		machine.Status.Ready = true
		machine.Status.Phase = "Ready"
		if pnLabelPending {
			return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
		}
		return ctrl.Result{}, nil
	}
	machine.Status.Phase = "Bootstrapping"
	return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
}

// reconcileNode stamps the foreign providerID (so CAPI links Machine↔Node)
// and the dynamic pn-ipv4 label onto the Node, both idempotently.
func (r *ScalewayInstanceMachineReconciler) reconcileNode(ctx context.Context, machine *infrav1.ScalewayInstanceMachine, node *corev1.Node) error {
	helper, err := patch.NewHelper(node, r.Client)
	if err != nil {
		return err
	}
	changed := false

	if node.Spec.ProviderID == "" && machine.Spec.ProviderID != nil {
		node.Spec.ProviderID = *machine.Spec.ProviderID
		changed = true
	}

	if machine.Spec.PrivateNetworkID != "" && node.Labels[pnIPv4Label] == "" {
		logger := log.FromContext(ctx)
		ip, ipErr := r.privateNetworkIP(ctx, machine)
		switch {
		case ipErr != nil:
			logger.Info("pn-ipv4 unresolved, will retry", "node", node.Name, "err", ipErr.Error())
		case ip == "":
			logger.Info("pn-ipv4 IPAM address not assigned yet, will retry", "node", node.Name)
		default:
			if node.Labels == nil {
				node.Labels = map[string]string{}
			}
			node.Labels[pnIPv4Label] = ip
			changed = true
			logger.Info("stamped pn-ipv4 label", "node", node.Name, "ip", ip)
		}
	}

	if !changed {
		return nil
	}
	return helper.Patch(ctx, node)
}

func (r *ScalewayInstanceMachineReconciler) privateNetworkIP(ctx context.Context, machine *infrav1.ScalewayInstanceMachine) (string, error) {
	zone, err := scw.ParseZone(firstNonEmpty(machine.Spec.Zone, r.DefaultZone))
	if err != nil {
		return "", err
	}
	server, err := r.ScalewayClient.GetServer(ctx, zone, machine.Status.ServerID)
	if err != nil {
		return "", err
	}
	return r.ScalewayClient.PrivateNetworkIP(ctx, server, machine.Spec.PrivateNetworkID)
}

func (r *ScalewayInstanceMachineReconciler) reconcileDelete(ctx context.Context, machine *infrav1.ScalewayInstanceMachine) (ctrl.Result, error) {
	if machine.Status.ServerID != "" {
		zone, err := scw.ParseZone(firstNonEmpty(machine.Spec.Zone, r.DefaultZone))
		if err == nil {
			done, delErr := r.ScalewayClient.DeleteInstance(ctx, zone, machine.Status.ServerID)
			if delErr != nil {
				r.event(machine, "DeleteFailed", "delete Scaleway instance %s: %v (will retry)", machine.Status.ServerID, delErr)
				return ctrl.Result{}, delErr
			}
			if !done {
				machine.Status.Phase = "Deleting"
				return ctrl.Result{RequeueAfter: 15 * time.Second}, nil
			}
		}
	}

	// Drop the per-machine kubelet identity (ServiceAccount + token Secret +
	// ClusterRoleBinding) once the instance is gone, so a deleted machine
	// doesn't leave behind a long-lived token bound to system:node.
	if err := r.CredentialsManager.DeleteNodeIdentity(ctx, machine.Name); err != nil {
		r.event(machine, "DeleteIdentityFailed", "delete node identity: %v (will retry)", err)
		return ctrl.Result{}, err
	}

	controllerutil.RemoveFinalizer(machine, InstanceMachineFinalizer)
	return ctrl.Result{}, nil
}

func (r *ScalewayInstanceMachineReconciler) fail(machine *infrav1.ScalewayInstanceMachine, reason, message string) (ctrl.Result, error) {
	machine.Status.Phase = "Failed"
	machine.Status.FailureReason = &reason
	machine.Status.FailureMessage = &message
	r.event(machine, reason, "%s", message)
	return ctrl.Result{}, nil
}

func (r *ScalewayInstanceMachineReconciler) event(machine *infrav1.ScalewayInstanceMachine, reason, format string, args ...any) {
	if r.Recorder != nil {
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, reason, format, args...)
	}
}

func (r *ScalewayInstanceMachineReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.ScalewayInstanceMachine{}).
		Complete(r)
}

func nodeReady(node *corev1.Node) bool {
	for _, c := range node.Status.Conditions {
		if c.Type == corev1.NodeReady && c.Status == corev1.ConditionTrue {
			return true
		}
	}
	return false
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
