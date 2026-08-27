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

// Spec.EgressBudgetMbps is stamped identically onto every machine a
// MachineTemplate clones, so it cannot describe a fleet whose boxes differ, and
// over-stating a box's budget shows up as traffic overrunning the wire rather than
// as an error. This reads the individual box's limitation instead.

// DisableEgressDiscoveryAnnotation excludes one machine, presence-only like CAPI's
// cluster.x-k8s.io/paused, so the flag has no value to spell wrong. Per machine
// because that is the blast radius of a bad reading; a staged rollout is annotating
// the boxes that should wait and un-annotating them one at a time.
//
// CAPI SSA-patches this object's annotations from the MachineSet template every
// reconcile, but under a field manager that owns no keys while our templates set
// none, so a hand-set key survives. Adding this key to a MachineDeployment template
// hands ownership over and makes it a fleet-wide override.
const DisableEgressDiscoveryAnnotation = "tuist.dev/disable-egress-discovery"

const (
	// The machine reconciles every 10 minutes; the reading tracks a contract, so
	// daily keeps that cadence from becoming OVH API traffic. It bounds a
	// successful read only — see egressReadRetryInterval for a failing one.
	egressDiscoveryRefreshInterval = 24 * time.Hour

	// A failed read leaves EgressResolvedAt unstamped, so nothing would hold back
	// the next attempt — and a machine in the Provisioned-but-not-Ready tail
	// requeues every 20s, turning a permanently failing read (renamed endpoint,
	// credential problem) into three OVH calls and three error lines a minute.
	// This floors the retry at what a healthy node already does, without the day of
	// blindness that stamping the full refresh interval would buy.
	egressReadRetryInterval = 10 * time.Minute
)

// Both halves of the feature ask this — whether to call OVH, and whether a reading
// may rate the node — so annotating a machine also retires the reading it holds.
func egressDiscoveryDisabled(machine *infrav1.OVHDedicatedMachine) bool {
	_, set := machine.Annotations[DisableEgressDiscoveryAnnotation]
	return set
}

// resolvedEgressReading reports whether OVH gave us a number at all. There is no
// plausibility band around it: the floor already refuses anything below the
// configured budget, so a decode that starts yielding 1 after a response-shape
// change is refused and surfaced as a reduction rather than silently applied, and a
// ceiling would only ever be a guess that the next faster box trips.
func resolvedEgressReading(mbps int32) bool {
	return mbps > 0
}

// EgressOverrideAnnotation pins one machine's advertised budget to a value the
// operator chose, in Mbps, whatever discovery reports. It is the single lever for
// changing a live node: Spec.EgressBudgetMbps reaches a machine only when it is
// cloned from its template (the MachineDeployment is OnDelete), so it is the fleet
// default and the floor rather than something an operator moves.
//
// Reversible by removing it — see EgressSource for why that needs the source to be
// recorded. A value that is not a positive integer is ignored rather than treated
// as zero, which would withdraw the machine from egress governance entirely: a much
// larger action than the annotation asked for, and one Spec.EgressBudgetMbps: 0
// already expresses deliberately.
//
// Pinning downward is not free on a busy box: the capacity it lowers is a
// non-overcommittable extended resource the cache pods already hold, and lowering it
// under what is allocated is neither refused nor evicting. The node sits
// over-allocated until the next admission decision, which then fails those pods.
// Check the allocated total first — see the reduction runbook in AGENTS.md.
//
// It does not apply to a machine whose configured budget is zero. That machine is
// out of egress governance, and a pin cannot bring it in for one reconcile and let
// it back out later: the node-capacity helper writes the key but has no path that
// removes it, so removing the annotation would leave the node advertising the
// operator's number for good. A pin that cannot be undone is not the lever this is
// meant to be, so the budget has to be set first.
const EgressOverrideAnnotation = "tuist.dev/egress-mbps-override"

// Sources recorded in Status.EgressSource. Only egressSourceManual is load-bearing
// — egressFloor reads it to release a removed pin. The rest answer "why is this node
// at N" for a human, which is a job they only do if each one is true.
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
// machine no longer holds. Read here rather than checked inside the discovery
// function because most paths that reach a capacity decision never enter it: a
// machine inside the read backoff, or one whose serviceName an operator cleared to
// force re-adoption, would otherwise rate a new box from its predecessor's number.
func cachedEgressMbps(machine *infrav1.OVHDedicatedMachine) int32 {
	if machine.Status.EgressResolvedServiceName != machine.Status.ServiceName {
		return 0
	}
	return machine.Status.EgressMbps
}

// egressFloor is the budget the node may not fall below on its own: whatever it
// already advertises, or the configured budget, whichever is higher.
//
// The ratchet exists because the two directions are not symmetric. A box's
// contractual bandwidth does not shrink on its own — it shrinks because someone
// downgraded the plan, an action that already has a human attached — whereas a
// wrong-low reading (an API blip, a partial response, a box throttled over its
// monthly quota) is plausible and expensive: the egress-tree agent re-rates the
// node's HTB root in place, throttling live cache traffic on a box that can carry
// far more. The plausibility floor only catches garbage; a wrong 1000 on a 3
// Gbit/s box clears it.
//
// A pin that has just been removed resets it. The anchor is what the node
// advertises, and while a pin was in force that number is one a human typed, not
// one discovery supports — carrying it into the ratchet would strand the node
// there forever. Ignoring it for exactly one reconcile hands the machine back to
// its readings; from the next reconcile the anchor is a discovered value again.
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
// A machine with no configured budget is answered first, ahead of the pin. Zero
// means the box does not participate in egress governance, and a pin must not opt
// it back in: ReconcileNodeEgressCapacity writes the capacity key but has no path
// that removes it, so a pinned zero-budget machine could never be un-pinned — the
// node would keep advertising the operator's number after the annotation was gone,
// with nothing left running that would correct it. Refusing the pin is what keeps
// the annotation reversible everywhere it applies.
//
// A pin otherwise wins outright, in both directions, including against a machine
// whose discovery is disabled: it is the most specific and most deliberate signal
// there is. Disabling discovery is an explicit decision too and applies directly,
// downward included — the ratchet only ever holds against the controller's own
// readings. Otherwise the reading is taken when it is usable and at or above the
// floor; below it, the floor holds and the reading is recorded and surfaced instead
// (capt_ovh_egress_reported_mbps, against capt_ovh_egress_advertised_mbps — nothing
// on the node moved, so no event is raised).
//
// A held floor above the configured budget is reported by where the floor came
// from, which is not always a reading. When one exists, the floor is an earlier
// reading of the same box and "discovery" is the truth. When none does — a machine
// that has never resolved whose node advertises more than its spec, which is what an
// operator hand-lowering spec.egressBudgetMbps on a live CR leaves behind — the
// number is whatever the node was already carrying, and calling that "discovery"
// would have status.egressSource and capt_ovh_egress_advertised_mbps assert OVH
// backing for a figure no reading supports. It reports "held" instead. Nothing
// branches on either value; the point is that the field answering "why is this node
// at N" should not answer it wrongly.
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

// Bounds a successful read, including one that returned something unusable, so a
// box we cannot read costs one call a day rather than one per reconcile. A failed
// call leaves it unstamped and is bounded by egressReadBackedOff instead.
//
// A reading recorded against a different service name is always due: hand-patching
// these CRs is the normal operating mode, so clearing status.serviceName to force
// re-adoption is a plausible action, and it would otherwise rate a freshly adopted
// box from the previous one's reading for a day.
func egressDiscoveryDue(machine *infrav1.OVHDedicatedMachine, now time.Time) bool {
	if machine.Status.EgressResolvedAt == nil || machine.Status.EgressResolvedServiceName != machine.Status.ServiceName {
		return true
	}
	return now.Sub(machine.Status.EgressResolvedAt.Time) >= egressDiscoveryRefreshInterval
}

// reconcileNodeEgress decides the budget the node should advertise, patches it,
// and records what decided it.
//
// The order of the last three statements is load-bearing, which is why they live
// here rather than inline in reconcileNormal. Everything after the capacity patch
// describes what the node now carries, so none of it may run on a write that did
// not land: an event would announce a budget change that never happened, the
// advertised gauge would report a number the node is not serving, and — the
// expensive one — Status.EgressSource is what ends the single-reconcile reset that
// releases a removed pin. Ending that reset on a failed patch leaves the node
// advertising the pin's value with the reset already spent, and from the next
// reconcile the ratchet anchors on that value and holds it there for good. The
// deferred patch in Reconcile persists status whatever this returns, so leaving the
// source alone is what makes the failure retryable.
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

	// Ahead of every guard below, because this is a statement about the cached value
	// rather than about whether a read is owed. A reading recorded against another
	// service describes hardware this machine no longer holds, and every guard that
	// follows returns — so dropping it any later leaves the dead box's number in
	// status and in capt_ovh_egress_reported_mbps for as long as the machine is
	// skipped: until the retry lands inside the read backoff, until tomorrow on a
	// fresh reading, and indefinitely on a box that is annotated out or has no
	// configured budget. cachedEgressMbps already refuses to rate a node from it;
	// this is the half a human reads, and the runbook's SEEN column is exactly it.
	//
	// EgressResolvedServiceName itself stays put: egressFloor keys the ratchet reset
	// on it still naming the old box, and egressDiscoveryDue keys the re-read on it.
	if machine.Status.EgressResolvedServiceName != machine.Status.ServiceName {
		machine.Status.EgressMbps = 0
		machine.Status.EgressTier = ""
		forgetEgressReported(machine.Name)
	}

	// Nothing to ask OVH about: an operator has excluded this box, or it has not been
	// adopted yet.
	if egressDiscoveryDisabled(machine) || machine.Status.ServiceName == "" {
		return
	}
	// A machine with no configured budget does not participate in egress governance
	// at all: the chart omits the field, ReconcileNodeEgressCapacity no-ops on it, and
	// the tree agent leaves such a node's pods unshaped. Rating it from OVH would
	// override that opt-out, and the annotation could not take it back — the shared
	// helper can lower an advertised capacity but never remove the key. A pin does not
	// opt it back in either (see effectiveEgressMbps), so there is nothing a reading
	// could rate here. An ignored pin is logged because the annotation is obeyed
	// everywhere else, and an operator who pinned a box and saw nothing happen has no
	// other way to find out why.
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

	// An unusable reading must not overwrite a good one. By the client's contract a
	// renamed or dropped bandwidth block is an ordinary answer returning zero, so
	// writing it through would hand the node back to a spec value that may sit well
	// above the wire — the over-commit this exists to prevent, arriving as a
	// successful response. Still stamped as resolved, so it retries daily rather
	// than every tick.
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

	// Logged, not evented: whether the node's budget actually moves is decided by
	// the caller, and an event that fires on a reading which changes nothing is an
	// event nobody can act on. The standing disagreement is a metric —
	// capt_ovh_egress_reported_mbps against capt_ovh_egress_advertised_mbps — which
	// has history and does not depend on catching the moment it appeared.
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

// recordEgressBudgetChange emits an event when the node's advertised budget
// actually moves, naming both numbers and what decided the new one. Firing on a
// change rather than on a reading keeps it to one event per transition, and keeps
// it truthful: a reading that the floor refuses changes nothing on the node, and
// saying otherwise is what sends someone chasing a budget that never moved.
//
// It deliberately carries no remedy. Accepting a reduction is pin, lower the
// budget, unpin — in that order, since lowering the budget on its own moves the
// other side of max(advertised, spec) and leaves the node exactly where it was —
// and a three-move runbook belongs in AGENTS.md rather than in one line of an event
// someone reads at 3am.
func (r *OVHDedicatedMachineReconciler) recordEgressBudgetChange(machine *infrav1.OVHDedicatedMachine, from, to int32, source string) {
	switch {
	case to <= 0:
		// ReconcileNodeEgressCapacity does not write a non-positive budget, and has
		// no path that removes the key, so whatever the node already advertises it
		// keeps. Nothing moved, whatever `from` says.
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

// egressReadBackedOff reports a machine whose last read failed too recently to try
// again. Kept in memory rather than status: losing it on an operator restart costs
// one extra attempt per machine, which is the behaviour you would want anyway.
func (r *OVHDedicatedMachineReconciler) egressReadBackedOff(machine *infrav1.OVHDedicatedMachine, now time.Time) bool {
	last, ok := r.egressReadFailures.Load(machine.UID)
	if !ok {
		return false
	}
	failedAt, ok := last.(time.Time)
	return ok && now.Sub(failedAt) < egressReadRetryInterval
}
