package macos

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"slices"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/uuid"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/kubeconfig"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// RackHostLeaseFinalizer keeps a lease until this cluster holds nothing on its
// host: no Node, no identity, no key.
const RackHostLeaseFinalizer = "rackhostlease.infrastructure.cluster.x-k8s.io/finalizer"

// RackHostLeaseReconciler is the borrowing side of a rack host another env
// lends this cluster (rack_lend.go is the lending side). It runs the host's
// runner runtime exactly like the drift loop runs a rented mini's: this
// operator's tart-kubelet, fleet config, tailnet tags, cache-volume server and
// node identity, rolled out by this env's deploys. What it never does is what
// the site's owner does: power, OS updates, bootstrapping a reinstalled host,
// or recovering one that stopped answering.
//
// It dials with a key of its own, which the lender authorizes on the host, and
// every push claims the host's runtime owner marker, which the lender moves to
// this env only once it stopped pushing itself.
type RackHostLeaseReconciler struct {
	client.Client
	Scheme             *runtime.Scheme
	Recorder           record.EventRecorder
	CredentialsManager *credentials.Manager
	Kubeconfig         *kubeconfig.Builder

	// Env is this operator's environment, the runtime owner its pushes claim.
	Env string
	// FleetName names the borrowed hosts' Nodes (`<fleet>-<host>`) and is their
	// `tuist.dev/fleet` label, which this env's rack pools select.
	FleetName string
	// Hosts are the RackHosts this env runs when they are lent to it. A lease
	// for any other host is refused.
	Hosts []string

	// The same fleet config, Tart releases and rack overlay this operator
	// pushes to every macOS host it runs.
	FleetConfig          bootstrap.Config
	TartReleases         map[string][]byte
	VMCacheGatewayCIDRs  []string
	ImageMirrors         []string
	DefaultGuestCapacity int

	TartKubeletBinarySHA          string
	TartKubeletMaxUpdateAttempts  int32
	TartKubeletTerminalRetryAfter time.Duration

	EgressNamespace      string
	EgressProxyGroup     string
	EgressMagicDNSSuffix string

	// pushRuntime pushes the runtime; nil is bootstrap.UpdateTartKubelet.
	pushRuntime func(ctx context.Context, cfg bootstrap.Config) (string, error)
	// probeHost checks the host can be pushed to; nil is bootstrap.Probe.
	probeHost func(ctx context.Context, cfg bootstrap.Config) (string, error)
}

const leaseRequeue = 5 * time.Minute

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackhostleases,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackhostleases/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackhostleases/finalizers,verbs=update

func (r *RackHostLeaseReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	lease := &infrav1.RackHostLease{}
	if getErr := r.Get(ctx, req.NamespacedName, lease); getErr != nil {
		return ctrl.Result{}, client.IgnoreNotFound(getErr)
	}
	patchHelper, err := patch.NewHelper(lease, r.Client)
	if err != nil {
		return ctrl.Result{}, err
	}
	defer func() {
		if patchErr := patchHelper.Patch(ctx, lease); patchErr != nil && err == nil {
			err = patchErr
		}
	}()

	node := r.nodeName(lease)
	lease.Status.Node = node

	if !lease.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, lease, node)
	}
	if !controllerutil.ContainsFinalizer(lease, RackHostLeaseFinalizer) {
		controllerutil.AddFinalizer(lease, RackHostLeaseFinalizer)
	}

	declared := slices.Contains(r.Hosts, lease.Name)
	if !declared || lease.Spec.Phase == infrav1.LeaseReturning {
		return r.release(ctx, lease, node, declared)
	}

	privateKey, publicKey, err := r.CredentialsManager.EnsureLeaseKey(ctx, leaseKeySecretName(lease.Name), "tuist-rack-lease-"+lease.Name)
	if err != nil {
		return ctrl.Result{}, err
	}
	lease.Status.SSHPublicKey = publicKey
	if lease.Spec.Phase != infrav1.LeaseLent || lease.Spec.GrantedKeyFingerprint != leaseKeyFingerprint(publicKey) {
		if lease.Status.State != infrav1.LeaseActive {
			lease.Status.State = infrav1.LeaseAccepted
		}
		return ctrl.Result{RequeueAfter: lendingDrainRequeue}, nil
	}

	if err := r.reconcileEgress(ctx, lease, node); err != nil {
		if apierrors.IsConflict(err) {
			return ctrl.Result{Requeue: true}, nil
		}
		return ctrl.Result{}, err
	}

	// While the lender acts on the host for this env, nothing is pushed to it.
	if result, held, err := r.reconcileSiteRequest(ctx, lease, node); err != nil || held {
		return result, err
	}

	if !conditions.IsTrue(lease, BootstrappedCondition) {
		if result, err := r.takeOver(ctx, lease, node, privateKey); err != nil || !result.IsZero() {
			return result, err
		}
	} else if result, err := r.reconcileDrift(ctx, lease, node, privateKey); err != nil || !result.IsZero() {
		return result, err
	}

	ready, err := nodeIsReady(ctx, r.Client, node)
	if err != nil {
		return ctrl.Result{}, err
	}
	lease.Status.NodeReady = ready
	lease.Status.State = infrav1.LeaseActive
	if !terminalPhasePinned(lease.Status.FailureReason) {
		lease.Status.Phase = "Ready"
	}
	return ctrl.Result{RequeueAfter: leaseRequeue}, nil
}

// takeOver is the first push of this env's runtime to the host: after the
// Node it ran under before is drained, with a fresh tailnet login, so the host
// leaves the lender's tailnet tags for this env's.
func (r *RackHostLeaseReconciler) takeOver(ctx context.Context, lease *infrav1.RackHostLease, node string, privateKey []byte) (ctrl.Result, error) {
	// Nothing is drained before the host is known to answer this env's key and
	// to be this env's to push to: a missing route or grant must not take the
	// Node it runs under now out of service.
	probe := r.probeHost
	if probe == nil {
		probe = bootstrap.Probe
	}
	ip := lease.Spec.Host.Address
	if h := rackEgressHost(r.egressConfig(), lease.Name); h != "" {
		ip = h
	}
	if _, err := probe(ctx, bootstrap.Config{
		IP: ip, SSHUser: lease.Spec.Host.SSHUser, SSHPrivateKey: privateKey,
		KnownHostFingerprint: lease.Spec.Host.HostKeyFingerprint, RuntimeOwner: r.Env,
	}); err != nil {
		reason := "HostUnreachable"
		if bootstrap.IsRuntimeOwnerError(err) {
			reason = "RuntimeOwnedElsewhere"
		}
		conditions.MarkFalse(lease, BootstrappedCondition, reason, clusterv1.ConditionSeverityWarning, "%v", err)
		return ctrl.Result{RequeueAfter: lendingRequeue}, nil
	}

	previous := lease.Spec.PreviousNodeName
	if previous != "" && previous != node {
		active, err := drainNodeForLease(ctx, r.Client, previous, r.Env)
		if err != nil {
			return ctrl.Result{}, err
		}
		if len(active) > 0 {
			conditions.MarkFalse(lease, BootstrappedCondition, "PreviousNodeDraining", clusterv1.ConditionSeverityInfo,
				"waiting for %d job(s) on %s to finish: %v", len(active), previous, active)
			return ctrl.Result{RequeueAfter: lendingDrainRequeue}, nil
		}
	}

	lease.Status.Phase = "Bootstrapping"
	desired := r.desiredHostConfigHash(lease)
	if _, err := r.push(ctx, lease, node, privateKey, true); err != nil {
		lease.Status.BootstrapAttempts++
		reason := "TakeOverFailed"
		if bootstrap.IsRuntimeOwnerError(err) {
			reason = "RuntimeOwnedElsewhere"
		}
		conditions.MarkFalse(lease, BootstrappedCondition, reason, clusterv1.ConditionSeverityWarning, "%v", err)
		r.Recorder.Eventf(lease, corev1.EventTypeWarning, reason, "Taking %s over: %v (attempt %d, will retry)", lease.Name, err, lease.Status.BootstrapAttempts)
		return ctrl.Result{RequeueAfter: lendingRequeue}, nil
	}

	conditions.MarkTrue(lease, BootstrappedCondition)
	lease.Status.BootstrapAttempts = 0
	lease.Status.HostConfigHash = desired
	lease.Status.TartKubeletBinarySHA = r.TartKubeletBinarySHA
	lease.Status.TartKubeletUpdateAttempts = 0
	if previous != "" && previous != node {
		if err := r.Delete(ctx, &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: previous}}); err != nil && !apierrors.IsNotFound(err) {
			return ctrl.Result{}, fmt.Errorf("delete the previous Node %s: %w", previous, err)
		}
	}
	r.Recorder.Eventf(lease, corev1.EventTypeNormal, "TookOver", "%s runs this env's runtime as Node %s", lease.Name, node)
	return ctrl.Result{}, nil
}

// reconcileDrift re-pushes the runtime when this operator's config moved,
// with the terminal-failure rules every macOS kind shares.
func (r *RackHostLeaseReconciler) reconcileDrift(ctx context.Context, lease *infrav1.RackHostLease, node string, privateKey []byte) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	reportUnavailableTartPin(lease, r.FleetConfig, r.TartReleases, r.Recorder)
	desired := r.desiredHostConfigHash(lease)
	terminal := lease.Status.FailureReason != nil
	if shouldClearTerminalFailure(desired, lease.Status.FailedHostConfigHash, terminal,
		lease.Status.LastUpdateFailureTime, r.TartKubeletTerminalRetryAfter, time.Now()) {
		reason := "host config drifted since the failure was recorded"
		if desired != "" && desired == lease.Status.FailedHostConfigHash {
			reason = "retry cooldown elapsed"
		}
		clearUpdateFailure(lease, reason, logger, r.Recorder)
		terminal = false
	}
	if !hostConfigDrift(desired, lease.Status.HostConfigHash) || terminal {
		return ctrl.Result{}, nil
	}
	if _, err := r.push(ctx, lease, node, privateKey, false); err != nil {
		recordUpdateFailure(lease, fmt.Errorf("tart-kubelet update: %w", err), r.TartKubeletMaxUpdateAttempts, desired, logger, r.Recorder)
		if lease.Status.FailureReason != nil {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{RequeueAfter: lendingRequeue}, nil
	}
	lease.Status.HostConfigHash = desired
	lease.Status.TartKubeletBinarySHA = r.TartKubeletBinarySHA
	lease.Status.TartKubeletUpdateAttempts = 0
	r.Recorder.Eventf(lease, corev1.EventTypeNormal, "AgentRolled", "Rolled tart-kubelet to %s on %s", r.TartKubeletBinarySHA, lease.Name)
	return ctrl.Result{}, nil
}

// push sends this env's runtime to the host through the rack's edges, and over
// the host's own tailnet device when that path does not answer, as the
// lender's drift loop does. A takeover only goes through the edges: until it
// succeeds, the host's device is the lender's.
func (r *RackHostLeaseReconciler) push(ctx context.Context, lease *infrav1.RackHostLease, node string, privateKey []byte, takeOver bool) (string, error) {
	pushRuntime := r.pushRuntime
	if pushRuntime == nil {
		pushRuntime = bootstrap.UpdateTartKubelet
	}
	perHost, err := r.perHostConfig(ctx, lease, node, privateKey)
	if err != nil {
		return "", err
	}
	perHost.TailscaleForceReauth = takeOver
	cfg := applyHostSizing(r.leaseFleetConfig(lease), r.hostSizing(lease), perHost)
	fingerprint, err := pushRuntime(ctx, cfg)
	if err != nil && fingerprint == "" && !takeOver {
		if fallback := egressServiceHost(r.egressConfig(), node); fallback != "" && fallback != cfg.IP {
			cfg.IP = fallback
			cfg.SkipTailscaleInstall = true
			fingerprint, err = pushRuntime(ctx, cfg)
		}
	}
	return fingerprint, err
}

func (r *RackHostLeaseReconciler) perHostConfig(ctx context.Context, lease *infrav1.RackHostLease, node string, privateKey []byte) (bootstrap.PerHost, error) {
	identity, err := r.CredentialsManager.EnsureNodeIdentity(ctx, node, "")
	if err != nil {
		return bootstrap.PerHost{}, fmt.Errorf("ensure node identity: %w", err)
	}
	kubeconfigYAML, err := r.Kubeconfig.Render(ctx, node, identity.Token, identity.CA)
	if err != nil {
		return bootstrap.PerHost{}, fmt.Errorf("render kubeconfig: %w", err)
	}
	tailscaleAuthKey, err := r.CredentialsManager.GetTailscaleAuthKey(ctx)
	if err != nil {
		return bootstrap.PerHost{}, fmt.Errorf("get tailscale auth key: %w", err)
	}
	ip := lease.Spec.Host.Address
	if h := rackEgressHost(r.egressConfig(), lease.Name); h != "" {
		ip = h
	}
	labels := map[string]string{}
	if r.FleetName != "" {
		labels["tuist.dev/fleet"] = r.FleetName
	}
	return bootstrap.PerHost{
		IP:                   ip,
		SSHUser:              lease.Spec.Host.SSHUser,
		SSHPrivateKey:        privateKey,
		NodeName:             node,
		ProviderID:           fmt.Sprintf("rack-applesilicon://%s/%s", lease.Spec.Host.Site, lease.Spec.Host.Serial),
		Kubeconfig:           kubeconfigYAML,
		TailscaleAuthKey:     tailscaleAuthKey,
		VNCRelayHost:         egressServiceHost(r.egressConfig(), node),
		NodeLabels:           labels,
		KnownHostFingerprint: lease.Spec.Host.HostKeyFingerprint,
		RuntimeOwner:         r.Env,
	}, nil
}

// leaseFleetConfig is this operator's fleet config with what a rack host
// needs on top, as rackFleetConfig gives the lender's own hosts: a standard
// tailnet device, and an SSH ingress guard that admits the rack's edges.
func (r *RackHostLeaseReconciler) leaseFleetConfig(lease *infrav1.RackHostLease) bootstrap.Config {
	cfg := r.FleetConfig
	cfg.TailscalePersistentDevice = true
	cfg.SSHIngressAllowCIDRs = append(slices.Clone(r.FleetConfig.SSHIngressAllowCIDRs), lease.Spec.Host.SSHIngressAllowCIDRs...)
	cfg.VMCacheGatewayCIDRs = slices.Clone(r.VMCacheGatewayCIDRs)
	cfg.ImageMirrors = slices.Clone(r.ImageMirrors)
	return cfg
}

// hostSizing is the hardware the lender describes, falling back to this
// operator's defaults for what it leaves out.
func (r *RackHostLeaseReconciler) hostSizing(lease *infrav1.RackHostLease) hostSizing {
	m := lease.Spec.Host.Machine
	sizing := hostSizing{
		HostCPU:              r.FleetConfig.HostCPU,
		HostMemoryMB:         r.FleetConfig.HostMemoryMB,
		MaxPods:              r.FleetConfig.MaxPods,
		GuestCapacity:        r.DefaultGuestCapacity,
		RunnerCacheVolumeGiB: r.FleetConfig.RunnerCacheVolumeGiB,
	}
	if m.HostCPU > 0 {
		sizing.HostCPU = m.HostCPU
	}
	if m.HostMemoryMB > 0 {
		sizing.HostMemoryMB = m.HostMemoryMB
	}
	if m.MaxPods > 0 {
		sizing.MaxPods = m.MaxPods
	}
	if m.GuestCapacity > 0 {
		sizing.GuestCapacity = m.GuestCapacity
	}
	if sizing.GuestCapacity < 1 {
		sizing.GuestCapacity = 1
	}
	if gib := m.RunnerCacheVolumeGiB; gib != nil && *gib >= 0 {
		sizing.RunnerCacheVolumeGiB = *gib
	}
	sizing.TartVersion, sizing.TartTarball = hostTart(lease, r.FleetConfig, r.TartReleases)
	return sizing
}

// desiredHostConfigHash covers the Node's fleet label too, which is per host
// and so stripped from the fleet hash.
func (r *RackHostLeaseReconciler) desiredHostConfigHash(lease *infrav1.RackHostLease) string {
	hash := hostConfigHashFor(r.leaseFleetConfig(lease), r.hostSizing(lease))
	if hash == "" {
		return ""
	}
	sum := sha256.Sum256([]byte(hash + "\nnodeFleet=" + r.FleetName))
	return hex.EncodeToString(sum[:])
}

// release gives the host back: this env's jobs on it finish, then its Node and
// identity go and nothing is pushed any more.
func (r *RackHostLeaseReconciler) release(ctx context.Context, lease *infrav1.RackHostLease, node string, declared bool) (ctrl.Result, error) {
	nodes := []string{node}
	if previous := lease.Spec.PreviousNodeName; previous != "" && previous != node {
		nodes = append(nodes, previous)
	}
	var active []string
	for _, name := range nodes {
		running, err := drainNodeForLease(ctx, r.Client, name, lease.Spec.Lender)
		if err != nil {
			return ctrl.Result{}, err
		}
		active = append(active, running...)
	}
	if len(active) > 0 {
		lease.Status.State = infrav1.LeaseDraining
		conditions.MarkFalse(lease, BootstrappedCondition, "Draining", clusterv1.ConditionSeverityInfo,
			"waiting for %d job(s) to finish before giving %s back: %v", len(active), lease.Name, active)
		return ctrl.Result{RequeueAfter: lendingDrainRequeue}, nil
	}
	if err := r.retire(ctx, lease, nodes); err != nil {
		return ctrl.Result{}, err
	}
	lease.Status.NodeReady = false
	lease.Status.HostConfigHash = ""
	if conditions.Has(lease, BootstrappedCondition) {
		conditions.MarkFalse(lease, BootstrappedCondition, "Released", clusterv1.ConditionSeverityInfo,
			"gave %s back to %s", lease.Name, lease.Spec.Lender)
	}
	switch {
	case !declared && lease.Spec.Phase == infrav1.LeaseOffered:
		lease.Status.State = infrav1.LeaseRefused
		lease.Status.SSHPublicKey = ""
	case lease.Status.State != infrav1.LeaseReleased:
		lease.Status.State = infrav1.LeaseReleased
		r.Recorder.Eventf(lease, corev1.EventTypeNormal, "Released", "Gave %s back to %s", lease.Name, lease.Spec.Lender)
	}
	lease.Status.Phase = ""
	return ctrl.Result{RequeueAfter: leaseRequeue}, nil
}

// retire removes what this cluster holds for the host: the identity first, so
// a tart-kubelet still running on it cannot register the Node again.
func (r *RackHostLeaseReconciler) retire(ctx context.Context, lease *infrav1.RackHostLease, nodes []string) error {
	if err := r.CredentialsManager.DeleteNodeIdentity(ctx, nodes[0]); err != nil {
		return fmt.Errorf("revoke node identity: %w", err)
	}
	for _, name := range nodes {
		if err := r.Delete(ctx, &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: name}}); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete Node %s: %w", name, err)
		}
	}
	if r.EgressProxyGroup == "" || r.EgressNamespace == "" {
		return nil
	}
	for _, name := range []string{nodes[0], rackEgressServiceName(lease.Name)} {
		svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: r.EgressNamespace}}
		if err := r.Delete(ctx, svc); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete egress Service %s: %w", name, err)
		}
	}
	return nil
}

func (r *RackHostLeaseReconciler) reconcileDelete(ctx context.Context, lease *infrav1.RackHostLease, node string) (ctrl.Result, error) {
	nodes := []string{node}
	if previous := lease.Spec.PreviousNodeName; previous != "" && previous != node {
		nodes = append(nodes, previous)
	}
	if err := r.retire(ctx, lease, nodes); err != nil {
		return ctrl.Result{RequeueAfter: lendingDrainRequeue}, err
	}
	if err := r.CredentialsManager.DeleteLeaseKey(ctx, leaseKeySecretName(lease.Name)); err != nil {
		return ctrl.Result{RequeueAfter: lendingDrainRequeue}, err
	}
	controllerutil.RemoveFinalizer(lease, RackHostLeaseFinalizer)
	return ctrl.Result{}, nil
}

func (r *RackHostLeaseReconciler) reconcileEgress(ctx context.Context, lease *infrav1.RackHostLease, node string) error {
	cfg := r.egressConfig()
	if err := reconcileRackEgressService(ctx, r.Client, cfg, lease.Name, lease.Spec.Host.Address, r.FleetName); err != nil {
		return err
	}
	return reconcileEgressService(ctx, r.Client, cfg, node, r.FleetName, r.hostSizing(lease).GuestCapacity)
}

func (r *RackHostLeaseReconciler) egressConfig() egressConfig {
	return egressConfig{
		Namespace:      r.EgressNamespace,
		ProxyGroup:     r.EgressProxyGroup,
		MagicDNSSuffix: r.EgressMagicDNSSuffix,
		ManagedBy:      operatorName,
	}
}

func (r *RackHostLeaseReconciler) nodeName(lease *infrav1.RackHostLease) string {
	return rackMachineName(r.FleetName, lease.Name)
}

func leaseKeySecretName(host string) string {
	return "rack-lease-" + host + "-ssh"
}

func nodeIsReady(ctx context.Context, c client.Reader, name string) (bool, error) {
	node := &corev1.Node{}
	if err := c.Get(ctx, client.ObjectKey{Name: name}, node); err != nil {
		return false, client.IgnoreNotFound(err)
	}
	for _, cond := range node.Status.Conditions {
		if cond.Type == corev1.NodeReady {
			return cond.Status == corev1.ConditionTrue, nil
		}
	}
	return false, nil
}

func (r *RackHostLeaseReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.RackHostLease{}).
		Complete(r)
}

// reconcileSiteRequest asks the lender for what the lease's annotations name
// and holds this env's pushes until it has answered: a power cycle at once,
// an update once this env's jobs on the host have finished. After an update
// the runtime is pushed again, since the installer resets files the host
// config owns, and the Node goes back in service unless the update changed
// the host and failed. held is set while the request is open.
func (r *RackHostLeaseReconciler) reconcileSiteRequest(ctx context.Context, lease *infrav1.RackHostLease, node string) (ctrl.Result, bool, error) {
	if target, asked := lease.Annotations[OSReinstallAnnotation]; asked {
		delete(lease.Annotations, OSReinstallAnnotation)
		r.Recorder.Eventf(lease, corev1.EventTypeWarning, "ReinstallRefused",
			"Not asking %s to reinstall %s on macOS %s: it wipes this env's runtime and the lease key. Ask %s to return the host and reinstall it.",
			lease.Spec.Lender, lease.Name, target, lease.Spec.Lender)
	}
	req := lease.Status.SiteRequest
	if req == nil {
		if req = siteRequestFromAnnotations(lease); req == nil {
			return ctrl.Result{}, false, nil
		}
		lease.Status.SiteRequest = req
		r.Recorder.Eventf(lease, corev1.EventTypeNormal, "SiteRequested", "Asked %s for %s %s", lease.Spec.Lender, req.Action, req.Target)
	}
	if req.Action == infrav1.SiteRequestOSUpdate && !req.Drained {
		active, err := drainNodeForLease(ctx, r.Client, node, lease.Spec.Lender)
		if err != nil {
			return ctrl.Result{}, true, err
		}
		if len(active) > 0 {
			conditions.MarkFalse(lease, SiteRequestCondition, "Draining", clusterv1.ConditionSeverityInfo,
				"waiting for %d job(s) to finish before %s updates the host: %v", len(active), lease.Spec.Lender, active)
			return ctrl.Result{RequeueAfter: lendingDrainRequeue}, true, nil
		}
		req.Drained = true
	}

	res := lease.Spec.SiteRequestResult
	if res == nil || res.ID != req.ID || !siteRequestAnswered(res.Phase) {
		message := fmt.Sprintf("waiting for %s", lease.Spec.Lender)
		if res != nil && res.ID == req.ID && res.Message != "" {
			message = res.Message
		}
		conditions.MarkFalse(lease, SiteRequestCondition, "InProgress", clusterv1.ConditionSeverityInfo, "%s %s: %s", req.Action, req.Target, message)
		return ctrl.Result{RequeueAfter: lendingDrainRequeue}, true, nil
	}

	if req.Action == infrav1.SiteRequestOSUpdate {
		if res.Phase == infrav1.SiteRequestSucceeded {
			lease.Status.HostConfigHash = ""
		}
		if res.ReturnToService {
			if err := uncordonNodeAfterLease(ctx, r.Client, node); err != nil {
				return ctrl.Result{}, true, err
			}
		}
		delete(lease.Annotations, OSUpdateAnnotation)
	} else {
		delete(lease.Annotations, PowerCycleAnnotation)
	}
	eventType := corev1.EventTypeNormal
	if res.Phase == infrav1.SiteRequestFailed {
		eventType = corev1.EventTypeWarning
		conditions.MarkFalse(lease, SiteRequestCondition, "Failed", clusterv1.ConditionSeverityWarning, "%s %s: %s", req.Action, req.Target, res.Message)
	} else {
		conditions.MarkTrue(lease, SiteRequestCondition)
	}
	r.Recorder.Eventf(lease, eventType, "SiteRequest"+res.Phase, "%s %s: %s", req.Action, req.Target, res.Message)
	lease.Status.SiteRequest = nil
	return ctrl.Result{}, false, nil
}

// SiteRequestCondition reports the borrower's last site request.
const SiteRequestCondition clusterv1.ConditionType = "SiteRequest"

func siteRequestFromAnnotations(lease *infrav1.RackHostLease) *infrav1.RackHostLeaseSiteRequest {
	now := metav1.Now()
	if _, asked := lease.Annotations[PowerCycleAnnotation]; asked {
		return &infrav1.RackHostLeaseSiteRequest{ID: string(uuid.NewUUID()), Action: infrav1.SiteRequestPowerCycle, RequestedAt: &now}
	}
	if target, asked := lease.Annotations[OSUpdateAnnotation]; asked {
		return &infrav1.RackHostLeaseSiteRequest{ID: string(uuid.NewUUID()), Action: infrav1.SiteRequestOSUpdate, Target: strings.TrimSpace(target), RequestedAt: &now}
	}
	return nil
}
