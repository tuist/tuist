package shared

import (
	"strconv"
	"strings"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// EgressOverrideAnnotation pins a machine's advertised egress budget, in Mbps, in
// either direction. It is temporary: while it is set the node advertises this
// number and nothing the controller derived counts as a promise, so removing it
// re-derives the budget from the configured value and the provider's reading.
// Remove it once those are known to be right. A value that is not a positive
// integer is ignored.
const EgressOverrideAnnotation = "tuist.dev/egress-mbps-override"

// DisableEgressDiscoveryAnnotation, by its presence alone, stops the controller
// reading the provider for this machine. The node keeps the budget it has.
//
// CAPI SSA-patches the InfraMachine's annotations from the MachineSet template
// under a field manager that owns only the keys the template sets; ours set none,
// so a hand-set key survives. Putting this key in a MachineDeployment template
// turns it into a fleet-wide switch.
const DisableEgressDiscoveryAnnotation = "tuist.dev/disable-egress-discovery"

// What decided a node's egress budget.
const (
	EgressSourceConfigured = "configured"
	EgressSourceDiscovery  = "discovery"
	EgressSourceManual     = "manual"
)

// EgressOverrideMbps is the operator's pinned budget, or 0 when the annotation is
// absent or does not carry a positive integer.
func EgressOverrideMbps(obj metav1.Object) int32 {
	raw, set := obj.GetAnnotations()[EgressOverrideAnnotation]
	if !set {
		return 0
	}
	mbps, err := strconv.ParseInt(strings.TrimSpace(raw), 10, 32)
	if err != nil || mbps <= 0 {
		return 0
	}
	return int32(mbps)
}

func EgressDiscoveryDisabled(obj metav1.Object) bool {
	_, set := obj.GetAnnotations()[DisableEgressDiscoveryAnnotation]
	return set
}

// EgressInputs is everything the budget decision depends on.
type EgressInputs struct {
	// ConfiguredMbps is spec.egressBudgetMbps: the fleet default and the floor.
	ConfiguredMbps int32
	// BudgetMbps and Source are what the node was last set to and why.
	BudgetMbps int32
	Source     string
	// ReportedMbps is the provider's last usable reading, or 0.
	ReportedMbps int32
	OverrideMbps int32
	Disabled     bool
}

type EgressDecision struct {
	// NodeMbps is what the node should advertise; 0 removes the capacity.
	NodeMbps int32
	// BudgetMbps and Source are what to record in status.
	BudgetMbps int32
	Source     string
}

// DecideEgress is the whole budget policy.
//
// The budget only ever rises on the controller's own authority: the configured
// value seeds it and raises it, a reading above it raises it, and nothing lowers
// it. A pin sets the node outright and, being temporary, leaves no promise behind:
// once it is gone the budget is derived afresh from the configured value and the
// reading, which is where the operator wanted the node to land. Disabling
// discovery only stops readings from raising the budget.
func DecideEgress(in EgressInputs) EgressDecision {
	if in.ConfiguredMbps <= 0 {
		return EgressDecision{}
	}
	if in.OverrideMbps > 0 {
		return EgressDecision{NodeMbps: in.OverrideMbps, BudgetMbps: in.OverrideMbps, Source: EgressSourceManual}
	}
	budget, source := in.BudgetMbps, in.Source
	if source == EgressSourceManual {
		budget = 0
	}
	if in.ConfiguredMbps > budget {
		budget, source = in.ConfiguredMbps, EgressSourceConfigured
	}
	if !in.Disabled && in.ReportedMbps > budget {
		budget, source = in.ReportedMbps, EgressSourceDiscovery
	}
	return EgressDecision{NodeMbps: budget, BudgetMbps: budget, Source: source}
}
