package linux

import (
	"context"
	"strconv"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
)

// Spec.EgressBudgetMbps is stamped identically onto every machine a MachineTemplate
// clones, so it cannot describe a fleet whose boxes differ — and over-stating a box
// shows up as traffic overrunning the wire, not as an error. This reads the box.

// DisableEgressDiscoveryAnnotation excludes one machine, presence-only like CAPI's
// cluster.x-k8s.io/paused, so the flag has no value to spell wrong.
//
// CAPI SSA-patches this object's annotations from the MachineSet template every
// reconcile, under a field manager that owns no keys while our templates set none —
// so a hand-set key survives, and putting this key in a MachineDeployment template
// hands ownership over and makes it a fleet-wide override.
const DisableEgressDiscoveryAnnotation = "tuist.dev/disable-egress-discovery"

const (
	// The machine reconciles every 10 minutes and the reading tracks a contract, so
	// daily keeps that cadence from becoming OVH API traffic. Successful reads only.
	egressDiscoveryRefreshInterval = 24 * time.Hour

	// A failed read leaves EgressResolvedAt unstamped, so nothing else bounds the
	// next attempt — and a machine in the Provisioned-but-not-Ready tail requeues
	// every 20s, turning a permanently failing read into three calls a minute.
	// Stamping the full refresh interval instead would buy a day of blindness.
	egressReadRetryInterval = 10 * time.Minute
)

func egressDiscoveryDisabled(machine *infrav1.OVHDedicatedMachine) bool {
	_, set := machine.Annotations[DisableEgressDiscoveryAnnotation]
	return set
}

// resolvedEgressReading reports whether OVH gave us a number at all. No plausibility
// band: the floor already refuses anything below the configured budget, so a decode
// yielding 1 is caught there, and a ceiling would be a guess the next faster box trips.
func resolvedEgressReading(mbps int32) bool {
	return mbps > 0
}

// EgressOverrideAnnotation pins one machine's advertised budget, in Mbps, whatever
// discovery reports. It is the single lever for changing a live node:
// Spec.EgressBudgetMbps reaches a machine only when it is cloned from its template
// (the MachineDeployment is OnDelete), so it is the fleet default, not a live control.
//
// A value that is not a positive integer is ignored rather than read as zero, which
// would withdraw the machine from egress governance — a far larger action than the
// annotation asked for, and one Spec.EgressBudgetMbps: 0 already expresses.
//
// Ignored on a machine whose configured budget is zero, so that the pin stays
// reversible everywhere it does apply; see effectiveEgressMbps. Pinning downward on a
// busy box needs the allocated total checked first — see the runbook in AGENTS.md.
const EgressOverrideAnnotation = "tuist.dev/egress-mbps-override"

// Sources recorded in Status.EgressSource. Only egressSourceManual is load-bearing:
// egressFloor reads it to release a removed pin. The rest answer "why is this node at
// N" for a human, a job they only do if each one is true.
const (
	egressSourceDiscovery  = "discovery"
	egressSourceManual     = "manual"
	egressSourceConfigured = "configured"
	egressSourceHeld       = "held"
)

// egressOverrideMbps is the operator's pinned budget, or 0 when the annotation is
// absent or does not carry a positive integer.
func egressOverrideMbps(machine *infrav1.OVHDedicatedMachine) int32 {
	raw, set := machine.Annotations[EgressOverrideAnnotation]
	if !set {
		return 0
	}
	mbps, err := strconv.ParseInt(strings.TrimSpace(raw), 10, 32)
	if err != nil || mbps <= 0 {
		return 0
	}
	return int32(mbps)
}

// cachedEgressMbps is the machine's reading, or 0 when it was taken from a box this
// machine no longer holds. Checked here rather than inside the discovery function
// because most paths reaching a capacity decision never enter it — a machine inside
// the read backoff, or one whose serviceName was cleared to force re-adoption.
func cachedEgressMbps(machine *infrav1.OVHDedicatedMachine) int32 {
	if machine.Status.EgressResolvedServiceName != machine.Status.ServiceName {
		return 0
	}
	return machine.Status.EgressMbps
}

// egressFloor is the budget the node may not fall below on its own: whatever it
// already advertises, or the configured budget, whichever is higher.
//
// The directions are not symmetric. A box's contractual bandwidth shrinks only
// because someone downgraded the plan — an action with a human already attached —
// whereas a wrong-low reading (an API blip, a partial response, a box throttled over
// quota) is plausible and expensive: the egress-tree agent re-rates the node's HTB
// root in place, throttling live traffic on a box that can carry far more.
//
// A just-removed pin resets it. The anchor is what the node advertises, and under a
// pin that is a number a human typed rather than one discovery supports, so carrying
// it into the ratchet would strand the node there for good.
func egressFloor(machine *infrav1.OVHDedicatedMachine, advertisedMbps int32) int32 {
	if machine.Status.EgressSource == egressSourceManual && egressOverrideMbps(machine) == 0 {
		return machine.Spec.EgressBudgetMbps
	}
	// A machine re-adopted onto another box resets it too, and dropping the stale
	// reading is not enough on its own: the anchor is the node's advertised
	// capacity, which survives a kubelet re-registration by design, so the previous
	// box's budget would otherwise hold the new one up forever.
	//
	// Only when a reading actually exists to be stale. A machine that has never
	// resolved has no recorded service, which is not a mismatch — treating it as one
	// would reset the ratchet for every machine on the first reconcile after this
	// ships.
	if machine.Status.EgressResolvedServiceName != "" &&
		machine.Status.EgressResolvedServiceName != machine.Status.ServiceName {
		return machine.Spec.EgressBudgetMbps
	}
	if advertisedMbps > machine.Spec.EgressBudgetMbps {
		return advertisedMbps
	}
	return machine.Spec.EgressBudgetMbps
}

// effectiveEgressMbps is the budget the node should advertise, and what decided it.
//
// A zero configured budget is answered first, ahead of the pin: the machine is out of
// egress governance, and ReconcileNodeEgressCapacity has no path that removes the
// capacity key, so a pin here could never be undone. Refusing it is what keeps the
// annotation reversible everywhere it does apply.
//
// A pin otherwise wins outright, in both directions and over a disabled machine —
// the most deliberate signal there is. Disabling discovery is explicit too, so it
// applies downward directly; the ratchet only ever holds against our own readings.
//
// A held floor reports "held" rather than "discovery" when no reading backs it — a
// machine that never resolved whose node advertises above its spec, which is what
// hand-lowering spec.egressBudgetMbps on a live CR leaves behind. Nothing branches on
// the value; it is the field answering "why is this node at N".
func effectiveEgressMbps(disabled bool, specMbps, discoveredMbps, floorMbps, overrideMbps int32) (int32, string) {
	if specMbps <= 0 {
		return specMbps, egressSourceConfigured
	}
	if overrideMbps > 0 {
		return overrideMbps, egressSourceManual
	}
	if disabled {
		return specMbps, egressSourceConfigured
	}
	if resolvedEgressReading(discoveredMbps) && discoveredMbps >= floorMbps {
		return discoveredMbps, egressSourceDiscovery
	}
	if floorMbps > specMbps {
		if resolvedEgressReading(discoveredMbps) {
			return floorMbps, egressSourceDiscovery
		}
		return floorMbps, egressSourceHeld
	}
	return specMbps, egressSourceConfigured
}

// Bounds a successful read, unusable answers included, so a box we cannot read costs
// one call a day rather than one per reconcile; a failed call is bounded by
// egressReadBackedOff instead. A reading recorded against another service name is
// always due, or a re-adopted machine would carry the old box's number for a day.
func egressDiscoveryDue(machine *infrav1.OVHDedicatedMachine, now time.Time) bool {
	if machine.Status.EgressResolvedAt == nil || machine.Status.EgressResolvedServiceName != machine.Status.ServiceName {
		return true
	}
	return now.Sub(machine.Status.EgressResolvedAt.Time) >= egressDiscoveryRefreshInterval
}

// reconcileNodeEgress decides the budget the node should advertise, patches it, and
// records what decided it.
//
// Nothing after the capacity patch may run on a write that did not land — which is
// why these statements live here rather than inline in reconcileNormal. The costly
// one is Status.EgressSource: it ends the single-reconcile reset that releases a
// removed pin, so ending it on a failed patch leaves the node on the pin's value with
// the reset spent, and the ratchet then anchors there for good. Leaving the source
// alone is what makes the failure retryable.
func (r *OVHDedicatedMachineReconciler) reconcileNodeEgress(ctx context.Context, machine *infrav1.OVHDedicatedMachine, node *corev1.Node) error {
	advertisedMbps := shared.NodeEgressMbps(node)
	floorMbps := egressFloor(machine, advertisedMbps)
	r.reconcileEgressDiscovery(ctx, machine, floorMbps)
	mbps, source := effectiveEgressMbps(egressDiscoveryDisabled(machine),
		machine.Spec.EgressBudgetMbps, cachedEgressMbps(machine), floorMbps,
		egressOverrideMbps(machine))

	if err := shared.ReconcileNodeEgressCapacity(ctx, r.Client, node, mbps); err != nil {
		return err
	}

	machine.Status.EgressSource = source
	recordEgressBudgets(machine.Name, machine.Spec.FleetName, machine.Spec.EgressBudgetMbps, mbps, source)
	r.recordEgressBudgetChange(machine, advertisedMbps, mbps, source)
	return nil
}

// reconcileEgressDiscovery records what OVH reports in status, which the
// reconciler's deferred patch persists. It returns no error: a failed read must not
// hold up the node reconcile it rides along with, and the last reading stays in
// force, so an OVH outage degrades to advertising what we already advertise.
func (r *OVHDedicatedMachineReconciler) reconcileEgressDiscovery(ctx context.Context, machine *infrav1.OVHDedicatedMachine, floorMbps int32) {
	logger := log.FromContext(ctx)

	// Ahead of every guard below, because this is about the cached value rather than
	// whether a read is owed: every guard that follows returns, so dropping it later
	// leaves a dead box's number in status and in capt_ovh_egress_reported_mbps for as
	// long as the machine is skipped — indefinitely for one annotated out.
	// cachedEgressMbps already refuses to rate a node from it; this is the half a
	// human reads.
	//
	// EgressResolvedServiceName itself stays put: egressFloor keys the ratchet reset
	// on it still naming the old box, and egressDiscoveryDue keys the re-read on it.
	if machine.Status.EgressResolvedServiceName != machine.Status.ServiceName {
		machine.Status.EgressMbps = 0
		machine.Status.EgressTier = ""
		forgetEgressReported(machine.Name)
	}

	if egressDiscoveryDisabled(machine) || machine.Status.ServiceName == "" {
		return
	}
	// A machine with no configured budget is out of egress governance: the chart omits
	// the field, ReconcileNodeEgressCapacity no-ops, and the tree agent leaves its pods
	// unshaped. A pin does not opt it back in either (see effectiveEgressMbps), so
	// there is nothing here a reading could rate. The ignored pin is logged because the
	// annotation is obeyed everywhere else, and an operator who pinned a box and saw
	// nothing happen has no other way to find out why.
	if machine.Spec.EgressBudgetMbps <= 0 {
		if egressOverrideMbps(machine) > 0 {
			logger.Info("ignoring the egress pin on a machine with no configured budget; set spec.egressBudgetMbps to bring the box into egress governance",
				"service", machine.Status.ServiceName)
		}
		return
	}
	now := time.Now()
	if !egressDiscoveryDue(machine, now) || r.egressReadBackedOff(machine, now) {
		return
	}

	discovered, err := r.OVHClient.PublicEgress(ctx, machine.Status.ServiceName)
	if err != nil {
		// Not a condition or an Event: the last reading stays in force, so a
		// transient 5xx once a day is not worth paging anyone.
		r.egressReadFailures.Store(machine.UID, now)
		logger.Error(err, "reading the box's egress limitation failed; keeping the last known value",
			"service", machine.Status.ServiceName)
		return
	}
	r.egressReadFailures.Delete(machine.UID)

	// An unusable reading must not overwrite a good one: a renamed or dropped bandwidth
	// block is an ordinary answer returning zero, so writing it through would hand the
	// node back to a spec value that may sit well above the wire. Stamped as resolved
	// even so, or an unreadable box would be re-read every tick.
	if !resolvedEgressReading(discovered.Mbps) {
		machine.Status.EgressResolvedAt = &metav1.Time{Time: now}
		machine.Status.EgressResolvedServiceName = machine.Status.ServiceName
		logger.Info("OVH reported no egress limitation we could read; keeping the last known value",
			"service", machine.Status.ServiceName, "unit", discovered.Unit, "value", discovered.Value,
			"keeping_mbps", machine.Status.EgressMbps)
		return
	}

	previous := machine.Status.EgressMbps
	machine.Status.EgressMbps = discovered.Mbps
	machine.Status.EgressTier = discovered.Tier
	machine.Status.EgressResolvedAt = &metav1.Time{Time: now}
	machine.Status.EgressResolvedServiceName = machine.Status.ServiceName
	recordEgressReported(machine.Name, machine.Spec.FleetName, machine.Status.ServiceName, discovered.Tier, discovered.Mbps)

	if discovered.Mbps == previous {
		return
	}

	// Logged, not evented: the caller decides whether the node's budget moves, and a
	// reading that changes nothing is nothing to act on. The standing disagreement is
	// capt_ovh_egress_reported_mbps against capt_ovh_egress_advertised_mbps.
	if discovered.Mbps < floorMbps {
		logger.Info("OVH reports less egress than the node's floor; the reading is recorded, not applied",
			"service", machine.Status.ServiceName, "mbps", discovered.Mbps,
			"tier", discovered.Tier, "floor_mbps", floorMbps,
			"configured_mbps", machine.Spec.EgressBudgetMbps)
		return
	}

	logger.Info("OVH reports egress at or above the node's floor",
		"service", machine.Status.ServiceName, "mbps", discovered.Mbps,
		"tier", discovered.Tier, "floor_mbps", floorMbps,
		"configured_mbps", machine.Spec.EgressBudgetMbps)
}

// recordEgressBudgetChange emits an event when the node's advertised budget actually
// moves, naming both numbers and what decided the new one — one event per transition,
// and none for a reading the floor refused, which changed nothing on the node.
//
// It carries no remedy: accepting a reduction is pin, lower the budget, unpin, and
// naming one of those moves would send people to do the one that is inert on its own
// (lowering the budget moves the other side of max(advertised, spec)).
func (r *OVHDedicatedMachineReconciler) recordEgressBudgetChange(machine *infrav1.OVHDedicatedMachine, from, to int32, source string) {
	switch {
	case to <= 0:
		// ReconcileNodeEgressCapacity writes no non-positive budget and never removes
		// the key, so the node keeps what it had. Nothing moved, whatever `from` says.
	case from == to:
	case from == 0:
		r.event(machine, "EgressBudgetIncreased",
			"node egress budget set to %d Mbps (%s)", to, egressSourceDescription(machine, source))
	case to > from:
		r.event(machine, "EgressBudgetIncreased",
			"node egress budget raised from %d to %d Mbps (%s)", from, to, egressSourceDescription(machine, source))
	default:
		r.event(machine, "EgressBudgetReduced",
			"node egress budget reduced from %d to %d Mbps (%s)", from, to, egressSourceDescription(machine, source))
	}
}

// egressSourceDescription says which input decided the budget, in the terms an
// operator would use to change it.
func egressSourceDescription(machine *infrav1.OVHDedicatedMachine, source string) string {
	switch source {
	case egressSourceManual:
		return "pinned by " + EgressOverrideAnnotation
	case egressSourceDiscovery:
		return "reported by OVH for " + machine.Status.ServiceName
	case egressSourceHeld:
		return "held at the budget the node already advertised"
	default:
		return "spec.egressBudgetMbps"
	}
}

// egressReadBackedOff reports a machine whose last read failed too recently to retry.
// In memory rather than status: losing it on a restart costs one extra attempt per
// machine, which is what you would want anyway.
func (r *OVHDedicatedMachineReconciler) egressReadBackedOff(machine *infrav1.OVHDedicatedMachine, now time.Time) bool {
	last, ok := r.egressReadFailures.Load(machine.UID)
	if !ok {
		return false
	}
	failedAt, ok := last.(time.Time)
	return ok && now.Sub(failedAt) < egressReadRetryInterval
}
