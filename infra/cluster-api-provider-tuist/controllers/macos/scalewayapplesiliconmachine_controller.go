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

	// DashboardVNCRelayPort is the stable host-side port tart-kubelet
	// advertises for dashboard VNC sessions through the per-Mac Tailscale
	// egress Service.
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

	// TartKubeletBinary is the darwin/arm64 binary baked into the
	// operator's own image. Read once at operator startup, uploaded to
	// each Mac mini over SSH at provision time and on every drift-
	// detected rolling update.
	TartKubeletBinary []byte

	// TartKubeletBinarySHA is the SHA-256 of TartKubeletBinary. Used
	// as the version stamp on each ScalewayAppleSiliconMachine: when
	// status.tartKubeletBinarySHA != this value, the reconciler
	// re-uploads + reloads launchd.
	TartKubeletBinarySHA string

	// HostConfigHash is the fleet-wide canonical hash of every host
	// config the operator pushes (bootstrap.HostConfigHash over the
	// rendered install scripts + embedded binaries). It's the version
	// stamp that drives the host-config drift loop: when
	// status.hostConfigHash != this value the reconciler re-pushes the
	// host config. Broader than TartKubeletBinarySHA, which only catches
	// a tart-kubelet binary change — this also catches a script tweak or
	// a fleet-config (CIDR/tags/accept-routes) change.
	HostConfigHash string

	// TartTarball is the gzipped tar of the upstream `tart.app` bundle
	// pinned in the operator's Dockerfile and read at startup. Uploaded
	// to each Mac mini over SSH at first bootstrap. We do not run a
	// drift loop on the Tart version: a Mac mini already running VMs
	// can't safely have its hypervisor swapped out from under them, so
	// upgrading Tart fleet-wide goes through Machine replacement (the
	// new Mac mini gets the operator-image-pinned Tart on bootstrap).
	TartTarball []byte

	// TailscaleBinaries is the gzipped tarball of darwin/arm64
	// `tailscale` + `tailscaled` cross-built from upstream source at
	// the operator-image-pinned tag (TAILSCALE_VERSION in the
	// Dockerfile). Same drift policy as TartTarball: version bumps
	// roll via operator-image replacement, not in-place updates of
	// running hosts (the running tailnet connection doesn't tolerate
	// a daemon swap mid-flight). Empty disables the Tailscale step.
	TailscaleBinaries []byte

	// NodeExporterBinary is the darwin/arm64 node_exporter binary,
	// cross-compiled in the operator image. Installed on each Mac
	// mini at bootstrap and supervised by launchd; scraped over the
	// tailnet at <node-ip>:9100. Empty disables the host-metrics
	// step (paired with TailscaleBinaries — node_exporter without
	// Tailscale would bind to a public interface, which is the kind
	// of mistake we don't want a chart-level toggle to make easy).
	NodeExporterBinary []byte

	// TailscaleTags are the Tailscale ACL tags every Mac mini in
	// the fleet advertises at `tailscale up` time (e.g.
	// `["tag:tuist-macmini"]`). Bound to the operator-namespace
	// auth key — see acls.json's tagOwners block. Empty means the
	// minis use whatever default tag the auth key carries.
	TailscaleTags []string

	// TailscaleAcceptRoutes makes every Mac mini run `tailscale up
	// --accept-routes`, installing the subnet routes the cluster's
	// Connector advertises (the Service CIDR) so Tart runner VMs can
	// reach the in-cluster Kura runner-cache Service. See
	// bootstrap.Config.TailscaleAcceptRoutes for the single-
	// advertiser caveat.
	TailscaleAcceptRoutes bool

	// VMKuraEgressCIDR / VMClusterDNSIP parameterize the VM egress
	// firewall's runner-cache carve-out (Kura ports on the Service
	// CIDR + cluster DNS). Empty leaves the firewall as a pure
	// blocklist. See the bootstrap.Config fields of the same names.
	VMKuraEgressCIDR string
	VMClusterDNSIP   string

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
	VMCachePNCIDR string

	// VPC find-or-creates the runner-cache Private Network the Mac
	// fleet shares with the Elastic Metal cache node, resolving
	// VMCachePNName to an ID. Same shared client as the EM reconciler,
	// so the two fleets land on one PN per env.
	VPC *scaleway.VPCClient

	// TartKubelet host advertising — passed into bootstrap which bakes
	// them into the launchd plist on each Mac mini.
	TartKubeletHostCPU           int
	TartKubeletHostMemoryMB      int
	TartKubeletMaxPods           int
	TartKubeletRunnerCacheRoot   string
	TartKubeletHostKuraVersion   string
	TartKubeletEMPeerURLTemplate string

	// TartKubeletMaxUpdateAttempts caps how many times the drift loop
	// retries a failing UpdateTartKubelet before transitioning the CR
	// to a terminal Failed state. Without a cap the operator
	// SSH-hammers a wedged host every 60s indefinitely with no
	// terminal-failure surface for ops. Defaulted to 5 attempts in
	// the manager binary; chart can override per env if needed.
	TartKubeletMaxUpdateAttempts int32

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

	// DefaultAdoptPoolPrefix is the pool prefix reconcileDelete falls
	// back to when a CR's Spec.AdoptPoolPrefix is empty. Spec now
	// requires the field (MinLength=1), so this only covers legacy CRs
	// created before that contract existed: without a fallback their
	// delete skips the Scaleway release and strands the host. Empty
	// preserves the skip behavior (no pool prefix to release into).
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
		vncRelayPort := r.dashboardVNCRelayPort()

		fingerprint, err := bootstrap.Run(ctx, bootstrap.Config{
			IP:                    ip,
			SSHUser:               bootstrapCreds.SSHUsername,
			UserPassword:          bootstrapCreds.SudoPassword,
			SSHPrivateKey:         sshKey,
			NodeName:              machine.Name,
			ProviderID:            providerIDOf(machine),
			Kubeconfig:            kubeconfigYAML,
			TartKubeletBinary:     r.TartKubeletBinary,
			TartTarball:           r.TartTarball,
			TailscaleBinaries:     r.TailscaleBinaries,
			TailscaleAuthKey:      tailscaleAuthKey,
			TailscaleTags:         r.TailscaleTags,
			TailscaleAcceptRoutes: r.TailscaleAcceptRoutes,
			VMKuraEgressCIDR:      r.VMKuraEgressCIDR,
			VMClusterDNSIP:        r.VMClusterDNSIP,
			VMCachePNCIDR:         r.VMCachePNCIDR,
			VMCachePNVLAN:         vmCachePNVLAN,
			NodeExporterBinary:    r.NodeExporterBinary,
			HostCPU:               hostCPUFor(machine, r.TartKubeletHostCPU),
			HostMemoryMB:          hostMemoryMBFor(machine, r.TartKubeletHostMemoryMB),
			MaxPods:               r.TartKubeletMaxPods,
			VNCRelayHost:          vncRelayHost,
			VNCRelayPort:          vncRelayPort,
			NodeLabels:            machineNodeLabels(machine),
			RunnerCacheRoot:       r.TartKubeletRunnerCacheRoot,
			HostKuraVersion:       r.TartKubeletHostKuraVersion,
			EMPeerURLTemplate:     r.TartKubeletEMPeerURLTemplate,
			KnownHostFingerprint:  bootstrapCreds.HostFingerprint,
			GHActionsRunner:       ghRunner,
		})
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
			return handleBootstrapFailure(ctx, machine, err, r.ScalewayClient, r.CredentialsManager, r.Recorder, logger, r.BootstrapRebootAfter, r.BootstrapMaxAttempts), nil
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
	configDrift := hostConfigDrift(r.HostConfigHash, machine.Status.HostConfigHash)
	// Once a CR enters the terminal-failed state (FailureReason set
	// and FailureMessage describes the underlying error) we stop
	// firing the drift loop. CAPI core takes over: surfaces the
	// failure on the parent Machine and refuses to drive replacement
	// without operator action. Recovery: clear FailureReason +
	// reset TartKubeletUpdateAttempts to resume the loop.
	terminalFailure := machine.Status.FailureReason != nil
	if configDrift && !terminalFailure {
		ip := machineIP(machine)
		if ip == "" {
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		identity, err := r.CredentialsManager.EnsureNodeIdentity(ctx, machine.Name, "")
		if err != nil {
			recordUpdateFailure(machine, fmt.Errorf("ensure node identity: %w", err), r.TartKubeletMaxUpdateAttempts, logger, r.Recorder)
			if machine.Status.FailureReason != nil {
				return ctrl.Result{}, nil
			}
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		kubeconfigYAML, err := r.Kubeconfig.Render(ctx, machine.Name, identity.Token, identity.CA)
		if err != nil {
			recordUpdateFailure(machine, fmt.Errorf("render kubeconfig: %w", err), r.TartKubeletMaxUpdateAttempts, logger, r.Recorder)
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
			recordUpdateFailure(machine, fmt.Errorf("get tailscale auth key: %w", err), r.TartKubeletMaxUpdateAttempts, logger, r.Recorder)
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
		vncRelayPort := r.dashboardVNCRelayPort()

		fingerprint, err := bootstrap.UpdateTartKubelet(ctx, bootstrap.Config{
			IP:                ip,
			SSHUser:           bootstrapCreds.SSHUsername,
			SSHPrivateKey:     sshKey,
			NodeName:          machine.Name,
			ProviderID:        providerIDOf(machine),
			Kubeconfig:        kubeconfigYAML,
			TartKubeletBinary: r.TartKubeletBinary,
			TailscaleBinaries: r.TailscaleBinaries,
			TailscaleAuthKey:  tailscaleAuthKey,
			// Tailscale + firewall config rides the drift loop too —
			// UpdateTartKubelet re-runs installTailscale and
			// installVMEgressFirewall, so an accept-routes or
			// carve-out values change lands on existing minis with
			// the next operator-image roll instead of waiting for
			// re-provisioning.
			TailscaleAcceptRoutes: r.TailscaleAcceptRoutes,
			VMKuraEgressCIDR:      r.VMKuraEgressCIDR,
			VMClusterDNSIP:        r.VMClusterDNSIP,
			VMCachePNCIDR:         r.VMCachePNCIDR,
			VMCachePNVLAN:         vmCachePNVLAN,
			// node_exporter is re-installed on every drift-loop run,
			// not just on first bootstrap, so a chart-driven binary
			// bump (NODE_EXPORTER_VERSION ARG in the operator
			// Dockerfile) lands on running minis the next time the
			// tart-kubelet binary drifts. Forgetting this here made
			// node_exporter silently skip on every drift update —
			// installNodeExporter short-circuits when its binary is
			// empty.
			NodeExporterBinary: r.NodeExporterBinary,
			HostCPU:            hostCPUFor(machine, r.TartKubeletHostCPU),
			HostMemoryMB:       hostMemoryMBFor(machine, r.TartKubeletHostMemoryMB),
			MaxPods:            r.TartKubeletMaxPods,
			VNCRelayHost:       vncRelayHost,
			VNCRelayPort:       vncRelayPort,
			NodeLabels:         machineNodeLabels(machine),
			RunnerCacheRoot:    r.TartKubeletRunnerCacheRoot,
			HostKuraVersion:    r.TartKubeletHostKuraVersion,
			EMPeerURLTemplate:  r.TartKubeletEMPeerURLTemplate,
			// Builder hosts must keep `--disable-vm-gc` across binary
			// rolls. This path re-renders the plist but doesn't re-resolve
			// GHActionsRunner (which renderLaunchdPlist otherwise keys the
			// flag off), so carry the builder signal explicitly — without
			// it the roll strips the flag and the orphan-VM GC reaps the
			// in-flight image-bake VM mid-`tart push`.
			DisableVMGC:          machine.Spec.GHActionsRunner != nil,
			KnownHostFingerprint: bootstrapCreds.HostFingerprint,
		})
		if fingerprint != "" && fingerprint != bootstrapCreds.HostFingerprint {
			if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, fingerprint); perr != nil {
				logger.Error(perr, "persist host fingerprint on update; will retry")
			}
		}
		if err != nil {
			recordUpdateFailure(machine, fmt.Errorf("tart-kubelet update: %w", err), r.TartKubeletMaxUpdateAttempts, logger, r.Recorder)
			if machine.Status.FailureReason != nil {
				return ctrl.Result{}, nil
			}
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		}
		machine.Status.TartKubeletBinarySHA = r.TartKubeletBinarySHA
		machine.Status.HostConfigHash = r.HostConfigHash
		machine.Status.TartKubeletUpdateAttempts = 0
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, "AgentRolled",
			"Rolled tart-kubelet to %s", r.TartKubeletBinarySHA)
		logger.Info("rolled new tart-kubelet", "host", ip, "sha", r.TartKubeletBinarySHA,
			"hostConfigHash", r.HostConfigHash)
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
	machine.Status.Phase = "Ready"
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
	// Legacy CRs predating the required-AdoptPoolPrefix contract may
	// still exist with the field unset (the older chart only
	// rendered `adoptPoolPrefix` when the value was non-empty, so
	// fleets that didn't set it produced bare CRs). For those, fall
	// back to the controller-level DefaultAdoptPoolPrefix so the host
	// still returns to the pool. Only when neither the CR nor the
	// controller default carries a prefix do we skip the Scaleway
	// release (the client rejects an empty prefix to avoid orphaning a
	// host outside the pool namespace), leave the host running, and
	// let the orphan-reclaim sweep or an operator clean it up. Without
	// this fallthrough, deleting a bare legacy CR would loop forever on
	// a precondition error and block fleet teardown.
	if machine.Status.ServerID != "" {
		poolPrefix := machine.Spec.AdoptPoolPrefix
		if poolPrefix == "" {
			poolPrefix = r.DefaultAdoptPoolPrefix
		}
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
			if err := r.ScalewayClient.ReleaseToPool(ctx, machine.Status.ServerID, machine.Spec.Zone, poolPrefix); err != nil {
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

// reconcileTailscaleEgressService maintains one ExternalName Service
// per Mac mini in the egress namespace. The Tailscale K8s operator
// detects the `tailscale.com/tailnet-fqdn` annotation and rewrites
// the Service's externalName to point at a ClusterIP fronting the
// named ProxyGroup; from then on any cluster Pod that resolves the
// Service DNS gets routed through the ProxyGroup's tailnet identity
// to the Mac mini.
//
// Idempotent via CreateOrUpdate: a re-reconcile with no spec change
// is a noop on the apiserver. Empty EgressProxyGroup short-circuits
// the whole thing for OSS/self-hosted clusters.
func (r *ScalewayAppleSiliconMachineReconciler) reconcileTailscaleEgressService(
	ctx context.Context,
	machine *infrav1.ScalewayAppleSiliconMachine,
) error {
	if r.EgressProxyGroup == "" {
		return nil
	}
	if r.EgressMagicDNSSuffix == "" {
		return fmt.Errorf("EgressMagicDNSSuffix empty but EgressProxyGroup=%q set", r.EgressProxyGroup)
	}
	if r.EgressNamespace == "" {
		return fmt.Errorf("EgressNamespace empty but EgressProxyGroup=%q set", r.EgressProxyGroup)
	}

	// FQDN is the tailnet hostname (= machine.Name; see
	// bootstrap.go's `tailscale up --hostname=$NodeName`) suffixed
	// with the tailnet's MagicDNS domain (operator flag, set per
	// env in the chart).
	fqdn := machine.Name + "." + r.EgressMagicDNSSuffix

	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{
		Name:      machine.Name,
		Namespace: r.EgressNamespace,
	}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, svc, func() error {
		if svc.Labels == nil {
			svc.Labels = map[string]string{}
		}
		// Label alloy-metrics' Service-role discovery filters on. The
		// label values stay stable across reconciles so the same
		// Service is reused; only its Spec/annotations get patched.
		svc.Labels["app.kubernetes.io/managed-by"] = "capi-scaleway-applesilicon"
		svc.Labels["app.kubernetes.io/component"] = "macmini-egress"
		svc.Labels["tuist.dev/macmini-egress"] = "true"
		svc.Labels["tuist.dev/macmini-machine"] = machine.Name

		if svc.Annotations == nil {
			svc.Annotations = map[string]string{}
		}
		svc.Annotations["tailscale.com/tailnet-fqdn"] = fqdn
		svc.Annotations["tailscale.com/proxy-group"] = r.EgressProxyGroup

		svc.Spec.Type = corev1.ServiceTypeExternalName
		// On first create, seed externalName with a syntactically
		// valid placeholder. The Tailscale operator rewrites it at
		// admission time to a ClusterIP Service fronting the
		// ProxyGroup; on re-reconcile we don't stamp it back, so the
		// operator's rewrite sticks.
		if svc.Spec.ExternalName == "" {
			svc.Spec.ExternalName = "placeholder." + r.EgressNamespace + ".svc.cluster.local"
		}
		// Two named ports — alloy-metrics filters on port_name to
		// dispatch each to the right scrape job (see
		// infra/helm/k8s-monitoring/values.yaml's
		// collectors.alloy-metrics.extraConfig).
		svc.Spec.Ports = []corev1.ServicePort{
			{Name: "node-exporter", Port: 9100, Protocol: corev1.ProtocolTCP},
			{Name: "tart-kubelet", Port: 8080, Protocol: corev1.ProtocolTCP},
			{Name: "vnc-relay", Port: DashboardVNCRelayPort, Protocol: corev1.ProtocolTCP},
		}
		return nil
	})
	return err
}

func (r *ScalewayAppleSiliconMachineReconciler) dashboardVNCRelayHost(machineName string) string {
	if r.EgressProxyGroup == "" || r.EgressNamespace == "" {
		return ""
	}
	return fmt.Sprintf("%s.%s.svc.cluster.local", machineName, r.EgressNamespace)
}

func (r *ScalewayAppleSiliconMachineReconciler) dashboardVNCRelayPort() int {
	if r.EgressProxyGroup == "" || r.EgressNamespace == "" {
		return 0
	}
	return DashboardVNCRelayPort
}

// hostConfigDrift reports whether the host config the operator would
// push (operatorHash) differs from what the Machine last recorded
// (machineHash). An empty operatorHash (hash not computed) never drifts.
// An empty machineHash on a non-empty operatorHash drifts once — the
// migration case for machines provisioned before the hash existed.
func hostConfigDrift(operatorHash, machineHash string) bool {
	return operatorHash != "" && machineHash != operatorHash
}

// recordUpdateFailure increments the drift-loop retry counter and,
// once it crosses maxAttempts, flips the CR into a terminal Failed
// state. The counter is reset on successful UpdateTartKubelet. We
// don't try to be clever about which step in the loop failed; from
// the CR's perspective, any failure that prevents the kubeconfig
// landing on the host counts the same. Recovery is operator-driven:
// `kubectl patch` to clear status.failureReason + zero
// status.tartKubeletUpdateAttempts and the loop resumes.
func recordUpdateFailure(machine *infrav1.ScalewayAppleSiliconMachine, err error, maxAttempts int32, logger logr.Logger, recorder record.EventRecorder) {
	machine.Status.TartKubeletUpdateAttempts++
	logger.Error(err, "tart-kubelet update step failed",
		"attempt", machine.Status.TartKubeletUpdateAttempts,
		"max", maxAttempts)
	if maxAttempts > 0 && machine.Status.TartKubeletUpdateAttempts >= maxAttempts {
		reason := "TartKubeletUpdateExceededRetries"
		msg := fmt.Sprintf("tart-kubelet update failed %d times: %v",
			machine.Status.TartKubeletUpdateAttempts, err)
		machine.Status.FailureReason = &reason
		machine.Status.FailureMessage = &msg
		machine.Status.Phase = "Failed"
		recorder.Eventf(machine, corev1.EventTypeWarning, reason, "%s", msg)
		logger.Error(err, "tart-kubelet update permanently failed; CR transitioned to Failed",
			"attempts", machine.Status.TartKubeletUpdateAttempts)
		return
	}
	recorder.Eventf(machine, corev1.EventTypeWarning, "AgentRollFailed",
		"tart-kubelet update attempt %d/%d: %v",
		machine.Status.TartKubeletUpdateAttempts, maxAttempts, err)
}

// bootstrapRecoveryClient is the narrow Scaleway surface
// handleBootstrapFailure needs. Tests can satisfy it with a tiny
// in-memory stub; the production *scaleway.Client satisfies it
// natively.
type bootstrapRecoveryClient interface {
	RebootServer(ctx context.Context, id, zone string) error
	ReleaseToPool(ctx context.Context, id, zone, poolPrefix string) error
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
) ctrl.Result {
	machine.Status.BootstrapAttempts++
	attempts := machine.Status.BootstrapAttempts

	conditions.MarkFalse(machine, BootstrappedCondition, "BootstrapFailed",
		clusterv1.ConditionSeverityWarning, "%v", err)
	recorder.Eventf(machine, corev1.EventTypeWarning, "BootstrapFailed",
		"%v (attempt %d, will retry)", err, attempts)

	hostAdoptable := machine.Status.ServerID != "" && machine.Spec.AdoptPoolPrefix != ""
	switch {
	case maxAttempts > 0 && attempts >= maxAttempts && hostAdoptable:
		if releaseErr := client.ReleaseToPool(ctx, machine.Status.ServerID, machine.Spec.Zone, machine.Spec.AdoptPoolPrefix); releaseErr != nil {
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
	machine.Status.Phase = "Adopting"
	r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Adopting",
		"Searching pool %q for an unclaimed %s Mac mini in zone %s",
		machine.Spec.AdoptPoolPrefix, machine.Spec.Type, machine.Spec.Zone)
	srv, err := r.ScalewayClient.AdoptFromPool(
		ctx,
		machine.Name,
		machine.Spec.Zone,
		machine.Spec.Type,
		machine.Spec.OS,
		machine.Spec.AdoptPoolPrefix,
	)
	if errors.Is(err, scaleway.ErrNoAvailableHost) {
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAvailableHost",
			clusterv1.ConditionSeverityWarning,
			"no server with prefix %q matching %s/%s/%s in zone %s; pre-order more capacity",
			machine.Spec.AdoptPoolPrefix, machine.Spec.Type, machine.Spec.OS,
			"ready", machine.Spec.Zone)
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "NoAvailableHost",
			"No pre-ordered Mac mini matching pool=%q type=%s os=%s zone=%s; waiting for operator to pre-order more capacity",
			machine.Spec.AdoptPoolPrefix, machine.Spec.Type, machine.Spec.OS, machine.Spec.Zone)
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
		srv.ID, machine.Spec.AdoptPoolPrefix, machine.Name)
	return srv, 0, nil
}

// nodeBootstrapGrace is how long after BootstrappedCondition flips to
// True we tolerate a missing Node before deciding it's drift. tart-
// kubelet's launchd job typically registers within ~30s of bootstrap
// completion; 2 min absorbs apiserver + watch propagation delays
// without giving up so long that the deploy waits multiple reconcile
// cycles to detect the drift.
const nodeBootstrapGrace = 2 * time.Minute

// nodeMissingAfterBootstrap returns true when the operator previously
// bootstrapped this Machine (BootstrappedCondition=True for at least
// nodeBootstrapGrace) but the Node it registered no longer exists.
// The grace window prevents the initial post-bootstrap requeue from
// looking like drift while tart-kubelet's first registration is still
// propagating.
func (r *ScalewayAppleSiliconMachineReconciler) nodeMissingAfterBootstrap(
	ctx context.Context,
	machine *infrav1.ScalewayAppleSiliconMachine,
) (bool, error) {
	cond := conditions.Get(machine, BootstrappedCondition)
	if cond == nil || cond.Status != corev1.ConditionTrue {
		return false, nil
	}
	if time.Since(cond.LastTransitionTime.Time) < nodeBootstrapGrace {
		return false, nil
	}
	node := &corev1.Node{}
	err := r.Get(ctx, client.ObjectKey{Name: machine.Name}, node)
	if apierrors.IsNotFound(err) {
		return true, nil
	}
	if err != nil {
		return false, err
	}
	return false, nil
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
	if r.VMCachePNName == "" || r.VMCachePNCIDR == "" || machine.Status.ServerID == "" {
		return 0, nil
	}
	pnID, err := r.VPC.EnsurePrivateNetworkByName(ctx, scaleway.RegionFromZoneString(machine.Spec.Zone), r.VMCachePNName, r.VMCachePNCIDR)
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

// hostCPUFor / hostMemoryMBFor select the per-Machine capacity
// override when set on the spec, falling back to the operator-
// global flag default. Lets a single operator instance manage
// heterogeneous fleets (e.g. xcresult-fleet on M2-M and
// runners-fleet on M2-L) without spawning a deployment per fleet
// or under-advertising on the larger SKU.
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
