package linux

import (
	"context"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
)

// Spec.EgressBudgetMbps is stamped identically onto every machine a MachineTemplate
// clones, so it cannot describe a fleet whose boxes differ. The reconciler reads
// each box's public egress limitation from OVH and lets it raise the node's budget
// above the configured one; the policy itself is shared.DecideEgress.

// EgressDiscoveredCondition reports the last attempt to read the box's egress
// limitation from OVH. False with EgressReadFailedReason counts consecutive
// failures in its message.
const EgressDiscoveredCondition clusterv1.ConditionType = "EgressDiscovered"

const (
	EgressReadFailedReason        = "ReadFailed"
	EgressUnresolvedReason        = "Unresolved"
	EgressDiscoveryDisabledReason = "Disabled"
)

const (
	egressProvider = "ovh"

	// The reading tracks a contract; the machine reconciles every 10 minutes.
	egressDiscoveryRefreshInterval = 24 * time.Hour
	// A machine in the Provisioned-but-not-Ready tail requeues every 20s, which
	// would turn a permanently failing read into three calls a minute.
	egressReadRetryInterval = 10 * time.Minute
)

// reconcileNodeEgress decides the budget the node should advertise, records it in
// status, and patches the node. Status carries the intent, so a failed node patch
// is simply retried by the next reconcile.
func (r *OVHDedicatedMachineReconciler) reconcileNodeEgress(ctx context.Context, machine *infrav1.OVHDedicatedMachine, node *corev1.Node) error {
	advertised := shared.NodeEgressMbps(node)
	configured := machine.Spec.EgressBudgetMbps

	if configured <= 0 {
		machine.Status.Egress = nil
		conditions.Delete(machine, EgressDiscoveredCondition)
		if err := shared.ReconcileNodeEgressCapacity(ctx, r.Client, node, 0); err != nil {
			return err
		}
		shared.ForgetEgressMetrics(machine.Name)
		r.recordEgressBudgetChange(machine, advertised, 0, "")
		return nil
	}

	egress := machine.Status.Egress
	if egress == nil || egress.ServiceName != machine.Status.ServiceName {
		egress = &infrav1.EgressStatus{ServiceName: machine.Status.ServiceName}
		shared.ForgetEgressReported(machine.Name)
	}

	disabled := shared.EgressDiscoveryDisabled(machine)
	now := time.Now()
	if !disabled && egress.ServiceName != "" && r.egressReadDue(machine, egress, now) {
		r.readEgress(ctx, machine, egress, now)
	}

	decision := shared.DecideEgress(shared.EgressInputs{
		ConfiguredMbps: configured,
		BudgetMbps:     egress.BudgetMbps,
		Source:         egress.Source,
		ReportedMbps:   egress.ReportedMbps,
		OverrideMbps:   shared.EgressOverrideMbps(machine),
		Disabled:       disabled,
	})
	egress.BudgetMbps, egress.Source = decision.BudgetMbps, decision.Source
	machine.Status.Egress = egress
	if disabled {
		conditions.MarkFalse(machine, EgressDiscoveredCondition, EgressDiscoveryDisabledReason, clusterv1.ConditionSeverityInfo,
			"%s is set; the node keeps its %d Mbps budget", shared.DisableEgressDiscoveryAnnotation, decision.NodeMbps)
	}

	if err := shared.ReconcileNodeEgressCapacity(ctx, r.Client, node, decision.NodeMbps); err != nil {
		return err
	}
	shared.RecordEgressBudgets(egressProvider, machine.Name, machine.Spec.FleetName, configured, decision.NodeMbps, decision.Source)
	r.recordEgressBudgetChange(machine, advertised, decision.NodeMbps, decision.Source)
	return nil
}

// egressReadDue bounds the OVH calls: daily after a usable or unusable answer,
// every 10 minutes while calls fail, and immediately after discovery is re-enabled.
func (r *OVHDedicatedMachineReconciler) egressReadDue(machine *infrav1.OVHDedicatedMachine, egress *infrav1.EgressStatus, now time.Time) bool {
	if egress.AttemptedAt == nil {
		return true
	}
	if conditions.GetReason(machine, EgressDiscoveredCondition) == EgressDiscoveryDisabledReason {
		return true
	}
	interval := egressDiscoveryRefreshInterval
	if egress.ReadFailures > 0 {
		interval = egressReadRetryInterval
	}
	return now.Sub(egress.AttemptedAt.Time) >= interval
}

// readEgress records what OVH reports. A failed or unusable read leaves the last
// usable reading in place, so an OVH outage degrades to advertising what the node
// already advertises.
func (r *OVHDedicatedMachineReconciler) readEgress(ctx context.Context, machine *infrav1.OVHDedicatedMachine, egress *infrav1.EgressStatus, now time.Time) {
	logger := log.FromContext(ctx)
	egress.AttemptedAt = &metav1.Time{Time: now}

	discovered, err := r.OVHClient.PublicEgress(ctx, egress.ServiceName)
	if err != nil {
		egress.ReadFailures++
		conditions.MarkFalse(machine, EgressDiscoveredCondition, EgressReadFailedReason, clusterv1.ConditionSeverityWarning,
			"%d consecutive failed reads for %s; last: %v", egress.ReadFailures, egress.ServiceName, err)
		logger.Error(err, "reading the box's egress limitation failed; keeping the last reading",
			"service", egress.ServiceName, "failures", egress.ReadFailures)
		return
	}
	egress.ReadFailures = 0

	if discovered.Mbps <= 0 {
		conditions.MarkFalse(machine, EgressDiscoveredCondition, EgressUnresolvedReason, clusterv1.ConditionSeverityInfo,
			"OVH reported no usable egress limitation for %s (unit %q, value %d)", egress.ServiceName, discovered.Unit, discovered.Value)
		logger.Info("OVH reported no egress limitation we could read; keeping the last reading",
			"service", egress.ServiceName, "unit", discovered.Unit, "value", discovered.Value)
		return
	}

	egress.ReportedMbps = discovered.Mbps
	egress.Tier = discovered.Tier
	egress.ResolvedAt = &metav1.Time{Time: now}
	conditions.MarkTrue(machine, EgressDiscoveredCondition)
	shared.RecordEgressReported(egressProvider, machine.Name, machine.Spec.FleetName, egress.ServiceName, discovered.Tier, discovered.Mbps)
}

// recordEgressBudgetChange emits one event per transition of the node's advertised
// budget, naming both numbers and what decided the new one.
func (r *OVHDedicatedMachineReconciler) recordEgressBudgetChange(machine *infrav1.OVHDedicatedMachine, from, to int32, source string) {
	switch {
	case from == to:
	case to == 0:
		r.event(machine, "EgressBudgetRemoved", "node egress budget of %d Mbps removed (spec.egressBudgetMbps is 0)", from)
	case from == 0:
		r.event(machine, "EgressBudgetIncreased", "node egress budget set to %d Mbps (%s)", to, egressSourceDescription(machine, source))
	case to > from:
		r.event(machine, "EgressBudgetIncreased", "node egress budget raised from %d to %d Mbps (%s)", from, to, egressSourceDescription(machine, source))
	default:
		r.event(machine, "EgressBudgetReduced", "node egress budget reduced from %d to %d Mbps (%s)", from, to, egressSourceDescription(machine, source))
	}
}

func egressSourceDescription(machine *infrav1.OVHDedicatedMachine, source string) string {
	switch source {
	case shared.EgressSourceManual:
		return "pinned by " + shared.EgressOverrideAnnotation
	case shared.EgressSourceDiscovery:
		return "reported by OVH for " + machine.Status.ServiceName
	default:
		return "spec.egressBudgetMbps"
	}
}
