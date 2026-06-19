package linux

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
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/dedibox"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/kubeconfig"
	"github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	// DediboxMachineFinalizer guards the CR until the node identity is cleaned
	// up. Like OVH, a Dedibox server is a monthly contract, so CR deletion
	// leaves the physical box intact (release is "drop the Node + identity");
	// terminating the contract is an operator action.
	DediboxMachineFinalizer = "dedibox.cluster.x-k8s.io/finalizer"

	// dediboxBootstrapUser is the login the online.net install authorizes the
	// SSH key for. online.net adds the key to root's authorized_keys, so the
	// self-join runs directly as root (no sudo). VERIFY against a live install.
	dediboxBootstrapUser = "root"

	// dediboxInstanceType is the node.cluster.x-k8s.io/instance-type label value
	// the self-join stamps.
	dediboxInstanceType = "dedibox"
)

// DediboxMachineReconciler reconciles a DediboxMachine: it adopts a pre-ordered
// online.net Dedibox server by hostname prefix, drives the OS install, then
// SSH-delivers the shared Linux self-join over its public IP. Structurally a
// twin of the OVH kind (customer-facing public box, no Scaleway Private
// Network; the online.net RPN private mesh is a multi-box follow-up).
type DediboxMachineReconciler struct {
	client.Client
	// APIReader is the uncached reader for the cross-namespace kube-dns read.
	APIReader     client.Reader
	Scheme        *runtime.Scheme
	DediboxClient *dedibox.Client
	Recorder      record.EventRecorder

	CredentialsManager *credentials.Manager
	Kubeconfig         *kubeconfig.Builder

	KubernetesMinor   string
	DefaultDatacenter string
	DefaultOS         string
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=dediboxmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=dediboxmachines/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=dediboxmachines/finalizers,verbs=update

func (r *DediboxMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	machine := &infrav1.DediboxMachine{}
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

	if !controllerutil.ContainsFinalizer(machine, DediboxMachineFinalizer) {
		controllerutil.AddFinalizer(machine, DediboxMachineFinalizer)
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

	return r.reconcileNormal(ctx, machine)
}

func (r *DediboxMachineReconciler) reconcileNormal(ctx context.Context, machine *infrav1.DediboxMachine) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	datacenter := firstNonEmpty(machine.Spec.Datacenter, r.DefaultDatacenter)

	if machine.Spec.ProviderID == nil || *machine.Spec.ProviderID == "" {
		fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
		privateKey, keyErr := r.CredentialsManager.EnsureFleetSSHKey(ctx, fleet)
		if keyErr != nil {
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "SSHKeyUnavailable",
				clusterv1.ConditionSeverityError, "%v", keyErr)
			machine.Status.Phase = "Pending"
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		publicKey, pubErr := sshPublicKey(privateKey)
		if pubErr != nil {
			return ctrl.Result{}, fmt.Errorf("derive ssh public key: %w", pubErr)
		}

		// Adopt: claim a free pre-ordered box not already held by a sibling CR.
		if machine.Status.ServerID == 0 {
			claimed, claimErr := r.claimedServerIDs(ctx, machine)
			if claimErr != nil {
				return ctrl.Result{}, claimErr
			}
			server, adoptErr := r.DediboxClient.FindAdoptableServer(ctx, dedibox.AdoptParams{
				Datacenter:     datacenter,
				HostnamePrefix: machine.Spec.AdoptHostnamePrefix,
			}, claimed)
			if adoptErr != nil {
				return ctrl.Result{}, adoptErr
			}
			if server == nil {
				conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAdoptableServer",
					clusterv1.ConditionSeverityInfo,
					"no free pre-ordered Dedibox server under %q in %s; awaiting capacity", machine.Spec.AdoptHostnamePrefix, datacenter)
				machine.Status.Phase = "Adopting"
				logger.Info("no adoptable Dedibox server yet", "prefix", machine.Spec.AdoptHostnamePrefix, "datacenter", datacenter)
				return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
			}
			machine.Status.ServerID = server.ID
			machine.Status.Addresses = []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: server.PublicIPv4()}}
			machine.Status.Phase = "Adopting"
			r.event(machine, "Adopted", "Adopted Dedibox server %d in %s", server.ID, datacenter)
			logger.Info("adopted Dedibox server", "id", server.ID, "datacenter", datacenter)
		}

		keyName := fleet
		if err := r.DediboxClient.EnsureSSHKey(ctx, keyName, publicKey); err != nil {
			return ctrl.Result{}, fmt.Errorf("ensure Dedibox ssh key: %w", err)
		}

		state, stateErr := r.DediboxClient.InstallState(ctx, machine.Status.ServerID)
		if stateErr != nil {
			return ctrl.Result{}, stateErr
		}
		switch state {
		case dedibox.InstallFailed:
			return r.fail(machine, "InstallFailed",
				fmt.Sprintf("Dedibox server %d OS install failed", machine.Status.ServerID))
		case dedibox.InstallPending:
			if !conditions.IsTrue(machine, OSInstallRequestedCondition) {
				osID, osErr := r.DediboxClient.ResolveOSID(ctx, machine.Status.ServerID, firstNonEmpty(machine.Spec.OS, r.DefaultOS))
				if osErr != nil {
					return ctrl.Result{}, osErr
				}
				if err := r.DediboxClient.StartInstall(ctx, machine.Status.ServerID, dedibox.InstallParams{
					OSID:       osID,
					Hostname:   machine.Name,
					SSHKeyName: keyName,
				}); err != nil {
					return ctrl.Result{}, fmt.Errorf("start Dedibox install: %w", err)
				}
				conditions.MarkTrue(machine, OSInstallRequestedCondition)
				r.event(machine, "Installing", "Started OS install on Dedibox server %d", machine.Status.ServerID)
			}
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "Installing",
				clusterv1.ConditionSeverityInfo, "server %d installing", machine.Status.ServerID)
			machine.Status.Phase = "Installing"
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		case dedibox.InstallRunning:
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "Installing",
				clusterv1.ConditionSeverityInfo, "server %d installing", machine.Status.ServerID)
			machine.Status.Phase = "Installing"
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		}

		server, getErr := r.DediboxClient.GetServer(ctx, machine.Status.ServerID)
		if getErr != nil {
			return ctrl.Result{}, getErr
		}
		host := server.PublicIPv4()
		if host == "" {
			machine.Status.Phase = "Provisioning"
			logger.Info("public IP not assigned yet", "id", machine.Status.ServerID)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		machine.Status.Addresses = []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: host}}

		identity, idErr := r.CredentialsManager.EnsureNodeIdentity(ctx, machine.Name, linuxNodeIdentityClusterRole)
		if idErr != nil {
			machine.Status.Phase = "Pending"
			return ctrl.Result{RequeueAfter: 20 * time.Second}, fmt.Errorf("mint node identity: %w", idErr)
		}
		kubeconfigYAML, kcErr := r.Kubeconfig.Render(ctx, machine.Name, identity.Token, identity.CA)
		if kcErr != nil {
			return ctrl.Result{}, fmt.Errorf("render kubelet kubeconfig: %w", kcErr)
		}
		script := renderLinuxBootstrapScript(linuxCloudInitOptions{
			NodeName:       machine.Name,
			KubeconfigYAML: kubeconfigYAML,
			K8sMinor:       firstNonEmpty(r.KubernetesMinor, "v1.34"),
			Taints:         machine.Spec.NodeTaints,
			BootstrapUser:  dediboxBootstrapUser,
			ClusterDNS:     discoverClusterDNS(ctx, r.APIReader),
			InstanceType:   dediboxInstanceType,
		})

		machine.Status.Phase = "Bootstrapping"
		// TOFU host-key pinning, same as the OVH/EM kinds.
		known := ""
		if creds, fpErr := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name); fpErr != nil {
			return ctrl.Result{}, fmt.Errorf("read host fingerprint: %w", fpErr)
		} else if creds != nil {
			known = creds.HostFingerprint
		}
		hk := bootstrap.NewHostKeyState(known)
		bootErr := bootstrapOverSSH(ctx, dediboxBootstrapUser, host, privateKey, script, hk)
		if observed := hk.Observed(); observed != "" && observed != known {
			if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, observed); perr != nil {
				logger.Error(perr, "persist host fingerprint; will retry")
			}
		}
		if bootErr != nil {
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "BootstrapFailed",
				clusterv1.ConditionSeverityWarning, "%v", bootErr)
			machine.Status.BootstrapAttempts++
			logger.Info("bootstrap over SSH failed, will retry", "host", host, "err", bootErr.Error())
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		machine.Status.BootstrapAttempts = 0

		providerID := dedibox.ProviderID(datacenter, machine.Status.ServerID)
		machine.Spec.ProviderID = &providerID
		conditions.MarkTrue(machine, shared.ProvisionedCondition)
		r.event(machine, "Bootstrapped", "Bootstrapped Dedibox server %d as %s@%s", machine.Status.ServerID, dediboxBootstrapUser, host)
		return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
	}

	node := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: machine.Name}, node); err != nil {
		if apierrors.IsNotFound(err) {
			machine.Status.Phase = "Bootstrapping"
			return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
		}
		return ctrl.Result{}, err
	}

	if node.Spec.ProviderID == "" && machine.Spec.ProviderID != nil {
		helper, err := patch.NewHelper(node, r.Client)
		if err != nil {
			return ctrl.Result{}, err
		}
		node.Spec.ProviderID = *machine.Spec.ProviderID
		if err := helper.Patch(ctx, node); err != nil {
			return ctrl.Result{}, err
		}
	}

	if nodeReady(node) {
		machine.Status.Ready = true
		machine.Status.Phase = "Ready"
		conditions.MarkTrue(machine, NodeReadyCondition)
		return ctrl.Result{}, nil
	}
	machine.Status.Phase = "Bootstrapping"
	return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
}

// claimedServerIDs is the set of online.net server IDs already held by other
// DediboxMachines in the namespace, so adoption never double-claims a box.
func (r *DediboxMachineReconciler) claimedServerIDs(ctx context.Context, self *infrav1.DediboxMachine) (map[int]bool, error) {
	list := &infrav1.DediboxMachineList{}
	if err := r.List(ctx, list, client.InNamespace(self.Namespace)); err != nil {
		return nil, fmt.Errorf("list DediboxMachines: %w", err)
	}
	claimed := make(map[int]bool, len(list.Items))
	for i := range list.Items {
		m := &list.Items[i]
		if m.UID == self.UID {
			continue
		}
		if m.Status.ServerID != 0 {
			claimed[m.Status.ServerID] = true
		}
	}
	return claimed, nil
}

// reconcileDelete releases the Machine without terminating the Dedibox contract
// (monthly): it drops the per-machine kubelet identity + bootstrap Secret and
// removes the finalizer, leaving the physical box for re-adoption.
func (r *DediboxMachineReconciler) reconcileDelete(ctx context.Context, machine *infrav1.DediboxMachine) (ctrl.Result, error) {
	machine.Status.Phase = "Deleting"
	if err := r.CredentialsManager.DeleteNodeIdentity(ctx, machine.Name); err != nil {
		r.event(machine, "DeleteIdentityFailed", "delete node identity: %v (will retry)", err)
		return ctrl.Result{}, err
	}
	if err := r.CredentialsManager.DeleteMachineBootstrap(ctx, machine.Name); err != nil {
		r.event(machine, "DeleteBootstrapFailed", "delete machine bootstrap secret: %v (will retry)", err)
		return ctrl.Result{}, err
	}
	controllerutil.RemoveFinalizer(machine, DediboxMachineFinalizer)
	return ctrl.Result{}, nil
}

func (r *DediboxMachineReconciler) fail(machine *infrav1.DediboxMachine, reason, message string) (ctrl.Result, error) {
	machine.Status.Phase = "Failed"
	machine.Status.FailureReason = &reason
	machine.Status.FailureMessage = &message
	conditions.MarkFalse(machine, shared.ProvisionedCondition, reason, clusterv1.ConditionSeverityError, "%s", message)
	r.event(machine, reason, "%s", message)
	return ctrl.Result{}, nil
}

func (r *DediboxMachineReconciler) event(machine *infrav1.DediboxMachine, reason, format string, args ...any) {
	if r.Recorder != nil {
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, reason, format, args...)
	}
}

func (r *DediboxMachineReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.DediboxMachine{}).
		Complete(r)
}
