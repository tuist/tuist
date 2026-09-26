package macos

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/utils/ptr"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/collections"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

const (
	// RackHostLabel names the RackHost a Machine or RackAppleSiliconMachine
	// is.
	RackHostLabel = "tuist.dev/rack-host"

	// rackMachineDeletingRequeue is how soon a host is looked at again while
	// its Machine is being deleted.
	rackMachineDeletingRequeue = 15 * time.Second
)

// RackMachines is how the operator makes each rack host a node: one CAPI
// Machine per host in ClusterName, whose bootstrap data is BootstrapSecret,
// owning the host's RackAppleSiliconMachine in FleetName.
type RackMachines struct {
	ClusterName     string
	BootstrapSecret string
	FleetName       string
}

// rackMachineName keeps the fleet's name in its Nodes' names, which is what
// dashboards and alerts on the Mac fleets select a fleet by.
func rackMachineName(fleetName, hostName string) string {
	return fleetName + "-" + hostName
}

// reconcileMachine keeps the host's RackAppleSiliconMachine and the CAPI
// Machine that owns it, with the host as the Machine's controller. It deletes
// the Machine of a parked host, and of one whose MachineHealthCheck asks the
// owner to remediate it, and makes it again once it is gone. A non-zero result
// means a Machine is being deleted.
func (r *RackHostReconciler) reconcileMachine(ctx context.Context, host *infrav1.RackHost) (ctrl.Result, error) {
	if r.Machines == nil {
		return ctrl.Result{}, nil
	}
	if host.Status.Machine == "" {
		name, err := r.machineNameFor(ctx, host)
		if err != nil {
			return ctrl.Result{}, err
		}
		host.Status.Machine = name
	}
	key := types.NamespacedName{Namespace: host.Namespace, Name: host.Status.Machine}

	machine := &clusterv1.Machine{}
	if err := r.Get(ctx, key, machine); err != nil {
		if !apierrors.IsNotFound(err) {
			return ctrl.Result{}, err
		}
		machine = nil
	}
	infra := &infrav1.RackAppleSiliconMachine{}
	if err := r.Get(ctx, key, infra); err != nil {
		if !apierrors.IsNotFound(err) {
			return ctrl.Result{}, err
		}
		infra = nil
	}
	if (machine != nil && !machine.DeletionTimestamp.IsZero()) || (infra != nil && !infra.DeletionTimestamp.IsZero()) {
		return ctrl.Result{RequeueAfter: rackMachineDeletingRequeue}, nil
	}

	if host.Spec.Parked {
		if machine != nil {
			if err := r.Delete(ctx, machine); err != nil && !apierrors.IsNotFound(err) {
				return ctrl.Result{}, fmt.Errorf("delete Machine %s of parked host: %w", machine.Name, err)
			}
			r.Recorder.Eventf(host, corev1.EventTypeNormal, "MachineDeleted", "Deleted Machine %s: %s is parked", machine.Name, host.Name)
			return ctrl.Result{RequeueAfter: rackMachineDeletingRequeue}, nil
		}
		if infra != nil {
			if err := r.Delete(ctx, infra); err != nil && !apierrors.IsNotFound(err) {
				return ctrl.Result{}, fmt.Errorf("delete RackAppleSiliconMachine %s of parked host: %w", infra.Name, err)
			}
			return ctrl.Result{RequeueAfter: rackMachineDeletingRequeue}, nil
		}
		return ctrl.Result{}, nil
	}

	if machine != nil && collections.IsUnhealthyAndOwnerRemediated(machine) {
		if err := r.Delete(ctx, machine); err != nil && !apierrors.IsNotFound(err) {
			return ctrl.Result{}, fmt.Errorf("delete unhealthy Machine %s: %w", machine.Name, err)
		}
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "MachineRemediated",
			"Deleted Machine %s, which its MachineHealthCheck found unhealthy (%s); a new one bootstraps %s again",
			machine.Name, conditions.GetMessage(machine, clusterv1.MachineHealthCheckSucceededCondition), host.Name)
		return ctrl.Result{RequeueAfter: rackMachineDeletingRequeue}, nil
	}

	if err := r.keepInfraMachine(ctx, host, key); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{}, r.keepMachine(ctx, host, key)
}

func (r *RackHostReconciler) machineLabels(host *infrav1.RackHost) map[string]string {
	return map[string]string{
		clusterv1.ClusterNameLabel: r.Machines.ClusterName,
		"tuist.dev/fleet":          r.Machines.FleetName,
		RackHostLabel:              host.Name,
	}
}

// machineSetLabels are the labels a MachineSet stamps on the Machines it
// makes, and selects them by.
var machineSetLabels = []string{
	clusterv1.MachineSetNameLabel,
	clusterv1.MachineDeploymentNameLabel,
	clusterv1.MachineDeploymentUniqueLabel,
}

func (r *RackHostReconciler) keepInfraMachine(ctx context.Context, host *infrav1.RackHost, key types.NamespacedName) error {
	infra := &infrav1.RackAppleSiliconMachine{ObjectMeta: metav1.ObjectMeta{Name: key.Name, Namespace: key.Namespace}}
	_, err := controllerutil.CreateOrPatch(ctx, r.Client, infra, func() error {
		setRackLabels(&infra.ObjectMeta, r.machineLabels(host))
		infra.Spec.Host = host.Name
		infra.Spec.FleetName = r.Machines.FleetName
		sizing := host.Spec.Machine
		infra.Spec.HostCPU = sizing.HostCPU
		infra.Spec.HostMemoryMB = sizing.HostMemoryMB
		infra.Spec.GuestCapacity = sizing.GuestCapacity
		infra.Spec.MaxPods = sizing.MaxPods
		infra.Spec.RunnerCacheVolumeGiB = nil
		if gib := sizing.RunnerCacheVolumeGiB; gib != nil {
			infra.Spec.RunnerCacheVolumeGiB = ptr.To(*gib)
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("keep RackAppleSiliconMachine %s: %w", key.Name, err)
	}
	return nil
}

// keepMachine keeps the CAPI Machine that makes the host a node. A Machine a
// MachineSet made for this host, which has the host's providerID, is adopted:
// it loses the MachineSet's owner reference and labels, so the MachineSet
// neither deletes it nor counts it, and keeps its name, its Node and its host.
func (r *RackHostReconciler) keepMachine(ctx context.Context, host *infrav1.RackHost, key types.NamespacedName) error {
	providerID := rackProviderID(host)
	machine := &clusterv1.Machine{ObjectMeta: metav1.ObjectMeta{Name: key.Name, Namespace: key.Namespace}}
	adoptedFrom := ""
	op, err := controllerutil.CreateOrPatch(ctx, r.Client, machine, func() error {
		if ptr.Deref(machine.Spec.ProviderID, "") == providerID {
			adoptedFrom = releaseFromMachineSet(machine)
		}
		setRackLabels(&machine.ObjectMeta, r.machineLabels(host))
		if err := controllerutil.SetControllerReference(host, machine, r.Scheme); err != nil {
			return err
		}
		if machine.ResourceVersion == "" {
			secret := r.Machines.BootstrapSecret
			machine.Spec = clusterv1.MachineSpec{
				ClusterName: r.Machines.ClusterName,
				Bootstrap:   clusterv1.Bootstrap{DataSecretName: &secret},
				InfrastructureRef: corev1.ObjectReference{
					APIVersion: infrav1.GroupVersion.String(),
					Kind:       "RackAppleSiliconMachine",
					Name:       key.Name,
					Namespace:  key.Namespace,
				},
			}
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("keep Machine %s: %w", key.Name, err)
	}
	switch {
	case op == controllerutil.OperationResultCreated:
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "MachineCreated", "Created Machine %s, which makes %s a node", machine.Name, host.Name)
	case adoptedFrom != "":
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "MachineAdopted",
			"Adopted Machine %s from MachineSet %s: its providerID %s is %s's", machine.Name, adoptedFrom, providerID, host.Name)
	}
	return nil
}

// releaseFromMachineSet drops a Machine's MachineSet owner references and the
// labels a MachineSet selects it by, and returns the MachineSet it released
// the Machine from, if any.
func releaseFromMachineSet(machine *clusterv1.Machine) string {
	released := ""
	var kept []metav1.OwnerReference
	for _, ref := range machine.OwnerReferences {
		if ref.Kind == "MachineSet" && ref.APIVersion == clusterv1.GroupVersion.String() {
			released = ref.Name
			continue
		}
		kept = append(kept, ref)
	}
	machine.OwnerReferences = kept
	for _, label := range machineSetLabels {
		delete(machine.Labels, label)
	}
	return released
}

func setRackLabels(meta *metav1.ObjectMeta, labels map[string]string) {
	if meta.Labels == nil {
		meta.Labels = map[string]string{}
	}
	for _, label := range machineSetLabels {
		delete(meta.Labels, label)
	}
	for k, v := range labels {
		meta.Labels[k] = v
	}
}

// machineNameFor names the host's Machine: a Machine that already has the
// host's providerID keeps its name, and the controller adopts it; otherwise
// it is <fleet>-<host>. A Machine with the host's providerID that another
// RackHost controls means two hosts declare one box, and the host gets none.
func (r *RackHostReconciler) machineNameFor(ctx context.Context, host *infrav1.RackHost) (string, error) {
	providerID := rackProviderID(host)
	machines := &clusterv1.MachineList{}
	if err := r.List(ctx, machines, client.InNamespace(host.Namespace),
		client.MatchingLabels{clusterv1.ClusterNameLabel: r.Machines.ClusterName}); err != nil {
		return "", fmt.Errorf("list Machines: %w", err)
	}
	for i := range machines.Items {
		m := &machines.Items[i]
		if m.Spec.InfrastructureRef.Kind != "RackAppleSiliconMachine" || ptr.Deref(m.Spec.ProviderID, "") != providerID {
			continue
		}
		if owner := metav1.GetControllerOf(m); owner != nil && owner.Kind == "RackHost" && owner.Name != host.Name {
			r.Recorder.Eventf(host, corev1.EventTypeWarning, "DuplicateHost",
				"Machine %s of RackHost %s has this host's providerID %s: both declare one box", m.Name, owner.Name, providerID)
			return "", fmt.Errorf("RackHost %s already has a Machine for %s", owner.Name, providerID)
		}
		return m.Name, nil
	}
	return rackMachineName(r.Machines.FleetName, host.Name), nil
}
