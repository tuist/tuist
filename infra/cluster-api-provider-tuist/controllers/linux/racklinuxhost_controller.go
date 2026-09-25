package linux

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
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
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/tailnet"
)

// TailnetJoinedCondition reports whether the host's device is on the tailnet.
const TailnetJoinedCondition clusterv1.ConditionType = "TailnetJoined"

// RackLinuxHostFinalizer holds a deleted host until the operator retired it.
const RackLinuxHostFinalizer = "racklinuxhost.cluster.x-k8s.io/finalizer"

const rackLinuxHostPollInterval = 2 * time.Minute

// TailnetAPI is the subset of the Tailscale API the host controller uses.
type TailnetAPI interface {
	Devices(ctx context.Context) ([]tailnet.Device, error)
	DeleteDevice(ctx context.Context, nodeID string) error
	RenameDevice(ctx context.Context, nodeID, name string) error
	CreateAuthKey(ctx context.Context, tags []string, expiry time.Duration, description string) (tailnet.AuthKey, error)
}

// RackLinuxHostReconciler keeps each host's tailnet device current: it finds
// the device the host joined as, removes the devices earlier installs of the
// same box left behind, and names the current one after the host. It publishes
// installs for hosts to netboot (racklinuxhost_install.go), scales a pool's
// MachineDeployment up as its hosts come onto the tailnet, and releases a claim
// whose machine is gone. It never claims or joins a host. A deleted host is
// retired before its finalizer goes, and a pool left without hosts or Machines
// loses its MachineDeployment (racklinuxhost_retire.go).
type RackLinuxHostReconciler struct {
	client.Client
	Scheme   *runtime.Scheme
	Recorder record.EventRecorder

	// APIReader reads the host from the API server. A reconcile mints join keys
	// and powers hosts, and the cache can still hold the host as it was before
	// the previous reconcile's status patch. Nil reads through Client.
	APIReader client.Reader

	// Tailnet is nil when no Tailscale credential is configured; hosts then
	// report TailnetJoined False and no machine can reach them.
	Tailnet TailnetAPI

	// Install is nil when the operator publishes no installs.
	Install *RackInstall

	// AMT is nil when the operator activates no AMT.
	AMT *RackAMT
	// AMTPower is overridden in tests.
	AMTPower amtPowerFunc

	CredentialsManager *credentials.Manager
	EgressNamespace    string
	EgressProxyGroup   string

	// RunScript and Now are overridden in tests.
	RunScript RunRackScript
	Now       func() time.Time
}

func (r *RackLinuxHostReconciler) now() time.Time {
	if r.Now != nil {
		return r.Now()
	}
	return time.Now()
}

func (r *RackLinuxHostReconciler) egress() rackEgress {
	return rackEgress{Namespace: r.EgressNamespace, ProxyGroup: r.EgressProxyGroup}
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racklinuxhosts,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racklinuxhosts/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racklinuxhosts/finalizers,verbs=update
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racklinuxmachines,verbs=get;list;watch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racklinuxmachinetemplates,verbs=get;list;watch;delete
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=machines,verbs=get;list;watch;patch;delete
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=machinedeployments,verbs=get;list;watch;patch;delete

func (r *RackLinuxHostReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	host := &infrav1.RackLinuxHost{}
	var reader client.Reader = r.Client
	if r.APIReader != nil {
		reader = r.APIReader
	}
	if getErr := reader.Get(ctx, req.NamespacedName, host); getErr != nil {
		if apierrors.IsNotFound(getErr) {
			pending, err := r.retireEmptyPools(ctx, req.Namespace)
			if err != nil || !pending {
				return ctrl.Result{}, err
			}
			return ctrl.Result{RequeueAfter: time.Minute}, nil
		}
		return ctrl.Result{}, getErr
	}

	patchHelper, helperErr := patch.NewHelper(host, r.Client)
	if helperErr != nil {
		return ctrl.Result{}, helperErr
	}
	defer func() {
		if patchErr := patchHelper.Patch(ctx, host); patchErr != nil && err == nil {
			err = patchErr
		}
	}()

	if !host.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, host)
	}
	controllerutil.AddFinalizer(host, RackLinuxHostFinalizer)

	if err := r.releaseIfOrphaned(ctx, host); err != nil {
		return ctrl.Result{}, err
	}
	requeue, listed := r.observeTailnet(ctx, host)
	if listed {
		after, err := r.reconcileInstall(ctx, host)
		if err != nil {
			return ctrl.Result{}, err
		}
		if after > 0 && after < requeue {
			requeue = after
		}
		r.reconcileAMTPower(ctx, host)
		if after := r.reconcileAMT(ctx, host); after > 0 && after < requeue {
			requeue = after
		}
		if err := r.scaleUpPool(ctx, host); err != nil {
			return ctrl.Result{}, err
		}
	}
	if _, err := r.retireEmptyPools(ctx, host.Namespace); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: requeue}, nil
}

func (r *RackLinuxHostReconciler) releaseIfOrphaned(ctx context.Context, host *infrav1.RackLinuxHost) error {
	if host.Status.ClaimedBy == "" {
		return nil
	}
	machine := &infrav1.RackLinuxMachine{}
	err := r.Get(ctx, types.NamespacedName{Namespace: host.Namespace, Name: host.Status.ClaimedBy}, machine)
	switch {
	case err == nil:
		return nil
	case !apierrors.IsNotFound(err):
		return err
	}
	r.Recorder.Eventf(host, corev1.EventTypeWarning, "ClaimReleased",
		"Released the claim held by %s: no such RackLinuxMachine", host.Status.ClaimedBy)
	host.Status.ClaimedBy = ""
	host.Status.ClaimedAt = nil
	return nil
}

// observeTailnet records the host's device and returns when to look again,
// and whether it could list the tailnet's devices.
//
// A device is the host's when its OS hostname is the host's name and it
// carries every tag the host names. The newest connected one is current, else
// the newest. The others are removed only while the current one is connected
// and they are not: one box runs one install, so they are registrations of
// installs that box no longer holds.
func (r *RackLinuxHostReconciler) observeTailnet(ctx context.Context, host *infrav1.RackLinuxHost) (time.Duration, bool) {
	logger := log.FromContext(ctx)
	if r.Tailnet == nil {
		conditions.MarkFalse(host, TailnetJoinedCondition, "NoTailnetCredential", clusterv1.ConditionSeverityError,
			"the operator has no Tailscale OAuth client, so it cannot find hosts on the tailnet")
		return 10 * time.Minute, false
	}
	if len(host.Spec.Tailnet.Tags) == 0 {
		conditions.MarkFalse(host, TailnetJoinedCondition, "NoTailnetTags", clusterv1.ConditionSeverityError,
			"spec.tailnet.tags is empty; a device is only this host when it carries the host's tags")
		return 10 * time.Minute, false
	}

	devices, err := r.Tailnet.Devices(ctx)
	if err != nil {
		conditions.MarkFalse(host, TailnetJoinedCondition, "TailnetAPIError", clusterv1.ConditionSeverityWarning, "%v", err)
		return time.Minute, false
	}
	matches := hostDevices(devices, host)
	if len(matches) == 0 {
		host.Status.Tailnet = nil
		conditions.MarkFalse(host, TailnetJoinedCondition, "NotOnTailnet", clusterv1.ConditionSeverityInfo,
			"no tailnet device named %s carries %s; set its bootMAC so it installs itself when it netboots, or install it from a stick written by rack:write-install-usb",
			host.Name, strings.Join(host.Spec.Tailnet.Tags, ","))
		return time.Minute, true
	}

	current := matches[0]
	for _, d := range matches {
		if d.ConnectedToControl {
			current = d
			break
		}
	}
	var remaining []tailnet.Device
	for _, d := range matches {
		if d.NodeID == current.NodeID {
			continue
		}
		if !current.ConnectedToControl || d.ConnectedToControl {
			remaining = append(remaining, d)
			continue
		}
		if err := r.Tailnet.DeleteDevice(ctx, d.NodeID); err != nil {
			r.Recorder.Eventf(host, corev1.EventTypeWarning, "ReplacedDeviceNotRemoved",
				"Could not remove %s (%s), the device an earlier install left: %v", d.Name, d.NodeID, err)
			remaining = append(remaining, d)
			continue
		}
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "ReplacedDeviceRemoved",
			"Removed %s (%s, %s), the device an earlier install left; the host is now %s",
			d.Name, d.NodeID, d.IPv4(), current.NodeID)
		logger.Info("removed a rack host's replaced tailnet device", "host", host.Name, "device", d.NodeID)
	}

	if len(remaining) == 0 && current.ConnectedToControl && current.ShortName() != host.Name {
		if err := r.Tailnet.RenameDevice(ctx, current.NodeID, host.Name); err != nil {
			r.Recorder.Eventf(host, corev1.EventTypeWarning, "DeviceNotRenamed",
				"Could not rename %s to %s: %v", current.Name, host.Name, err)
		} else {
			r.Recorder.Eventf(host, corev1.EventTypeNormal, "DeviceRenamed", "Renamed %s to %s", current.Name, host.Name)
			if _, domain, ok := strings.Cut(current.Name, "."); ok {
				current.Name = host.Name + "." + domain
			} else {
				current.Name = host.Name
			}
		}
	}

	status := &infrav1.RackLinuxHostTailnetStatus{
		DeviceID:  current.NodeID,
		Name:      current.Name,
		Address:   current.IPv4(),
		Connected: current.ConnectedToControl,
	}
	if t := current.CreatedAt(); !t.IsZero() {
		status.Created = &metav1.Time{Time: t}
	}
	if t := current.LastSeenAt(); !t.IsZero() {
		status.LastSeen = &metav1.Time{Time: t}
	}
	host.Status.Tailnet = status

	switch {
	case len(remaining) > 0:
		ids := make([]string, 0, len(remaining))
		for _, d := range remaining {
			ids = append(ids, d.NodeID)
		}
		conditions.MarkFalse(host, TailnetJoinedCondition, "DuplicateDevices", clusterv1.ConditionSeverityWarning,
			"%s is current, and %d other device(s) also claim to be this host: %s", current.NodeID, len(remaining), strings.Join(ids, ", "))
	case status.Address == "":
		conditions.MarkFalse(host, TailnetJoinedCondition, "NoTailnetAddress", clusterv1.ConditionSeverityWarning,
			"device %s has no IPv4 address", current.NodeID)
	case !current.ConnectedToControl:
		conditions.MarkFalse(host, TailnetJoinedCondition, "Disconnected", clusterv1.ConditionSeverityWarning,
			"device %s is not connected to the tailnet", current.NodeID)
	default:
		conditions.MarkTrue(host, TailnetJoinedCondition)
	}
	return rackLinuxHostPollInterval, true
}

// hostDevices are the devices that claim to be host, newest first. A host
// without tags has none.
func hostDevices(devices []tailnet.Device, host *infrav1.RackLinuxHost) []tailnet.Device {
	if len(host.Spec.Tailnet.Tags) == 0 {
		return nil
	}
	var out []tailnet.Device
	for _, d := range devices {
		if strings.EqualFold(d.Hostname, host.Name) && d.HasTags(host.Spec.Tailnet.Tags) {
			out = append(out, d)
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		ti, tj := out[i].CreatedAt(), out[j].CreatedAt()
		if !ti.Equal(tj) {
			return ti.After(tj)
		}
		return out[i].NodeID > out[j].NodeID
	})
	return out
}

func (r *RackLinuxHostReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.RackLinuxHost{}).
		Complete(r)
}

func describeTailnet(host *infrav1.RackLinuxHost) string {
	if host.Status.Tailnet == nil {
		return "not on the tailnet"
	}
	return fmt.Sprintf("%s at %s", host.Status.Tailnet.Name, host.Status.Tailnet.Address)
}
