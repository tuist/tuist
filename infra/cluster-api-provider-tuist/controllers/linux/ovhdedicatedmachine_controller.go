package linux

import (
	"context"
	"errors"
	"fmt"
	"net"
	"strings"
	"sync"
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

	"golang.org/x/crypto/ssh"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/kubeconfig"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
	"github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	// OVHDedicatedMachineFinalizer guards the CR until the node identity is
	// cleaned up and the box is reinstalled back to the pool. It does NOT guard
	// a paid resource the way the Elastic Metal finalizer does: an OVH dedicated
	// server is a monthly contract, so release wipes the OS back to a clean,
	// claimable state but keeps the box; terminating the contract is an operator
	// action.
	OVHDedicatedMachineFinalizer = "ovhdedicated.cluster.x-k8s.io/finalizer"

	// ovhBootstrapUser is the login the OVH Ubuntu install lands on (with
	// sudo). Like Elastic Metal, the self-join is delivered over SSH and
	// escalates with sudo because the login user isn't root.
	ovhBootstrapUser = "ubuntu"

	// ovhInstanceType is the node.cluster.x-k8s.io/instance-type label value
	// the self-join stamps, so an OVH node is distinguishable from a Scaleway
	// one.
	ovhInstanceType = "ovh"

	// ovhSSHTimeout caps the per-attempt SSH dial + bootstrap run.
	ovhSSHTimeout = 5 * time.Minute

	// ovhReleaseRetryInterval bounds how long a failed release reinstall waits
	// before retrying. Returning the error instead would hand the retry to
	// controller-runtime's default backoff, which doubles to a 1000s cap: during
	// the 2026-09-03 wedge it had already stretched to ~6 minutes and was heading
	// for ~17, so the Machine would have idled in Deleting long after OVH freed
	// the server. The reinstall POST is the only OVH call on this path, so
	// retrying it every minute costs nothing worth backing off from.
	ovhReleaseRetryInterval = 60 * time.Second
)

// OVHDedicatedMachineReconciler reconciles an OVHDedicatedMachine: it adopts a
// pre-ordered OVH dedicated server by reverse-DNS prefix, drives the OVH install
// API to lay down the OS and authorize the fleet SSH key, then SSH-delivers the
// same self-join cloud-init the Scaleway Linux kinds use so the host registers
// as an ordinary Linux Node and links by providerID. The operator only
// pre-orders the box and points its reverse DNS at the adopt prefix; the OS
// install is scripted, never manual. There is no Scaleway Private Network: a
// customer-facing box serves public cache traffic over its public IP, so the
// self-join runs with VLAN 0.
type OVHDedicatedMachineReconciler struct {
	client.Client
	// APIReader is the uncached reader for the cross-namespace kube-dns read
	// (clusterDNS discovery), same as the Scaleway Linux reconcilers.
	APIReader client.Reader
	Scheme    *runtime.Scheme
	OVHClient *ovh.Client
	Recorder  record.EventRecorder

	CredentialsManager *credentials.Manager
	Kubeconfig         *kubeconfig.Builder

	// adoptMu serializes the claim window across the controller's concurrent
	// workers (see --machine-max-concurrent-reconciles). Leader election means
	// one manager reconciles at a time, so a process-local lock is the whole
	// mutual exclusion this needs.
	adoptMu sync.Mutex

	// KubernetesMinor is the pkgs.k8s.io channel the self-join installs kubelet
	// from (e.g. "v1.34"); keep in step with the control plane.
	KubernetesMinor string

	// DefaultDatacenter / DefaultOS fill a spec that left them empty.
	DefaultDatacenter string
	DefaultOS         string
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=ovhdedicatedmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=ovhdedicatedmachines/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=ovhdedicatedmachines/finalizers,verbs=update

func (r *OVHDedicatedMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	machine := &infrav1.OVHDedicatedMachine{}
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

	if !controllerutil.ContainsFinalizer(machine, OVHDedicatedMachineFinalizer) {
		controllerutil.AddFinalizer(machine, OVHDedicatedMachineFinalizer)
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

	return r.reconcileNormal(ctx, machine, patchHelper)
}

func (r *OVHDedicatedMachineReconciler) reconcileNormal(ctx context.Context, machine *infrav1.OVHDedicatedMachine, patchHelper *patch.Helper) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	datacenter := firstNonEmpty(machine.Spec.Datacenter, r.DefaultDatacenter)

	// Provision: adopt a pre-ordered server, install the OS, then SSH-bootstrap.
	// ServiceName is recorded as soon as the server is claimed so a controller
	// restart re-finds it rather than double-claiming; providerID is set only
	// once the bootstrap completes so a transient failure retries.
	if machine.Spec.ProviderID == nil || *machine.Spec.ProviderID == "" {
		fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
		privateKey, keyErr := r.CredentialsManager.EnsureFleetSSHKey(ctx, fleet)
		if keyErr != nil {
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "SSHKeyUnavailable",
				clusterv1.ConditionSeverityError, "%v", keyErr)
			machine.Status.Phase = "Pending"
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		// Adopt: claim a free pre-ordered box not already held by a sibling CR.
		if machine.Status.ServiceName == "" {
			// A claim only becomes visible to siblings once its status patch
			// lands, so the read-pick-persist window has to be atomic: two
			// workers that both list before either writes will pick the same
			// box, bootstrap it twice, and leave two Nodes sharing one
			// providerID, which wedges the CAPI node lookup for both.
			r.adoptMu.Lock()
			defer r.adoptMu.Unlock()

			claimed, claimErr := r.claimedServiceNames(ctx, machine)
			if claimErr != nil {
				return ctrl.Result{}, claimErr
			}
			server, adoptErr := r.OVHClient.FindAdoptableServer(ctx, ovh.AdoptParams{
				Datacenter:        datacenter,
				Offer:             machine.Spec.Offer,
				DisplayNamePrefix: machine.Spec.AdoptDisplayNamePrefix,
			}, claimed)
			if adoptErr != nil {
				return ctrl.Result{}, adoptErr
			}
			if server == nil {
				conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAdoptableServer",
					clusterv1.ConditionSeverityInfo,
					"no free pre-ordered OVH server in %s under %q; awaiting capacity", datacenter, machine.Spec.AdoptDisplayNamePrefix)
				machine.Status.Phase = "Adopting"
				logger.Info("no adoptable OVH server yet", "datacenter", datacenter, "prefix", machine.Spec.AdoptDisplayNamePrefix)
				return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
			}
			machine.Status.ServiceName = server.Name
			machine.Status.Addresses = []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: server.IP}}
			machine.Status.Phase = "Adopting"
			r.event(machine, "Adopted", "Adopted OVH server %s in %s", server.Name, datacenter)
			logger.Info("adopted OVH server", "service", server.Name, "datacenter", datacenter)
			// Persist inside the lock: the deferred patch flushes only after the
			// lock is released, which would reopen the window it exists to close.
			if patchErr := patchHelper.Patch(ctx, machine); patchErr != nil {
				return ctrl.Result{}, fmt.Errorf("persist adoption claim for %s: %w", server.Name, patchErr)
			}
			// Requeue rather than bootstrapping inline: the next reconcile
			// resumes from the now-durable claim (re-fetching the box via
			// GetServer), so a crash or leader failover during the long
			// bootstrap that follows never drops the claim.
			return ctrl.Result{RequeueAfter: time.Second}, nil
		}

		server, getErr := r.OVHClient.GetServer(ctx, machine.Status.ServiceName)
		if getErr != nil {
			return ctrl.Result{}, getErr
		}
		// Adoption is claim + self-join, never install. The operator owns putting a
		// valid box into rotation: install it (Ubuntu + the fleet key + ubuntu
		// passwordless sudo) and verify it is reachable BEFORE setting its adoption
		// displayName (`mise run baremetal:prep-ovh`), so a claimed box is already
		// up — the same shape as a Scaleway mini that is already running. Keeping
		// the OS install off this path is what makes adoption a ~2-5 min self-join,
		// so the fleet MachineDeployment goes Ready quickly and never wedges helm
		// --wait; the reinstall that wipes a box back to a clean, claimable state
		// lives on the release path (reconcileDelete).
		if server.IP == "" {
			machine.Status.Phase = "Provisioning"
			logger.Info("public IP not assigned yet", "service", machine.Status.ServiceName)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		machine.Status.Addresses = []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: server.IP}}

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
		opts := r.hostOptions(machine)
		opts.KubeconfigYAML = kubeconfigYAML
		opts.ClusterCAPEM = identity.CA
		opts.ClusterDNS = discoverClusterDNS(ctx, r.APIReader)
		opts.SudoPassword = sudoPassword
		script := renderLinuxBootstrapScript(opts)

		machine.Status.Phase = "Bootstrapping"
		// TOFU host-key pinning: persist the fingerprint observed on the first
		// dial and verify it on every retry, so the bootstrap that ships the
		// kubelet identity can't be MITM'd after the first contact.
		known := ""
		if creds, fpErr := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name); fpErr != nil {
			return ctrl.Result{}, fmt.Errorf("read host fingerprint: %w", fpErr)
		} else if creds != nil {
			known = creds.HostFingerprint
		}
		hk := bootstrap.NewHostKeyState(known)
		bootErr := bootstrapOverSSH(ctx, ovhBootstrapUser, server.IP, privateKey, script, hk)
		if observed := hk.Observed(); observed != "" && observed != known {
			if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, observed); perr != nil {
				logger.Error(perr, "persist host fingerprint; will retry")
			}
		}
		if bootErr != nil {
			if errors.Is(bootErr, bootstrap.ErrHostKeyMismatch) {
				// Reinstall-on-release race: reinstallToPool is fire-and-forget,
				// so a fresh claim can dial the box mid-reimage and pin a key the
				// completed reinstall then rotates. Clear the stale pin so the next
				// dial re-TOFUs the reinstalled key. Bounded to bootstrap — a
				// Provisioned box is never re-dialed.
				if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, ""); perr != nil {
					logger.Error(perr, "clear stale host fingerprint after reinstall; will retry")
				}
			}
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "BootstrapFailed",
				clusterv1.ConditionSeverityWarning, "%v", bootErr)
			machine.Status.BootstrapAttempts++
			logger.Info("bootstrap over SSH failed, will retry", "host", server.IP, "err", bootErr.Error())
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		machine.Status.BootstrapAttempts = 0

		providerID := ovh.ProviderID(firstNonEmpty(server.Datacenter, datacenter), machine.Status.ServiceName)
		machine.Spec.ProviderID = &providerID
		conditions.MarkTrue(machine, shared.ProvisionedCondition)
		r.event(machine, "Bootstrapped", "Bootstrapped OVH server %s as %s@%s", machine.Status.ServiceName, ovhBootstrapUser, server.IP)
		return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
	}

	// Provisioned: link + finish once the self-joined Node appears.
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
	if err := r.reconcileNodeEgress(ctx, machine, node); err != nil {
		return ctrl.Result{}, err
	}

	// Same idea for memory: cache pods run with a ceiling above their floor, so
	// their ceilings oversubscribe the box and the native requests.memory
	// bin-pack cannot see them. Advertise a bounded ceiling budget for the
	// scheduler to pack them against.
	if err := shared.ReconcileNodeMemoryCeilingCapacity(ctx, r.Client, node); err != nil {
		return ctrl.Result{}, err
	}

	if nodeReady(node) {
		machine.Status.Ready = true
		machine.Status.Phase = "Ready"
		conditions.MarkTrue(machine, NodeReadyCondition)
		if machine.Status.FailureReason == nil {
			fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
			if requeue, driftErr := reconcileLinuxKubeletConfigDrift(ctx, r.Client, r.APIReader, r.CredentialsManager, machine.Name, fleet, ovhBootstrapUser, node); driftErr != nil {
				logger.Error(driftErr, "kubelet config re-push failed; will retry")
				return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
			} else if requeue {
				return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
			}
			if requeue, kataErr := reconcileLinuxKataRuntimeDrift(ctx, r.Client, r.CredentialsManager, machine, machine.Name, fleet, r.hostOptions(machine), node); kataErr != nil {
				logger.Error(kataErr, "kata runtime repair failed; will retry")
				return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
			} else if requeue {
				return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
			}
			if requeue, quotaErr := reconcileLinuxContainerdQuotaDrift(ctx, r.Client, r.CredentialsManager, machine, machine.Name, fleet, r.hostOptions(machine), node); quotaErr != nil {
				logger.Error(quotaErr, "containerd quota lift failed; will retry")
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

// hostOptions is the host shape both the first bootstrap and the in-place repair
// paths render from. They share one builder deliberately: the repair can only
// converge a node onto a capability it knows the machine asked for, so a future
// bootstrap-time field added to the render must land in both — and here it does
// so by construction rather than by remembering to update two call sites.
func (r *OVHDedicatedMachineReconciler) hostOptions(machine *infrav1.OVHDedicatedMachine) linuxCloudInitOptions {
	return linuxCloudInitOptions{
		NodeName:      machine.Name,
		K8sMinor:      firstNonEmpty(r.KubernetesMinor, "v1.34"),
		Taints:        machine.Spec.NodeTaints,
		KataRuntime:   machine.Spec.KataRuntime,
		BootstrapUser: ovhBootstrapUser,
		InstanceType:  ovhInstanceType,
	}
}

func (r *OVHDedicatedMachineReconciler) reader() client.Reader {
	if r.APIReader != nil {
		return r.APIReader
	}
	return r.Client
}

// claimedServiceNames is the set of OVH service names already held by other
// OVHDedicatedMachines in the namespace, so adoption never double-claims a box.
// Claim state lives in the CR status rather than OVH-side because the cluster
// is the durable record and OVH dedicated servers carry no operator-writable
// claim marker the way Scaleway names do.
func (r *OVHDedicatedMachineReconciler) claimedServiceNames(ctx context.Context, self *infrav1.OVHDedicatedMachine) (map[string]bool, error) {
	list := &infrav1.OVHDedicatedMachineList{}
	// Uncached: the informer cache lags its own writes by long enough that a
	// sibling that already claimed a box still reads as unclaimed, which is a
	// double-claim rather than a stale view a later reconcile repairs.
	if err := r.reader().List(ctx, list, client.InNamespace(self.Namespace)); err != nil {
		return nil, fmt.Errorf("list OVHDedicatedMachines: %w", err)
	}
	claimed := make(map[string]bool, len(list.Items))
	for i := range list.Items {
		m := &list.Items[i]
		if m.UID == self.UID {
			continue
		}
		if m.Status.ServiceName != "" {
			claimed[m.Status.ServiceName] = true
		}
	}
	return claimed, nil
}

// reconcileDelete returns the Machine's box to the pool. An OVH dedicated server
// is a monthly contract, so "release" is not a contract termination: it reinstalls
// the box to a clean, key-authorized state so the next claim self-joins it with no
// operator prep, then drops the per-machine kubelet identity + bootstrap Secret +
// Node and removes the finalizer. Reinstalling on release (rather than on adoption)
// is what keeps adoption a fast self-join.
func (r *OVHDedicatedMachineReconciler) reconcileDelete(ctx context.Context, machine *infrav1.OVHDedicatedMachine) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	machine.Status.Phase = "Deleting"
	if err := r.CredentialsManager.DeleteNodeIdentity(ctx, machine.Name); err != nil {
		r.event(machine, "DeleteIdentityFailed", "delete node identity: %v (will retry)", err)
		return ctrl.Result{}, err
	}
	// Drop the per-machine bootstrap Secret (the TOFU host fingerprint), so a
	// replacement Machine re-pins the box's key fresh instead of failing against
	// a stale pin keyed on the deleted Machine's name.
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
	// Reinstall the box back to a clean, claimable state as the last step before
	// dropping the finalizer — it's the only step that retries on failure, so on
	// the happy path it fires exactly once. Fire-and-forget: the wipe + reimage
	// (Ubuntu + fleet key + ubuntu login) finishes after the Machine is gone,
	// leaving a box the next claim self-joins.
	if machine.Status.ServiceName != "" {
		err := r.reinstallToPool(ctx, machine)
		switch {
		case err == nil:
			r.event(machine, "ReleasedToPool", "Reinstalling OVH server %s to a clean, claimable state", machine.Status.ServiceName)
			logger.Info("reinstalling OVH box on release", "service", machine.Status.ServiceName)
		case r.reinstallAlreadyInFlight(ctx, machine, err):
			r.event(machine, "ReleasedToPool", "OVH server %s is already being reinstalled; releasing without queueing a second install", machine.Status.ServiceName)
			logger.Info("release found an OVH reinstall already in flight", "service", machine.Status.ServiceName)
		default:
			r.event(machine, "ReleaseReinstallFailed", "reinstall on release: %v (retrying in %s)", err, ovhReleaseRetryInterval)
			logger.Error(err, "reinstall OVH box on release", "service", machine.Status.ServiceName)
			return ctrl.Result{RequeueAfter: ovhReleaseRetryInterval}, nil
		}
	}
	shared.ForgetEgressMetrics(machine.Name)
	forgetKataRuntimeMetric(machine.Name)
	controllerutil.RemoveFinalizer(machine, OVHDedicatedMachineFinalizer)
	return ctrl.Result{}, nil
}

// reinstallAlreadyInFlight reports whether a failed release reinstall can be
// accepted as done because OVH is already reinstalling the box.
//
// OVH rejects a reinstall on a server that already has one queued with
// Client::BadRequest::TaskAlreadyExists, and keeps rejecting it for the ~30
// minutes the queued install runs. Treating that as retryable holds the
// finalizer for the whole window: the Machine sits in Deleting, its
// MachineDeployment stays a replica above spec, and a `helm upgrade --atomic`
// rollback waiting on that replica count runs out its step ceiling. Two
// Machines double-claimed one box on 2026-09-03 (fixed in #12779) and the loser
// wedged for 13 minutes that way; a controller restart between a successful
// POST and the finalizer patch reaches the same state with one Machine.
//
// reinstallToPool's postcondition is "this box is being returned to a clean,
// claimable state", and an install already in flight meets it, so the release
// drops the finalizer instead of queueing a second wipe of the same box.
//
// The task type is checked rather than assumed: TaskAlreadyExists says only that
// SOME task is queued, and a reboot or a hardware intervention leaves the box in
// whatever state the Machine left it. InstallState reads the task list and
// reports Running only when the newest install-function task is unfinished.
//
// What is NOT verified is that the queued install carries this fleet's SSH key
// and OS template. OVH's task resource exposes a function and a status, not the
// install parameters, so the only in-band signal is the type. Requiring a
// sibling Machine to vouch for the parameters would reject the single-Machine
// restart case above — the more likely trigger, and the one this exists to
// unwedge. The residual risk is an operator reinstalling, out of band, a box a
// live Machine still holds: that already breaks the Machine, and its blast
// radius is a box that fails to self-join on its next claim rather than one that
// joins wrong.
func (r *OVHDedicatedMachineReconciler) reinstallAlreadyInFlight(ctx context.Context, machine *infrav1.OVHDedicatedMachine, err error) bool {
	if !ovh.IsTaskAlreadyExists(err) {
		return false
	}
	state, stateErr := r.OVHClient.InstallState(ctx, machine.Status.ServiceName)
	if stateErr != nil {
		log.FromContext(ctx).Error(stateErr, "read OVH task list to classify a rejected release reinstall",
			"service", machine.Status.ServiceName)
		return false
	}
	return state == ovh.InstallRunning
}

// reinstallToPool wipes the adopted box back to a clean Ubuntu install with the
// fleet key authorized, so the next claim self-joins it without operator prep.
// Fire-and-forget: it kicks the install off and returns.
func (r *OVHDedicatedMachineReconciler) reinstallToPool(ctx context.Context, machine *infrav1.OVHDedicatedMachine) error {
	fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
	privateKey, keyErr := r.CredentialsManager.EnsureFleetSSHKey(ctx, fleet)
	if keyErr != nil {
		return keyErr
	}
	signer, signErr := ssh.ParsePrivateKey(privateKey)
	if signErr != nil {
		return fmt.Errorf("parse fleet ssh key: %w", signErr)
	}
	template, tmplErr := r.OVHClient.ResolveTemplate(ctx, machine.Status.ServiceName, firstNonEmpty(machine.Spec.OS, "ubuntu_24.04"))
	if tmplErr != nil {
		return tmplErr
	}
	return r.OVHClient.StartInstall(ctx, machine.Status.ServiceName, ovh.InstallParams{
		TemplateName: template,
		Hostname:     machine.Name,
		// TrimSpace is load-bearing. MarshalAuthorizedKey ends the line with a
		// newline, and OVH reads that trailing byte as a second, empty key:
		// "only 1 single SSH key can be provided". That 400 is returned on every
		// retry, so the release wedges the Machine in Deleting forever and the box
		// is never returned to the pool. The adopt path never hit it because prep
		// passes the key read straight from 1Password, which carries no newline.
		SSHKey: strings.TrimSpace(string(ssh.MarshalAuthorizedKey(signer.PublicKey()))),
	})
}

func (r *OVHDedicatedMachineReconciler) event(machine *infrav1.OVHDedicatedMachine, reason, format string, args ...any) {
	if r.Recorder != nil {
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, reason, format, args...)
	}
}

func (r *OVHDedicatedMachineReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.OVHDedicatedMachine{}).
		Complete(r)
}

// bootstrapOverSSH SSHes into the freshly-installed host as the install user and
// pipes the rendered self-join script to bash. The script is idempotent, so a
// retried bootstrap after a partial run converges. Shared shape with the Elastic
// Metal kind's SSH bootstrap.
func bootstrapOverSSH(ctx context.Context, user, host string, privateKey []byte, script string, hk *bootstrap.HostKeyState) error {
	signer, err := ssh.ParsePrivateKey(privateKey)
	if err != nil {
		return fmt.Errorf("parse ssh private key: %w", err)
	}
	cfg := &ssh.ClientConfig{
		User:            user,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: hk.Callback(),
		Timeout:         30 * time.Second,
	}

	dialCtx, cancel := context.WithTimeout(ctx, ovhSSHTimeout)
	defer cancel()

	var d net.Dialer
	conn, err := d.DialContext(dialCtx, "tcp", net.JoinHostPort(host, "22"))
	if err != nil {
		return fmt.Errorf("dial %s:22: %w", host, err)
	}
	defer conn.Close()
	if deadline, ok := dialCtx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}

	sshConn, chans, reqs, err := ssh.NewClientConn(conn, net.JoinHostPort(host, "22"), cfg)
	if err != nil {
		return fmt.Errorf("ssh handshake %s: %w", host, err)
	}
	sshClient := ssh.NewClient(sshConn, chans, reqs)
	defer sshClient.Close()

	session, err := sshClient.NewSession()
	if err != nil {
		return fmt.Errorf("open ssh session: %w", err)
	}
	defer session.Close()

	session.Stdin = strings.NewReader(script)
	if out, runErr := session.CombinedOutput("bash -s"); runErr != nil {
		return fmt.Errorf("run bootstrap on %s: %w (output: %s)", host, runErr, truncate(out, 2000))
	}
	return nil
}
