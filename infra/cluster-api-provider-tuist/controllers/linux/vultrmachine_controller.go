package linux

import (
	"context"
	_ "embed"
	"errors"
	"fmt"
	"regexp"
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

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util"
	"sigs.k8s.io/cluster-api/util/annotations"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/kubeconfig"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/vultr"
	"github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// vultrConvertScript is the canonical disk conversion, shared byte-for-byte with
// `mise run baremetal:prep-vultr` so the controller and out-of-band prep cannot
// drift. Embedded rather than reimplemented in Go: it is disk surgery whose
// every step is an mdadm/mkfs invocation, and a second implementation of it is a
// second thing to get wrong.
//
//go:embed vultr_convert.sh
var vultrConvertScript string

// vultrConvertResult parses the machine-readable tail the conversion prints, so
// status records what the box actually ended up with rather than what was asked
// for.
var vultrConvertResult = regexp.MustCompile(`RESULT device=(\S+) fstype=(\S+) quota=(\S+)`)

const (
	// VultrMachineFinalizer guards the CR until the node identity is cleaned up
	// and the box is reinstalled and untagged back to the pool. Like the OVH
	// finalizer it does not guard a paid resource: release wipes the OS back to a
	// claimable state but keeps the box.
	VultrMachineFinalizer = "vultr.cluster.x-k8s.io/finalizer"

	// vultrBootstrapUser is empty on purpose. Vultr's bare-metal install lands on
	// root with no unprivileged login, so the shared self-join runs with no sudo
	// prefix and needs no fleet sudo password, unlike the OVH and Elastic Metal
	// kinds.
	vultrBootstrapUser = ""

	// vultrInstanceType is the node.cluster.x-k8s.io/instance-type label value
	// the self-join stamps.
	vultrInstanceType = "vultr"

	// vultrReleaseRetryInterval bounds a failed release retry, for the same
	// reason the OVH one does: controller-runtime's default backoff doubles to a
	// 1000s cap and would leave the Machine idling in Deleting long after the box
	// was free.
	vultrReleaseRetryInterval = 60 * time.Second

	// vultrConvertRetryInterval bounds a failed conversion retry. The conversion
	// is disk surgery, so a failure is usually a state that needs looking at
	// rather than one that clears on its own.
	vultrConvertRetryInterval = 2 * time.Minute

	// vultrMaxConvertAttempts stops an endlessly retrying conversion from
	// hammering a box whose disks are genuinely wrong. Past this the machine
	// fails loudly instead, because a box that silently never converts is one
	// that would host unbounded cache volumes.
	vultrMaxConvertAttempts = 5
)

// VultrMachineReconciler reconciles a VultrMachine: it adopts a pre-ordered
// Vultr bare-metal box by tag, converts its disk layout, then SSH-delivers the
// same self-join the other Linux kinds use.
//
// The Converting stage has no counterpart in the other kinds and is not
// optional. Vultr exposes no partitioning control and its installer produces
// either one filesystem spanning both disks or no RAID at all, so the mirrored
// root plus separate XFS /data that tuist.kuraVolumeQuotaProgram requires can
// only be reached afterwards. A box that skips it hosts cache volumes nothing
// bounds, which is the shape of the 2026-07-16 eu-central outage.
type VultrMachineReconciler struct {
	client.Client
	APIReader   client.Reader
	Scheme      *runtime.Scheme
	VultrClient *vultr.Client
	Recorder    record.EventRecorder

	CredentialsManager *credentials.Manager
	Kubeconfig         *kubeconfig.Builder

	// adoptMu serializes the claim window across concurrent workers, exactly as
	// the OVH reconciler does: two workers that both list before either writes
	// would claim the same box and leave two Nodes sharing one providerID.
	adoptMu sync.Mutex

	KubernetesMinor string

	// DefaultRegion fills a spec that left it empty.
	DefaultRegion string

	// runScript is the SSH runner the conversion stage uses. A seam rather than a
	// direct call because the conversion is the one stage with no counterpart in
	// the other kinds, and it is what stands between a box and hosting unbounded
	// cache volumes, so it is worth being able to test without a box. Nil uses
	// runScriptOverSSH.
	runScript func(ctx context.Context, user, host string, privateKey []byte, script string, hk *bootstrap.HostKeyState) (string, error)
}

func (r *VultrMachineReconciler) runner() func(context.Context, string, string, []byte, string, *bootstrap.HostKeyState) (string, error) {
	if r.runScript != nil {
		return r.runScript
	}
	return runScriptOverSSH
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=vultrmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=vultrmachines/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=vultrmachines/finalizers,verbs=update

func (r *VultrMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	logger := log.FromContext(ctx)

	machine := &infrav1.VultrMachine{}
	if err := r.Get(ctx, req.NamespacedName, machine); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	owner, err := util.GetOwnerMachine(ctx, r.Client, machine.ObjectMeta)
	if err != nil {
		return ctrl.Result{}, err
	}
	if owner == nil {
		logger.V(1).Info("waiting for the owning Machine")
		return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
	}
	if annotations.HasPaused(owner) {
		logger.V(1).Info("owning Machine is paused")
		return ctrl.Result{}, nil
	}

	patchHelper, err := patch.NewHelper(machine, r.Client)
	if err != nil {
		return ctrl.Result{}, err
	}
	defer func() {
		if patchErr := patchHelper.Patch(ctx, machine); patchErr != nil && err == nil {
			err = patchErr
		}
	}()

	if !machine.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, machine)
	}
	if !controllerutil.ContainsFinalizer(machine, VultrMachineFinalizer) {
		controllerutil.AddFinalizer(machine, VultrMachineFinalizer)
	}
	return r.reconcileNormal(ctx, machine, patchHelper)
}

func (r *VultrMachineReconciler) reconcileNormal(ctx context.Context, machine *infrav1.VultrMachine, patchHelper *patch.Helper) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	region := firstNonEmpty(machine.Spec.Region, r.DefaultRegion)

	if machine.Spec.ProviderID == nil || *machine.Spec.ProviderID == "" {
		fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
		privateKey, keyErr := r.CredentialsManager.EnsureFleetSSHKey(ctx, fleet)
		if keyErr != nil {
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "SSHKeyUnavailable",
				clusterv1.ConditionSeverityError, "%v", keyErr)
			machine.Status.Phase = "Pending"
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}

		if machine.Status.InstanceID == "" {
			// Held for the whole read-pick-persist window: a claim is only visible
			// to siblings once its status patch lands.
			r.adoptMu.Lock()
			defer r.adoptMu.Unlock()

			claimed, claimErr := r.claimedInstanceIDs(ctx, machine)
			if claimErr != nil {
				return ctrl.Result{}, claimErr
			}
			server, adoptErr := r.VultrClient.FindAdoptableServer(ctx, vultr.AdoptParams{
				Tag:    machine.Spec.AdoptTag,
				Region: region,
				Plan:   machine.Spec.Plan,
			}, claimed)
			if adoptErr != nil {
				return ctrl.Result{}, adoptErr
			}
			if server == nil {
				conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAdoptableServer",
					clusterv1.ConditionSeverityInfo,
					"no free pre-ordered Vultr box in %s tagged %q; awaiting capacity", region, machine.Spec.AdoptTag)
				machine.Status.Phase = "Adopting"
				logger.Info("no adoptable Vultr box yet", "region", region, "tag", machine.Spec.AdoptTag)
				return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
			}
			machine.Status.InstanceID = server.ID
			machine.Status.Addresses = []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: server.MainIP}}
			machine.Status.Phase = "Adopting"
			r.event(machine, "Adopted", "Adopted Vultr box %s (%s) in %s", server.Label, server.ID, region)
			// Persist inside the lock; the deferred patch would flush after release.
			if patchErr := patchHelper.Patch(ctx, machine); patchErr != nil {
				return ctrl.Result{}, fmt.Errorf("persist adoption claim for %s: %w", server.ID, patchErr)
			}
			return ctrl.Result{RequeueAfter: time.Second}, nil
		}

		server, getErr := r.VultrClient.GetServer(ctx, machine.Status.InstanceID)
		if getErr != nil {
			return ctrl.Result{}, getErr
		}

		// `active` is not readiness. Measured on a real reinstall, status returns
		// to active about 86 seconds before SSH answers, and for the first minute
		// after a reinstall request it is still the OLD system responding. So a
		// box mid-reinstall is waited out here, and the conversion below is what
		// actually proves the machine is the one we expect.
		if state, stateErr := r.VultrClient.InstallState(ctx, machine.Status.InstanceID); stateErr != nil {
			return ctrl.Result{}, stateErr
		} else if state != vultr.InstallSettled {
			machine.Status.Phase = "Installing"
			logger.Info("box is still reinstalling", "instance", machine.Status.InstanceID, "state", state)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		if server.MainIP == "" {
			machine.Status.Phase = "Provisioning"
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		machine.Status.Addresses = []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: server.MainIP}}

		// Convert before bootstrapping. The self-join refuses a box whose /data
		// cannot enforce quotas, so ordering this after the join would produce a
		// node that is up and unbounded, which is worse than one that is not up.
		if done, res, convErr := r.reconcileConversion(ctx, machine, server, privateKey); convErr != nil {
			return ctrl.Result{}, convErr
		} else if !done {
			return res, nil
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
		opts := r.hostOptions(machine)
		opts.KubeconfigYAML = kubeconfigYAML
		opts.ClusterCAPEM = identity.CA
		opts.ClusterDNS = discoverClusterDNS(ctx, r.APIReader)
		// No SudoPassword: the install lands on root, so the rendered script has no
		// escalation prefix and nothing to escalate with.
		script := renderLinuxBootstrapScript(opts)

		machine.Status.Phase = "Bootstrapping"
		known := ""
		if creds, fpErr := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name); fpErr != nil {
			return ctrl.Result{}, fmt.Errorf("read host fingerprint: %w", fpErr)
		} else if creds != nil {
			known = creds.HostFingerprint
		}
		hk := bootstrap.NewHostKeyState(known)
		bootErr := bootstrapOverSSH(ctx, vultrBootstrapUser, server.MainIP, privateKey, script, hk)
		if observed := hk.Observed(); observed != "" && observed != known {
			if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, observed); perr != nil {
				logger.Error(perr, "persist host fingerprint; will retry")
			}
		}
		if bootErr != nil {
			if errors.Is(bootErr, bootstrap.ErrHostKeyMismatch) {
				// A reinstall rotates the host key, and release is fire-and-forget,
				// so a fresh claim can pin a key the completed reinstall replaces.
				if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, ""); perr != nil {
					logger.Error(perr, "clear stale host fingerprint after reinstall; will retry")
				}
			}
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "BootstrapFailed",
				clusterv1.ConditionSeverityWarning, "%v", bootErr)
			machine.Status.BootstrapAttempts++
			logger.Info("bootstrap over SSH failed, will retry", "host", server.MainIP, "err", bootErr.Error())
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		machine.Status.BootstrapAttempts = 0

		providerID := fmt.Sprintf("vultr://%s/%s", firstNonEmpty(server.Region, region), machine.Status.InstanceID)
		machine.Spec.ProviderID = &providerID
		conditions.MarkTrue(machine, shared.ProvisionedCondition)
		r.event(machine, "Bootstrapped", "Bootstrapped Vultr box %s at %s", machine.Status.InstanceID, server.MainIP)
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

	if err := shared.ReconcileNodeMemoryCeilingCapacity(ctx, r.Client, node); err != nil {
		return ctrl.Result{}, err
	}

	if nodeReady(node) {
		machine.Status.Ready = true
		machine.Status.Phase = "Ready"
		conditions.MarkTrue(machine, NodeReadyCondition)
		if machine.Status.FailureReason == nil {
			fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
			if requeue, driftErr := reconcileLinuxKubeletConfigDrift(ctx, r.Client, r.APIReader, r.CredentialsManager, machine.Name, fleet, vultrBootstrapUser, node); driftErr != nil {
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

// reconcileConversion gives the box the disk layout the install cannot produce.
// Returns done=true only when /data is a separate XFS filesystem carrying
// project quotas, verified by the script itself rather than assumed from a
// zero exit.
//
// The recorded status is keyed by instance id so a machine that moves to another
// box, or a box that has since been reinstalled, is never credited with a
// predecessor's conversion.
func (r *VultrMachineReconciler) reconcileConversion(
	ctx context.Context,
	machine *infrav1.VultrMachine,
	server *vultr.Server,
	privateKey []byte,
) (bool, ctrl.Result, error) {
	logger := log.FromContext(ctx)

	if c := machine.Status.Converted; c != nil && c.InstanceID == server.ID && c.QuotaEnforced {
		return true, ctrl.Result{}, nil
	}
	if machine.Status.Converted == nil || machine.Status.Converted.InstanceID != server.ID {
		machine.Status.Converted = &infrav1.ConversionStatus{InstanceID: server.ID}
	}
	status := machine.Status.Converted

	if status.Attempts >= vultrMaxConvertAttempts {
		reason := "DiskConversionFailed"
		msg := fmt.Sprintf("conversion of %s did not produce an enforceable /data after %d attempts", server.ID, status.Attempts)
		machine.Status.FailureReason = &reason
		machine.Status.FailureMessage = &msg
		machine.Status.Phase = "Failed"
		conditions.MarkFalse(machine, shared.ProvisionedCondition, reason, clusterv1.ConditionSeverityError, "%s", msg)
		return false, ctrl.Result{}, nil
	}

	machine.Status.Phase = "Converting"
	now := metav1.Now()
	status.AttemptedAt = &now

	known := ""
	if creds, fpErr := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name); fpErr != nil {
		return false, ctrl.Result{}, fmt.Errorf("read host fingerprint: %w", fpErr)
	} else if creds != nil {
		known = creds.HostFingerprint
	}
	hk := bootstrap.NewHostKeyState(known)
	out, err := r.runner()(ctx, vultrBootstrapUser, server.MainIP, privateKey, vultrConvertScript, hk)
	if observed := hk.Observed(); observed != "" && observed != known {
		if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, observed); perr != nil {
			logger.Error(perr, "persist host fingerprint; will retry")
		}
	}
	if err != nil {
		status.Attempts++
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "DiskConversionFailed",
			clusterv1.ConditionSeverityWarning, "%v", err)
		logger.Info("disk conversion failed, will retry", "instance", server.ID, "attempt", status.Attempts, "err", err.Error())
		return false, ctrl.Result{RequeueAfter: vultrConvertRetryInterval}, nil
	}

	m := vultrConvertResult.FindStringSubmatch(out)
	if m == nil {
		// The script exits non-zero when the gates fail, so a zero exit without a
		// result line means it is not the script we think it is.
		status.Attempts++
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "DiskConversionUnverified",
			clusterv1.ConditionSeverityWarning, "conversion produced no result line")
		return false, ctrl.Result{RequeueAfter: vultrConvertRetryInterval}, nil
	}
	status.DataDevice, status.DataFilesystem, status.QuotaEnforced = m[1], m[2], m[3] == "true"
	status.ConvertedAt = &now
	status.Attempts = 0
	r.event(machine, "Converted", "Converted %s: /data on %s (%s) with project quotas", server.ID, status.DataDevice, status.DataFilesystem)
	logger.Info("converted disk layout", "instance", server.ID, "data", status.DataDevice)
	return true, ctrl.Result{}, nil
}

func (r *VultrMachineReconciler) hostOptions(machine *infrav1.VultrMachine) linuxCloudInitOptions {
	return linuxCloudInitOptions{
		NodeName:      machine.Name,
		K8sMinor:      firstNonEmpty(r.KubernetesMinor, "v1.34"),
		Taints:        machine.Spec.NodeTaints,
		BootstrapUser: vultrBootstrapUser,
		InstanceType:  vultrInstanceType,
	}
}

func (r *VultrMachineReconciler) reader() client.Reader {
	if r.APIReader != nil {
		return r.APIReader
	}
	return r.Client
}

// claimedInstanceIDs is every box a sibling CR already holds, so adoption never
// hands the same box to two Machines.
func (r *VultrMachineReconciler) claimedInstanceIDs(ctx context.Context, self *infrav1.VultrMachine) (map[string]bool, error) {
	list := &infrav1.VultrMachineList{}
	if err := r.reader().List(ctx, list, client.InNamespace(self.Namespace)); err != nil {
		return nil, err
	}
	claimed := map[string]bool{}
	for i := range list.Items {
		m := &list.Items[i]
		if m.Name == self.Name {
			continue
		}
		if m.Status.InstanceID != "" {
			claimed[m.Status.InstanceID] = true
		}
	}
	return claimed, nil
}

func (r *VultrMachineReconciler) reconcileDelete(ctx context.Context, machine *infrav1.VultrMachine) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	machine.Status.Phase = "Deleting"

	if err := r.CredentialsManager.DeleteNodeIdentity(ctx, machine.Name); err != nil {
		return ctrl.Result{}, fmt.Errorf("delete node identity: %w", err)
	}

	if machine.Status.InstanceID != "" {
		// Reinstall wipes the OS, the fleet key's authorized_keys entry and the
		// conversion, returning the box to the state a fresh claim expects. It is
		// also why the next claimant must convert again: the layout does not
		// survive.
		if err := r.VultrClient.StartInstall(ctx, machine.Status.InstanceID, ""); err != nil {
			logger.Error(err, "release reinstall failed; will retry", "instance", machine.Status.InstanceID)
			return ctrl.Result{RequeueAfter: vultrReleaseRetryInterval}, nil
		}
		// The conversion is gone with the OS, so drop the record rather than
		// leaving a claim a re-adoption could read as still true.
		machine.Status.Converted = nil
		r.event(machine, "Released", "Reinstalled Vultr box %s back to the pool", machine.Status.InstanceID)
	}

	controllerutil.RemoveFinalizer(machine, VultrMachineFinalizer)
	return ctrl.Result{}, nil
}

func (r *VultrMachineReconciler) event(machine *infrav1.VultrMachine, reason, format string, args ...any) {
	if r.Recorder == nil {
		return
	}
	r.Recorder.Eventf(machine, corev1.EventTypeNormal, reason, format, args...)
}

func (r *VultrMachineReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.VultrMachine{}).
		Complete(r)
}
