package macos

import (
	"context"
	"fmt"
	"slices"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util"
	"sigs.k8s.io/cluster-api/util/annotations"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/kubeconfig"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
	"github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// RackMachineFinalizer keeps the CR alive until the machine's kubelet
// identity, bootstrap Secret, Node and egress Services are gone.
const RackMachineFinalizer = "rackapplesilicon.cluster.x-k8s.io/finalizer"

// RackAppleSiliconMachineReconciler joins Mac minis we own to the cluster.
//
// It is the Scaleway kind's reconciler with the provider removed: the host is
// the RackHost that keeps this machine, named by spec.host. Everything from
// "we have a host and its credentials" onwards is shared (see hostagent.go):
// the same bootstrap, the same host-config drift loop, the same
// terminal-failure and cooldown rules, the same tailnet egress Service. What
// differs is only ever about ownership: how a host is rebooted, and what
// happens when it cannot be made to work:
//
//   - There is nothing to provision and nothing to wait for; the box is
//     already running.
//   - Reboot is a PDU outlet, not an API call.
//   - Giving up quarantines the host: its identity and host key pin are
//     dropped, and bootstrap starts over when the quarantine expires.
//   - Delete stops. No reinstall, no wipe: no API can do either to hardware
//     in our own rack, and the host is expected to outlive every Kubernetes
//     object that ever referred to it.
type RackAppleSiliconMachineReconciler struct {
	client.Client
	Scheme             *runtime.Scheme
	CredentialsManager *credentials.Manager
	Recorder           record.EventRecorder

	// Kubeconfig builds the per-host kubeconfig the bootstrap installs.
	Kubeconfig *kubeconfig.Builder

	// FleetConfig is every field of the host config that is identical across
	// the fleet: the operator-image binaries and the chart-driven fleet
	// settings. The manager builds it once and hands the same value to every
	// macOS reconciler, so a rack mini and a rented one converge on the same
	// host config, which is the point. A second fleet config would be a second
	// set of bugs, and the drift loop's whole contract is that what the
	// operator hashes and what it pushes cannot be two different things.
	// The settings a rack host needs on top are overlaid by rackFleetConfig,
	// which both the push and the hash go through.
	FleetConfig bootstrap.Config

	// DefaultGuestCapacity is the fleet-wide fallback for a Machine that does
	// not set spec.guestCapacity.
	DefaultGuestCapacity int

	// TartKubeletBinarySHA is the SHA-256 of the operator image's tart-kubelet,
	// stamped on each machine after a successful push.
	TartKubeletBinarySHA string

	// TartKubeletMaxUpdateAttempts caps how many times the drift loop retries a
	// failing push before the CR goes terminally Failed.
	TartKubeletMaxUpdateAttempts int32

	// TartKubeletTerminalRetryAfter re-arms the drift loop this long after the
	// failure that drove a host terminal, so a host that was merely unreachable
	// recovers on its own. Zero disables the re-arm (hash-drift only).
	TartKubeletTerminalRetryAfter time.Duration

	// BootstrapRebootAfter is the consecutive-failure count at which the
	// bootstrap-failure path cycles the host's outlet. Most bootstrap failures
	// seen on the rented fleet are host-volatile: PAM lockouts from sudo
	// retries, sshd throttling, half-open SSH sessions, and clear on a boot.
	BootstrapRebootAfter int32

	// BootstrapMaxAttempts is the consecutive-failure count at which the
	// controller quarantines the host.
	BootstrapMaxAttempts int32

	// MaxConcurrentReconciles parallelises across distinct machines. Bootstrap
	// blocks its worker for minutes, so a rack bring-up is otherwise serialised
	// host by host.
	MaxConcurrentReconciles int

	// Tailscale egress Service materialisation; empty EgressProxyGroup disables
	// it for the OSS / self-hosted shape.
	EgressNamespace      string
	EgressProxyGroup     string
	EgressMagicDNSSuffix string

	// Power resolves a host's outlet driver for the bootstrap-recovery reboot.
	// Nil leaves the reboot tier unavailable; bootstrap failures then escalate
	// straight from retrying to quarantine, which is worse but not broken.
	Power *power.Registry

	// SecretsNamespace is where per-endpoint power credential Secrets live.
	SecretsNamespace string

	// PowerCycleSettle overrides how long a recovery cycle holds the outlet
	// down; zero means defaultPowerCycleSettle. See the RackHost reconciler's
	// field for why this is not operator-facing.
	PowerCycleSettle time.Duration
}

func (r *RackAppleSiliconMachineReconciler) powerCycleSettle() time.Duration {
	if r.PowerCycleSettle > 0 {
		return r.PowerCycleSettle
	}
	return defaultPowerCycleSettle
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackapplesiliconmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackapplesiliconmachines/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackapplesiliconmachines/finalizers,verbs=update
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackhosts,verbs=get;list;watch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackhosts/status,verbs=get;update;patch

// Reconcile uses named returns so the deferred patchHelper.Patch can promote a
// patch error into the function's return value. Without named returns the
// deferred assignment would target a variable Go has already evaluated for the
// return, the defer would swallow the patch failure, and the function would
// report success with the machine's status unpersisted.
func (r *RackAppleSiliconMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	logger := log.FromContext(ctx).WithValues("machine", req.NamespacedName)

	machine := &infrav1.RackAppleSiliconMachine{}
	if getErr := r.Get(ctx, req.NamespacedName, machine); getErr != nil {
		if apierrors.IsNotFound(getErr) {
			forgetRackMachinePhase(req.Name)
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
	defer func() { recordRackMachinePhase(machine) }()

	ownerMachine, ownerErr := util.GetOwnerMachine(ctx, r.Client, machine.ObjectMeta)
	if ownerErr != nil {
		return ctrl.Result{}, fmt.Errorf("get owner Machine: %w", ownerErr)
	}

	if !machine.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, machine)
	}

	if ownerMachine == nil {
		logger.Info("waiting for the Machine controller to set an owner reference")
		return ctrl.Result{}, nil
	}

	var cluster *clusterv1.Cluster
	if ownerMachine.Spec.ClusterName != "" {
		cluster = &clusterv1.Cluster{}
		clusterName := ownerMachine.Spec.ClusterName
		if err := r.Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: clusterName}, cluster); err != nil {
			if apierrors.IsNotFound(err) {
				logger.Info("parent Cluster not found; requeueing", "cluster", clusterName)
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			return ctrl.Result{}, err
		}
	}

	// Pause gate, evaluated before the readiness check: the pause signal is
	// "operator wants me to stop", and honouring it takes priority over
	// requeueing on an unready cluster. It is also the latch an operator sets
	// before hand-editing status.
	if cluster != nil && cluster.Spec.Paused {
		logger.Info("parent Cluster paused; skipping reconcile")
		return ctrl.Result{}, nil
	}
	if annotations.HasPaused(machine) {
		logger.Info("Machine paused via annotation; skipping reconcile")
		return ctrl.Result{}, nil
	}

	if cluster != nil && !cluster.Status.InfrastructureReady {
		logger.Info("parent Cluster InfrastructureReady=false; requeueing")
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	return r.reconcileNormal(ctx, machine)
}

func (r *RackAppleSiliconMachineReconciler) reconcileNormal(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	// Stage 0: the host this machine is.
	host, result, err := r.hostOf(ctx, machine)
	if err != nil || host == nil {
		return result, err
	}
	if !controllerutil.ContainsFinalizer(machine, RackMachineFinalizer) {
		controllerutil.AddFinalizer(machine, RackMachineFinalizer)
	}
	if host.Status.Quarantined && !conditions.IsTrue(machine, BootstrappedCondition) {
		machine.Status.Phase = "Quarantined"
		return ctrl.Result{RequeueAfter: time.Minute}, nil
	}

	// Stage 1: the fleet credential. Read-only, unlike the Scaleway path's
	// EnsureFleetSSHKey: these hosts were keyed by MDM before this controller
	// ever saw them, so a key minted here is one no host will accept and a sudo
	// password minted here breaks auto-login on the first push. See
	// ReadFleetSSHCredentials.
	sshKey, sudoPassword, err := r.CredentialsManager.ReadFleetSSHCredentials(ctx, r.fleetName(machine))
	if err != nil {
		conditions.MarkFalse(machine, BootstrappedCondition, "FleetCredentialsUnavailable",
			clusterv1.ConditionSeverityWarning, "%v", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// The operator has no direct route to a rack host: it sits on a LAN behind a
	// subnet router, reachable only through the tailnet egress ProxyGroup. So
	// the Service that fronts it has to exist before the first dial, not as a
	// fallback after one fails the way the rented fleet's does.
	if err := r.reconcileRackEgress(ctx, machine, host); err != nil {
		if apierrors.IsConflict(err) {
			return ctrl.Result{Requeue: true}, nil
		}
		conditions.MarkFalse(machine, BootstrappedCondition, "RackEgressUnavailable",
			clusterv1.ConditionSeverityWarning, "%v", err)
		logger.Error(err, "reconcile rack host egress Service; will retry")
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	bootstrapCreds, err := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name)
	if err != nil {
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}
	knownFingerprint := ""
	if bootstrapCreds != nil {
		knownFingerprint = bootstrapCreds.HostFingerprint
	}

	// Bootstrap previously succeeded but the Node is gone: re-running bootstrap
	// reloads launchd and tart-kubelet re-registers. Flipping the condition
	// False lets the stage below drive the repair.
	if missing, lookupErr := nodeMissingAfterBootstrap(ctx, r.Client, machine, machine.Name); lookupErr != nil {
		logger.Error(lookupErr, "Node existence check failed; will retry")
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	} else if missing {
		conditions.MarkFalse(machine, BootstrappedCondition, "NodeMissing",
			clusterv1.ConditionSeverityWarning,
			"Node %s not found in cluster despite Bootstrapped=True; re-running bootstrap", machine.Name)
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "NodeMissing",
			"Node %s missing; reloading tart-kubelet on %s to re-register", machine.Name, host.Name)
	}

	// Stage 2: bootstrap (idempotent; re-running picks up where it left off).
	if !conditions.IsTrue(machine, BootstrappedCondition) {
		machine.Status.Phase = "Bootstrapping"
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Bootstrapping",
			"Installing Tart + tart-kubelet on %s (%s)", host.Name, host.Spec.Address)

		perHost, prepErr := r.perHostConfig(ctx, machine, host, sshKey, sudoPassword, knownFingerprint)
		if prepErr != nil {
			conditions.MarkFalse(machine, BootstrappedCondition, prepErr.reason,
				clusterv1.ConditionSeverityWarning, "%v", prepErr.err)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}

		fingerprint, runErr := bootstrap.Run(ctx, r.hostConfig(machine, host, perHost))
		// Persist whatever fingerprint Run captured even on the error path, so
		// a transient failure doesn't lose the TOFU pin we already verified.
		r.persistFingerprint(ctx, machine, fingerprint, knownFingerprint)
		if runErr != nil {
			return r.handleBootstrapFailure(ctx, machine, host, runErr), nil
		}

		conditions.MarkTrue(machine, BootstrappedCondition)
		// A long retry chain that finally succeeded is, from the cluster's
		// perspective, the same shape as a first-try success.
		machine.Status.BootstrapAttempts = 0
		machine.Status.BootstrapRebootIssued = false
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Bootstrapped",
			"%s joined the cluster as Node %s", host.Name, machine.Name)
		logger.Info("bootstrap complete", "host", host.Name, "address", host.Spec.Address)
	}

	// Stage 3: host-config drift.
	if result, driftErr := r.reconcileHostConfigDrift(ctx, machine, host, sshKey, sudoPassword, knownFingerprint); driftErr != nil || !result.IsZero() {
		return result, driftErr
	}

	// Stage 4: the per-machine Tailscale egress Service. Doesn't gate on
	// bootstrap: the FQDN is deterministic, so the Service can exist before the
	// host has joined the tailnet and the Tailscale operator pends its rewrite
	// until the name resolves.
	if err := r.reconcileTailscaleEgressService(ctx, machine); err != nil {
		// Conflicts are benign: the Tailscale operator and this reconciler
		// write to the same Service. Requeue so the next pass reads the fresh
		// version; no error, no Event, no noise.
		if apierrors.IsConflict(err) {
			return ctrl.Result{Requeue: true}, nil
		}
		logger.Error(err, "reconcile tailscale egress Service; will retry")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "EgressServiceFailed",
			"reconcile tailscale egress Service: %v (will retry)", err)
		return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
	}

	machine.Status.Ready = true
	if !terminalPhasePinned(machine.Status.FailureReason) {
		machine.Status.Phase = "Ready"
	}
	return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
}

// reconcileHostConfigDrift re-pushes the host config when the operator's
// desired hash differs from what this machine last recorded. Returns a non-zero
// Result when the caller should stop and requeue.
//
// The terminal-failure handling is the shared one and the reasoning for every
// branch lives with it (see shouldClearTerminalFailure). What is per-kind here
// is only the transport fallback below.
func (r *RackAppleSiliconMachineReconciler) reconcileHostConfigDrift(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
	host *infrav1.RackHost,
	sshKey []byte,
	sudoPassword, knownFingerprint string,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	desiredHash := r.desiredHostConfigHash(machine, host)
	drift := hostConfigDrift(desiredHash, machine.Status.HostConfigHash)
	terminal := machine.Status.FailureReason != nil

	if shouldClearTerminalFailure(
		desiredHash,
		machine.Status.FailedHostConfigHash,
		terminal,
		machine.Status.LastUpdateFailureTime,
		r.TartKubeletTerminalRetryAfter,
		time.Now(),
	) {
		reason := "host config drifted since the failure was recorded"
		if desiredHash != "" && desiredHash == machine.Status.FailedHostConfigHash {
			reason = "retry cooldown elapsed"
		}
		clearUpdateFailure(machine, reason, logger, r.Recorder)
		terminal = false
	}
	if !drift || terminal {
		return ctrl.Result{}, nil
	}

	perHost, prepErr := r.perHostConfig(ctx, machine, host, sshKey, sudoPassword, knownFingerprint)
	if prepErr != nil {
		recordUpdateFailure(machine, prepErr.err, r.TartKubeletMaxUpdateAttempts, desiredHash, logger, r.Recorder)
		if machine.Status.FailureReason != nil {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	updateCfg := r.hostConfig(machine, host, perHost)
	fingerprint, err := bootstrap.UpdateTartKubelet(ctx, updateCfg)

	// Tailnet fallback, for the same reason the Scaleway kind has one: once a
	// mini starts booting Tart VMs, its Internet Sharing / vmnet setup filters
	// inbound :22 on the interface the operator was dialling, so the push times
	// out while the host stays reachable through its own tailnet identity. An
	// empty fingerprint means the SSH handshake never completed: a pure
	// connect failure, distinct from a mid-session error, so retry over the
	// egress Service, which routes through the ProxyGroup.
	//
	// SkipTailscaleInstall on that path because installTailscale stops
	// tailscaled to swap its binary, which over a tailnet-transported session
	// would drop the tunnel and strand the host. That is exactly what the rack
	// design avoids for the FIRST dial by routing a rack address through a
	// separate subnet router; this fallback is the degraded path for after the
	// primary address stops answering, so it accepts the same limitation the
	// rented fleet lives with.
	if err != nil && fingerprint == "" {
		if egressHost := r.egressHost(machine.Name); egressHost != "" && egressHost != r.dialTarget(host) {
			logger.Info("host-address config push failed; retrying over the tailnet",
				"machine", machine.Name, "egressHost", egressHost, "cause", err.Error())
			updateCfg.IP = egressHost
			updateCfg.SkipTailscaleInstall = true
			fingerprint, err = bootstrap.UpdateTartKubelet(ctx, updateCfg)
		}
	}
	r.persistFingerprint(ctx, machine, fingerprint, knownFingerprint)

	if err != nil {
		recordUpdateFailure(machine, fmt.Errorf("tart-kubelet update: %w", err), r.TartKubeletMaxUpdateAttempts, desiredHash, logger, r.Recorder)
		if machine.Status.FailureReason != nil {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
	}

	machine.Status.TartKubeletBinarySHA = r.TartKubeletBinarySHA
	machine.Status.HostConfigHash = desiredHash
	machine.Status.TartKubeletUpdateAttempts = 0
	r.Recorder.Eventf(machine, corev1.EventTypeNormal, "AgentRolled",
		"Rolled tart-kubelet to %s on %s", r.TartKubeletBinarySHA, host.Name)
	logger.Info("rolled new host config", "host", host.Name, "sha", r.TartKubeletBinarySHA, "hostConfigHash", desiredHash)
	return ctrl.Result{}, nil
}

// hostOf resolves the RackHost this machine is. It returns no host, with the
// reason on the Provisioned condition, for a machine that names no host, whose
// host is gone or incomplete, or that is not its host's machine: none of those
// may dial the box.
func (r *RackAppleSiliconMachineReconciler) hostOf(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
) (*infrav1.RackHost, ctrl.Result, error) {
	if machine.Spec.Host == "" {
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoHost",
			clusterv1.ConditionSeverityWarning,
			"names no RackHost; each rack host keeps its own machine, so this one dials nothing")
		return nil, ctrl.Result{}, nil
	}

	host := &infrav1.RackHost{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: machine.Spec.Host}, host); err != nil {
		if !apierrors.IsNotFound(err) {
			return nil, ctrl.Result{}, err
		}
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "HostNotFound",
			clusterv1.ConditionSeverityWarning, "RackHost %s not found", machine.Spec.Host)
		return nil, ctrl.Result{RequeueAfter: time.Minute}, nil
	}
	if host.Status.Machine != machine.Name {
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "NotTheHostsMachine",
			clusterv1.ConditionSeverityWarning, "RackHost %s's machine is %q", host.Name, host.Status.Machine)
		return nil, ctrl.Result{RequeueAfter: time.Minute}, nil
	}
	if host.Spec.Address == "" || host.Spec.Location.Site == "" {
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "IncompleteHost",
			clusterv1.ConditionSeverityError,
			"RackHost %s needs an address and a location.site: one is dialled and the other composes the providerID", host.Name)
		return nil, ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
	}

	machine.Status.Addresses = []clusterv1.MachineAddress{{
		Type:    clusterv1.MachineInternalIP,
		Address: host.Spec.Address,
	}}
	if machine.Spec.ProviderID == nil {
		providerID := rackProviderID(host)
		machine.Spec.ProviderID = &providerID
	}
	conditions.MarkTrue(machine, shared.ProvisionedCondition)
	return host, ctrl.Result{}, nil
}

// handleBootstrapFailure records the error and escalates recovery.
//
// Tier 1, at BootstrapRebootAfter: cycle the host's outlet. Most bootstrap
// failures on the rented fleet are host-volatile state that a boot clears, and
// on hardware we own the outlet is the only way to force one. Gated on
// BootstrapRebootIssued so a long retry tail doesn't power-cycle the box every
// minute; a failed cycle leaves the flag false so the next attempt retries it.
//
// Tier 2, at BootstrapMaxAttempts: retire the machine's identity and
// quarantine the host. Bootstrap starts over from nothing when the quarantine
// expires.
func (r *RackAppleSiliconMachineReconciler) handleBootstrapFailure(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
	host *infrav1.RackHost,
	cause error,
) ctrl.Result {
	logger := log.FromContext(ctx)

	machine.Status.BootstrapAttempts++
	attempts := machine.Status.BootstrapAttempts

	conditions.MarkFalse(machine, BootstrappedCondition, "BootstrapFailed",
		clusterv1.ConditionSeverityWarning, "%v", cause)
	r.Recorder.Eventf(machine, corev1.EventTypeWarning, "BootstrapFailed",
		"%v (attempt %d on %s, will retry)", cause, attempts, host.Name)

	switch {
	case r.BootstrapMaxAttempts > 0 && attempts >= r.BootstrapMaxAttempts:
		if err := r.retireIdentity(ctx, machine); err != nil {
			logger.Error(err, "retire the machine's identity after bootstrap exhaustion; will retry")
			r.Recorder.Eventf(machine, corev1.EventTypeWarning, "RetireFailed",
				"Could not retire %s's identity: %v (will retry before quarantining %s)", machine.Name, err, host.Name)
			return ctrl.Result{RequeueAfter: 30 * time.Second}
		}
		reason := fmt.Sprintf("bootstrap failed %d times: %v", attempts, cause)
		if err := r.quarantineHost(ctx, host, reason); err != nil {
			logger.Error(err, "quarantine rack host after bootstrap exhaustion; will retry")
			r.Recorder.Eventf(machine, corev1.EventTypeWarning, "QuarantineFailed",
				"Could not quarantine %s: %v (will retry)", host.Name, err)
			return ctrl.Result{RequeueAfter: 60 * time.Second}
		}
		machine.Status.BootstrapAttempts = 0
		machine.Status.BootstrapRebootIssued = false
		machine.Status.Ready = false
		machine.Status.Phase = "Quarantined"
		conditions.MarkFalse(machine, BootstrappedCondition, "HostQuarantined",
			clusterv1.ConditionSeverityWarning,
			"quarantined %s after %d bootstrap failures; bootstrap starts over when the quarantine expires", host.Name, attempts)
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "BootstrapExhausted",
			"Quarantined %s after %d bootstrap failures; bootstrap starts over when the quarantine expires", host.Name, attempts)

	case r.BootstrapRebootAfter > 0 && attempts >= r.BootstrapRebootAfter && !machine.Status.BootstrapRebootIssued:
		if err := r.cycleHostPower(ctx, host); err != nil {
			logger.Error(err, "power cycle for bootstrap recovery failed; will retry on the next attempt")
			r.Recorder.Eventf(machine, corev1.EventTypeWarning, "RebootForRecoveryFailed",
				"Power cycle of %s after %d bootstrap failures: %v (will retry)", host.Name, attempts, err)
		} else {
			machine.Status.BootstrapRebootIssued = true
			r.Recorder.Eventf(machine, corev1.EventTypeNormal, "RebootingForRecovery",
				"Cycled %s's outlet after %d bootstrap failures to clear volatile host state",
				host.Name, attempts)
		}
	}

	return ctrl.Result{RequeueAfter: 60 * time.Second}
}

// retireIdentity revokes the machine's kubelet identity, deletes its Node and
// drops its bootstrap Secret with the host key it pinned, so the next
// bootstrap starts from nothing. A host that exhausted its attempts may still
// run tart-kubelet with a working token, or have been re-imaged under a new
// host key that the old pin rejects on every dial.
func (r *RackAppleSiliconMachineReconciler) retireIdentity(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
) error {
	if err := r.CredentialsManager.DeleteNodeIdentity(ctx, machine.Name); err != nil {
		return fmt.Errorf("revoke node identity: %w", err)
	}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: machine.Name}}
	if err := r.Client.Delete(ctx, node); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete stale Node: %w", err)
	}
	if err := r.CredentialsManager.DeleteMachineBootstrap(ctx, machine.Name); err != nil {
		return fmt.Errorf("delete per-machine bootstrap secret: %w", err)
	}
	return nil
}

// quarantineHost holds off the host's bootstrap until the RackHost controller
// expires the quarantine.
func (r *RackAppleSiliconMachineReconciler) quarantineHost(ctx context.Context, host *infrav1.RackHost, reason string) error {
	fresh := &infrav1.RackHost{}
	if err := r.Get(ctx, client.ObjectKeyFromObject(host), fresh); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return err
	}
	fresh.Status.Quarantined = true
	fresh.Status.QuarantineReason = reason
	fresh.Status.QuarantinedAt = &metav1.Time{Time: time.Now()}
	if err := r.Status().Update(ctx, fresh); err != nil {
		return err
	}
	r.Recorder.Eventf(fresh, corev1.EventTypeWarning, "Quarantined",
		"Bootstrap held off: %s", reason)
	return nil
}

func (r *RackAppleSiliconMachineReconciler) cycleHostPower(ctx context.Context, host *infrav1.RackHost) error {
	driver, outlet, err := rackHostOutlet(ctx, r.Client, r.Power, r.SecretsNamespace, r.egressConfig(), host)
	if err != nil {
		return fmt.Errorf("host %s: %w", host.Name, err)
	}
	return power.Cycle(ctx, driver, outlet, r.powerCycleSettle())
}

func (r *RackAppleSiliconMachineReconciler) reconcileDelete(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	machine.Status.Phase = "Deleting"

	// Nothing is reinstalled or wiped, unlike every other adopt-style kind
	// here. There is no API that could, and there is no billing reason to: the
	// host keeps running with a launchd job whose credentials this invalidates,
	// and the host's next machine re-pushes the whole config over it. A host
	// that must be returned to a clean state is a DFU restore, which is a
	// deliberate physical act and not something a Machine deletion should ever
	// trigger.

	// Stage 1: drop the per-machine kubelet identity. The token is long-lived
	// and bound to a ClusterRole that reads Secrets and ConfigMaps
	// cluster-wide; leaving it behind orphans a valid privileged credential on
	// a host that is no longer ours to trust. This matters MORE here than on
	// rented capacity, not less: nothing wipes the disk afterwards, so the
	// kubeconfig stays on the box until the next bootstrap overwrites it.
	if err := r.CredentialsManager.DeleteNodeIdentity(ctx, machine.Name); err != nil {
		logger.Error(err, "delete node identity; will retry")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "DeleteFailed",
			"delete node identity: %v (will retry)", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Stage 2: drop the per-machine bootstrap Secret (SSH username, TOFU host
	// fingerprint).
	if err := r.CredentialsManager.DeleteMachineBootstrap(ctx, machine.Name); err != nil {
		logger.Error(err, "delete machine bootstrap; will retry")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "DeleteFailed",
			"delete machine bootstrap: %v (will retry)", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Stage 3: drop the Node. The host's kubelet cannot deregister itself, so
	// without this the Node lingers NotReady forever and confuses drain and
	// scaling semantics downstream.
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: machine.Name}}
	if err := r.Client.Delete(ctx, node); err != nil && !apierrors.IsNotFound(err) {
		logger.Error(err, "delete Node object; will retry")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "DeleteFailed",
			"delete Node: %v (will retry)", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Stage 4: drop the egress Services. Cross-namespace OwnerRefs aren't
	// allowed, so neither cascades.
	//
	// Two of them, because a rack host is reached two different ways over its
	// life: the Machine-named Service fronts the mini's own tailnet identity
	// for scraping, and the host-named one fronts its LAN address for the SSH
	// the operator needs before that identity exists. The host-named one is
	// only this machine's while the host has no other.
	if r.EgressProxyGroup != "" {
		names := []string{machine.Name}
		ownsHostService, err := r.isHostsMachine(ctx, machine)
		if err != nil {
			return ctrl.Result{}, err
		}
		if ownsHostService {
			names = append(names, rackEgressServiceName(machine.Spec.Host))
		}
		for _, name := range names {
			svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{
				Name:      name,
				Namespace: r.EgressNamespace,
			}}
			if err := r.Client.Delete(ctx, svc); err != nil && !apierrors.IsNotFound(err) {
				logger.Error(err, "delete egress Service; will retry", "service", name)
				r.Recorder.Eventf(machine, corev1.EventTypeWarning, "DeleteFailed",
					"delete egress Service %s/%s: %v (will retry)", r.EgressNamespace, name, err)
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
		}
	}

	controllerutil.RemoveFinalizer(machine, RackMachineFinalizer)
	return ctrl.Result{}, nil
}

// isHostsMachine reports whether the machine names a host that has no other
// machine: one that is gone, has none, or has this one.
func (r *RackAppleSiliconMachineReconciler) isHostsMachine(ctx context.Context, machine *infrav1.RackAppleSiliconMachine) (bool, error) {
	if machine.Spec.Host == "" {
		return false, nil
	}
	host := &infrav1.RackHost{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: machine.Spec.Host}, host); err != nil {
		if apierrors.IsNotFound(err) {
			return true, nil
		}
		return false, err
	}
	return host.Status.Machine == "" || host.Status.Machine == machine.Name, nil
}

// === helpers ================================================================

// prepError carries a condition reason alongside the cause, so the bootstrap
// and drift paths can report the same preparation failures in their own idiom
// (a Bootstrapped condition on one, a counted update failure on the other).
type prepError struct {
	reason string
	err    error
}

// perHostConfig assembles everything about one host that bootstrap needs.
// Shared by the bootstrap and drift paths so a field can never reach one
// without the other: the failure mode that has bitten this provider four
// times, most expensively when the Tailscale tags reached only the bootstrap
// path and froze the production fleet.
func (r *RackAppleSiliconMachineReconciler) perHostConfig(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
	host *infrav1.RackHost,
	sshKey []byte,
	sudoPassword, knownFingerprint string,
) (bootstrap.PerHost, *prepError) {
	identity, err := r.CredentialsManager.EnsureNodeIdentity(ctx, machine.Name, "")
	if err != nil {
		return bootstrap.PerHost{}, &prepError{"NodeIdentityUnavailable", fmt.Errorf("ensure node identity: %w", err)}
	}
	kubeconfigYAML, err := r.Kubeconfig.Render(ctx, machine.Name, identity.Token, identity.CA)
	if err != nil {
		return bootstrap.PerHost{}, &prepError{"KubeconfigUnavailable", fmt.Errorf("render kubeconfig: %w", err)}
	}
	// Read on the drift path too, not just at bootstrap: the launchd plist is
	// re-rendered on every push, and without the key the renderer drops
	// `--node-ip-source=tailscale` and silently flips the kubelet back to
	// advertising the host's LAN address, which nothing in the cluster can
	// route to.
	tailscaleAuthKey, err := r.CredentialsManager.GetTailscaleAuthKey(ctx)
	if err != nil {
		return bootstrap.PerHost{}, &prepError{"TailscaleAuthKeyUnavailable", fmt.Errorf("get tailscale auth key: %w", err)}
	}

	return bootstrap.PerHost{
		IP:                   r.dialTarget(host),
		SSHUser:              host.Spec.SSHUser,
		UserPassword:         sudoPassword,
		SSHPrivateKey:        sshKey,
		NodeName:             machine.Name,
		ProviderID:           providerIDOfRack(machine),
		Kubeconfig:           kubeconfigYAML,
		TailscaleAuthKey:     tailscaleAuthKey,
		VNCRelayHost:         r.egressHost(machine.Name),
		NodeLabels:           rackMachineNodeLabels(machine),
		KnownHostFingerprint: knownFingerprint,
	}, nil
}

// persistFingerprint stores a newly-observed TOFU pin. Failures are logged, not
// returned: losing a pin costs a re-capture on the next dial, while failing the
// push over it would turn a successful bootstrap into a retry.
func (r *RackAppleSiliconMachineReconciler) persistFingerprint(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
	observed, known string,
) {
	if observed == "" || observed == known {
		return
	}
	if err := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, observed); err != nil {
		log.FromContext(ctx).Error(err, "persist host fingerprint; will retry")
	}
}

func (r *RackAppleSiliconMachineReconciler) fleetName(machine *infrav1.RackAppleSiliconMachine) string {
	if machine.Spec.FleetName != "" {
		return machine.Spec.FleetName
	}
	return machine.Namespace + "-" + machine.Name
}

// dialTarget is what the operator opens SSH to for this host: the egress
// Service when the tailnet egress is wired, and the host's own address
// otherwise (the OSS shape, or a cluster that sits on the same network as the
// rack and needs no proxy).
//
// It is a pure dial target. HostConfigHash strips PerHost.IP, so switching
// between the two does not drift a host's config.
func (r *RackAppleSiliconMachineReconciler) dialTarget(host *infrav1.RackHost) string {
	if h := rackEgressHost(r.egressConfig(), host.Name); h != "" {
		return h
	}
	return host.Spec.Address
}

func (r *RackAppleSiliconMachineReconciler) reconcileRackEgress(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
	host *infrav1.RackHost,
) error {
	return reconcileRackEgressService(ctx, r.Client, r.egressConfig(),
		host.Name, host.Spec.Address, machine.Spec.FleetName)
}

func (r *RackAppleSiliconMachineReconciler) egressConfig() egressConfig {
	return egressConfig{
		Namespace:      r.EgressNamespace,
		ProxyGroup:     r.EgressProxyGroup,
		MagicDNSSuffix: r.EgressMagicDNSSuffix,
		ManagedBy:      operatorName,
	}
}

func (r *RackAppleSiliconMachineReconciler) egressHost(machineName string) string {
	return egressServiceHost(r.egressConfig(), machineName)
}

func (r *RackAppleSiliconMachineReconciler) reconcileTailscaleEgressService(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
) error {
	return reconcileEgressService(ctx, r.Client, r.egressConfig(),
		machine.Name, machine.Spec.FleetName, r.hostSizing(machine).GuestCapacity)
}

// hostSizing resolves this Machine's SKU-shaped fields: the per-Machine
// override where set, the operator-global default otherwise.
func (r *RackAppleSiliconMachineReconciler) hostSizing(machine *infrav1.RackAppleSiliconMachine) hostSizing {
	sizing := hostSizing{
		HostCPU:              r.FleetConfig.HostCPU,
		HostMemoryMB:         r.FleetConfig.HostMemoryMB,
		MaxPods:              r.FleetConfig.MaxPods,
		GuestCapacity:        r.DefaultGuestCapacity,
		RunnerCacheVolumeGiB: r.FleetConfig.RunnerCacheVolumeGiB,
	}
	if machine.Spec.HostCPU > 0 {
		sizing.HostCPU = machine.Spec.HostCPU
	}
	if machine.Spec.HostMemoryMB > 0 {
		sizing.HostMemoryMB = machine.Spec.HostMemoryMB
	}
	if machine.Spec.MaxPods > 0 {
		sizing.MaxPods = machine.Spec.MaxPods
	}
	if machine.Spec.GuestCapacity > 0 {
		sizing.GuestCapacity = machine.Spec.GuestCapacity
	}
	if sizing.GuestCapacity < 1 {
		// A host that runs no guests is not a thing this operator provisions,
		// and a 0 would propagate into the relay-port range and the goldens
		// floor as "none".
		sizing.GuestCapacity = 1
	}
	// Resolved on PRESENCE, not truthiness: an explicit 0 means "cache volumes
	// off on this host", which on the prototype's 256 GB disk is the only
	// setting that fits. A negative value is treated as unset: it cannot be an
	// intent, and degrading to the fleet default beats pushing a quota that
	// would fail the diskutil call at bootstrap.
	if gib := machine.Spec.RunnerCacheVolumeGiB; gib != nil && *gib >= 0 {
		sizing.RunnerCacheVolumeGiB = *gib
	}
	return sizing
}

// rackFleetConfig is the shared fleet config with the two settings that keep
// a rack host reachable after it loses its tailnet identity. A rented mini
// can lose its device and still be dialled on its allow-listed public address;
// a rack mini's only other path is its subnet router, so:
//
//   - it joins as a standard device, so being powered off does not delete it
//     (see bootstrap's renderTailscaleScript), and
//   - its SSH ingress guard admits the host's subnet routers, the source its
//     LAN dial arrives from.
//
// Both push paths and the stamped hash go through here, so a change to either
// drifts the host rather than being recorded as converged without reaching it.
func (r *RackAppleSiliconMachineReconciler) rackFleetConfig(host *infrav1.RackHost) bootstrap.Config {
	cfg := r.FleetConfig
	cfg.TailscalePersistentDevice = true
	cfg.SSHIngressAllowCIDRs = append(slices.Clone(r.FleetConfig.SSHIngressAllowCIDRs), host.Spec.SSHIngressAllowCIDRs...)
	return cfg
}

func (r *RackAppleSiliconMachineReconciler) hostConfig(
	machine *infrav1.RackAppleSiliconMachine,
	host *infrav1.RackHost,
	perHost bootstrap.PerHost,
) bootstrap.Config {
	return applyHostSizing(r.rackFleetConfig(host), r.hostSizing(machine), perHost)
}

func (r *RackAppleSiliconMachineReconciler) desiredHostConfigHash(
	machine *infrav1.RackAppleSiliconMachine,
	host *infrav1.RackHost,
) string {
	return hostConfigHashFor(r.rackFleetConfig(host), r.hostSizing(machine))
}

// rackProviderID composes the providerID from the host's two durable physical
// facts, so re-cabling a box to a new address does not change its identity to
// CAPI. The scheme is foreign to the Hetzner CCM, which is what keeps it from
// reaping these Nodes.
func rackProviderID(host *infrav1.RackHost) string {
	serial := host.Spec.Serial
	if serial == "" {
		// An inventory record with no serial is still usable: the CR name is
		// unique in the namespace and stable, but it is worse, because the
		// identity now moves if the record is ever recreated under a new name.
		// hostOf requires an address and a site, not a serial,
		// because a missing serial degrades rather than breaks.
		serial = host.Name
	}
	return fmt.Sprintf("rack-applesilicon://%s/%s", host.Spec.Location.Site, serial)
}

func providerIDOfRack(m *infrav1.RackAppleSiliconMachine) string {
	if m.Spec.ProviderID == nil {
		return ""
	}
	return *m.Spec.ProviderID
}

// rackMachineNodeLabels are the labels tart-kubelet stamps on the Node it
// registers: the fleet membership label workloads pin to via nodeSelector,
// matching what the Scaleway kind writes so one workload can target both.
func rackMachineNodeLabels(m *infrav1.RackAppleSiliconMachine) map[string]string {
	if m.Spec.FleetName == "" {
		return nil
	}
	return map[string]string{"tuist.dev/fleet": m.Spec.FleetName}
}

func (r *RackAppleSiliconMachineReconciler) SetupWithManager(mgr ctrl.Manager) error {
	concurrency := r.MaxConcurrentReconciles
	if concurrency <= 0 {
		concurrency = 1
	}
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.RackAppleSiliconMachine{}).
		WithOptions(controller.Options{MaxConcurrentReconciles: concurrency}).
		Watches(
			&clusterv1.Machine{},
			handler.EnqueueRequestsFromMapFunc(rackMachineForCAPIMachine),
		).
		// Wake on the host, so a lifted quarantine or a new address is picked up
		// at once rather than at the next requeue.
		Watches(
			&infrav1.RackHost{},
			handler.EnqueueRequestsFromMapFunc(rackMachineForRackHost),
		).
		Complete(r)
}

func rackMachineForCAPIMachine(_ context.Context, o client.Object) []reconcile.Request {
	m, ok := o.(*clusterv1.Machine)
	if !ok {
		return nil
	}
	if m.Spec.InfrastructureRef.Kind != "RackAppleSiliconMachine" {
		return nil
	}
	return []reconcile.Request{{
		NamespacedName: types.NamespacedName{
			Namespace: m.Spec.InfrastructureRef.Namespace,
			Name:      m.Spec.InfrastructureRef.Name,
		},
	}}
}

// rackMachineForRackHost maps a host event to the host's machine.
func rackMachineForRackHost(_ context.Context, o client.Object) []reconcile.Request {
	host, ok := o.(*infrav1.RackHost)
	if !ok || host.Status.Machine == "" {
		return nil
	}
	return []reconcile.Request{{
		NamespacedName: types.NamespacedName{Namespace: host.Namespace, Name: host.Status.Machine},
	}}
}
