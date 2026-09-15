// Package macos contains the reconcilers for the macOS (Apple Silicon)
// machine kind and its fleet controllers (fleet-spread, orphan reclaim).
package macos

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/go-logr/logr"
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
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/runner"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/scaleway"
	"github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	// MachineFinalizer prevents the CR from being garbage-collected
	// before we've released the underlying Scaleway server (Apple's
	// 24h floor means leaks cost money — this matters).
	MachineFinalizer = "scalewayapplesilicon.cluster.x-k8s.io/finalizer"

	// BootstrappedCondition is macOS-specific (the tart-kubelet SSH bootstrap
	// step); the cross-cutting shared.ProvisionedCondition lives in the shared package.
	BootstrappedCondition clusterv1.ConditionType = "Bootstrapped"

	// DashboardVNCRelayPort is the stable host-side BASE port tart-kubelet
	// advertises for dashboard VNC sessions through the per-Mac Tailscale
	// egress Service.
	//
	// A host that runs N guests binds N contiguous ports from here, one
	// per guest, and its egress Service declares all N — a pinned port
	// is a per-host resource while a relay is per-Pod, so a single port
	// would let only the first guest on a host ever open a session.
	// Apple's SLA caps N at 2.
	DashboardVNCRelayPort = 5900
)

// ScalewayAppleSiliconMachineReconciler reconciles ScalewayAppleSiliconMachine objects.
type ScalewayAppleSiliconMachineReconciler struct {
	client.Client
	Scheme             *runtime.Scheme
	ScalewayClient     *scaleway.Client
	CredentialsManager *credentials.Manager

	// Recorder emits Events on lifecycle transitions. `kubectl describe
	// scalewayapplesiliconmachine` then shows a tail-followable timeline
	// of state changes alongside the static Conditions block, which is
	// the difference between "I can see this is broken" and "I can see
	// what step it's currently doing" while a Mac mini is mid-bootstrap.
	Recorder record.EventRecorder

	// Kubeconfig builds the per-host kubeconfig the bootstrap installs.
	// Required for tart-kubelet to authenticate to the cluster.
	Kubeconfig *kubeconfig.Builder

	// FleetConfig is every field of the host config that is identical
	// across the fleet: the operator-image binaries and the chart-driven
	// fleet settings. The manager builds it once, hands the same value
	// here, and derives HostConfigHash from it, so what the operator
	// hashes and what it pushes cannot be two different things.
	//
	// Both push paths start from this value and overlay only per-host
	// fields (see bootstrap.PerHost). Previously each path assembled its
	// own bootstrap.Config field by field from separate reconciler
	// fields, and a field wired into one path but not the other made the
	// operator stamp a host as converged to a config it never received.
	// The Tailscale tags were lost that way and froze the production
	// fleet on 2026-08-18.
	FleetConfig bootstrap.Config

	// DefaultGuestCapacity is the fleet-wide fallback for a Machine
	// that does not set `spec.guestCapacity` — how many Tart guests a
	// host is expected to run concurrently. 1 (the operator flag
	// default) preserves the one-guest-per-host behaviour.
	//
	// It lives here rather than on FleetConfig because it is an
	// operator-level intent, not a wire field: hostConfig expands it
	// into the two bootstrap.Config fields that are actually pushed
	// (VNCRelayPortCount, MinGoldensKept).
	DefaultGuestCapacity int

	// TartKubeletBinarySHA is the SHA-256 of TartKubeletBinary. Used
	// as the version stamp on each ScalewayAppleSiliconMachine: when
	// status.tartKubeletBinarySHA != this value, the reconciler
	// re-uploads + reloads launchd.
	TartKubeletBinarySHA string

	// VMCachePNName / VMCachePNCIDR configure the Scaleway Private
	// Network carrying the kura runner-cache NodePort endpoints.
	// When both are set, the reconciler resolves the PN by name
	// through VPC (creating it from the CIDR if absent), ensures every
	// Mac mini is attached to it (Apple Silicon Private Networks API, a
	// no-reboot operation), resolves the per-host VLAN, and bootstrap
	// materializes the VLAN interface + firewall pass + VM NAT. Empty
	// disables the PN data plane. See
	// bootstrap.Config.VMCachePNCIDR / VMCachePNVLAN.
	VMCachePNName string

	// VPC find-or-creates the runner-cache Private Network the Mac
	// fleet shares with the Elastic Metal cache node, resolving
	// VMCachePNName to an ID. Same shared client as the EM reconciler,
	// so the two fleets land on one PN per env.
	VPC *scaleway.VPCClient

	// TartKubeletMaxUpdateAttempts caps how many times the drift loop
	// retries a failing UpdateTartKubelet before transitioning the CR
	// to a terminal Failed state. Without a cap the operator
	// SSH-hammers a wedged host every 60s indefinitely with no
	// terminal-failure surface for ops. Defaulted to 5 attempts in
	// the manager binary; chart can override per env if needed.
	TartKubeletMaxUpdateAttempts int32

	// TartKubeletTerminalRetryAfter re-arms the drift loop this long
	// after the update failure that drove a host terminal. The terminal
	// state's other exit — a new HostConfigHash — only covers a host
	// that rejected the config; it never fires for the common case of a
	// host that was unreachable while the operator tried to push, which
	// then stays frozen at a stale config forever while its Node keeps
	// taking jobs. A cooldown bounds that to one fresh attempt budget
	// per interval. Zero disables the re-arm (hash-drift only).
	TartKubeletTerminalRetryAfter time.Duration

	// BootstrapRebootAfter is the consecutive-failure count at which
	// the BootstrapFailed path asks Scaleway to reboot the host. The
	// reboot clears volatile state (PAM lockouts, sshd throttling)
	// without paying for a disk reinstall, and is a no-op when the
	// host wasn't the problem. Fires once per host (gated on
	// Status.BootstrapRebootIssued). Default 3.
	BootstrapRebootAfter int32

	// BootstrapMaxAttempts is the consecutive-failure count at which
	// the controller gives up on the current host and returns it to
	// the adopt pool — Scaleway's ReinstallServer then wipes the disk
	// and the next reconcile claims a different mini. Without this
	// cap, a mini stuck in an unrecoverable state (stale
	// authorized_keys from a previous tenant, wedged sshd, OS
	// corruption) gets retried indefinitely against the same broken
	// host. Default 8.
	BootstrapMaxAttempts int32

	// MaxConcurrentReconciles is how many machines this controller
	// reconciles in parallel. controller-runtime's default of 1
	// serializes first-time fleet bring-up: each Mac mini's
	// AdoptFromPool + SSH bootstrap blocks the worker for ~50 min, so
	// N machines take N × that wall-clock. Reconciles for the same
	// machine are still serialized by controller-runtime's per-key
	// locking — bumping this only parallelizes across distinct CRs.
	MaxConcurrentReconciles int

	// DefaultAdoptPoolPrefix is the pool prefix every path falls back
	// to when a CR's Spec.AdoptPoolPrefix is empty — adoption,
	// bootstrap-exhaustion release, and delete alike. A CR reaches
	// that shape either by predating the field or by being cloned
	// from a MachineTemplate that drifted without it (helm patches
	// these CRs manifest-to-manifest, so a field the live object
	// never received is never backfilled). Empty means no prefix
	// resolves at all: adoption refuses to scan (an unprefixed scan
	// would claim an arbitrary server) and release skips, leaving the
	// host running for the orphan-reclaim sweep.
	DefaultAdoptPoolPrefix string

	// Tailscale egress Service materialisation. When EgressProxyGroup
	// is non-empty, the reconciler maintains one ExternalName Service
	// per Mac mini in EgressNamespace, annotated so the Tailscale K8s
	// operator binds it to the named ProxyGroup. The Service lets
	// alloy-metrics (and any other in-cluster Pod) scrape the Mac
	// mini at its MagicDNS FQDN without joining the tailnet itself —
	// see infra/helm/tailscale-operator/templates/macmini-egress.yaml
	// for the ProxyGroup side.
	//
	// Empty EgressProxyGroup disables the whole behavior; the OSS /
	// self-hosted shape (no tailnet) keeps working untouched.
	//
	// Cross-namespace OwnerRef isn't allowed, so reconcileDelete
	// explicitly removes the Service rather than relying on cascade.
	EgressNamespace      string
	EgressProxyGroup     string
	EgressMagicDNSSuffix string

	// RunnerResolver turns a Machine's `Spec.GHActionsRunner` into a
	// fully-populated `*bootstrap.GHActionsRunnerConfig` with a fresh
	// short-lived registration token. Empty when no Machine in the
	// cluster carries a GHActionsRunner spec (a pure-Node fleet);
	// non-nil for clusters that include the buildersFleet or any
	// future workload-on-host fleet.
	//
	// Lives behind an interface so the Scaleway-specific Machine
	// reconciler doesn't import workload-credential-specific code.
	// Production wires the GitHub-App-backed implementation in
	// `cmd/manager/main.go`; tests inject a stub that returns a
	// canned config without dialing GitHub or reading a Secret.
	RunnerResolver runner.Resolver
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconmachines/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconmachines/finalizers,verbs=update
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=machines,verbs=get;list;watch
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=clusters,verbs=get;list;watch
// +kubebuilder:rbac:groups="",resources=secrets,verbs=get;list;watch;create;update;delete
// +kubebuilder:rbac:groups="",resources=nodes,verbs=get;list;watch;delete
// +kubebuilder:rbac:groups="",resources=serviceaccounts,verbs=get;list;watch;create;update;delete
// +kubebuilder:rbac:groups="",resources=configmaps,resourceNames=cluster-info,verbs=get
// +kubebuilder:rbac:groups="",resources=services,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=rbac.authorization.k8s.io,resources=clusterrolebindings,verbs=get;list;watch;create;update;delete

// Reconcile uses named returns so the deferred patchHelper.Patch can
// promote a patch error into the function's return value. Without
// named returns, `err = perr` in the defer would assign to a local
// variable that Go has already evaluated for the return — the defer
// would silently swallow the patch failure and the function would
// report success, leaving Status.ServerID unpersisted after a
// successful AdoptFromPool and letting the next reconcile claim a
// second Mac mini from the pool.
func (r *ScalewayAppleSiliconMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	logger := log.FromContext(ctx).WithValues("machine", req.NamespacedName)
	logger.Info("reconcile entry")

	machine := &infrav1.ScalewayAppleSiliconMachine{}
	if getErr := r.Get(ctx, req.NamespacedName, machine); getErr != nil {
		if apierrors.IsNotFound(getErr) {
			// CR is gone; drop its phase series so a deleted machine
			// stops emitting a phantom phase (and never alerts on a
			// stale Failed).
			forgetMachinePhase(req.Name)
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

	// Publish the phase this reconcile leaves the machine in, so a host
	// stuck terminal Failed (TartKubeletUpdateExceededRetries) is alertable
	// instead of only visible via `kubectl get machine`. Deferred so it
	// reads the final status set below (including the delete path's
	// Deleting; the NotFound branch above forgets it once fully gone).
	defer recordMachinePhase(machine)

	// Resolve the parent CAPI Machine, if there is one. The chart
	// renders MachineDeployment → MachineSet → Machine →
	// ScalewayAppleSiliconMachine; CAPI core stamps an OwnerRef on
	// our CR pointing at the Machine, and we drive most lifecycle
	// off the parent's spec / status. Standalone CRs (no parent
	// Machine) are still reconciled normally — useful for tests
	// and for any operator-side bring-up before MachineDeployment
	// adoption completes.
	ownerMachine, ownerErr := util.GetOwnerMachine(ctx, r.Client, machine.ObjectMeta)
	if ownerErr != nil {
		return ctrl.Result{}, fmt.Errorf("get owner Machine: %w", ownerErr)
	}

	// Handle deletion.
	if !machine.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, machine)
	}

	// Make sure we have a finalizer so we always get a chance to
	// release the Scaleway server before the CR disappears.
	if !controllerutil.ContainsFinalizer(machine, MachineFinalizer) {
		controllerutil.AddFinalizer(machine, MachineFinalizer)
	}

	// Resolve parent Cluster (if any) for the readiness + pause gates.
	// Standalone CRs (no owner Machine) skip the lookup but still
	// honor a per-object pause annotation below.
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

	// Pause gate. Respects both Cluster.Spec.Paused AND the standard
	// CAPI cluster.x-k8s.io/paused annotation on the infra CR itself.
	// The per-object annotation is the operator's safety latch for
	// out-of-band cleanup: when manually clearing status.ServerID +
	// spec.ProviderID before a `kubectl delete` (e.g. to release a CR
	// without releasing its underlying Scaleway server — the
	// duplicate-claim recovery dance), the reconciler must NOT see the
	// transient "fresh CR" shape and run AdoptFromPool against the pool
	// in between. Set the annotation first, patch second, delete
	// third; the annotation latches reconcileNormal off until the
	// DeletionTimestamp lands and reconcileDelete (which runs above,
	// regardless of pause) takes over.
	//
	// annotations.IsPaused panics on nil cluster, so split the two
	// signals — Cluster.Spec.Paused is only meaningful when a parent
	// Cluster exists, and HasPaused covers the standalone case (and
	// the owned case where the operator annotated just the CR).
	//
	// Evaluated BEFORE the InfrastructureReady check below: a paused
	// CR whose parent Cluster is also infra-not-ready should go
	// silent, not requeue every 30s. The pause signal is "operator
	// wants me to stop"; honoring it has priority over readiness gating.
	if cluster != nil && cluster.Spec.Paused {
		logger.Info("parent Cluster paused; skipping reconcile")
		return ctrl.Result{}, nil
	}
	if annotations.HasPaused(machine) {
		logger.Info("Machine paused via annotation; skipping reconcile")
		return ctrl.Result{}, nil
	}

	// CAPI's Machine controller waits for the InfrastructureCluster's
	// Status.Ready before stamping our CR's OwnerRef, but we still
	// gate on the parent Cluster being ready before touching
	// Scaleway — covers the brief window where a Machine exists but
	// the cluster's not provisioned.
	if cluster != nil && !cluster.Status.InfrastructureReady {
		logger.Info("parent Cluster InfrastructureReady=false; requeueing")
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	return r.reconcileNormal(ctx, machine)
}

func (r *ScalewayAppleSiliconMachineReconciler) reconcileNormal(
	ctx context.Context,
	machine *infrav1.ScalewayAppleSiliconMachine,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	// Stage 0: ensure the per-fleet SSH key is registered with Scaleway
	// BEFORE we adopt the Mac mini. Scaleway only injects project SSH
	// keys at the host's first-boot — keys registered after the order
	// are not auto-installed, leaving us locked out of SSH and unable
	// to bootstrap kubelet. Doing this first means a freshly pre-
	// ordered Mac mini comes up with our pubkey already in
	// ~/.ssh/authorized_keys, ready for adoption.
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
		srv, requeue, err := r.acquireServer(ctx, machine)
		if err != nil {
			return ctrl.Result{RequeueAfter: requeue}, nil
		}
		if srv == nil {
			// Adoption path with no available host. Requeue and
			// keep the operator-visible event/condition state.
			return ctrl.Result{RequeueAfter: requeue}, nil
		}

		machine.Status.ServerID = srv.ID
		// New host adopted — the failure-tracking state from a
		// previously-discarded host doesn't apply. (The
		// BootstrapFailed path that called ReleaseToPool already
		// resets these, but cover the case where ServerID flipped
		// without going through that path — e.g., legacy CR or
		// manual operator intervention.)
		machine.Status.BootstrapAttempts = 0
		machine.Status.BootstrapRebootIssued = false
		machine.Status.Addresses = []clusterv1.MachineAddress{{
			Type:    clusterv1.MachineExternalIP,
			Address: srv.IP,
		}}
		providerID := fmt.Sprintf("scw-applesilicon://%s/%s", machine.Spec.Zone, srv.ID)
		machine.Spec.ProviderID = &providerID

		// Persist sudo password + SSH username in a per-machine
		// Secret in the operator's namespace, gated by the chart's
		// RBAC and never exposed via the CR's wider read surface
		// (etcd backups, audit logs, `kubectl describe`).
		if err := r.CredentialsManager.SetMachineCredentials(ctx, machine.Name, srv.SudoPassword, srv.SSHUsername); err != nil {
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "CredentialsPersistFailed",
				clusterv1.ConditionSeverityError, "%v", err)
			r.Recorder.Eventf(machine, corev1.EventTypeWarning, "ProvisioningFailed",
				"persist machine credentials: %v", err)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		conditions.MarkTrue(machine, shared.ProvisionedCondition)
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Provisioned",
			"Mac mini %s ready, IP=%s", srv.ID, srv.IP)
		logger.Info("provisioned Scaleway Mac mini", "id", srv.ID, "ip", srv.IP)
	}

	bootstrapCreds, err := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name)
	if err != nil {
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}
	if bootstrapCreds == nil {
		// Stage 1 didn't write the Secret yet (fresh CR mid-reconcile,
		// or operator pod that crashed between AdoptFromPool + Secret
		// write). Requeue.
		return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
	}

	// Refuse to bootstrap with an empty sudo password. The bootstrap
	// path stages `/etc/kcpassword` from `UserPassword`; an empty
	// value XORs to just the cipher key padding, loginwindow rejects
	// the auto-login, and Aqua never comes up — `tart run` then fails
	// on every Pod with a 30s SIGHUP timeout for the lifetime of the
	// host.
	//
	// Before refusing, attempt to reclaim the password from Scaleway.
	// Machines that hit the pre-fix failure mode still have
	// Status.ServerID set and a bootstrap Secret with an empty
	// sudo-password, so this reconcile pass would skip Stage 1 (which
	// is where the vnc_url fallback runs) and loop on
	// MissingSudoPassword forever. A fresh GetServer goes through
	// scalewayServerToServer, which now reads the password out of
	// vnc_url; if that produces a non-empty value, persist it to the
	// Secret and proceed with bootstrap. Only surface
	// MissingSudoPassword when even the refresh comes back empty (the
	// host genuinely has no recoverable credentials).
	//
	// The same recovery applies when the Secret holds Scaleway's
	// `<sealed>` placeholder — surfaced verbatim when macOS Tahoe
	// seals the OS-level auto-login credential. The marker isn't a
	// usable password (sudo rejects it as "Sorry, try again") but is
	// non-empty so the bare `== ""` check would treat it as valid
	// and skip the recovery path. Drop it the same way an empty
	// value gets dropped.
	if bootstrapCreds.SudoPassword == scaleway.SealedSecretMarker {
		bootstrapCreds.SudoPassword = ""
	}
	if bootstrapCreds.SudoPassword == "" && machine.Status.ServerID != "" {
		srv, refreshErr := r.ScalewayClient.GetServer(ctx, machine.Status.ServerID, machine.Spec.Zone)
		switch {
		case refreshErr != nil:
			// Transient Scaleway error (network blip, 5xx, throttle).
			// Don't bury it as `MissingSudoPassword` with a 5-minute
			// backoff — that condition is reserved for a definitive
			// "Scaleway says there's no password". Surface a
			// retryable condition and requeue soon so the refresh
			// gets another chance on the next reconcile tick.
			conditions.MarkFalse(machine, BootstrappedCondition, "CredentialsRefreshFailed",
				clusterv1.ConditionSeverityWarning, "%v", refreshErr)
			r.Recorder.Eventf(machine, corev1.EventTypeWarning, "CredentialsRefreshFailed",
				"Scaleway GetServer for %s failed while trying to recover sudo password: %v",
				machine.Name, refreshErr)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		case srv != nil && srv.SudoPassword != "":
			if writeErr := r.CredentialsManager.SetMachineCredentials(ctx, machine.Name, srv.SudoPassword, srv.SSHUsername); writeErr != nil {
				logger.Error(writeErr, "refresh bootstrap secret from Scaleway")
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			r.Recorder.Eventf(machine, corev1.EventTypeNormal, "CredentialsReclaimed",
				"Recovered sudo password for %s from Scaleway vnc_url; bootstrap will resume",
				machine.Name)
			bootstrapCreds.SudoPassword = srv.SudoPassword
			bootstrapCreds.SSHUsername = srv.SSHUsername
		}
	}
	if bootstrapCreds.SudoPassword == "" {
		conditions.MarkFalse(machine, BootstrappedCondition, "MissingSudoPassword",
			clusterv1.ConditionSeverityError,
			"bootstrap secret has no sudo password and Scaleway did not surface one; refusing to bootstrap a host without auto-login credentials")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "MissingSudoPassword",
			"Bootstrap secret for %s has no sudo password and the Scaleway refresh did not recover one — verify credentials at the source",
			machine.Name)
		return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
	}

	// Detect Node drift: bootstrap previously succeeded
	// (BootstrappedCondition=True) but the Node tart-kubelet
	// registered no longer exists in the cluster. Causes seen in
	// practice: upstream CAPI core deleting the Node during workload-
	// cluster reconcile churn, manual `kubectl delete node`, or a
	// cluster-level cleanup controller. The Mac mini host itself is
	// still allocated at Scaleway and the launchd job is still loaded;
	// re-running bootstrap reloads launchd, which makes tart-kubelet
	// re-register the Node. No Scaleway re-provisioning needed and the
	// existing per-machine token + ServiceAccount + ClusterRoleBinding
	// stay in place. Flipping the condition False here lets Stage 2's
	// existing gate drive the re-bootstrap.
	if missing, lookupErr := r.nodeMissingAfterBootstrap(ctx, machine); lookupErr != nil {
		logger.Error(lookupErr, "Node existence check failed; will retry")
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	} else if missing {
		conditions.MarkFalse(machine, BootstrappedCondition, "NodeMissing",
			clusterv1.ConditionSeverityWarning,
			"Node %s not found in cluster despite Bootstrapped=True; re-running bootstrap", machine.Name)
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "NodeMissing",
			"Node %s missing; reloading tart-kubelet on the existing Mac mini to re-register",
			machine.Name)
	}

	// Stage 2: bootstrap (idempotent — re-running picks up where it
	// left off).
	if !conditions.IsTrue(machine, BootstrappedCondition) {
		machine.Status.Phase = "Bootstrapping"
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Bootstrapping",
			"Installing Tart + tart-kubelet on %s", machineIP(machine))

		ip := machineIP(machine)
		if ip == "" {
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}

		identity, err := r.CredentialsManager.EnsureNodeIdentity(ctx, machine.Name, "")
		if err != nil {
			conditions.MarkFalse(machine, BootstrappedCondition, "NodeIdentityUnavailable",
				clusterv1.ConditionSeverityWarning, "%v", err)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		kubeconfigYAML, err := r.Kubeconfig.Render(ctx, machine.Name, identity.Token, identity.CA)
		if err != nil {
			conditions.MarkFalse(machine, BootstrappedCondition, "KubeconfigUnavailable",
				clusterv1.ConditionSeverityWarning, "%v", err)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}

		tailscaleAuthKey, err := r.CredentialsManager.GetTailscaleAuthKey(ctx)
		if err != nil {
			conditions.MarkFalse(machine, BootstrappedCondition, "TailscaleAuthKeyUnavailable",
				clusterv1.ConditionSeverityWarning, "%v", err)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}

		var ghRunner *bootstrap.GHActionsRunnerConfig
		if machine.Spec.GHActionsRunner != nil {
			if r.RunnerResolver == nil {
				return ctrl.Result{}, fmt.Errorf("RunnerResolver not wired on reconciler; the manager binary must set it when any fleet carries a ghActionsRunner spec")
			}
			ghRunner, err = r.RunnerResolver.Resolve(ctx, machine.Namespace, machine.Spec.GHActionsRunner)
			if err != nil {
				conditions.MarkFalse(machine, BootstrappedCondition, "GHRunnerRegistrationTokenUnavailable",
					clusterv1.ConditionSeverityWarning, "%v", err)
				r.Recorder.Eventf(machine, corev1.EventTypeWarning, "GHRunnerRegistrationTokenUnavailable",
					"%v (will retry; check the github-app Secret + GitHub App reachability)", err)
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
		}

		vmCachePNVLAN, err := r.ensureVMCachePN(ctx, machine)
		if err != nil {
			conditions.MarkFalse(machine, BootstrappedCondition, "CachePrivateNetworkUnavailable",
				clusterv1.ConditionSeverityWarning, "%v", err)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		vncRelayHost := r.dashboardVNCRelayHost(machine.Name)

		fingerprint, err := bootstrap.Run(ctx, r.hostConfig(machine, bootstrap.PerHost{
			IP:                   ip,
			SSHUser:              bootstrapCreds.SSHUsername,
			UserPassword:         bootstrapCreds.SudoPassword,
			SSHPrivateKey:        sshKey,
			NodeName:             machine.Name,
			ProviderID:           providerIDOf(machine),
			Kubeconfig:           kubeconfigYAML,
			TailscaleAuthKey:     tailscaleAuthKey,
			VMCachePNVLAN:        vmCachePNVLAN,
			VNCRelayHost:         vncRelayHost,
			NodeLabels:           machineNodeLabels(machine),
			KnownHostFingerprint: bootstrapCreds.HostFingerprint,
			GHActionsRunner:      ghRunner,
		}))
		// Persist whatever fingerprint Run captured even on the error
		// path, so a transient bootstrap failure doesn't lose the
		// TOFU pin we already verified successfully.
		if fingerprint != "" && fingerprint != bootstrapCreds.HostFingerprint {
			if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, fingerprint); perr != nil {
				logger.Error(perr, "persist host fingerprint; will retry")
			} else {
				bootstrapCreds.HostFingerprint = fingerprint
			}
		}
		if err != nil {
			return handleBootstrapFailure(ctx, machine, err, r.ScalewayClient, r.CredentialsManager, r.Recorder, logger, r.BootstrapRebootAfter, r.BootstrapMaxAttempts, r.adoptPoolPrefix(machine)), nil
		}

		conditions.MarkTrue(machine, BootstrappedCondition)
		// Reset failure-tracking state — a long retry chain that
		// finally succeeded is, from the cluster's perspective, the
		// same shape as a first-try success.
		machine.Status.BootstrapAttempts = 0
		machine.Status.BootstrapRebootIssued = false
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Bootstrapped",
			"Mac mini joined cluster as Node %s", machine.Name)
		logger.Info("bootstrap complete", "host", ip)
	}

	// Stage 3: rolling tart-kubelet update.
	//
	// Bootstrap installs the agent once. After that, the operator's
	// own image carries the source-of-truth binary; deploying a new
	// operator image rolls a new kubelet across the fleet. We compare
	// the operator's binary SHA-256 to the last-applied SHA on each
	// Machine and on mismatch re-upload + reload launchd.
	//
	// Running Tart VMs survive an agent restart (`nohup`-detached) and
	// the kubelet's startup state-recovery pass re-binds them, so the
	// rollout is zero-downtime for workloads.
	// Drift on the fleet-wide host-config hash, not just the tart-kubelet
	// binary SHA: a change to ANY pushed config — an install-script tweak,
	// a fleet CIDR / tag / accept-routes flip, or any re-baked binary —
	// moves the hash and re-pushes the host config. Existing machines
	// carry an empty Status.HostConfigHash, so the first reconcile after
	// this upgrade drifts once and re-pushes — the intended migration.
	// Resolved per machine, not read from a fleet-wide field: HostCPU and
	// HostMemoryMB are overridable per Machine, so the desired hash for an
	// overridden host is not the fleet's. See desiredHostConfigHash.
	desiredHostConfigHash := r.desiredHostConfigHash(machine)
	configDrift := hostConfigDrift(desiredHostConfigHash, machine.Status.HostConfigHash)
	// Once a CR enters the terminal-failed state (FailureReason set
	// and FailureMessage describes the underlying error) we stop
	// firing the drift loop. CAPI core takes over: surfaces the
	// failure on the parent Machine and refuses to drive replacement
	// without operator action. Recovery: clear FailureReason +
	// reset TartKubeletUpdateAttempts to resume the loop.
	terminalFailure := machine.Status.FailureReason != nil
	// Self-heal on config change: a terminal failure is a verdict on the
	// config the operator was trying to push when it exhausted its retries. If
	// the desired host config differs from the one that failed, a new —
	// typically fixed — config has landed, and it deserves its own retry budget
	// rather than inheriting the old config's verdict. Clearing the terminal
	// state here makes pushing a corrected operator image self-heal every host
	// a bad rollout bricked, instead of requiring a manual status patch per host.
	//
	// Crucially, this compares the desired hash against the recorded FAILED
	// hash, NOT the last-applied Status.HostConfigHash. A broken config can
	// never be applied, so Status.HostConfigHash never advances to it and plain
	// drift stays true forever — comparing against it would reset the retry cap
	// every reconcile and hammer the same broken config indefinitely, defeating
	// the cap. Against the failed hash, an unchanged broken config stays
	// terminal while a genuinely new config retries.
	//
	// Self-heal on time too: config drift only lifts the state for a host that
	// REJECTED the config, and most terminal failures are instead a host the
	// operator could not reach (`dial tcp ...:22: i/o timeout`). Those stayed
	// terminal indefinitely — Ready, schedulable, still running jobs — pinned
	// to whatever config was last pushed, so a networking fix could roll to the
	// fleet and silently miss them. The cooldown gives such a host one fresh
	// attempt budget per interval once it is reachable again.
	if shouldClearTerminalFailure(
		desiredHostConfigHash,
		machine.Status.FailedHostConfigHash,
		terminalFailure,
		machine.Status.LastUpdateFailureTime,
		r.TartKubeletTerminalRetryAfter,
		time.Now(),
	) {
		reason := "host config drifted since the failure was recorded"
		if desiredHostConfigHash != "" && desiredHostConfigHash == machine.Status.FailedHostConfigHash {
			reason = "retry cooldown elapsed"
		}
		clearUpdateFailure(machine, reason, logger, r.Recorder)
		terminalFailure = false
	}
	if configDrift && !terminalFailure {
		ip := machineIP(machine)
		if ip == "" {
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		identity, err := r.CredentialsManager.EnsureNodeIdentity(ctx, machine.Name, "")
		if err != nil {
			recordUpdateFailure(machine, fmt.Errorf("ensure node identity: %w", err), r.TartKubeletMaxUpdateAttempts, desiredHostConfigHash, logger, r.Recorder)
			if machine.Status.FailureReason != nil {
				return ctrl.Result{}, nil
			}
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		kubeconfigYAML, err := r.Kubeconfig.Render(ctx, machine.Name, identity.Token, identity.CA)
		if err != nil {
			recordUpdateFailure(machine, fmt.Errorf("render kubeconfig: %w", err), r.TartKubeletMaxUpdateAttempts, desiredHostConfigHash, logger, r.Recorder)
			if machine.Status.FailureReason != nil {
				return ctrl.Result{}, nil
			}
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		// On the drift-update path the auth key is read to drive the
		// kubelet's --node-ip-source decision in the regenerated
		// launchd plist — without it, a re-render would drop the
		// `--node-ip-source=tailscale` arg and silently flip kubelet
		// back to the public IP. Fetching the key here is the cheap
		// way to keep the plist render correct.
		tailscaleAuthKey, err := r.CredentialsManager.GetTailscaleAuthKey(ctx)
		if err != nil {
			recordUpdateFailure(machine, fmt.Errorf("get tailscale auth key: %w", err), r.TartKubeletMaxUpdateAttempts, desiredHostConfigHash, logger, r.Recorder)
			if machine.Status.FailureReason != nil {
				return ctrl.Result{}, nil
			}
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}

		vmCachePNVLAN, err := r.ensureVMCachePN(ctx, machine)
		if err != nil {
			// Zero VLAN skips interface management but keeps the
			// firewall pass rule; don't let a transient Scaleway API
			// error stall a kubelet binary roll.
			logger.Error(err, "resolve cache private network VLAN; continuing drift update without interface management")
			vmCachePNVLAN = 0
		}
		vncRelayHost := r.dashboardVNCRelayHost(machine.Name)

		// The drift update dials the mini's public IP first (see the
		// tailnet fallback right after this call). cfg.IP is a pure dial
		// target on the update path — HostConfigHash strips it and nothing
		// else reads it — so the fallback re-points it without changing
		// what we push.
		updateCfg := r.hostConfig(machine, bootstrap.PerHost{
			IP:               ip,
			SSHUser:          bootstrapCreds.SSHUsername,
			SSHPrivateKey:    sshKey,
			NodeName:         machine.Name,
			ProviderID:       providerIDOf(machine),
			Kubeconfig:       kubeconfigYAML,
			TailscaleAuthKey: tailscaleAuthKey,
			VMCachePNVLAN:    vmCachePNVLAN,
			VNCRelayHost:     vncRelayHost,
			NodeLabels:       machineNodeLabels(machine),
			// Builder hosts must keep `--disable-vm-gc` across binary
			// rolls. This path re-renders the plist but doesn't re-resolve
			// GHActionsRunner (which renderLaunchdPlist otherwise keys the
			// flag off), so carry the builder signal explicitly — without
			// it the roll strips the flag and the orphan-VM GC reaps the
			// in-flight image-bake VM mid-`tart push`.
			DisableVMGC:          machine.Spec.GHActionsRunner != nil,
			KnownHostFingerprint: bootstrapCreds.HostFingerprint,
		})
		fingerprint, err := bootstrap.UpdateTartKubelet(ctx, updateCfg)
		// Tailnet fallback. A running runner mini filters inbound :22 on
		// its public interface once Internet Sharing / vmnet reconfigures
		// the public path (it starts booting Tart VMs), so the public dial
		// times out and the whole fleet's rolls wedge — while the host
		// stays reachable on the tailnet (that's how its metrics are
		// scraped). An empty fingerprint means the SSH handshake never
		// completed (a pure connect failure, distinct from a mid-session
		// command error), so retry over the mini's egress-Service DNS,
		// which routes through the ProxyGroup. Public-first keeps the
		// common path fast and lets the tailscale reinstall run on a
		// transport it can safely restart; the fallback sets
		// SkipTailscaleInstall because stopping tailscaled to swap its
		// binary would drop the very tunnel this session rides. Fresh /
		// idle minis (public open) never reach the fallback, so this never
		// races egress-Service creation (Stage 4) — by the time a mini's
		// public path is filtered its Service has long existed.
		if err != nil && fingerprint == "" {
			if egressHost := r.egressHost(machine.Name); egressHost != "" && egressHost != ip {
				logger.Info("public-IP tart-kubelet update dial failed; retrying over the tailnet",
					"machine", machine.Name, "egressHost", egressHost, "cause", err.Error())
				updateCfg.IP = egressHost
				updateCfg.SkipTailscaleInstall = true
				fingerprint, err = bootstrap.UpdateTartKubelet(ctx, updateCfg)
			}
		}
		if fingerprint != "" && fingerprint != bootstrapCreds.HostFingerprint {
			if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, fingerprint); perr != nil {
				logger.Error(perr, "persist host fingerprint on update; will retry")
			}
		}
		if err != nil {
			recordUpdateFailure(machine, fmt.Errorf("tart-kubelet update: %w", err), r.TartKubeletMaxUpdateAttempts, desiredHostConfigHash, logger, r.Recorder)
			if machine.Status.FailureReason != nil {
				return ctrl.Result{}, nil
			}
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		}
		machine.Status.TartKubeletBinarySHA = r.TartKubeletBinarySHA
		machine.Status.HostConfigHash = desiredHostConfigHash
		machine.Status.TartKubeletUpdateAttempts = 0
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, "AgentRolled",
			"Rolled tart-kubelet to %s", r.TartKubeletBinarySHA)
		logger.Info("rolled new tart-kubelet", "host", ip, "sha", r.TartKubeletBinarySHA,
			"hostConfigHash", desiredHostConfigHash)
	}

	// Stage 4: materialise the per-machine Tailscale egress Service
	// (when wired by the chart). Doesn't gate on bootstrap success —
	// the FQDN is deterministic (`<machine.Name>.<suffix>`), so the
	// Service can exist before the host has joined the tailnet; the
	// Tailscale operator pends the ExternalName rewrite until the
	// FQDN resolves and reconciles transparently when it does.
	if err := r.reconcileTailscaleEgressService(ctx, machine); err != nil {
		// Conflicts are benign: the Tailscale operator and this
		// reconciler write to the same Service (it owns the
		// externalName rewrite + ts-condition annotations, we own
		// the tailnet-fqdn + ports). When they race, one Update
		// loses the resourceVersion check. Requeue immediately so
		// the next reconcile reads the fresh version; don't log an
		// error or surface an Event for the noise.
		if apierrors.IsConflict(err) {
			return ctrl.Result{Requeue: true}, nil
		}
		// Don't fail the whole reconcile: bootstrap already succeeded
		// and the egress Service is the scrape boundary, not the
		// workload boundary. Surface the failure as an Event and
		// requeue.
		logger.Error(err, "reconcile tailscale egress Service; will retry")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "EgressServiceFailed",
			"reconcile tailscale egress Service: %v (will retry)", err)
		return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
	}

	// Mac mini is now running tart-kubelet and registering itself as a
	// real Node. From CAPI's perspective the Machine is Ready as soon
	// as bootstrap returns; whether the Node has reported Ready yet is
	// a separate concern observable via `kubectl get nodes`.
	machine.Status.Ready = true
	if !terminalPhasePinned(machine.Status.FailureReason) {
		machine.Status.Phase = "Ready"
	}
	return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
}

func (r *ScalewayAppleSiliconMachineReconciler) reconcileDelete(
	ctx context.Context,
	machine *infrav1.ScalewayAppleSiliconMachine,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	machine.Status.Phase = "Deleting"

	// Stage 1: release the Scaleway server back into the pool —
	// rename + reinstall — so the host stays alive for the next
	// adopt. Skip if already released (mid-cleanup retry).
	//
	// CRs with an unset AdoptPoolPrefix fall back to the
	// controller-level DefaultAdoptPoolPrefix so the host still
	// returns to the pool. Only when neither the CR nor the
	// controller default carries a prefix do we skip the Scaleway
	// release (the client rejects an empty prefix to avoid orphaning a
	// host outside the pool namespace), leave the host running, and
	// let the orphan-reclaim sweep or an operator clean it up. Without
	// this fallthrough, deleting a bare CR would loop forever on
	// a precondition error and block fleet teardown.
	if machine.Status.ServerID != "" {
		poolPrefix := r.adoptPoolPrefix(machine)
		switch {
		case poolPrefix == "":
			r.Recorder.Eventf(machine, corev1.EventTypeWarning, "ReleaseSkipped",
				"No AdoptPoolPrefix on the CR and no controller default; skipping Scaleway release of %s — the orphan-reclaim sweep or an operator must return it to the pool",
				machine.Status.ServerID)
			logger.Info("no pool prefix available; skipping Scaleway release",
				"serverID", machine.Status.ServerID)
			machine.Status.ServerID = ""
		default:
			r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Releasing",
				"Returning Scaleway server %s to pool %q (with reinstall)",
				machine.Status.ServerID, poolPrefix)
			if err := releaseHostToPool(ctx, r.ScalewayClient, r.Recorder, machine, poolPrefix); err != nil {
				logger.Error(err, "Scaleway release-to-pool failed; will retry")
				r.Recorder.Eventf(machine, corev1.EventTypeWarning, "ReleaseFailed",
					"Scaleway ReleaseToPool: %v (will retry)", err)
				return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
			}
			machine.Status.ServerID = ""
			r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Released",
				"Scaleway server returned to pool; reinstall triggered")
		}
	}

	// Stage 2: drop the per-machine kubelet identity. The token is
	// long-lived and bound to a ClusterRole that reads Secrets and
	// ConfigMaps cluster-wide; leaving it behind after the host is
	// released would orphan a valid privileged credential. The
	// credentials.Manager deletes the ClusterRoleBinding first so the
	// token loses authority before the token Secret itself is removed.
	if err := r.CredentialsManager.DeleteNodeIdentity(ctx, machine.Name); err != nil {
		logger.Error(err, "delete node identity; will retry")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "DeleteFailed",
			"delete node identity: %v (will retry)", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Stage 3: drop the per-machine bootstrap Secret (sudo password,
	// SSH username, TOFU host fingerprint).
	if err := r.CredentialsManager.DeleteMachineBootstrap(ctx, machine.Name); err != nil {
		logger.Error(err, "delete machine bootstrap; will retry")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "DeleteFailed",
			"delete machine bootstrap: %v (will retry)", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Stage 4: drop the cluster Node object the kubelet registered.
	// The host is gone, so the kubelet can't deregister itself;
	// without this the Node lingers as NotReady forever and confuses
	// scaling / drain semantics for downstream tooling.
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: machine.Name}}
	if err := r.Client.Delete(ctx, node); err != nil && !apierrors.IsNotFound(err) {
		logger.Error(err, "delete Node object; will retry")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "DeleteFailed",
			"delete Node: %v (will retry)", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Stage 5: drop the per-machine Tailscale egress Service if the
	// chart wired it up. Cross-namespace OwnerRef isn't allowed
	// (Service lives in the tailscale-operator namespace, this CR
	// lives in the operator's), so we delete explicitly.
	if r.EgressProxyGroup != "" {
		svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{
			Name:      machine.Name,
			Namespace: r.EgressNamespace,
		}}
		if err := r.Client.Delete(ctx, svc); err != nil && !apierrors.IsNotFound(err) {
			logger.Error(err, "delete egress Service; will retry")
			r.Recorder.Eventf(machine, corev1.EventTypeWarning, "DeleteFailed",
				"delete egress Service %s/%s: %v (will retry)", r.EgressNamespace, machine.Name, err)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
	}

	controllerutil.RemoveFinalizer(machine, MachineFinalizer)
	return ctrl.Result{}, nil
}

// === helpers ================================================================

// egressConfig gathers this reconciler's chart-driven Tailscale egress wiring
// into the value the shared helpers take.
func (r *ScalewayAppleSiliconMachineReconciler) egressConfig() egressConfig {
	return egressConfig{
		Namespace:      r.EgressNamespace,
		ProxyGroup:     r.EgressProxyGroup,
		MagicDNSSuffix: r.EgressMagicDNSSuffix,
		ManagedBy:      operatorName,
	}
}

func (r *ScalewayAppleSiliconMachineReconciler) reconcileTailscaleEgressService(
	ctx context.Context,
	machine *infrav1.ScalewayAppleSiliconMachine,
) error {
	return reconcileEgressService(ctx, r.Client, r.egressConfig(),
		machine.Name, machine.Spec.FleetName,
		guestCapacityFor(machine, r.DefaultGuestCapacity))
}

func (r *ScalewayAppleSiliconMachineReconciler) egressHost(machineName string) string {
	return egressServiceHost(r.egressConfig(), machineName)
}

func (r *ScalewayAppleSiliconMachineReconciler) dashboardVNCRelayHost(machineName string) string {
	return r.egressHost(machineName)
}

// hostSizing resolves this Machine's SKU-shaped fields: the per-Machine
// override where set, the operator-global default otherwise. Lets a single
// operator instance manage heterogeneous fleets (e.g. xcresult-fleet on M2-M
// and runners-fleet on M2-L, or M2-L and M4-XL side by side in ONE runners
// fleet) without spawning a deployment per SKU or under-advertising on the
// larger one.
//
// Everything resolved here reaches both push paths and the hash through
// applyHostSizing, so a change to any of it drifts the host.
func (r *ScalewayAppleSiliconMachineReconciler) hostSizing(
	machine *infrav1.ScalewayAppleSiliconMachine,
) hostSizing {
	return hostSizing{
		HostCPU:              hostCPUFor(machine, r.FleetConfig.HostCPU),
		HostMemoryMB:         hostMemoryMBFor(machine, r.FleetConfig.HostMemoryMB),
		MaxPods:              maxPodsFor(machine, r.FleetConfig.MaxPods),
		GuestCapacity:        guestCapacityFor(machine, r.DefaultGuestCapacity),
		RunnerCacheVolumeGiB: runnerCacheVolumeGiBFor(machine, r.FleetConfig.RunnerCacheVolumeGiB),
	}
}

// hostConfig is the config for one Mac mini: the fleet-wide config the manager
// built, with this machine's sizing and per-host fields overlaid. Both push
// paths go through it, so neither can push a config the operator did not hash.
func (r *ScalewayAppleSiliconMachineReconciler) hostConfig(
	machine *infrav1.ScalewayAppleSiliconMachine,
	perHost bootstrap.PerHost,
) bootstrap.Config {
	return applyHostSizing(r.FleetConfig, r.hostSizing(machine), perHost)
}

// desiredHostConfigHash is the fingerprint of the config this machine should be
// running — the hash of exactly what hostConfig would push.
func (r *ScalewayAppleSiliconMachineReconciler) desiredHostConfigHash(
	machine *infrav1.ScalewayAppleSiliconMachine,
) string {
	return hostConfigHashFor(r.FleetConfig, r.hostSizing(machine))
}

// poolReleaser is the one call releaseHostToPool needs, so both the
// full *scaleway.Client on the reconciler and the narrow
// bootstrapRecoveryClient can go through the same policy.
type poolReleaser interface {
	ReleaseToPool(ctx context.Context, id, zone, poolPrefix string, pin scaleway.ReleasePin) error
}

// releaseHostToPool returns a host to the pool, reinstalling it onto
// the fleet's pinned image so the next AdoptFromPool scan — which
// matches the image name exactly — can claim it back.
//
// A pin Scaleway has retired is downgraded to an unpinned release
// rather than failed. Every Machine created before an operator
// repoints its fleet carries the old pin baked into its own spec, and
// failing here would wedge each of them on delete: the host stays
// claimed and billing, the finalizer never clears, and the fleet
// can't shed the Machine to get a correctly-pinned replacement. The
// host lands on the server type's default image instead, which is
// what a repointed fleet will be pinned to anyway. The event names
// the pin so the fix is obvious.
func releaseHostToPool(
	ctx context.Context,
	client poolReleaser,
	recorder record.EventRecorder,
	machine *infrav1.ScalewayAppleSiliconMachine,
	poolPrefix string,
) error {
	err := client.ReleaseToPool(ctx, machine.Status.ServerID, machine.Spec.Zone, poolPrefix,
		scaleway.ReleasePin{Family: machine.Spec.OS, ServerType: machine.Spec.Type})
	if !errors.Is(err, scaleway.ErrOSNotPublished) {
		return err
	}
	recorder.Eventf(machine, corev1.EventTypeWarning, "OSPinUnavailable",
		"Fleet os pin %q is no longer published by Scaleway; releasing %s onto the server type default instead. Repoint the fleet's os pin: %v",
		machine.Spec.OS, machine.Status.ServerID, err)
	return client.ReleaseToPool(ctx, machine.Status.ServerID, machine.Spec.Zone, poolPrefix, scaleway.ReleasePin{})
}

// bootstrapRecoveryClient is the narrow Scaleway surface
// handleBootstrapFailure needs. Tests can satisfy it with a tiny
// in-memory stub; the production *scaleway.Client satisfies it
// natively.
type bootstrapRecoveryClient interface {
	RebootServer(ctx context.Context, id, zone string) error
	ReleaseToPool(ctx context.Context, id, zone, poolPrefix string, pin scaleway.ReleasePin) error
}

// bootstrapSecretCleaner wipes the per-machine bootstrap Secret that
// holds the previous host's sudo password, SSH username, and TOFU
// host fingerprint. The production *credentials.Manager satisfies it
// via DeleteMachineBootstrap. Separating this from the Scaleway
// surface keeps both interfaces narrow and lets tests stub the
// concerns independently.
type bootstrapSecretCleaner interface {
	DeleteMachineBootstrap(ctx context.Context, machineName string) error
}

// handleBootstrapFailure records the bootstrap error on the machine
// and runs tiered host recovery. Returns the ctrl.Result the caller
// should propagate.
//
// Tier 1: at `rebootAfter` consecutive failures, ask Scaleway to
// reboot the host once. Most BootstrapFailed errors observed in
// production are host-volatile (PAM account lockouts from sudo
// retries, sshd connection throttling, half-open SSH sessions) and
// resolve after a clean boot. Gated on Status.BootstrapRebootIssued so
// a long retry tail doesn't re-reboot the same host. If RebootServer
// returns an error the flag stays false and the next reconcile retries
// the reboot (the condition is `>=` rather than `==`).
//
// Tier 2: at `maxAttempts` consecutive failures, return the host to
// the adopt pool. ReleaseToPool renames + triggers ReinstallServer
// (full disk wipe + factory image), so the next reconcile claims a
// different mini via AdoptFromPool. Status.ServerID is cleared so the
// adoption stage re-runs; counter + reboot flag reset because they
// describe the now-discarded host. The per-machine bootstrap Secret is
// deleted so the next adopt rebuilds it from scratch — without that
// step the previous host's TOFU fingerprint would survive and
// SSH-verify against the replacement host's key, locking us into a
// fingerprint-mismatch bootstrap failure on the new mini.
// Outwardly-visible state tied to the discarded host (Status.Ready,
// Status.Phase, Spec.ProviderID, Status.Addresses, shared.ProvisionedCondition)
// is reset to its pre-adoption shape so CAPI and operators don't
// momentarily see a stale "Ready" Machine pointing at a server we no
// longer control.
//
// Order matters: at the maxAttempts threshold the release branch must
// win even if the reboot was never attempted (e.g., rebootAfter > 0
// but RebootServer kept failing). The switch is evaluated top-down so
// release is listed first.
//
// Either tier failing to call out to Scaleway (transient API error,
// 5xx) is non-fatal — the machine stays in the BootstrapFailed
// condition and the next reconcile retries the same tier on the next
// attempt count.
func handleBootstrapFailure(
	ctx context.Context,
	machine *infrav1.ScalewayAppleSiliconMachine,
	err error,
	client bootstrapRecoveryClient,
	secrets bootstrapSecretCleaner,
	recorder record.EventRecorder,
	logger logr.Logger,
	rebootAfter int32,
	maxAttempts int32,
	poolPrefix string,
) ctrl.Result {
	machine.Status.BootstrapAttempts++
	attempts := machine.Status.BootstrapAttempts

	conditions.MarkFalse(machine, BootstrappedCondition, "BootstrapFailed",
		clusterv1.ConditionSeverityWarning, "%v", err)
	recorder.Eventf(machine, corev1.EventTypeWarning, "BootstrapFailed",
		"%v (attempt %d, will retry)", err, attempts)

	hostAdoptable := machine.Status.ServerID != "" && poolPrefix != ""
	switch {
	case maxAttempts > 0 && attempts >= maxAttempts && hostAdoptable:
		if releaseErr := releaseHostToPool(ctx, client, recorder, machine, poolPrefix); releaseErr != nil {
			logger.Error(releaseErr, "release-to-pool after bootstrap exhaustion failed; will retry")
			recorder.Eventf(machine, corev1.EventTypeWarning, "ReleaseFailed",
				"Scaleway ReleaseToPool after %d bootstrap failures: %v (will retry)",
				attempts, releaseErr)
			return ctrl.Result{RequeueAfter: 60 * time.Second}
		}
		releasedID := machine.Status.ServerID
		// Wipe the per-machine bootstrap Secret. The host fingerprint
		// stored there is TOFU-pinned to the released mini's SSH key
		// and would silently reject the replacement host's key on
		// next bootstrap; nothing else in the Secret (sudo password,
		// SSH username) survives meaningfully across hosts either.
		if cleanErr := secrets.DeleteMachineBootstrap(ctx, machine.Name); cleanErr != nil {
			// Non-fatal: surface the error and continue. The next
			// adopt will overwrite the credentials, and the
			// fingerprint guard tolerates an empty pin (TOFU
			// captures fresh on first SSH). Failing the release here
			// would leave the host already returned to Scaleway with
			// no way to roll back.
			logger.Error(cleanErr, "delete per-machine bootstrap Secret on release; next adopt will recreate it")
			recorder.Eventf(machine, corev1.EventTypeWarning, "BootstrapSecretDeleteFailed",
				"delete per-machine bootstrap Secret after release: %v (next adopt will overwrite)",
				cleanErr)
		}
		recorder.Eventf(machine, corev1.EventTypeNormal, "BootstrapExhausted",
			"Released Scaleway server %s after %d bootstrap failures; will claim a fresh host from the pool",
			releasedID, attempts)
		machine.Status.ServerID = ""
		machine.Status.BootstrapAttempts = 0
		machine.Status.BootstrapRebootIssued = false
		machine.Status.Ready = false
		machine.Status.Addresses = nil
		machine.Status.Phase = "Pending"
		machine.Spec.ProviderID = nil
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "HostReleased",
			clusterv1.ConditionSeverityWarning,
			"released Scaleway server %s after %d bootstrap failures; awaiting fresh adopt",
			releasedID, attempts)
	case rebootAfter > 0 && attempts >= rebootAfter && !machine.Status.BootstrapRebootIssued && machine.Status.ServerID != "":
		if rebootErr := client.RebootServer(ctx, machine.Status.ServerID, machine.Spec.Zone); rebootErr != nil {
			logger.Error(rebootErr, "reboot for bootstrap recovery failed; will retry on next attempt")
			recorder.Eventf(machine, corev1.EventTypeWarning, "RebootForRecoveryFailed",
				"Scaleway RebootServer for %s after %d bootstrap failures: %v (will retry)",
				machine.Status.ServerID, attempts, rebootErr)
		} else {
			machine.Status.BootstrapRebootIssued = true
			recorder.Eventf(machine, corev1.EventTypeNormal, "RebootingForRecovery",
				"Rebooting %s after %d bootstrap failures to clear volatile host state",
				machine.Status.ServerID, attempts)
		}
	}

	return ctrl.Result{RequeueAfter: 60 * time.Second}
}

// adoptPoolPrefix resolves the pool prefix for a CR: its own spec
// first, the operator-global default when the spec is empty. Every
// caller goes through this rather than reading Spec.AdoptPoolPrefix
// directly, so a CR cloned from a MachineTemplate that never received
// the field still adopts into, and releases back to, the right pool.
func (r *ScalewayAppleSiliconMachineReconciler) adoptPoolPrefix(
	machine *infrav1.ScalewayAppleSiliconMachine,
) string {
	if machine.Spec.AdoptPoolPrefix != "" {
		return machine.Spec.AdoptPoolPrefix
	}
	return r.DefaultAdoptPoolPrefix
}

// acquireServer claims a pre-ordered host from the pool. Returns
// (nil, requeue, nil) on `ErrNoAvailableHost` — that's a transient
// "wait for operator pre-order" state, not a failure; surfaces a
// `NoAvailableHost` event so the operator sees the queue. On any
// other error the caller requeues and the condition message carries
// the detail.
func (r *ScalewayAppleSiliconMachineReconciler) acquireServer(
	ctx context.Context,
	machine *infrav1.ScalewayAppleSiliconMachine,
) (*scaleway.Server, time.Duration, error) {
	poolPrefix := r.adoptPoolPrefix(machine)
	// An unprefixed scan would match every server in the project,
	// including hosts already claimed by other fleets, so refuse
	// rather than adopt something arbitrary. Requeue: the operator
	// fixes this by setting `--default-adopt-pool-prefix` or the
	// field on the template, and neither needs the CR recreated.
	if poolPrefix == "" {
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAdoptPoolPrefix",
			clusterv1.ConditionSeverityError,
			"no adoptPoolPrefix on the CR and no operator default; cannot scan the pool")
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "NoAdoptPoolPrefix",
			"No adoptPoolPrefix on the CR and no --default-adopt-pool-prefix on the operator; refusing to scan for an unprefixed host")
		return nil, 5 * time.Minute, nil
	}
	machine.Status.Phase = "Adopting"
	r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Adopting",
		"Searching pool %q for an unclaimed %s Mac mini in zone %s",
		poolPrefix, machine.Spec.Type, machine.Spec.Zone)
	srv, err := r.ScalewayClient.AdoptFromPool(
		ctx,
		machine.Name,
		machine.Spec.Zone,
		machine.Spec.Type,
		machine.Spec.OS,
		poolPrefix,
	)
	// A versioned pin is a configuration error, not absent capacity.
	// Reporting it as NoAvailableHost would send an operator to
	// pre-order hosts that could never match. Requeue slowly: nothing
	// changes on its own.
	//
	// The likeliest cause is not a mis-edited fleet but a Machine that
	// predates the switch to families: its spec carries a versioned pin
	// that the MachineTemplate no longer has, so editing the fleet
	// changes nothing for it. Under OnDelete nothing replaces it
	// either, so the message names deleting the Machine first —
	// MachineSet re-clones from the current template. This is reachable
	// without any operator action: handleBootstrapFailure releases the
	// host at exhaustion and leaves the Machine hostless, so a legacy
	// Machine sheds its host and lands here on the next reconcile.
	if errors.Is(err, scaleway.ErrOSPinNotFamily) {
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "InvalidOSPin",
			clusterv1.ConditionSeverityError, "%v", err)
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "InvalidOSPin",
			"This Machine's os %q pins a specific image; adoption requires a release family. "+
				"If the fleet's MachineTemplate already pins a family, this Machine predates it: "+
				"delete the Machine so its MachineSet re-clones from the template, or patch its spec.os. %v",
			machine.Spec.OS, err)
		return nil, 5 * time.Minute, nil
	}
	if errors.Is(err, scaleway.ErrNoAvailableHost) {
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAvailableHost",
			clusterv1.ConditionSeverityWarning,
			"no server with prefix %q matching %s/%s/%s in zone %s; pre-order more capacity",
			poolPrefix, machine.Spec.Type, machine.Spec.OS,
			"ready", machine.Spec.Zone)
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "NoAvailableHost",
			"No pre-ordered Mac mini matching pool=%q type=%s os=%s zone=%s; waiting for operator to pre-order more capacity",
			poolPrefix, machine.Spec.Type, machine.Spec.OS, machine.Spec.Zone)
		return nil, 60 * time.Second, nil
	}
	if err != nil {
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "ScalewayAdoptFailed",
			clusterv1.ConditionSeverityError, "%v", err)
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "ProvisioningFailed",
			"Scaleway AdoptFromPool: %v", err)
		return nil, 30 * time.Second, err
	}
	r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Adopted",
		"Claimed Mac mini %s from pool %q (renamed to %s)",
		srv.ID, poolPrefix, machine.Name)
	return srv, 0, nil
}

// nodeMissingAfterBootstrap re-checks this Machine's Node; see the shared
// helper for why a missing one is drift rather than a failure.
func (r *ScalewayAppleSiliconMachineReconciler) nodeMissingAfterBootstrap(
	ctx context.Context,
	machine *infrav1.ScalewayAppleSiliconMachine,
) (bool, error) {
	return nodeMissingAfterBootstrap(ctx, r.Client, machine, machine.Name)
}

func machineIP(m *infrav1.ScalewayAppleSiliconMachine) string {
	for _, a := range m.Status.Addresses {
		if a.Type == clusterv1.MachineExternalIP {
			return a.Address
		}
	}
	return ""
}

// providerIDOf returns the machine's providerID
// (scw-applesilicon://<zone>/<id>), set once the server is ordered or
// adopted. Empty until then — bootstrap renders no --provider-id flag
// and a later reconcile re-renders the plist once it's known.
// ensureVMCachePN resolves the per-host VLAN of the runner-cache
// Private Network attachment, attaching the server first if needed.
// Returns 0 (and no error) when the PN data plane is not configured
// or the machine has no Scaleway server yet.
func (r *ScalewayAppleSiliconMachineReconciler) ensureVMCachePN(ctx context.Context, machine *infrav1.ScalewayAppleSiliconMachine) (uint32, error) {
	if r.VMCachePNName == "" || r.FleetConfig.VMCachePNCIDR == "" || machine.Status.ServerID == "" {
		return 0, nil
	}
	pnID, err := r.VPC.EnsurePrivateNetworkByName(ctx, scaleway.RegionFromZoneString(machine.Spec.Zone), r.VMCachePNName, r.FleetConfig.VMCachePNCIDR)
	if err != nil {
		return 0, err
	}
	return r.ScalewayClient.EnsureServerPrivateNetwork(ctx, machine.Status.ServerID, machine.Spec.Zone, pnID)
}

func providerIDOf(m *infrav1.ScalewayAppleSiliconMachine) string {
	if m.Spec.ProviderID == nil {
		return ""
	}
	return *m.Spec.ProviderID
}

// hostCPUFor / hostMemoryMBFor / maxPodsFor / runnerCacheVolumeGiBFor
// select the per-Machine override when set on the spec, falling back
// to the operator-global flag default. Lets a single operator instance
// manage heterogeneous fleets (e.g. xcresult-fleet on M2-M and
// runners-fleet on M2-L, or M2-L and M4-XL side by side in ONE runners
// fleet) without spawning a deployment per SKU or under-advertising on
// the larger one.
//
// All four resolve through hostConfig, so they are reflected in the
// per-Machine host-config hash and drift the host when they change.
func hostCPUFor(m *infrav1.ScalewayAppleSiliconMachine, fallback int) int {
	if m.Spec.HostCPU > 0 {
		return m.Spec.HostCPU
	}
	return fallback
}

func hostMemoryMBFor(m *infrav1.ScalewayAppleSiliconMachine, fallback int) int {
	if m.Spec.HostMemoryMB > 0 {
		return m.Spec.HostMemoryMB
	}
	return fallback
}

func maxPodsFor(m *infrav1.ScalewayAppleSiliconMachine, fallback int) int {
	if m.Spec.MaxPods > 0 {
		return m.Spec.MaxPods
	}
	return fallback
}

// guestCapacityFor resolves how many Tart guests this host is expected
// to run concurrently, never returning less than 1 — a host that runs
// no guests is not a thing this operator provisions, and a 0 would
// propagate into the relay-port range and the goldens floor as "none".
func guestCapacityFor(m *infrav1.ScalewayAppleSiliconMachine, fallback int) int {
	capacity := fallback
	if m.Spec.GuestCapacity > 0 {
		capacity = m.Spec.GuestCapacity
	}
	if capacity < 1 {
		capacity = 1
	}
	return capacity
}

// runnerCacheVolumeGiBFor resolves on PRESENCE, not on truthiness, so
// an explicit 0 means "cache volumes off on this host" rather than
// collapsing into "unset" and silently inheriting the fleet default.
// That is why the spec field is a pointer while its sizing siblings
// are not: 0 is a value here, and nonsense for them.
//
// A negative value is still treated as unset — it cannot be an intent,
// and degrading to the fleet default beats pushing a quota that would
// fail the diskutil call at bootstrap.
func runnerCacheVolumeGiBFor(m *infrav1.ScalewayAppleSiliconMachine, fallback int) int {
	if gib := m.Spec.RunnerCacheVolumeGiB; gib != nil && *gib >= 0 {
		return *gib
	}
	return fallback
}

// machineNodeLabels returns the labels tart-kubelet will stamp on
// the Node it registers. v1 sets only `tuist.dev/fleet=<FleetName>`
// — the fleet membership label that workloads pin to via
// nodeSelector. Adding more labels (e.g. instance-type for multi-
// profile pre-warming) is a one-line change here; bootstrap +
// tart-kubelet already accept arbitrary maps.
func machineNodeLabels(m *infrav1.ScalewayAppleSiliconMachine) map[string]string {
	if m.Spec.FleetName == "" {
		return nil
	}
	return map[string]string{"tuist.dev/fleet": m.Spec.FleetName}
}

func (r *ScalewayAppleSiliconMachineReconciler) SetupWithManager(mgr ctrl.Manager) error {
	concurrency := r.MaxConcurrentReconciles
	if concurrency <= 0 {
		concurrency = 1
	}
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.ScalewayAppleSiliconMachine{}).
		WithOptions(controller.Options{MaxConcurrentReconciles: concurrency}).
		// Wake up on parent CAPI Machine events so a change in the
		// Machine (e.g. Cluster.InfrastructureReady flipping, the
		// bootstrap data secret landing, the parent being deleted)
		// reconciles the infra Machine immediately instead of
		// waiting for our own resync window.
		Watches(
			&clusterv1.Machine{},
			handler.EnqueueRequestsFromMapFunc(scalewayMachineForCAPIMachine),
		).
		Complete(r)
}

// scalewayMachineForCAPIMachine maps a CAPI Machine event to a
// reconcile request for the ScalewayAppleSiliconMachine it owns
// (if any). Machines with `infrastructureRef.Kind` other than ours
// are silently ignored — the same controller may run alongside
// other infrastructure providers.
func scalewayMachineForCAPIMachine(_ context.Context, o client.Object) []reconcile.Request {
	m, ok := o.(*clusterv1.Machine)
	if !ok {
		return nil
	}
	if m.Spec.InfrastructureRef.Kind != "ScalewayAppleSiliconMachine" {
		return nil
	}
	return []reconcile.Request{{
		NamespacedName: types.NamespacedName{
			Namespace: m.Spec.InfrastructureRef.Namespace,
			Name:      m.Spec.InfrastructureRef.Name,
		},
	}}
}
