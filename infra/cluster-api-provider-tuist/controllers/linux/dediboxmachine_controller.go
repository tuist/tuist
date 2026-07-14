package linux

import (
	"context"
	"errors"
	"fmt"
	"time"

	"golang.org/x/crypto/ssh"

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
	// up and the box is reinstalled back to the pool. Like OVH, a Dedibox server
	// is a monthly contract, so release wipes the OS back to a clean, claimable
	// state but keeps the box; terminating the contract is an operator action.
	DediboxMachineFinalizer = "dedibox.cluster.x-k8s.io/finalizer"

	// dediboxBootstrapUser is the sudo login the Scaleway Dedibox install creates
	// (Ubuntu installs require a user and disable root SSH), so the self-join runs
	// as this user via sudo, like the OVH "ubuntu" path. VERIFY against a live
	// install that the chosen OS reports RequiresUser.
	dediboxBootstrapUser = "tuist"

	// dediboxInstanceType is the node.cluster.x-k8s.io/instance-type label value
	// the self-join stamps.
	dediboxInstanceType = "dedibox"

	dediboxReleaseReinstallStartedAnnotation  = "dedibox.cluster.x-k8s.io/release-reinstall-started"
	dediboxReleaseReinstallObservedAnnotation = "dedibox.cluster.x-k8s.io/release-reinstall-observed"

	dediboxInstallPollInterval = time.Minute
)

// DediboxMachineReconciler reconciles a DediboxMachine: it adopts a pre-ordered
// Scaleway Dedibox server carrying its fleet's tag (the environment boundary,
// since every Dedibox shares the org's default project), narrowed by offer +
// datacenter, drives the OS install, then SSH-delivers the shared Linux
// self-join over its public IP. Structurally a twin of the OVH kind
// (customer-facing public box, no Scaleway Private Network; the RPN private mesh
// is a multi-box follow-up).
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

		// Adopt: claim a free pre-ordered box in this project not already held by
		// a sibling CR.
		if machine.Status.ServerID == 0 {
			claimed, claimErr := r.claimedServerIDs(ctx, machine)
			if claimErr != nil {
				return ctrl.Result{}, claimErr
			}
			server, adoptErr := r.DediboxClient.FindAdoptableServer(ctx, dedibox.AdoptParams{
				Tag:        machine.Spec.AdoptTag,
				Datacenter: datacenter,
				Offer:      machine.Spec.Offer,
			}, claimed)
			if adoptErr != nil {
				return ctrl.Result{}, adoptErr
			}
			if server == nil {
				conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAdoptableServer",
					clusterv1.ConditionSeverityInfo,
					"no free pre-ordered Dedibox server (tag %q, offer %q) in %s; awaiting capacity", machine.Spec.AdoptTag, machine.Spec.Offer, datacenter)
				machine.Status.Phase = "Adopting"
				logger.Info("no adoptable Dedibox server yet", "tag", machine.Spec.AdoptTag, "offer", machine.Spec.Offer, "datacenter", datacenter)
				return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
			}
			machine.Status.ServerID = int(server.ID)
			machine.Status.Zone = server.Zone
			machine.Status.Addresses = []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: server.PublicIP}}
			machine.Status.Phase = "Adopting"
			r.event(machine, "Adopted", "Adopted Dedibox server %d in %s/%s", server.ID, datacenter, server.Zone)
			logger.Info("adopted Dedibox server", "id", server.ID, "datacenter", datacenter, "zone", server.Zone)
			// Persist the claim before the long bootstrap that follows: a crash or
			// leader failover before the deferred status patch would drop the
			// in-memory claim and let a sibling Machine adopt the same box. Requeue
			// so the deferred patch flushes Status.ServerID now; the next reconcile
			// resumes from the durable claim (re-fetching the box via GetServer).
			return ctrl.Result{RequeueAfter: time.Second}, nil
		}

		serverID := uint64(machine.Status.ServerID)
		server, getErr := r.DediboxClient.GetServer(ctx, machine.Status.Zone, serverID)
		if getErr != nil {
			return ctrl.Result{}, getErr
		}
		installState, installErr := r.DediboxClient.InstallState(ctx, machine.Status.Zone, serverID)
		if installErr != nil {
			return ctrl.Result{}, fmt.Errorf("get Dedibox install state: %w", installErr)
		}
		if installState != dedibox.InstallDone {
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "InstallInProgress",
				clusterv1.ConditionSeverityInfo, "Dedibox server %d install is %s", serverID, installState)
			machine.Status.Phase = "Installing"
			logger.Info("waiting for Dedibox install before bootstrap", "id", machine.Status.ServerID, "state", installState.String())
			return ctrl.Result{RequeueAfter: dediboxInstallPollInterval}, nil
		}
		// Adoption is claim + self-join, never install. The operator prepares the
		// box (Ubuntu + the fleet key + tuist passwordless sudo) before tagging it
		// into the pool, so a claimed box is expected to be reachable — the same
		// shape as a Scaleway mini that is already up. The install-state gate above
		// keeps a box that is still being release-reinstalled out of the SSH path
		// until Scaleway reports the clean OS is back.
		host := server.PublicIP
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
		sudoPassword, pwErr := r.CredentialsManager.FleetSudoPassword(ctx, fleet)
		if pwErr != nil {
			return ctrl.Result{}, fmt.Errorf("fleet sudo password: %w", pwErr)
		}
		script := renderLinuxBootstrapScript(linuxCloudInitOptions{
			NodeName:       machine.Name,
			KubeconfigYAML: kubeconfigYAML,
			ClusterCAPEM:   identity.CA,
			K8sMinor:       firstNonEmpty(r.KubernetesMinor, "v1.34"),
			Taints:         machine.Spec.NodeTaints,
			BootstrapUser:  dediboxBootstrapUser,
			ClusterDNS:     discoverClusterDNS(ctx, r.APIReader),
			InstanceType:   dediboxInstanceType,
			SudoPassword:   sudoPassword,
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
			if errors.Is(bootErr, bootstrap.ErrHostKeyMismatch) {
				// A prior controller version or manual reinstall may leave a stale
				// TOFU pin for a host that has since been reimaged. Clear it so the
				// next bootstrap attempt can pin the freshly installed host key.
				if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, ""); perr != nil {
					logger.Error(perr, "clear stale host fingerprint after reinstall; will retry")
				}
			}
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "BootstrapFailed",
				clusterv1.ConditionSeverityWarning, "%v", bootErr)
			machine.Status.BootstrapAttempts++
			logger.Info("bootstrap over SSH failed, will retry", "host", host, "err", bootErr.Error())
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		machine.Status.BootstrapAttempts = 0

		providerID := dedibox.ProviderID(machine.Status.Zone, serverID)
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

	// Advertise the box's egress budget as node capacity so the scheduler
	// bin-packs egress-floored Kura cache pods against it. Idempotent and
	// re-applied each reconcile so a kubelet re-register can't strand it.
	if err := shared.ReconcileNodeEgressCapacity(ctx, r.Client, node, machine.Spec.EgressBudgetMbps); err != nil {
		return ctrl.Result{}, err
	}

	if nodeReady(node) {
		machine.Status.Ready = true
		machine.Status.Phase = "Ready"
		conditions.MarkTrue(machine, NodeReadyCondition)
		if machine.Status.FailureReason == nil {
			fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
			if requeue, driftErr := reconcileLinuxKubeletConfigDrift(ctx, r.Client, r.APIReader, r.CredentialsManager, machine.Name, fleet, dediboxBootstrapUser, node); driftErr != nil {
				logger.Error(driftErr, "kubelet config re-push failed; will retry")
				return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
			} else if requeue {
				return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
			}
		}
		return ctrl.Result{RequeueAfter: KubeletConfigDriftResyncInterval}, nil
	}
	machine.Status.Phase = "Bootstrapping"
	return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
}

// claimedServerIDs is the set of online.net server IDs already held by other
// DediboxMachines in the namespace, so adoption never double-claims a box.
func (r *DediboxMachineReconciler) claimedServerIDs(ctx context.Context, self *infrav1.DediboxMachine) (map[uint64]bool, error) {
	list := &infrav1.DediboxMachineList{}
	if err := r.List(ctx, list, client.InNamespace(self.Namespace)); err != nil {
		return nil, fmt.Errorf("list DediboxMachines: %w", err)
	}
	claimed := make(map[uint64]bool, len(list.Items))
	for i := range list.Items {
		m := &list.Items[i]
		if m.UID == self.UID {
			continue
		}
		if m.Status.ServerID != 0 {
			claimed[uint64(m.Status.ServerID)] = true
		}
	}
	return claimed, nil
}

// reconcileDelete returns the Machine's box to the pool. The Dedibox is a monthly
// contract, so "release" is not a contract termination: it reinstalls the box to a
// clean, key-authorized state so the next claim self-joins it with no operator
// prep, then drops the per-machine kubelet identity + bootstrap Secret + Node and
// removes the finalizer. Reinstalling on release (rather than on adoption) is what
// keeps adoption a fast self-join.
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
	// Drop the Node the kubelet registered: the host is gone, so it can't
	// deregister itself, and the foreign providerID means no CCM reaps it.
	// A lingering NotReady Node keeps its DaemonSet slot and wedges helm
	// --wait gates (e.g. the observability rollout) across the cluster.
	node := &corev1.Node{}
	node.SetName(machine.Name)
	if err := r.Delete(ctx, node); err != nil && !apierrors.IsNotFound(err) {
		r.event(machine, "DeleteNodeFailed", "delete Node: %v (will retry)", err)
		return ctrl.Result{}, err
	}
	// The reprovisioned box is wiped, so any node-local volume (local-path /
	// scw-local-nvme) it hosted is gone. Delete the PVCs still bound to those
	// dead-node PVs so their StatefulSets reprovision fresh volumes on the
	// replacement node instead of wedging Pending forever on an unbindable PV.
	if err := deleteNodeLocalPVCs(ctx, r.Client, machine.Name); err != nil {
		r.event(machine, "DeletePVCsFailed", "delete node-local PVCs orphaned by reprovision: %v (will retry)", err)
		return ctrl.Result{}, err
	}
	if machine.Status.ServerID != 0 {
		result, done, err := r.reconcileReleaseReinstall(ctx, machine)
		if err != nil || !done {
			return result, err
		}
	}
	controllerutil.RemoveFinalizer(machine, DediboxMachineFinalizer)
	return ctrl.Result{}, nil
}

func (r *DediboxMachineReconciler) reconcileReleaseReinstall(ctx context.Context, machine *infrav1.DediboxMachine) (ctrl.Result, bool, error) {
	logger := log.FromContext(ctx)
	if machine.Annotations == nil {
		machine.Annotations = map[string]string{}
	}

	serverID := uint64(machine.Status.ServerID)
	if machine.Annotations[dediboxReleaseReinstallStartedAnnotation] != "true" {
		if err := r.reinstallToPool(ctx, machine); err != nil {
			r.event(machine, "ReleaseReinstallFailed", "reinstall on release: %v (will retry)", err)
			return ctrl.Result{}, false, err
		}
		machine.Annotations[dediboxReleaseReinstallStartedAnnotation] = "true"
		machine.Status.Phase = "Reinstalling"
		r.event(machine, "ReleasedToPool", "Reinstalling Dedibox server %d to a clean, claimable state", machine.Status.ServerID)
		logger.Info("started Dedibox reinstall on release", "id", machine.Status.ServerID)
		return ctrl.Result{RequeueAfter: dediboxInstallPollInterval}, false, nil
	}

	state, err := r.DediboxClient.InstallState(ctx, machine.Status.Zone, serverID)
	if err != nil {
		r.event(machine, "ReleaseReinstallPollFailed", "poll reinstall on release: %v (will retry)", err)
		logger.Error(err, "poll Dedibox reinstall on release", "id", machine.Status.ServerID)
		return ctrl.Result{RequeueAfter: dediboxInstallPollInterval}, false, nil
	}
	if state != dedibox.InstallDone {
		machine.Annotations[dediboxReleaseReinstallObservedAnnotation] = "true"
		machine.Status.Phase = "Reinstalling"
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "ReleaseReinstalling",
			clusterv1.ConditionSeverityInfo, "Dedibox server %d release reinstall is %s", serverID, state)
		logger.Info("waiting for Dedibox release reinstall", "id", machine.Status.ServerID, "state", state.String())
		return ctrl.Result{RequeueAfter: dediboxInstallPollInterval}, false, nil
	}
	if machine.Annotations[dediboxReleaseReinstallObservedAnnotation] != "true" {
		machine.Status.Phase = "Reinstalling"
		logger.Info("waiting for Dedibox release reinstall to report in progress before accepting done", "id", machine.Status.ServerID)
		return ctrl.Result{RequeueAfter: dediboxInstallPollInterval}, false, nil
	}

	r.event(machine, "ReleasedToPool", "Reinstalled Dedibox server %d to a clean, claimable state", machine.Status.ServerID)
	logger.Info("Dedibox release reinstall completed", "id", machine.Status.ServerID)
	return ctrl.Result{}, true, nil
}

// reinstallToPool wipes the adopted box back to a clean Ubuntu install with the
// fleet key authorized and the tuist login, so the next claim self-joins it
// without operator prep. It kicks the install off and returns; reconcileDelete
// keeps the Machine finalizer until InstallState observes the reinstall complete.
func (r *DediboxMachineReconciler) reinstallToPool(ctx context.Context, machine *infrav1.DediboxMachine) error {
	fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
	privateKey, keyErr := r.CredentialsManager.EnsureFleetSSHKey(ctx, fleet)
	if keyErr != nil {
		return keyErr
	}
	signer, signErr := ssh.ParsePrivateKey(privateKey)
	if signErr != nil {
		return fmt.Errorf("parse fleet ssh key: %w", signErr)
	}
	sudoPassword, pwErr := r.CredentialsManager.FleetSudoPassword(ctx, fleet)
	if pwErr != nil {
		return fmt.Errorf("fleet sudo password: %w", pwErr)
	}
	serverID := uint64(machine.Status.ServerID)
	sshKeyID, regErr := r.DediboxClient.RegisterSSHKey(ctx, fleet, string(ssh.MarshalAuthorizedKey(signer.PublicKey())))
	if regErr != nil {
		return regErr
	}
	osChoice, osErr := r.DediboxClient.ResolveOS(ctx, machine.Status.Zone, serverID, firstNonEmpty(machine.Spec.OS, "ubuntu_24.04"))
	if osErr != nil {
		return osErr
	}
	// Set the login password to the fleet sudo password, exactly as prep does, so
	// the re-adopting self-join can escalate with `sudo -S` to drop the NOPASSWD
	// sudoers file. Omitting it was why the original release-reinstall failed the
	// self-join with "sudo: a password is required".
	return r.DediboxClient.StartInstall(ctx, dedibox.InstallParams{
		Zone:         machine.Status.Zone,
		ServerID:     serverID,
		OS:           osChoice,
		Hostname:     machine.Name,
		UserLogin:    dediboxBootstrapUser,
		SSHKeyIDs:    []string{sshKeyID},
		UserPassword: sudoPassword,
	})
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
