package linux

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
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

// HardwarePinnedCondition reports whether the host took its hardware from what
// the machine first announced.
const HardwarePinnedCondition clusterv1.ConditionType = "HardwarePinned"

// observeHardware takes what the machine announced about itself from the
// RackLinuxCandidate its install stick left under the same UUID, once, and
// records the boot MAC in effect: spec.bootMAC, else the management port it
// announced. The boot server hands the host's seed only to the NICs taken, so
// they are never taken from a candidate another announcement conflicts with,
// nor again later.
func (r *RackLinuxHostReconciler) observeHardware(ctx context.Context, host *infrav1.RackLinuxHost) error {
	if hw := host.Status.Hardware; hw == nil || hw.PinnedAt == nil {
		candidate := &infrav1.RackLinuxCandidate{}
		err := r.Get(ctx, types.NamespacedName{Namespace: host.Namespace, Name: host.Name}, candidate)
		switch {
		case apierrors.IsNotFound(err) || err == nil && candidate.Status.UUID != host.Name:
			conditions.MarkFalse(host, HardwarePinnedCondition, "NotAnnounced", clusterv1.ConditionSeverityInfo,
				"the machine has not announced itself; boot its install stick once")
		case err != nil:
			return fmt.Errorf("read RackLinuxCandidate %s: %w", host.Name, err)
		case candidate.Status.Conflict != nil:
			c := candidate.Status.Conflict
			conditions.MarkFalse(host, HardwarePinnedCondition, "CandidateConflict", clusterv1.ConditionSeverityWarning,
				"an announcement from %s at %s conflicts with what the machine first announced (%s); check what is on the management segment, then delete RackLinuxCandidate %s and boot the machine's install stick",
				c.Address, c.At.UTC().Format(time.RFC3339), c.Reason, candidate.Name)
		default:
			pinned := metav1.NewTime(r.now())
			host.Status.Hardware = &infrav1.RackLinuxHostHardware{
				Product:  candidate.Status.Product,
				Serial:   candidate.Status.Serial,
				NICs:     candidate.Status.NICs,
				BootMAC:  candidate.Status.BootMAC,
				PinnedAt: &pinned,
			}
			r.Recorder.Eventf(host, corev1.EventTypeNormal, "HardwarePinned",
				"Took %s's hardware from what it announced: serial %q, boot MAC %s, %d NICs", host.Spec.Hostname, candidate.Status.Serial, candidate.Status.BootMAC, len(candidate.Status.NICs))
			if host.Status.TPM == nil && candidate.Status.EK != "" {
				host.Status.TPM = pinnedTPM(candidate.Status.EK, pinned.Time)
			}
		}
	}
	if hw := host.Status.Hardware; hw != nil && hw.PinnedAt != nil {
		conditions.MarkTrue(host, HardwarePinnedCondition)
	}
	switch {
	case host.Spec.BootMAC != "":
		host.Status.BootMAC = host.Spec.BootMAC
	case host.Status.Hardware != nil && host.Status.Hardware.PinnedAt != nil:
		host.Status.BootMAC = host.Status.Hardware.BootMAC
	default:
		host.Status.BootMAC = ""
	}
	return nil
}
