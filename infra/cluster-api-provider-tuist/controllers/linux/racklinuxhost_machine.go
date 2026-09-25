package linux

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

const (
	// RackLinuxHostLabel names the RackLinuxHost a Machine or RackLinuxMachine
	// is.
	RackLinuxHostLabel = "tuist.dev/rack-linux-host"
	// RackLinuxRoleLabel carries the host's role onto its Machine.
	RackLinuxRoleLabel = "tuist.dev/rack-linux-role"
)

// RackMachines is how the operator makes each rack Linux host a node: one CAPI
// Machine per host, in ClusterName, whose bootstrap data is BootstrapSecret,
// owning the host's RackLinuxMachine. Both are named after the host.
type RackMachines struct {
	ClusterName     string
	BootstrapSecret string
}

// reconcileMachine keeps the host's RackLinuxMachine and the CAPI Machine that
// owns it. A host is one box and upgrades in place, so it is its own Machine
// rather than a replica a MachineDeployment claims boxes for.
func (r *RackLinuxHostReconciler) reconcileMachine(ctx context.Context, host *infrav1.RackLinuxHost) error {
	if r.Machines == nil {
		return nil
	}
	labels := map[string]string{
		clusterv1.ClusterNameLabel: r.Machines.ClusterName,
		RackLinuxHostLabel:         host.Name,
		RackLinuxRoleLabel:         host.Spec.Role,
	}

	rlm := &infrav1.RackLinuxMachine{ObjectMeta: metav1.ObjectMeta{Name: host.Name, Namespace: host.Namespace}}
	if _, err := controllerutil.CreateOrPatch(ctx, r.Client, rlm, func() error {
		if rlm.Labels == nil {
			rlm.Labels = map[string]string{}
		}
		for k, v := range labels {
			rlm.Labels[k] = v
		}
		rlm.Spec.Host = host.Name
		return nil
	}); err != nil {
		return fmt.Errorf("keep RackLinuxMachine %s: %w", host.Name, err)
	}

	machine := &clusterv1.Machine{ObjectMeta: metav1.ObjectMeta{Name: host.Name, Namespace: host.Namespace}}
	op, err := controllerutil.CreateOrPatch(ctx, r.Client, machine, func() error {
		if machine.Labels == nil {
			machine.Labels = map[string]string{}
		}
		for k, v := range labels {
			machine.Labels[k] = v
		}
		if err := controllerutil.SetControllerReference(host, machine, r.Client.Scheme()); err != nil {
			return err
		}
		if machine.CreationTimestamp.IsZero() {
			secret := r.Machines.BootstrapSecret
			machine.Spec = clusterv1.MachineSpec{
				ClusterName: r.Machines.ClusterName,
				Bootstrap:   clusterv1.Bootstrap{DataSecretName: &secret},
				InfrastructureRef: corev1.ObjectReference{
					APIVersion: infrav1.GroupVersion.String(),
					Kind:       "RackLinuxMachine",
					Name:       rlm.Name,
					Namespace:  rlm.Namespace,
				},
			}
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("keep Machine %s: %w", host.Name, err)
	}
	if op == controllerutil.OperationResultCreated {
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "MachineCreated", "Created Machine %s, which makes %s a node", machine.Name, host.Spec.Hostname)
	}
	return nil
}

// observeHardware records what the machine announced about itself, from the
// RackLinuxCandidate its install stick left under the same UUID, and the boot
// MAC in effect: spec.bootMAC, else the management port it announced.
func (r *RackLinuxHostReconciler) observeHardware(ctx context.Context, host *infrav1.RackLinuxHost) error {
	candidate := &infrav1.RackLinuxCandidate{}
	err := r.Get(ctx, types.NamespacedName{Namespace: host.Namespace, Name: host.Name}, candidate)
	switch {
	case apierrors.IsNotFound(err):
		candidate = nil
	case err != nil:
		return fmt.Errorf("read RackLinuxCandidate %s: %w", host.Name, err)
	}
	if candidate != nil && (candidate.Status.Product != "" || candidate.Status.Serial != "") {
		host.Status.Hardware = &infrav1.RackLinuxHostHardware{Product: candidate.Status.Product, Serial: candidate.Status.Serial}
	}
	switch {
	case host.Spec.BootMAC != "":
		host.Status.BootMAC = host.Spec.BootMAC
	case candidate != nil && candidate.Status.BootMAC != "":
		host.Status.BootMAC = candidate.Status.BootMAC
	}
	return nil
}
