package linux

import (
	"context"
	"strconv"
	"strings"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
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

	// Guards a decode that starts yielding 0 or 1 after a response-shape change: a
	// node advertising a couple of Mbps schedules and serves nothing, which is worse
	// than the stale value it replaced. No ceiling — too high is the failure a spec
	// value already risks, and any limit would be a guess that the next faster box
	// trips.
	minDiscoveredEgressMbps = 100
)

// Both halves of the feature ask this — whether to call OVH, and whether a reading
// may rate the node — so annotating a machine also retires the reading it holds.
func egressDiscoveryDisabled(machine *infrav1.OVHDedicatedMachine) bool {
	_, set := machine.Annotations[DisableEgressDiscoveryAnnotation]
	return set
}

func usableDiscoveredEgress(mbps int32) bool {
	return mbps >= minDiscoveredEgressMbps
}

// EgressOverrideAnnotation pins one machine's advertised budget to a value the
// operator chose, in Mbps, whatever discovery reports. It is the single lever for
// changing a live node: Spec.EgressBudgetMbps reaches a machine only when it is
// cloned from its template (the MachineDeployment is OnDelete), so it is the fleet
// default and the floor rather than something an operator moves.
//
// Reversible by removing it — see EgressSource for why that needs the source to be
// recorded. A value that is not a positive integer is logged and ignored rather
// than treated as zero, which would withdraw the machine from egress governance
// entirely: a much larger action than the annotation asked for, and one
// Spec.EgressBudgetMbps: 0 already expresses deliberately.
const EgressOverrideAnnotation = "tuist.dev/egress-mbps-override"

// Sources recorded in Status.EgressSource.
const (
	egressSourceDiscovery  = "discovery"
	egressSourceManual     = "manual"
	egressSourceConfigured = "configured"
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
	if advertisedMbps > machine.Spec.EgressBudgetMbps {
		return advertisedMbps
	}
	return machine.Spec.EgressBudgetMbps
}

// effectiveEgressMbps is the budget the node should advertise, and what decided it.
//
// A pin wins outright, in both directions: it is the most specific and most
// deliberate signal there is, including against Spec.EgressBudgetMbps: 0, where it
// opts a machine back into egress governance. Disabling discovery or zeroing the
// budget are explicit decisions too and apply directly, downward included — the
// ratchet only ever holds against the controller's own readings. Otherwise the
// reading is taken when it is usable and at or above the floor; below it, the floor
// holds and the reading is recorded and surfaced instead
// (capt_ovh_egress_reported_mbps, and an EgressBudgetReduced event).
//
// A held floor above the configured budget reports "discovery" rather than
// "configured": it is a reading from an earlier reconcile, and calling it
// configured would make the next reconcile mistake it for a stale pin.
func effectiveEgressMbps(disabled bool, specMbps, discoveredMbps, floorMbps, overrideMbps int32) (int32, string) {
	if overrideMbps > 0 {
		return overrideMbps, egressSourceManual
	}
	if disabled || specMbps <= 0 {
		return specMbps, egressSourceConfigured
	}
	if usableDiscoveredEgress(discoveredMbps) && discoveredMbps >= floorMbps {
		return discoveredMbps, egressSourceDiscovery
	}
	if floorMbps > specMbps {
		return floorMbps, egressSourceDiscovery
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

// reconcileEgressDiscovery records what OVH reports in status, which the
// reconciler's deferred patch persists. It returns no error: a failed read must not
// hold up the node reconcile it rides along with, and the last reading stays in
// force, so an OVH outage degrades to advertising what we already advertise.
func (r *OVHDedicatedMachineReconciler) reconcileEgressDiscovery(ctx context.Context, machine *infrav1.OVHDedicatedMachine, floorMbps int32) {
	logger := log.FromContext(ctx)

	// A machine with no configured budget is one that does not participate in
	// egress governance at all: the chart omits the field, ReconcileNodeEgressCapacity
	// no-ops on it, and the tree agent leaves such a node's pods unshaped. Rating it
	// from OVH would override that opt-out, and the annotation could not take it
	// back — the shared helper can lower an advertised capacity but never remove
	// the key.
	if egressDiscoveryDisabled(machine) || machine.Status.ServiceName == "" {
		return
	}
	if machine.Spec.EgressBudgetMbps <= 0 && egressOverrideMbps(machine) == 0 {
		return
	}
	now := time.Now()
	if !egressDiscoveryDue(machine, now) || r.egressReadBackedOff(machine, now) {
		return
	}
	if machine.Status.EgressResolvedServiceName != machine.Status.ServiceName {
		// The cached reading describes a box this machine no longer holds, and the
		// paths below deliberately keep the last value when a read fails or comes
		// back unusable. Drop it first so neither can preserve another server's
		// number for this one.
		machine.Status.EgressMbps = 0
		machine.Status.EgressTier = ""
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
	if !usableDiscoveredEgress(discovered.Mbps) {
		machine.Status.EgressResolvedAt = &metav1.Time{Time: now}
		machine.Status.EgressResolvedServiceName = machine.Status.ServiceName
		logger.Info("OVH reported no usable egress limitation; keeping the last known value",
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

	if discovered.Mbps < floorMbps {
		logger.Info("OVH reports less egress than the node advertises; the node keeps its budget",
			"service", machine.Status.ServiceName, "mbps", discovered.Mbps,
			"tier", discovered.Tier, "floor_mbps", floorMbps,
			"configured_mbps", machine.Spec.EgressBudgetMbps)
		r.event(machine, "EgressBudgetReduced",
			"OVH reports %d Mbps (%s) for %s, below the %d Mbps the node advertises; not applied — lower spec.egressBudgetMbps to accept it",
			discovered.Mbps, discovered.Tier, machine.Status.ServiceName, floorMbps)
		return
	}

	logger.Info("advertising the box's reported egress limitation",
		"service", machine.Status.ServiceName, "mbps", discovered.Mbps,
		"tier", discovered.Tier, "configured_mbps", machine.Spec.EgressBudgetMbps)
	r.event(machine, "EgressBudgetDiscovered",
		"OVH reports %d Mbps (%s) for %s; advertising it in place of the configured %d Mbps",
		discovered.Mbps, discovered.Tier, machine.Status.ServiceName, machine.Spec.EgressBudgetMbps)
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
