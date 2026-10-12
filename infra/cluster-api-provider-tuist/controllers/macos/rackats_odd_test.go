package macos

import (
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
)

// A preferred source the driver cannot read under a key it knows is reported
// like an unknown key: a factory card is adopted and observed, not left as a
// card of the wrong kind.
func TestARackATSWithAnUndecodablePreferredSourceIsAdoptedAndObserved(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.card.Mu.Lock()
	h.card.ATS.Settings["preferredInput"] = "A"
	h.card.Mu.Unlock()

	h.reconcile()

	ats := h.ats()
	if !ats.Status.Adopted || !conditions.IsTrue(ats, RackCardAdoptedCondition) {
		t.Fatalf("Adopted = %v, %+v; want the card adopted", ats.Status.Adopted, conditions.Get(ats, RackCardAdoptedCondition))
	}
	if !conditions.IsTrue(ats, clusterv1.ReadyCondition) || h.gauge("observed") != 1 || ats.Status.ActiveSource != 1 {
		t.Fatalf("Ready %+v, observed %v, active %d: want the switch observed", conditions.Get(ats, clusterv1.ReadyCondition), h.gauge("observed"), ats.Status.ActiveSource)
	}
	cond := conditions.Get(ats, RackCardConvergedCondition)
	if cond == nil || cond.Reason != "PreferredSourceUnrecognised" || !strings.Contains(cond.Message, "settings.preferredInput is A") {
		t.Fatalf("Converged = %+v, want PreferredSourceUnrecognised carrying the value", cond)
	}
	if h.eventsMatching("UnsupportedCard") != 0 {
		t.Fatalf("events = %v, want no UnsupportedCard", h.events)
	}
}

// An adopted switch whose preferred source turns undecodable keeps being
// observed.
func TestAnAdoptedRackATSWhosePreferredSourceTurnsUndecodableIsStillObserved(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	h.assertAdopted(1)
	h.card.Mu.Lock()
	h.card.ATS.Settings["preferredInput"] = float64(0)
	h.card.Mu.Unlock()

	h.reconcile()

	ats := h.ats()
	if !conditions.IsTrue(ats, clusterv1.ReadyCondition) || h.gauge("observed") != 1 || !conditions.IsTrue(ats, RackATSRedundantCondition) {
		t.Fatalf("Ready %+v, Redundant %+v, observed %v: want the switch observed",
			conditions.Get(ats, clusterv1.ReadyCondition), conditions.Get(ats, RackATSRedundantCondition), h.gauge("observed"))
	}
	if cond := conditions.Get(ats, RackCardConvergedCondition); cond == nil || cond.Reason != "PreferredSourceUnrecognised" || !strings.Contains(cond.Message, "settings.preferredInput is 0") {
		t.Fatalf("Converged = %+v", cond)
	}
}

// An adopted switch whose inputs stop saying which powers the load keeps
// reporting its inputs: only the active source and redundancy are unknown.
func TestAnAdoptedRackATSWithoutAnActiveSourceStillReportsItsInputs(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	h.assertAdopted(1)
	h.card.Mu.Lock()
	h.card.ATS.EditInput = func(_ int, input map[string]any) { delete(input["status"].(map[string]any), "supply") }
	h.card.Mu.Unlock()

	h.reconcile()

	ats := h.ats()
	if !conditions.IsTrue(ats, clusterv1.ReadyCondition) || h.gauge("observed") != 1 || len(ats.Status.Inputs) != 2 || h.gauge("input_good", "2") != 1 {
		t.Fatalf("Ready %+v, observed %v, inputs %+v: want the inputs observed", conditions.Get(ats, clusterv1.ReadyCondition), h.gauge("observed"), ats.Status.Inputs)
	}
	cond := conditions.Get(ats, RackATSRedundantCondition)
	if cond == nil || cond.Status != corev1.ConditionUnknown || cond.Reason != "ActiveSourceUnrecognised" || !strings.Contains(cond.Message, "status.supply") {
		t.Fatalf("Redundant = %+v, want Unknown/ActiveSourceUnrecognised", cond)
	}
	if h.eventsMatching("UnexpectedResponse") != 0 || h.eventsMatching("LoadNotPowered") != 0 {
		t.Fatalf("events = %v", h.events)
	}
}
