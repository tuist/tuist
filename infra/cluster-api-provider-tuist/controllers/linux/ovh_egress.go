package linux

import (
	"context"
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

// Falls back to the spec value rather than to zero: it is what the fleet ran on
// before discovery existed. A zeroed budget withdraws the machine from egress
// governance even when a reading is already cached — the same guard discovery
// applies, repeated here because zeroing a resolved box is a live operator action
// (spec is mutable, and OnDelete means a values change never reaches a machine)
// that would otherwise silently keep the node rated.
func effectiveEgressMbps(disabled bool, specMbps, discoveredMbps int32) int32 {
	if disabled || specMbps <= 0 || !usableDiscoveredEgress(discoveredMbps) {
		return specMbps
	}
	return discoveredMbps
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
func (r *OVHDedicatedMachineReconciler) reconcileEgressDiscovery(ctx context.Context, machine *infrav1.OVHDedicatedMachine) {
	logger := log.FromContext(ctx)

	// A machine with no configured budget is one that does not participate in
	// egress governance at all: the chart omits the field, ReconcileNodeEgressCapacity
	// no-ops on it, and the tree agent leaves such a node's pods unshaped. Rating it
	// from OVH would override that opt-out, and the annotation could not take it
	// back — the shared helper can lower an advertised capacity but never remove
	// the key.
	if egressDiscoveryDisabled(machine) || machine.Spec.EgressBudgetMbps <= 0 || machine.Status.ServiceName == "" {
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

	if discovered.Mbps == previous {
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
