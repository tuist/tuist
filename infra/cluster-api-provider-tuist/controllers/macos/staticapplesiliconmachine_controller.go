package macos

import (
	"context"
	"fmt"
	"sort"
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

// StaticMachineFinalizer keeps the CR alive until its RackHost claim is
// released. Unlike the Scaleway finalizer this guards no billing: we own the
// hardware either way, but a claim that outlives its Machine takes a physical
// box out of the pool, and in a rack sized to demand that is capacity nobody
// can get back without noticing the strand first.
const StaticMachineFinalizer = "staticapplesilicon.cluster.x-k8s.io/finalizer"

// StaticAppleSiliconMachineReconciler joins Mac minis we own to the cluster.
//
// It is the Scaleway kind's reconciler with the provider removed and the pool
// moved in-cluster. Everything from "we have a host and its credentials"
// onwards is shared (see hostagent.go): the same bootstrap, the same
// host-config drift loop, the same terminal-failure and cooldown rules, the
// same tailnet egress Service. What differs is only ever about ownership:
// where a host comes from, how it is rebooted, and what happens when it cannot
// be made to work:
//
//   - Acquire is a claim on a RackHost, not an order. There is nothing to
//     provision and nothing to wait for; the box is already running.
//   - Reboot is a PDU outlet, not an API call.
//   - Giving up quarantines the host instead of releasing it. Releasing is what
//     the Scaleway kind does so a DIFFERENT mini gets claimed, which works
//     because the pool is fungible and refilled by someone else's inventory.
//     Hand the same pool back a box we own and the next reconcile claims it
//     again, so the Machine loops on the one host that cannot work.
//   - Delete releases the claim and stops. No reinstall, no wipe: no API can
//     do either to hardware in our own rack, and the host is expected to
//     outlive every Kubernetes object that ever referred to it.
type StaticAppleSiliconMachineReconciler struct {
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
	// controller quarantines the host and lets the Machine claim another.
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

func (r *StaticAppleSiliconMachineReconciler) powerCycleSettle() time.Duration {
	if r.PowerCycleSettle > 0 {
		return r.PowerCycleSettle
	}
	return defaultPowerCycleSettle
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=staticapplesiliconmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=staticapplesiliconmachines/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=staticapplesiliconmachines/finalizers,verbs=update
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackhosts,verbs=get;list;watch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackhosts/status,verbs=get;update;patch

// Reconcile uses named returns so the deferred patchHelper.Patch can promote a
// patch error into the function's return value. Without named returns the
// deferred assignment would target a variable Go has already evaluated for the
// return, the defer would swallow the patch failure, and the function would
// report success: leaving Status.RackHost unpersisted after a successful claim
// and letting the next reconcile claim a second host.
func (r *StaticAppleSiliconMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	logger := log.FromContext(ctx).WithValues("machine", req.NamespacedName)

	machine := &infrav1.StaticAppleSiliconMachine{}
	if getErr := r.Get(ctx, req.NamespacedName, machine); getErr != nil {
		if apierrors.IsNotFound(getErr) {
			forgetStaticMachinePhase(req.Name)
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
	defer func() { recordStaticMachinePhase(machine) }()

	ownerMachine, ownerErr := util.GetOwnerMachine(ctx, r.Client, machine.ObjectMeta)
	if ownerErr != nil {
		return ctrl.Result{}, fmt.Errorf("get owner Machine: %w", ownerErr)
	}

	if !machine.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, machine)
	}

	if !controllerutil.ContainsFinalizer(machine, StaticMachineFinalizer) {
		controllerutil.AddFinalizer(machine, StaticMachineFinalizer)
	}

	var cluster *clusterv1.Cluster
	if ownerMachine != nil && ownerMachine.Spec.ClusterName != "" {
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
	// before hand-editing status: without it, clearing status.rackHost to
	// detach a CR races the reconcile loop straight into claiming another host.
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

func (r *StaticAppleSiliconMachineReconciler) reconcileNormal(
	ctx context.Context,
	machine *infrav1.StaticAppleSiliconMachine,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	// Stage 0: the fleet credential. Read-only, unlike the Scaleway path's
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

	// Stage 1: hold a host.
	host, result, err := r.claimRackHost(ctx, machine)
	if err != nil || host == nil {
		return result, err
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

		fingerprint, runErr := bootstrap.Run(ctx, r.hostConfig(machine, perHost))
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
func (r *StaticAppleSiliconMachineReconciler) reconcileHostConfigDrift(
	ctx context.Context,
	machine *infrav1.StaticAppleSiliconMachine,
	host *infrav1.RackHost,
	sshKey []byte,
	sudoPassword, knownFingerprint string,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	desiredHash := r.desiredHostConfigHash(machine)
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

	updateCfg := r.hostConfig(machine, perHost)
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

// claimRackHost binds this Machine to a free host, or confirms the binding it
// already has. Returns (nil, result, nil) when there is nothing to claim yet:
// a wait, not a failure.
func (r *StaticAppleSiliconMachineReconciler) claimRackHost(
	ctx context.Context,
	machine *infrav1.StaticAppleSiliconMachine,
) (*infrav1.RackHost, ctrl.Result, error) {
	logger := log.FromContext(ctx)

	if name := machine.Status.RackHost; name != "" {
		host := &infrav1.RackHost{}
		err := r.Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: name}, host)
		switch {
		case err != nil && !apierrors.IsNotFound(err):
			return nil, ctrl.Result{}, err
		case err == nil && host.Status.ClaimedBy == machine.Name:
			return host, ctrl.Result{}, nil
		}
		// The binding is gone: the inventory record was deleted, or someone
		// released the claim out of band. Drop our half and claim again rather
		// than bootstrapping a host we no longer hold.
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "ClaimLost",
			"No longer holding rack host %s; will claim another", name)
		logger.Info("rack host claim lost; re-claiming", "host", name)
		r.detachFromHost(machine)
	}

	pool := machine.Spec.AdoptPool
	if pool == "" {
		// An unscoped scan would claim an arbitrary host, possibly another
		// environment's. Requeue rather than fail: the operator fixes this on
		// the template and the CR does not need recreating.
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAdoptPool",
			clusterv1.ConditionSeverityError,
			"no adoptPool on the CR; refusing to scan the rack inventory unscoped")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "NoAdoptPool",
			"No adoptPool set; refusing to claim an arbitrary rack host")
		return nil, ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
	}

	machine.Status.Phase = "Adopting"

	hosts := &infrav1.RackHostList{}
	if err := r.List(ctx, hosts, client.InNamespace(machine.Namespace)); err != nil {
		return nil, ctrl.Result{}, fmt.Errorf("list rack hosts: %w", err)
	}

	candidates, skipped := selectClaimableHosts(hosts.Items, pool, machine.Name)
	if len(candidates) == 0 {
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAvailableHost",
			clusterv1.ConditionSeverityWarning,
			"no free RackHost in pool %q%s", pool, skipped.describe())
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "NoAvailableHost",
			"No free RackHost in pool %q%s", pool, skipped.describe())
		return nil, ctrl.Result{RequeueAfter: 60 * time.Second}, nil
	}

	host := &candidates[0]
	host.Status.ClaimedBy = machine.Name
	host.Status.ClaimedAt = &metav1.Time{Time: time.Now()}
	// Update, deliberately, not a merge patch: Update carries the
	// resourceVersion this object was read at, so the apiserver rejects the
	// write if anything changed underneath, which is what makes the claim
	// atomic. A merge patch sends no resourceVersion and two machines racing
	// for the last free host would both "succeed", both bootstrap it, and the
	// second would take over the first's Node.
	if err := r.Status().Update(ctx, host); err != nil {
		if apierrors.IsConflict(err) {
			// Someone else took it (or it changed): re-read and try again
			// immediately rather than waiting out a requeue interval.
			logger.Info("lost the race for a rack host; retrying", "host", host.Name)
			return nil, ctrl.Result{Requeue: true}, nil
		}
		return nil, ctrl.Result{}, fmt.Errorf("claim rack host %s: %w", host.Name, err)
	}

	machine.Status.RackHost = host.Name
	// The failure-tracking state describes the previous host, not this one.
	machine.Status.BootstrapAttempts = 0
	machine.Status.BootstrapRebootIssued = false
	machine.Status.Addresses = []clusterv1.MachineAddress{{
		Type:    clusterv1.MachineInternalIP,
		Address: host.Spec.Address,
	}}
	providerID := staticProviderID(host)
	machine.Spec.ProviderID = &providerID

	conditions.MarkTrue(machine, shared.ProvisionedCondition)
	r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Adopted",
		"Claimed rack host %s (serial %s, %s) at %s",
		host.Name, host.Spec.Serial, describeLocation(host), host.Spec.Address)
	logger.Info("claimed rack host", "host", host.Name, "serial", host.Spec.Serial, "address", host.Spec.Address)
	return host, ctrl.Result{}, nil
}

// skippedHosts counts why hosts in the right pool were passed over, so the
// "no available host" message says which of four very different problems this
// is rather than sending an operator to buy hardware they already have.
type skippedHosts struct {
	claimed     int
	quarantined int
	unclaimable int
	incomplete  int
}

func (s skippedHosts) describe() string {
	parts := []string{}
	for _, part := range []struct {
		n      int
		fmtStr string
	}{
		{s.claimed, "%d already claimed"},
		{s.quarantined, "%d quarantined (clear status.quarantined once fixed)"},
		{s.unclaimable, "%d marked unclaimable"},
		{s.incomplete, "%d missing an address or a location.site"},
	} {
		if part.n > 0 {
			parts = append(parts, fmt.Sprintf(part.fmtStr, part.n))
		}
	}
	if len(parts) == 0 {
		return "; the pool holds no hosts at all"
	}
	out := "; in that pool: "
	for i, p := range parts {
		if i > 0 {
			out += ", "
		}
		out += p
	}
	return out
}

// selectClaimableHosts returns the hosts in `pool` this machine may claim,
// in a stable order, plus a tally of why the rest were passed over.
//
// The order is by name and it matters: two reconciles of the same machine must
// reach for the same host, or a machine that loses a claim race repeatedly can
// walk the whole pool leaving a trail of half-claims behind it.
func selectClaimableHosts(all []infrav1.RackHost, pool, machineName string) ([]infrav1.RackHost, skippedHosts) {
	var (
		candidates []infrav1.RackHost
		skipped    skippedHosts
	)
	for _, host := range all {
		if host.Spec.Pool != pool {
			continue
		}
		switch {
		case host.Status.ClaimedBy != "" && host.Status.ClaimedBy != machineName:
			skipped.claimed++
		case host.Status.Quarantined:
			skipped.quarantined++
		case host.Spec.Unclaimable || !host.DeletionTimestamp.IsZero():
			skipped.unclaimable++
		case host.Spec.Address == "" || host.Spec.Location.Site == "":
			// Both are load-bearing: without an address there is nothing to
			// dial, and without a site the providerID would be malformed. An
			// incomplete inventory record is a typo in a values file, so say so
			// rather than claiming the host and failing later at a point that
			// looks like a host fault.
			skipped.incomplete++
		default:
			candidates = append(candidates, host)
		}
	}
	sort.Slice(candidates, func(i, j int) bool { return candidates[i].Name < candidates[j].Name })
	return candidates, skipped
}

// handleBootstrapFailure records the error and escalates recovery.
//
// Tier 1, at BootstrapRebootAfter: cycle the host's outlet. Most bootstrap
// failures on the rented fleet are host-volatile state that a boot clears, and
// on hardware we own the outlet is the only way to force one. Gated on
// BootstrapRebootIssued so a long retry tail doesn't power-cycle the box every
// minute; a failed cycle leaves the flag false so the next attempt retries it.
//
// Tier 2, at BootstrapMaxAttempts: quarantine the host and release it. This is
// where the kind diverges most from its Scaleway sibling, which releases the
// host to the pool so a different mini gets claimed. Releasing alone would hand
// this Machine the same box back on the next reconcile: the pool is our own
// inventory, not a provider's, so the host is marked out of the pool first.
// The Machine then claims a different host if the rack has one, and the bad box
// stays visible as quarantined until a human clears it.
func (r *StaticAppleSiliconMachineReconciler) handleBootstrapFailure(
	ctx context.Context,
	machine *infrav1.StaticAppleSiliconMachine,
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
		reason := fmt.Sprintf("bootstrap failed %d times: %v", attempts, cause)
		if err := r.quarantineHost(ctx, host, reason); err != nil {
			logger.Error(err, "quarantine rack host after bootstrap exhaustion; will retry")
			r.Recorder.Eventf(machine, corev1.EventTypeWarning, "QuarantineFailed",
				"Could not quarantine %s: %v (will retry)", host.Name, err)
			return ctrl.Result{RequeueAfter: 60 * time.Second}
		}
		// The TOFU fingerprint is pinned to the quarantined host's SSH key and
		// would reject the replacement host's key on the next bootstrap, so the
		// per-machine Secret goes with the host. Non-fatal: the next claim
		// rewrites it, and the fingerprint guard captures fresh on an empty pin.
		if err := r.CredentialsManager.DeleteMachineBootstrap(ctx, machine.Name); err != nil {
			logger.Error(err, "delete per-machine bootstrap Secret on quarantine; next claim will recreate it")
		}
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "BootstrapExhausted",
			"Quarantined %s after %d bootstrap failures; will claim another host from pool %q",
			host.Name, attempts, machine.Spec.AdoptPool)
		r.detachFromHost(machine)
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "HostQuarantined",
			clusterv1.ConditionSeverityWarning,
			"quarantined %s after %d bootstrap failures; awaiting a fresh claim", host.Name, attempts)

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

// detachFromHost resets every piece of outwardly-visible state tied to a host
// this Machine no longer holds, so CAPI and operators never briefly see a Ready
// Machine pointing at a box it does not have.
func (r *StaticAppleSiliconMachineReconciler) detachFromHost(machine *infrav1.StaticAppleSiliconMachine) {
	machine.Status.RackHost = ""
	machine.Status.BootstrapAttempts = 0
	machine.Status.BootstrapRebootIssued = false
	machine.Status.Ready = false
	machine.Status.Addresses = nil
	machine.Status.Phase = "Pending"
	machine.Spec.ProviderID = nil
	conditions.MarkFalse(machine, BootstrappedCondition, "HostReleased",
		clusterv1.ConditionSeverityWarning, "no longer holding a rack host")
}

// quarantineHost marks a host out of the pool and releases its claim, in that
// order. Quarantine first: releasing first would leave a window in which this
// machine's own next reconcile re-claims the box it just gave up on.
func (r *StaticAppleSiliconMachineReconciler) quarantineHost(ctx context.Context, host *infrav1.RackHost, reason string) error {
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
	fresh.Status.ClaimedBy = ""
	fresh.Status.ClaimedAt = nil
	if err := r.Status().Update(ctx, fresh); err != nil {
		return err
	}
	r.Recorder.Eventf(fresh, corev1.EventTypeWarning, "Quarantined",
		"Taken out of pool %q: %s. Clear status.quarantined once the host is fixed.", fresh.Spec.Pool, reason)
	return nil
}

// releaseHost clears this machine's claim without quarantining: the ordinary
// delete path. It is a no-op when the host is already free or has been claimed
// by someone else, so a retried delete cannot steal a live host's claim.
func (r *StaticAppleSiliconMachineReconciler) releaseHost(ctx context.Context, machine *infrav1.StaticAppleSiliconMachine) error {
	if machine.Status.RackHost == "" {
		return nil
	}
	host := &infrav1.RackHost{}
	err := r.Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: machine.Status.RackHost}, host)
	switch {
	case apierrors.IsNotFound(err):
		machine.Status.RackHost = ""
		return nil
	case err != nil:
		return err
	case host.Status.ClaimedBy != machine.Name:
		machine.Status.RackHost = ""
		return nil
	}

	host.Status.ClaimedBy = ""
	host.Status.ClaimedAt = nil
	if err := r.Status().Update(ctx, host); err != nil {
		return err
	}
	r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Released",
		"Released rack host %s back to pool %q", host.Name, host.Spec.Pool)
	machine.Status.RackHost = ""
	return nil
}

func (r *StaticAppleSiliconMachineReconciler) cycleHostPower(ctx context.Context, host *infrav1.RackHost) error {
	if host.Spec.Power == nil {
		return fmt.Errorf("host %s has no power outlet configured", host.Name)
	}
	if r.Power == nil {
		return fmt.Errorf("no power drivers wired into this operator build")
	}
	driver, err := r.Power.Get(host.Spec.Power.Driver)
	if err != nil {
		return err
	}
	outlet := power.Outlet{
		Driver: host.Spec.Power.Driver,
		Host:   host.Spec.Power.Host,
		Outlet: host.Spec.Power.Outlet,
	}
	if ref := host.Spec.Power.CredentialsSecretRef; ref != nil && ref.Name != "" {
		secret := &corev1.Secret{}
		if err := r.Get(ctx, types.NamespacedName{Namespace: r.SecretsNamespace, Name: ref.Name}, secret); err != nil {
			return fmt.Errorf("read power credentials %s/%s: %w", r.SecretsNamespace, ref.Name, err)
		}
		outlet.Username = string(secret.Data["username"])
		outlet.Password = string(secret.Data["password"])
	}
	return power.Cycle(ctx, driver, outlet, r.powerCycleSettle())
}

func (r *StaticAppleSiliconMachineReconciler) reconcileDelete(
	ctx context.Context,
	machine *infrav1.StaticAppleSiliconMachine,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	machine.Status.Phase = "Deleting"

	// Captured before Stage 1, which clears it: the egress Service is named
	// after the host, and releasing first would leave nothing to name it by.
	heldHost := machine.Status.RackHost

	// Stage 1: release the claim so the box is immediately re-claimable.
	//
	// Nothing is reinstalled or wiped, unlike every other adopt-style kind
	// here. There is no API that could, and there is no billing reason to: the
	// host keeps running with a launchd job whose credentials Stage 2 is about
	// to invalidate, and the next claim re-pushes the whole config over it. A
	// host that must be returned to a clean state is a DFU restore, which is a
	// deliberate physical act and not something a Machine deletion should ever
	// trigger.
	if err := r.releaseHost(ctx, machine); err != nil {
		logger.Error(err, "release rack host; will retry")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "ReleaseFailed",
			"release rack host: %v (will retry)", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Stage 2: drop the per-machine kubelet identity. The token is long-lived
	// and bound to a ClusterRole that reads Secrets and ConfigMaps
	// cluster-wide; leaving it behind orphans a valid privileged credential on
	// a host that is no longer ours to trust. This matters MORE here than on
	// rented capacity, not less: nothing wipes the disk afterwards, so the
	// kubeconfig stays on the box until the next claim overwrites it.
	if err := r.CredentialsManager.DeleteNodeIdentity(ctx, machine.Name); err != nil {
		logger.Error(err, "delete node identity; will retry")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "DeleteFailed",
			"delete node identity: %v (will retry)", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Stage 3: drop the per-machine bootstrap Secret (SSH username, TOFU host
	// fingerprint).
	if err := r.CredentialsManager.DeleteMachineBootstrap(ctx, machine.Name); err != nil {
		logger.Error(err, "delete machine bootstrap; will retry")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "DeleteFailed",
			"delete machine bootstrap: %v (will retry)", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Stage 4: drop the Node. The host's kubelet cannot deregister itself, so
	// without this the Node lingers NotReady forever and confuses drain and
	// scaling semantics downstream.
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: machine.Name}}
	if err := r.Client.Delete(ctx, node); err != nil && !apierrors.IsNotFound(err) {
		logger.Error(err, "delete Node object; will retry")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "DeleteFailed",
			"delete Node: %v (will retry)", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Stage 5: drop both egress Services. Cross-namespace OwnerRefs aren't
	// allowed, so neither cascades.
	//
	// Two of them, because a rack host is reached two different ways over its
	// life: the Machine-named Service fronts the mini's own tailnet identity
	// for scraping, and the host-named one fronts its LAN address for the SSH
	// the operator needs before that identity exists.
	if r.EgressProxyGroup != "" {
		names := []string{machine.Name}
		if heldHost != "" {
			names = append(names, rackEgressServiceName(heldHost))
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

	controllerutil.RemoveFinalizer(machine, StaticMachineFinalizer)
	return ctrl.Result{}, nil
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
func (r *StaticAppleSiliconMachineReconciler) perHostConfig(
	ctx context.Context,
	machine *infrav1.StaticAppleSiliconMachine,
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
		ProviderID:           providerIDOfStatic(machine),
		Kubeconfig:           kubeconfigYAML,
		TailscaleAuthKey:     tailscaleAuthKey,
		VNCRelayHost:         r.egressHost(machine.Name),
		NodeLabels:           staticMachineNodeLabels(machine),
		KnownHostFingerprint: knownFingerprint,
	}, nil
}

// persistFingerprint stores a newly-observed TOFU pin. Failures are logged, not
// returned: losing a pin costs a re-capture on the next dial, while failing the
// push over it would turn a successful bootstrap into a retry.
func (r *StaticAppleSiliconMachineReconciler) persistFingerprint(
	ctx context.Context,
	machine *infrav1.StaticAppleSiliconMachine,
	observed, known string,
) {
	if observed == "" || observed == known {
		return
	}
	if err := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, observed); err != nil {
		log.FromContext(ctx).Error(err, "persist host fingerprint; will retry")
	}
}

func (r *StaticAppleSiliconMachineReconciler) fleetName(machine *infrav1.StaticAppleSiliconMachine) string {
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
func (r *StaticAppleSiliconMachineReconciler) dialTarget(host *infrav1.RackHost) string {
	if h := rackEgressHost(r.egressConfig(), host.Name); h != "" {
		return h
	}
	return host.Spec.Address
}

func (r *StaticAppleSiliconMachineReconciler) reconcileRackEgress(
	ctx context.Context,
	machine *infrav1.StaticAppleSiliconMachine,
	host *infrav1.RackHost,
) error {
	return reconcileRackEgressService(ctx, r.Client, r.egressConfig(),
		host.Name, host.Spec.Address, machine.Spec.FleetName)
}

func (r *StaticAppleSiliconMachineReconciler) egressConfig() egressConfig {
	return egressConfig{
		Namespace:      r.EgressNamespace,
		ProxyGroup:     r.EgressProxyGroup,
		MagicDNSSuffix: r.EgressMagicDNSSuffix,
		ManagedBy:      operatorName,
	}
}

func (r *StaticAppleSiliconMachineReconciler) egressHost(machineName string) string {
	return egressServiceHost(r.egressConfig(), machineName)
}

func (r *StaticAppleSiliconMachineReconciler) reconcileTailscaleEgressService(
	ctx context.Context,
	machine *infrav1.StaticAppleSiliconMachine,
) error {
	return reconcileEgressService(ctx, r.Client, r.egressConfig(),
		machine.Name, machine.Spec.FleetName, r.hostSizing(machine).GuestCapacity)
}

// hostSizing resolves this Machine's SKU-shaped fields: the per-Machine
// override where set, the operator-global default otherwise.
func (r *StaticAppleSiliconMachineReconciler) hostSizing(machine *infrav1.StaticAppleSiliconMachine) hostSizing {
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

func (r *StaticAppleSiliconMachineReconciler) hostConfig(
	machine *infrav1.StaticAppleSiliconMachine,
	perHost bootstrap.PerHost,
) bootstrap.Config {
	return applyHostSizing(r.FleetConfig, r.hostSizing(machine), perHost)
}

func (r *StaticAppleSiliconMachineReconciler) desiredHostConfigHash(machine *infrav1.StaticAppleSiliconMachine) string {
	return hostConfigHashFor(r.FleetConfig, r.hostSizing(machine))
}

// staticProviderID composes the providerID from the host's two durable physical
// facts, so re-cabling a box to a new address does not change its identity to
// CAPI. The scheme is foreign to the Hetzner CCM, which is what keeps it from
// reaping these Nodes.
func staticProviderID(host *infrav1.RackHost) string {
	serial := host.Spec.Serial
	if serial == "" {
		// An inventory record with no serial is still usable: the CR name is
		// unique in the namespace and stable, but it is worse, because the
		// identity now moves if the record is ever recreated under a new name.
		// selectClaimableHosts requires an address and a site, not a serial,
		// because a missing serial degrades rather than breaks.
		serial = host.Name
	}
	return fmt.Sprintf("static-applesilicon://%s/%s", host.Spec.Location.Site, serial)
}

func providerIDOfStatic(m *infrav1.StaticAppleSiliconMachine) string {
	if m.Spec.ProviderID == nil {
		return ""
	}
	return *m.Spec.ProviderID
}

// staticMachineNodeLabels are the labels tart-kubelet stamps on the Node it
// registers: the fleet membership label workloads pin to via nodeSelector,
// matching what the Scaleway kind writes so one workload can target both.
func staticMachineNodeLabels(m *infrav1.StaticAppleSiliconMachine) map[string]string {
	if m.Spec.FleetName == "" {
		return nil
	}
	return map[string]string{"tuist.dev/fleet": m.Spec.FleetName}
}

func describeLocation(host *infrav1.RackHost) string {
	loc := host.Spec.Location
	out := loc.Site
	if loc.Rack != "" {
		out += "/" + loc.Rack
	}
	if loc.Shelf != "" {
		out += "/" + loc.Shelf
	}
	if loc.PositionU > 0 {
		out += fmt.Sprintf(" U%d", loc.PositionU)
	}
	return out
}

func (r *StaticAppleSiliconMachineReconciler) SetupWithManager(mgr ctrl.Manager) error {
	concurrency := r.MaxConcurrentReconciles
	if concurrency <= 0 {
		concurrency = 1
	}
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.StaticAppleSiliconMachine{}).
		WithOptions(controller.Options{MaxConcurrentReconciles: concurrency}).
		Watches(
			&clusterv1.Machine{},
			handler.EnqueueRequestsFromMapFunc(staticMachineForCAPIMachine),
		).
		// Wake on inventory changes so a host added to the pool, un-quarantined
		// or made claimable is picked up at once rather than at the next
		// requeue: the difference between a rack bring-up that converges as
		// hosts are declared and one that appears stuck for a minute per host.
		Watches(
			&infrav1.RackHost{},
			handler.EnqueueRequestsFromMapFunc(r.staticMachinesForRackHost),
		).
		Complete(r)
}

func staticMachineForCAPIMachine(_ context.Context, o client.Object) []reconcile.Request {
	m, ok := o.(*clusterv1.Machine)
	if !ok {
		return nil
	}
	if m.Spec.InfrastructureRef.Kind != "StaticAppleSiliconMachine" {
		return nil
	}
	return []reconcile.Request{{
		NamespacedName: types.NamespacedName{
			Namespace: m.Spec.InfrastructureRef.Namespace,
			Name:      m.Spec.InfrastructureRef.Name,
		},
	}}
}

// staticMachinesForRackHost enqueues the machines a host event could unblock:
// its current holder, plus every hostless machine whose pool it belongs to.
func (r *StaticAppleSiliconMachineReconciler) staticMachinesForRackHost(ctx context.Context, o client.Object) []reconcile.Request {
	host, ok := o.(*infrav1.RackHost)
	if !ok {
		return nil
	}

	machines := &infrav1.StaticAppleSiliconMachineList{}
	if err := r.List(ctx, machines, client.InNamespace(host.Namespace)); err != nil {
		log.FromContext(ctx).Error(err, "list machines for rack host event", "host", host.Name)
		return nil
	}

	var requests []reconcile.Request
	for i := range machines.Items {
		m := &machines.Items[i]
		holdsIt := m.Status.RackHost == host.Name
		waitingForOne := m.Status.RackHost == "" && m.Spec.AdoptPool == host.Spec.Pool
		if holdsIt || waitingForOne {
			requests = append(requests, reconcile.Request{
				NamespacedName: types.NamespacedName{Namespace: m.Namespace, Name: m.Name},
			})
		}
	}
	return requests
}
