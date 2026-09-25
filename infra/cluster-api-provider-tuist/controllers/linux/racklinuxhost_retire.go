package linux

import (
	"context"
	"fmt"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/utils/ptr"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/tailnet"
)

const (
	// rackRetireRequeue is how soon a deleted host is looked at again while a
	// machine still holds it.
	rackRetireRequeue = 15 * time.Second

	// rackEmptyPoolGrace spares a new MachineDeployment: Helm creates it before
	// the RackLinuxHosts of its pool.
	rackEmptyPoolGrace = 10 * time.Minute

	rackLinuxMachineTemplateKind = "RackLinuxMachineTemplate"
)

// reconcileDelete retires a deleted host. It withdraws the host's install, has
// the machine holding it removed and waits for the claim to be released, so
// the machine can still stop the host's kubelet over the tailnet. Then it
// removes the host's egress Service, tailnet devices, host key pins and console
// password, and drops the finalizer.
func (r *RackLinuxHostReconciler) reconcileDelete(ctx context.Context, host *infrav1.RackLinuxHost) (ctrl.Result, error) {
	if !controllerutil.ContainsFinalizer(host, RackLinuxHostFinalizer) {
		return ctrl.Result{}, nil
	}
	if r.Install != nil && host.Status.Install != nil {
		keyID := host.Status.Install.KeyID
		if err := r.withdrawInstall(ctx, host); err != nil {
			return ctrl.Result{}, err
		}
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "InstallWithdrawn", "Withdrew install %s: %s is being deleted", keyID, host.Name)
	}
	if err := r.releaseIfOrphaned(ctx, host); err != nil {
		return ctrl.Result{}, err
	}
	if host.Status.ClaimedBy != "" {
		if err := r.removeMachine(ctx, host); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{RequeueAfter: rackRetireRequeue}, nil
	}
	if err := r.egress().remove(ctx, r.Client, host.Name); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.removeDevices(ctx, host); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.removeConsolePassword(ctx, host); err != nil {
		return ctrl.Result{}, err
	}
	controllerutil.RemoveFinalizer(host, RackLinuxHostFinalizer)
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "Retired", "Retired %s", host.Name)
	log.FromContext(ctx).Info("retired a rack Linux host", "host", host.Name)
	return ctrl.Result{}, nil
}

// removeMachine has the machine holding a deleted host removed. While the
// MachineDeployment has more replicas than the pool's other hosts keep, the
// Machine is marked for its MachineSet to delete and the MachineDeployment is
// scaled down to them; otherwise the Machine is deleted and its replacement
// claims another host. The machine's delete releases the claim.
func (r *RackLinuxHostReconciler) removeMachine(ctx context.Context, host *infrav1.RackLinuxHost) error {
	holder := &infrav1.RackLinuxMachine{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: host.Namespace, Name: host.Status.ClaimedBy}, holder); err != nil {
		return client.IgnoreNotFound(err)
	}
	if !holder.DeletionTimestamp.IsZero() {
		return nil
	}
	machine, err := util.GetOwnerMachine(ctx, r.Client, holder.ObjectMeta)
	if err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("get the Machine owning %s: %w", holder.Name, err)
	}
	if machine == nil {
		if err := r.Delete(ctx, holder); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete RackLinuxMachine %s: %w", holder.Name, err)
		}
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "MachineDeleted",
			"Deleted RackLinuxMachine %s, which holds %s and has no Machine", holder.Name, host.Name)
		return nil
	}
	if !machine.DeletionTimestamp.IsZero() {
		return nil
	}

	md, err := r.poolDeploymentOf(ctx, host, machine)
	if err != nil {
		return err
	}
	if md != nil {
		keep, err := r.poolKeeps(ctx, host)
		if err != nil {
			return err
		}
		if md.Spec.Replicas != nil && *md.Spec.Replicas > keep {
			if machine.Annotations[clusterv1.DeleteMachineAnnotation] != "true" {
				base := machine.DeepCopy()
				if machine.Annotations == nil {
					machine.Annotations = map[string]string{}
				}
				machine.Annotations[clusterv1.DeleteMachineAnnotation] = "true"
				if err := r.Patch(ctx, machine, client.MergeFrom(base)); err != nil {
					return fmt.Errorf("mark Machine %s for deletion: %w", machine.Name, err)
				}
			}
			from := *md.Spec.Replicas
			base := md.DeepCopy()
			md.Spec.Replicas = ptr.To(keep)
			if err := r.Patch(ctx, md, client.MergeFrom(base)); err != nil {
				return fmt.Errorf("scale MachineDeployment %s to %d: %w", md.Name, keep, err)
			}
			r.Recorder.Eventf(host, corev1.EventTypeNormal, "PoolScaledDown",
				"Scaled MachineDeployment %s from %d to %d, marking Machine %s, which holds %s, for its MachineSet to delete",
				md.Name, from, keep, machine.Name, host.Name)
			return nil
		}
	}
	if err := r.Delete(ctx, machine); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete Machine %s: %w", machine.Name, err)
	}
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "MachineDeleted",
		"Deleted Machine %s, which holds %s; a replacement claims another host of pool %s", machine.Name, host.Name, host.Spec.Pool)
	return nil
}

// poolDeploymentOf is the MachineDeployment of the host's pool that the
// machine belongs to, if any.
func (r *RackLinuxHostReconciler) poolDeploymentOf(ctx context.Context, host *infrav1.RackLinuxHost, machine *clusterv1.Machine) (*clusterv1.MachineDeployment, error) {
	name := machine.Labels[clusterv1.MachineDeploymentNameLabel]
	if name == "" || host.Spec.Pool == "" {
		return nil, nil
	}
	md := &clusterv1.MachineDeployment{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: name}, md); err != nil {
		return nil, client.IgnoreNotFound(err)
	}
	if md.Labels[RackPoolLabel] != host.Spec.Pool {
		return nil, nil
	}
	return md, nil
}

// poolKeeps counts the other hosts of the host's pool that keep a machine: the
// ones on the tailnet, and the ones off it still holding one.
func (r *RackLinuxHostReconciler) poolKeeps(ctx context.Context, host *infrav1.RackLinuxHost) (int32, error) {
	hosts := &infrav1.RackLinuxHostList{}
	if err := r.List(ctx, hosts, client.InNamespace(host.Namespace)); err != nil {
		return 0, err
	}
	var keep int32
	for i := range hosts.Items {
		h := &hosts.Items[i]
		if h.Name == host.Name || h.Spec.Pool != host.Spec.Pool || !h.DeletionTimestamp.IsZero() {
			continue
		}
		if (h.Status.Tailnet != nil && h.Status.Tailnet.Connected) || h.Status.ClaimedBy != "" {
			keep++
		}
	}
	return keep, nil
}

// removeDevices deletes the device the host recorded and any other device that
// is the host's, with their host key pins.
func (r *RackLinuxHostReconciler) removeDevices(ctx context.Context, host *infrav1.RackLinuxHost) error {
	recorded := tailnetDeviceID(host)
	var pins []string
	if recorded != "" {
		pins = append(pins, recorded)
	}
	if r.Tailnet == nil {
		if recorded != "" {
			r.Recorder.Eventf(host, corev1.EventTypeWarning, "DeviceNotRemoved",
				"The operator has no Tailscale OAuth client, so %s's device %s stays on the tailnet; remove it in the admin console", host.Name, recorded)
		}
	} else {
		devices, err := r.Tailnet.Devices(ctx)
		if err != nil {
			return fmt.Errorf("list tailnet devices: %w", err)
		}
		targets := hostDevices(devices, host)
		for _, d := range devices {
			if d.NodeID == recorded && !containsDevice(targets, recorded) {
				targets = append([]tailnet.Device{d}, targets...)
			}
		}
		for _, d := range targets {
			if err := r.Tailnet.DeleteDevice(ctx, d.NodeID); err != nil {
				return err
			}
			r.Recorder.Eventf(host, corev1.EventTypeNormal, "DeviceRemoved", "Removed %s (%s, %s) from the tailnet", d.Name, d.NodeID, d.IPv4())
			if d.NodeID != recorded {
				pins = append(pins, d.NodeID)
			}
		}
	}
	host.Status.Tailnet = nil
	if r.CredentialsManager == nil {
		return nil
	}
	for _, device := range pins {
		if err := r.CredentialsManager.DeleteMachineBootstrap(ctx, rackLinuxPinKey(host.Name, device)); err != nil {
			return err
		}
	}
	return nil
}

func containsDevice(devices []tailnet.Device, id string) bool {
	for _, d := range devices {
		if d.NodeID == id {
			return true
		}
	}
	return false
}

// removeConsolePassword deletes the host's key from the <fleet>-console
// Secret.
func (r *RackLinuxHostReconciler) removeConsolePassword(ctx context.Context, host *infrav1.RackLinuxHost) error {
	if r.Install == nil || r.CredentialsManager == nil {
		return nil
	}
	secret := &corev1.Secret{}
	err := r.Get(ctx, types.NamespacedName{Namespace: r.CredentialsManager.Namespace, Name: rackConsoleSecretName(r.Install.FleetName)}, secret)
	switch {
	case apierrors.IsNotFound(err):
		return nil
	case err != nil:
		return err
	}
	if _, ok := secret.Data[host.Name]; !ok {
		return nil
	}
	delete(secret.Data, host.Name)
	if err := r.Update(ctx, secret); err != nil {
		return fmt.Errorf("remove %s's console password from Secret %s: %w", host.Name, secret.Name, err)
	}
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "ConsolePasswordRemoved", "Removed %s's console password from Secret %s", host.Name, secret.Name)
	return nil
}

// retireEmptyPools deletes a rack Linux pool's MachineDeployment once no
// RackLinuxHost is in the pool, it is scaled to zero and none of its Machines
// is left, and then the RackLinuxMachineTemplate it names unless another
// MachineDeployment names it too. It reports whether such a MachineDeployment
// is still waiting for its Machines to go.
func (r *RackLinuxHostReconciler) retireEmptyPools(ctx context.Context, namespace string) (bool, error) {
	deployments := &clusterv1.MachineDeploymentList{}
	if err := r.List(ctx, deployments, client.InNamespace(namespace)); err != nil {
		return false, err
	}
	hosts := &infrav1.RackLinuxHostList{}
	if err := r.List(ctx, hosts, client.InNamespace(namespace)); err != nil {
		return false, err
	}
	pools := map[string]bool{}
	for i := range hosts.Items {
		pools[hosts.Items[i].Spec.Pool] = true
	}

	pending := false
	retired := map[string]bool{}
	for i := range deployments.Items {
		md := &deployments.Items[i]
		pool, ok := md.Labels[RackPoolLabel]
		if !ok || md.Spec.Template.Spec.InfrastructureRef.Kind != rackLinuxMachineTemplateKind || pools[pool] {
			continue
		}
		if !md.DeletionTimestamp.IsZero() || md.Spec.Replicas == nil || *md.Spec.Replicas != 0 {
			continue
		}
		if r.now().Sub(md.CreationTimestamp.Time) < rackEmptyPoolGrace {
			pending = true
			continue
		}
		machines := &clusterv1.MachineList{}
		if err := r.List(ctx, machines, client.InNamespace(namespace), client.MatchingLabels{clusterv1.MachineDeploymentNameLabel: md.Name}); err != nil {
			return pending, err
		}
		if md.Status.Replicas != 0 || len(machines.Items) > 0 {
			pending = true
			continue
		}
		if err := r.Delete(ctx, md); err != nil && !apierrors.IsNotFound(err) {
			return pending, fmt.Errorf("delete MachineDeployment %s: %w", md.Name, err)
		}
		retired[md.Name] = true
		r.Recorder.Eventf(md, corev1.EventTypeNormal, "RackPoolRetired",
			"Deleted MachineDeployment %s: no RackLinuxHost is in pool %s and it has no Machines", md.Name, pool)
		log.FromContext(ctx).Info("deleted an empty rack pool's MachineDeployment", "machineDeployment", md.Name, "pool", pool)
		if err := r.deleteUnusedTemplate(ctx, md, deployments.Items, retired); err != nil {
			return pending, err
		}
	}
	return pending, nil
}

// deleteUnusedTemplate deletes the RackLinuxMachineTemplate a retired
// MachineDeployment names, unless a MachineDeployment still in place names it.
func (r *RackLinuxHostReconciler) deleteUnusedTemplate(ctx context.Context, md *clusterv1.MachineDeployment, deployments []clusterv1.MachineDeployment, retired map[string]bool) error {
	ref := md.Spec.Template.Spec.InfrastructureRef
	if ref.Kind != rackLinuxMachineTemplateKind || ref.Name == "" || !strings.HasPrefix(ref.APIVersion, infrav1.GroupVersion.Group+"/") {
		return nil
	}
	namespace := firstNonEmpty(ref.Namespace, md.Namespace)
	for i := range deployments {
		other := &deployments[i]
		if retired[other.Name] {
			continue
		}
		o := other.Spec.Template.Spec.InfrastructureRef
		if o.Kind == ref.Kind && o.Name == ref.Name && firstNonEmpty(o.Namespace, other.Namespace) == namespace {
			return nil
		}
	}
	template := &infrav1.RackLinuxMachineTemplate{ObjectMeta: metav1.ObjectMeta{Name: ref.Name, Namespace: namespace}}
	if err := r.Delete(ctx, template); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("delete RackLinuxMachineTemplate %s: %w", ref.Name, err)
	}
	r.Recorder.Eventf(md, corev1.EventTypeNormal, "RackPoolTemplateDeleted",
		"Deleted RackLinuxMachineTemplate %s, which no other MachineDeployment names", ref.Name)
	return nil
}
