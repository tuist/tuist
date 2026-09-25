package linux

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util"
	"sigs.k8s.io/cluster-api/util/annotations"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	RackLinuxMachineFinalizer = "racklinux.cluster.x-k8s.io/finalizer"

	// HostConvergedCondition reports whether the host's last converge
	// succeeded.
	HostConvergedCondition clusterv1.ConditionType = "HostConverged"

	// RackTailnetReadyCondition reports whether the claimed host is reachable
	// on the tailnet.
	RackTailnetReadyCondition clusterv1.ConditionType = "TailnetReady"

	defaultRackConvergeInterval = time.Hour
	rackNotReadyConvergeAfter   = 5 * time.Minute
	rackConvergeTimeout         = 15 * time.Minute
	rackLeaveTimeout            = time.Minute
)

var controlPlaneVersionPattern = regexp.MustCompile(`^v(\d+)\.(\d+)\.(\d+)`)

// RunRackScript runs a script as root on a rack host over SSH.
type RunRackScript func(ctx context.Context, user, host string, privateKey []byte, script string, timeout time.Duration, hk *bootstrap.HostKeyState) (string, error)

func runRackScriptOverSSH(ctx context.Context, user, host string, privateKey []byte, script string, timeout time.Duration, hk *bootstrap.HostKeyState) (string, error) {
	out, err := runOverSSH(ctx, user, host, privateKey, "sudo -n bash -s", script, timeout, hk)
	var exitErr *ssh.ExitError
	if errors.As(err, &exitErr) {
		return out, &scriptExitError{status: exitErr.ExitStatus(), err: err}
	}
	return out, err
}

// scriptExitError is a script that ran and exited non-zero.
type scriptExitError struct {
	status int
	err    error
}

func (e *scriptExitError) Error() string { return e.err.Error() }

func (e *scriptExitError) Unwrap() error { return e.err }

// RackLinuxMachineReconciler claims a RackLinuxHost, dials it over the tailnet
// and runs the converge script on it: on the first run with a one-hour
// bootstrap token so the kubelet gets its own system:node certificate, and
// afterwards whenever the rendered configuration or the host's tailnet device
// changes, while its Node is NotReady, and on ConvergeInterval.
type RackLinuxMachineReconciler struct {
	client.Client
	APIReader          client.Reader
	Scheme             *runtime.Scheme
	Recorder           record.EventRecorder
	CredentialsManager *credentials.Manager

	// APIServerURL is what the kubelet bootstraps against; empty takes the
	// server from kube-public/cluster-info.
	APIServerURL string

	// KubernetesMinor is the minor the kubelet configuration is rendered for;
	// a control plane on another minor holds converges.
	KubernetesMinor string

	// ControlPlaneVersion returns the API server's gitVersion.
	ControlPlaneVersion func(ctx context.Context) (string, error)

	EgressNamespace  string
	EgressProxyGroup string
	// EgressProxyTags are the tags the Tailscale operator gives a proxy of its
	// own, such as a host's kubelet proxy.
	EgressProxyTags string

	ConvergeInterval time.Duration

	// RunScript is overridden in tests.
	RunScript RunRackScript
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racklinuxmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racklinuxmachines/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racklinuxmachines/finalizers,verbs=update

func (r *RackLinuxMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	machine := &infrav1.RackLinuxMachine{}
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

	if !machine.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, machine)
	}

	ownerMachine, ownerErr := util.GetOwnerMachine(ctx, r.Client, machine.ObjectMeta)
	if ownerErr != nil {
		return ctrl.Result{}, fmt.Errorf("get owner Machine: %w", ownerErr)
	}
	if ownerMachine != nil && ownerMachine.Spec.ClusterName != "" {
		cluster := &clusterv1.Cluster{}
		if err := r.Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: ownerMachine.Spec.ClusterName}, cluster); err != nil {
			if apierrors.IsNotFound(err) {
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			return ctrl.Result{}, err
		}
		if cluster.Spec.Paused {
			return ctrl.Result{}, nil
		}
	}
	if annotations.HasPaused(machine) {
		return ctrl.Result{}, nil
	}

	if !controllerutil.ContainsFinalizer(machine, RackLinuxMachineFinalizer) {
		controllerutil.AddFinalizer(machine, RackLinuxMachineFinalizer)
	}
	return r.reconcileNormal(ctx, machine)
}

func (r *RackLinuxMachineReconciler) reconcileNormal(ctx context.Context, machine *infrav1.RackLinuxMachine) (ctrl.Result, error) {
	host, result, err := r.claimHost(ctx, machine)
	if host == nil || err != nil {
		return result, err
	}

	tn := host.Status.Tailnet
	if tn == nil || tn.Address == "" {
		machine.Status.Phase = "WaitingForTailnet"
		conditions.MarkFalse(machine, RackTailnetReadyCondition, "HostNotOnTailnet", clusterv1.ConditionSeverityInfo,
			"%s is not on the tailnet; install it from a stick written by rack:write-install-usb", host.Name)
		return ctrl.Result{RequeueAfter: time.Minute}, nil
	}
	machine.Status.Addresses = []clusterv1.MachineAddress{
		{Type: clusterv1.MachineInternalIP, Address: tn.Address},
		{Type: clusterv1.MachineHostName, Address: host.Name},
	}

	node := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: host.Name}, node); err != nil {
		if !apierrors.IsNotFound(err) {
			return ctrl.Result{}, err
		}
		node = nil
	}
	defer r.observeNode(machine, node)

	if !tn.Connected {
		conditions.MarkFalse(machine, RackTailnetReadyCondition, "HostDisconnected", clusterv1.ConditionSeverityWarning,
			"%s is not connected to the tailnet", describeTailnet(host))
		return ctrl.Result{RequeueAfter: time.Minute}, nil
	}
	conditions.MarkTrue(machine, RackTailnetReadyCondition)

	if err := r.egress().ensure(ctx, r.Client, host); err != nil {
		return ctrl.Result{}, fmt.Errorf("reconcile egress Service for %s: %w", host.Name, err)
	}
	if err := r.reconcileNodeAddresses(ctx, host, node); err != nil {
		return ctrl.Result{}, err
	}

	opts, holdReason, err := r.convergeOptions(ctx, machine, host)
	if err != nil {
		return ctrl.Result{}, err
	}
	if holdReason != "" {
		conditions.MarkFalse(machine, HostConvergedCondition, "ConvergeHeld", clusterv1.ConditionSeverityWarning, "%s", holdReason)
		return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
	}

	desired := rackConfigHash(opts)
	due, wait := r.convergeDue(machine, host, node, desired)
	if !due {
		return ctrl.Result{RequeueAfter: wait}, nil
	}
	if err := r.converge(ctx, machine, host, node, opts, desired); err != nil {
		machine.Status.ConvergeFailures++
		conditions.MarkFalse(machine, HostConvergedCondition, "ConvergeFailed", clusterv1.ConditionSeverityWarning, "%v", err)
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "ConvergeFailed", "%s: %v", host.Name, err)
		return ctrl.Result{RequeueAfter: convergeBackoff(machine.Status.ConvergeFailures)}, nil
	}
	return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
}

// observeNode derives readiness from the Node the host registered.
func (r *RackLinuxMachineReconciler) observeNode(machine *infrav1.RackLinuxMachine, node *corev1.Node) {
	switch {
	case node == nil:
		machine.Status.Ready = false
		conditions.MarkFalse(machine, NodeReadyCondition, "NodeNotRegistered", clusterv1.ConditionSeverityInfo, "no Node registered yet")
		if machine.Status.Phase != "WaitingForTailnet" {
			machine.Status.Phase = "Joining"
		}
	case nodeReady(node):
		machine.Status.Ready = true
		machine.Status.Phase = "Ready"
		conditions.MarkTrue(machine, NodeReadyCondition)
	default:
		machine.Status.Ready = false
		machine.Status.Phase = "NotReady"
		conditions.MarkFalse(machine, NodeReadyCondition, "NodeNotReady", clusterv1.ConditionSeverityWarning, "Node %s is not Ready", node.Name)
	}
}

// convergeDue reports whether to converge now and, when not, how long until
// the next check.
func (r *RackLinuxMachineReconciler) convergeDue(machine *infrav1.RackLinuxMachine, host *infrav1.RackLinuxHost, node *corev1.Node, desired string) (bool, time.Duration) {
	now := time.Now()
	if machine.Status.TailnetDeviceID != host.Status.Tailnet.DeviceID {
		return true, 0
	}
	if machine.Status.ConvergeFailures > 0 && machine.Status.LastConvergeAttemptTime != nil {
		backoff := convergeBackoff(machine.Status.ConvergeFailures)
		if elapsed := now.Sub(machine.Status.LastConvergeAttemptTime.Time); elapsed < backoff {
			return false, backoff - elapsed
		}
		return true, 0
	}
	if machine.Status.HostConfigHash != desired || machine.Status.LastConvergeTime == nil {
		return true, 0
	}
	since := now.Sub(machine.Status.LastConvergeTime.Time)
	if node == nil || !nodeReady(node) {
		if since >= rackNotReadyConvergeAfter {
			return true, 0
		}
		return false, rackNotReadyConvergeAfter - since
	}
	interval := r.ConvergeInterval
	if interval <= 0 {
		interval = defaultRackConvergeInterval
	}
	if since >= interval {
		return true, 0
	}
	return false, interval - since
}

func convergeBackoff(failures int32) time.Duration {
	backoff := time.Minute
	for i := int32(1); i < failures && backoff < 30*time.Minute; i++ {
		backoff *= 2
	}
	if backoff > 30*time.Minute {
		backoff = 30 * time.Minute
	}
	return backoff
}

// convergeOptions renders the desired configuration. A non-empty reason means
// converging has to wait for the cluster rather than the host.
func (r *RackLinuxMachineReconciler) convergeOptions(ctx context.Context, machine *infrav1.RackLinuxMachine, host *infrav1.RackLinuxHost) (rackConvergeOptions, string, error) {
	cpVersion, err := r.ControlPlaneVersion(ctx)
	if err != nil {
		return rackConvergeOptions{}, "", fmt.Errorf("read the control plane version: %w", err)
	}
	kubeletVersion, minor, ok := parseControlPlaneVersion(cpVersion)
	if !ok {
		return rackConvergeOptions{}, fmt.Sprintf("cannot parse the control plane version %q", cpVersion), nil
	}
	if minor != r.KubernetesMinor {
		return rackConvergeOptions{}, fmt.Sprintf("the control plane runs %s, and this operator renders kubelet configuration for %s; roll the operator for %s first",
			cpVersion, r.KubernetesMinor, minor), nil
	}
	clusterDNS := discoverClusterDNS(ctx, r.APIReader)
	if clusterDNS == "" {
		return rackConvergeOptions{}, "waiting for the kube-dns Service to resolve", nil
	}
	server, ca, err := readClusterInfo(ctx, r.APIReader)
	if err != nil {
		return rackConvergeOptions{}, "", err
	}
	if r.APIServerURL != "" {
		server = r.APIServerURL
	}
	return rackConvergeOptions{
		NodeName:       host.Name,
		NodeIP:         host.Status.Tailnet.Address,
		ProviderID:     rackLinuxProviderID(host),
		KubeletVersion: kubeletVersion,
		K8sMinor:       minor,
		ClusterCAPEM:   ca,
		ClusterDNS:     clusterDNS,
		NodeLabels:     machine.Spec.NodeLabels,
		NodeTaints:     machine.Spec.NodeTaints,
		ManagementMAC:  host.Spec.BootMAC,
		APIServerURL:   server,
	}, "", nil
}

func parseControlPlaneVersion(v string) (kubelet, minor string, ok bool) {
	m := controlPlaneVersionPattern.FindStringSubmatch(v)
	if m == nil {
		return "", "", false
	}
	return fmt.Sprintf("%s.%s.%s", m[1], m[2], m[3]), fmt.Sprintf("v%s.%s", m[1], m[2]), true
}

// readClusterInfo returns the API server and CA that kubeadm discovery
// publishes in kube-public/cluster-info.
func readClusterInfo(ctx context.Context, reader client.Reader) (string, []byte, error) {
	cm := &corev1.ConfigMap{}
	if err := reader.Get(ctx, types.NamespacedName{Namespace: "kube-public", Name: "cluster-info"}, cm); err != nil {
		return "", nil, fmt.Errorf("read kube-public/cluster-info: %w", err)
	}
	cfg, err := clientcmd.Load([]byte(cm.Data["kubeconfig"]))
	if err != nil {
		return "", nil, fmt.Errorf("parse kube-public/cluster-info: %w", err)
	}
	for _, c := range cfg.Clusters {
		if len(c.CertificateAuthorityData) > 0 {
			return c.Server, c.CertificateAuthorityData, nil
		}
	}
	return "", nil, fmt.Errorf("kube-public/cluster-info carries no cluster CA")
}

// converge runs the converge script on the host, minting a bootstrap token
// and running it again when the kubelet has no identity.
func (r *RackLinuxMachineReconciler) converge(
	ctx context.Context,
	machine *infrav1.RackLinuxMachine,
	host *infrav1.RackLinuxHost,
	node *corev1.Node,
	opts rackConvergeOptions,
	desired string,
) error {
	logger := log.FromContext(ctx)
	now := metav1.Now()
	machine.Status.LastConvergeAttemptTime = &now
	machine.Status.Phase = "Converging"
	if previous := machine.Status.TailnetDeviceID; previous != host.Status.Tailnet.DeviceID {
		machine.Status.TailnetDeviceID = host.Status.Tailnet.DeviceID
		machine.Status.ConvergeFailures = 0
		if previous != "" {
			r.Recorder.Eventf(machine, corev1.EventTypeNormal, "HostReinstalled",
				"%s is on tailnet device %s, not %s: it was reinstalled, so its SSH host key is pinned afresh",
				host.Name, host.Status.Tailnet.DeviceID, previous)
			if err := r.CredentialsManager.DeleteMachineBootstrap(ctx, rackLinuxPinKey(host.Name, previous)); err != nil {
				logger.Error(err, "delete the previous install's host key pin", "host", host.Name)
			}
		}
	}

	if err := r.checkCiliumExcludesRackNodes(ctx); err != nil {
		return err
	}

	key, err := r.CredentialsManager.ReadFleetSSHKey(ctx, machine.Spec.FleetName)
	if err != nil {
		return err
	}
	pinKey := rackLinuxPinKey(host.Name, host.Status.Tailnet.DeviceID)
	known := ""
	if creds, err := r.CredentialsManager.GetMachineBootstrap(ctx, pinKey); err != nil {
		return fmt.Errorf("read the host key pin: %w", err)
	} else if creds != nil {
		known = creds.HostFingerprint
	}
	hk := bootstrap.NewHostKeyState(known)
	defer func() {
		if observed := hk.Observed(); observed != "" && observed != known {
			if err := r.CredentialsManager.SetMachineHostFingerprint(ctx, pinKey, observed); err != nil {
				logger.Error(err, "persist the host key pin; will retry", "host", host.Name)
			}
		}
	}()

	user := firstNonEmpty(host.Spec.SSHUser, "tuist")
	target := r.egress().dialTarget(host)
	run := r.RunScript
	if run == nil {
		run = runRackScriptOverSSH
	}

	out, err := run(ctx, user, target, key, renderRackConvergeScript(opts), rackConvergeTimeout, hk)
	switch exitStatus(err) {
	case 0:
	case rackConvergeForeignJoin:
		return fmt.Errorf("%s was joined by kubeadm; reinstall it from a stick written by rack:write-install-usb", host.Name)
	case rackConvergeNeedsBootstrap:
		if node != nil {
			if node.Spec.ProviderID != "" && node.Spec.ProviderID != opts.ProviderID {
				return fmt.Errorf("node %s belongs to %s, not %s; refusing to replace it", node.Name, node.Spec.ProviderID, opts.ProviderID)
			}
			if err := r.Delete(ctx, node); err != nil && !apierrors.IsNotFound(err) {
				return fmt.Errorf("delete the stale Node %s: %w", node.Name, err)
			}
			r.Recorder.Eventf(machine, corev1.EventTypeNormal, "StaleNodeDeleted",
				"Deleted Node %s: its kubelet has no identity, so it registers afresh", node.Name)
		}
		secretName, token, err := r.CredentialsManager.MintNodeBootstrapToken(ctx, host.Name)
		if err != nil {
			return err
		}
		defer func() {
			if err := r.CredentialsManager.DeleteBootstrapToken(ctx, secretName); err != nil {
				logger.Error(err, "delete the bootstrap token; it expires within the hour", "token", secretName)
			}
		}()
		opts.BootstrapToken = token
		out, err = run(ctx, user, target, key, renderRackConvergeScript(opts), rackConvergeTimeout, hk)
		if err != nil {
			return err
		}
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Joined", "%s joined the cluster as Node %s", host.Name, host.Name)
	default:
		return err
	}

	summary := convergeSummary(out)
	if !strings.Contains(summary, "changed=none restarted=none") {
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Converged", "%s: %s", host.Name, summary)
	}
	logger.Info("converged rack host", "host", host.Name, "summary", summary)

	machine.Status.HostConfigHash = desired
	machine.Status.LastConvergeTime = &now
	machine.Status.ConvergeFailures = 0
	conditions.MarkTrue(machine, HostConvergedCondition)
	return nil
}

func exitStatus(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *scriptExitError
	if errors.As(err, &exitErr) {
		return exitErr.status
	}
	return -1
}

func convergeSummary(out string) string {
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		if strings.HasPrefix(line, "tuist-converge: changed=") {
			return strings.TrimPrefix(line, "tuist-converge: ")
		}
	}
	return "no summary"
}

// checkCiliumExcludesRackNodes refuses to converge while the cluster's Cilium
// agent would schedule onto a rack node. Every term of its node affinity has
// to exclude the label, since the terms are alternatives.
func (r *RackLinuxMachineReconciler) checkCiliumExcludesRackNodes(ctx context.Context) error {
	ds := &appsv1.DaemonSet{}
	if err := r.APIReader.Get(ctx, types.NamespacedName{Namespace: "kube-system", Name: "cilium"}, ds); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("read the Cilium DaemonSet: %w", err)
	}
	var terms []corev1.NodeSelectorTerm
	if a := ds.Spec.Template.Spec.Affinity; a != nil && a.NodeAffinity != nil && a.NodeAffinity.RequiredDuringSchedulingIgnoredDuringExecution != nil {
		terms = a.NodeAffinity.RequiredDuringSchedulingIgnoredDuringExecution.NodeSelectorTerms
	}
	excludes := len(terms) > 0
	for _, term := range terms {
		termExcludes := false
		for _, expr := range term.MatchExpressions {
			if expr.Key == ciliumNoScheduleLabel && expr.Operator == corev1.NodeSelectorOpNotIn && containsString(expr.Values, "true") {
				termExcludes = true
			}
		}
		excludes = excludes && termExcludes
	}
	if !excludes {
		return fmt.Errorf("the Cilium agent would schedule onto rack nodes: kube-system/cilium does not exclude %s=true (infra/k8s/mgmt/bootstrap/cilium-values.yaml)", ciliumNoScheduleLabel)
	}
	return nil
}

func containsString(values []string, want string) bool {
	for _, v := range values {
		if v == want {
			return true
		}
	}
	return false
}

// claimHost binds this machine to a free host in its pool, or confirms the
// binding it has. The claim is a status Update, so two racing claims cannot
// both win.
func (r *RackLinuxMachineReconciler) claimHost(ctx context.Context, machine *infrav1.RackLinuxMachine) (*infrav1.RackLinuxHost, ctrl.Result, error) {
	if name := machine.Status.RackLinuxHost; name != "" {
		host := &infrav1.RackLinuxHost{}
		err := r.Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: name}, host)
		switch {
		case err != nil && !apierrors.IsNotFound(err):
			return nil, ctrl.Result{}, err
		case err == nil && host.Status.ClaimedBy == machine.Name:
			return host, ctrl.Result{}, nil
		}
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "ClaimLost", "No longer holding rack host %s", name)
		machine.Status.RackLinuxHost = ""
		machine.Status.TailnetDeviceID = ""
		machine.Status.HostConfigHash = ""
		machine.Spec.ProviderID = nil
	}

	if machine.Spec.AdoptPool == "" {
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAdoptPool", clusterv1.ConditionSeverityError,
			"no adoptPool; refusing to claim an arbitrary rack host")
		return nil, ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
	}
	machine.Status.Phase = "Adopting"

	hosts := &infrav1.RackLinuxHostList{}
	if err := r.List(ctx, hosts, client.InNamespace(machine.Namespace)); err != nil {
		return nil, ctrl.Result{}, fmt.Errorf("list rack Linux hosts: %w", err)
	}
	var candidates []infrav1.RackLinuxHost
	for _, h := range hosts.Items {
		if h.Spec.Pool != machine.Spec.AdoptPool || !h.DeletionTimestamp.IsZero() || h.Spec.Location.Site == "" {
			continue
		}
		if h.Status.ClaimedBy == "" || h.Status.ClaimedBy == machine.Name {
			candidates = append(candidates, h)
		}
	}
	if len(candidates) == 0 {
		conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAvailableHost", clusterv1.ConditionSeverityWarning,
			"no free RackLinuxHost with a location.site in pool %q", machine.Spec.AdoptPool)
		return nil, ctrl.Result{RequeueAfter: time.Minute}, nil
	}
	sort.Slice(candidates, func(i, j int) bool {
		iMine, jMine := candidates[i].Status.ClaimedBy == machine.Name, candidates[j].Status.ClaimedBy == machine.Name
		if iMine != jMine {
			return iMine
		}
		return candidates[i].Name < candidates[j].Name
	})

	host := &candidates[0]
	host.Status.ClaimedBy = machine.Name
	host.Status.ClaimedAt = &metav1.Time{Time: time.Now()}
	if err := r.Status().Update(ctx, host); err != nil {
		if apierrors.IsConflict(err) {
			return nil, ctrl.Result{Requeue: true}, nil
		}
		return nil, ctrl.Result{}, fmt.Errorf("claim rack Linux host %s: %w", host.Name, err)
	}
	machine.Status.RackLinuxHost = host.Name
	providerID := rackLinuxProviderID(host)
	machine.Spec.ProviderID = &providerID
	conditions.MarkTrue(machine, shared.ProvisionedCondition)
	r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Adopted", "Claimed rack host %s (%s)", host.Name, host.Spec.Role)
	return host, ctrl.Result{}, nil
}

// reconcileDelete stops the host's kubelet and drops its identity (bounded,
// best effort), then deletes the Node, the egress Service and the host key pin
// and releases the claim. An unreachable host keeps its kubelet.
func (r *RackLinuxMachineReconciler) reconcileDelete(ctx context.Context, machine *infrav1.RackLinuxMachine) (ctrl.Result, error) {
	machine.Status.Phase = "Deleting"
	name := machine.Status.RackLinuxHost
	if name != "" {
		host := &infrav1.RackLinuxHost{}
		err := r.Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: name}, host)
		switch {
		case err != nil && !apierrors.IsNotFound(err):
			return ctrl.Result{}, err
		case err == nil && host.Status.ClaimedBy == machine.Name:
			r.leave(ctx, machine, host)
			if err := r.deleteNode(ctx, host); err != nil {
				return ctrl.Result{}, err
			}
			if err := r.egress().remove(ctx, r.Client, host.Name); err != nil {
				return ctrl.Result{}, err
			}
			for _, device := range []string{machine.Status.TailnetDeviceID, tailnetDeviceID(host)} {
				if device == "" {
					continue
				}
				if err := r.CredentialsManager.DeleteMachineBootstrap(ctx, rackLinuxPinKey(host.Name, device)); err != nil {
					return ctrl.Result{}, err
				}
			}
			host.Status.ClaimedBy = ""
			host.Status.ClaimedAt = nil
			if err := r.Status().Update(ctx, host); err != nil {
				return ctrl.Result{}, fmt.Errorf("release rack Linux host %s: %w", host.Name, err)
			}
			r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Released", "Released rack host %s", host.Name)
		}
	}
	controllerutil.RemoveFinalizer(machine, RackLinuxMachineFinalizer)
	return ctrl.Result{}, nil
}

const rackLeaveScript = `set -eu
systemctl disable --now kubelet >/dev/null 2>&1 || true
rm -rf /var/lib/kubelet/pki /var/lib/kubelet/kubeconfig /var/lib/kubelet/bootstrap-kubeconfig /var/lib/tuist/rack-converge.hash
`

func (r *RackLinuxMachineReconciler) leave(ctx context.Context, machine *infrav1.RackLinuxMachine, host *infrav1.RackLinuxHost) {
	if host.Status.Tailnet == nil || !host.Status.Tailnet.Connected {
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "LeaveSkipped",
			"%s is not on the tailnet, so its kubelet keeps running and re-registers its Node when it returns; reinstall it to retire it", host.Name)
		return
	}
	key, err := r.CredentialsManager.ReadFleetSSHKey(ctx, machine.Spec.FleetName)
	if err == nil {
		known := ""
		if creds, pinErr := r.CredentialsManager.GetMachineBootstrap(ctx, rackLinuxPinKey(host.Name, tailnetDeviceID(host))); pinErr == nil && creds != nil {
			known = creds.HostFingerprint
		}
		run := r.RunScript
		if run == nil {
			run = runRackScriptOverSSH
		}
		_, err = run(ctx, firstNonEmpty(host.Spec.SSHUser, "tuist"), r.egress().dialTarget(host), key, rackLeaveScript, rackLeaveTimeout, bootstrap.NewHostKeyState(known))
	}
	if err != nil {
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "LeaveFailed",
			"Could not stop %s's kubelet, so it re-registers its Node: %v", host.Name, err)
	}
}

func (r *RackLinuxMachineReconciler) deleteNode(ctx context.Context, host *infrav1.RackLinuxHost) error {
	node := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: host.Name}, node); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return err
	}
	if node.Spec.ProviderID != "" && node.Spec.ProviderID != rackLinuxProviderID(host) {
		return nil
	}
	if err := r.Delete(ctx, node); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete Node %s: %w", node.Name, err)
	}
	return nil
}

func (r *RackLinuxMachineReconciler) egress() rackEgress {
	return rackEgress{Namespace: r.EgressNamespace, ProxyGroup: r.EgressProxyGroup, ProxyTags: r.EgressProxyTags}
}

func rackLinuxProviderID(host *infrav1.RackLinuxHost) string {
	return fmt.Sprintf("rack-linux://%s/%s", host.Spec.Location.Site, host.Name)
}

// rackLinuxPinKey keys the SSH host key pin by host and tailnet device, which
// is one per install: a reinstalled host is trusted on first use again.
func rackLinuxPinKey(hostName, deviceID string) string {
	return "rack-linux-" + hostName + "-" + strings.ToLower(deviceID)
}

func tailnetDeviceID(host *infrav1.RackLinuxHost) string {
	if host.Status.Tailnet == nil {
		return ""
	}
	return host.Status.Tailnet.DeviceID
}

func (r *RackLinuxMachineReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.RackLinuxMachine{}).
		Watches(&clusterv1.Machine{}, handler.EnqueueRequestsFromMapFunc(rackLinuxMachineForCAPIMachine)).
		Watches(&infrav1.RackLinuxHost{}, handler.EnqueueRequestsFromMapFunc(r.machinesForHost)).
		Watches(&corev1.Pod{}, handler.EnqueueRequestsFromMapFunc(r.machineForKubeletProxy)).
		Complete(r)
}

func rackLinuxMachineForCAPIMachine(_ context.Context, o client.Object) []reconcile.Request {
	m, ok := o.(*clusterv1.Machine)
	if !ok || m.Spec.InfrastructureRef.Kind != "RackLinuxMachine" {
		return nil
	}
	return []reconcile.Request{{NamespacedName: types.NamespacedName{
		Namespace: m.Spec.InfrastructureRef.Namespace,
		Name:      m.Spec.InfrastructureRef.Name,
	}}}
}

// machinesForHost wakes the host's holder, and every machine waiting on its
// pool, when the host changes.
func (r *RackLinuxMachineReconciler) machinesForHost(ctx context.Context, o client.Object) []reconcile.Request {
	host, ok := o.(*infrav1.RackLinuxHost)
	if !ok {
		return nil
	}
	machines := &infrav1.RackLinuxMachineList{}
	if err := r.List(ctx, machines, client.InNamespace(host.Namespace)); err != nil {
		log.FromContext(ctx).Error(err, "list rack Linux machines for a host event", "host", host.Name)
		return nil
	}
	var requests []reconcile.Request
	for i := range machines.Items {
		m := &machines.Items[i]
		if m.Status.RackLinuxHost == host.Name || (m.Status.RackLinuxHost == "" && m.Spec.AdoptPool == host.Spec.Pool) {
			requests = append(requests, reconcile.Request{NamespacedName: types.NamespacedName{Namespace: m.Namespace, Name: m.Name}})
		}
	}
	return requests
}
