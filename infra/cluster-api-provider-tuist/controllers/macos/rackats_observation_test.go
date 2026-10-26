package macos

import (
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"
	corev1 "k8s.io/api/core/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power/eatontest"
)

// A load neither source powered that comes back is recorded like any other
// change of the source powering it: an event, status.lastTransfer from 0,
// and the counter with from="0".
func TestRackATSReportsALoadThatComesBack(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	lost := h.gauge("observed_transfers_total", "1", "0")
	restored := h.gauge("observed_transfers_total", "0", "2")

	h.card.SetSource(2, eatontest.SourceMissing, 0)
	h.card.SetSource(1, eatontest.SourceMissing, 0)
	h.reconcile()
	ats := h.ats()
	if ats.Status.ActiveSource != 0 || ats.Status.LastTransfer == nil || ats.Status.LastTransfer.From != 1 || ats.Status.LastTransfer.To != 0 {
		t.Fatalf("after the load lost power: active %d, last transfer %+v", ats.Status.ActiveSource, ats.Status.LastTransfer)
	}

	h.card.SetSource(2, eatontest.SourceGood, 230.2)
	h.reconcile()

	ats = h.ats()
	if ats.Status.ActiveSource != 2 || ats.Status.LastTransfer == nil || ats.Status.LastTransfer.From != 0 || ats.Status.LastTransfer.To != 2 {
		t.Fatalf("after the load came back: active %d, last transfer %+v", ats.Status.ActiveSource, ats.Status.LastTransfer)
	}
	if h.eventsMatching("LoadRestored") != 1 || h.eventsMatching("LoadNotPowered") != 1 {
		t.Fatalf("events = %v, want one LoadNotPowered and one LoadRestored", h.events)
	}
	if h.gauge("observed_transfers_total", "1", "0") != lost+1 || h.gauge("observed_transfers_total", "0", "2") != restored+1 {
		t.Fatal("the counter did not record the load going and coming back")
	}
}

// Standalone is no observation: nothing reads a stale Redundant as current.
func TestStandaloneRackATSHasNoObservation(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	if !conditions.IsTrue(h.ats(), RackATSRedundantCondition) {
		t.Fatal("not Redundant after adoption")
	}
	h.update(func(a *infrav1.RackATS) { a.Spec.ManagedBy = infrav1.RackCardManagedByStandalone })

	h.reconcile()

	if cond := h.condition(RackATSRedundantCondition); cond == nil || cond.Status != corev1.ConditionUnknown || cond.Reason != "Standalone" {
		t.Fatalf("Redundant = %+v, want Unknown/Standalone", cond)
	}
}

// A switch that cannot be read says nothing about convergence.
func TestRackATSConvergedIsUnknownWhenTheCardCannotBeRead(t *testing.T) {
	t.Run("login refused", func(t *testing.T) {
		h := newATSHarness(t, rackATS())
		h.reconcile()
		h.card.Mu.Lock()
		for _, a := range h.card.Accounts {
			if a.Name == "tuist-controller" {
				a.Password = "Somebody-else1"
			}
		}
		h.card.Mu.Unlock()
		h.card.Expire()
		setAccountPassword(h.card, "admin", "Somebody-else2")
		h.reconcile()
		if cond := h.condition(RackCardConvergedCondition); cond == nil || cond.Status != corev1.ConditionUnknown {
			t.Fatalf("Converged = %+v, want Unknown", cond)
		}
	})
	t.Run("unreachable", func(t *testing.T) {
		h := newATSHarness(t, rackATS())
		h.reconcile()
		h.card.Close()
		h.reconcile()
		if cond := h.condition(RackCardConvergedCondition); cond == nil || cond.Status != corev1.ConditionUnknown {
			t.Fatalf("Converged = %+v, want Unknown", cond)
		}
	})
}

// A transfer switch's card is a card, not an outlet.
func TestRackATSMessagesNameTheCard(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	h.card.Mu.Lock()
	for _, a := range h.card.Accounts {
		if a.Name == "tuist-controller" {
			a.Password = "Somebody-else1"
		}
	}
	h.card.Mu.Unlock()
	h.card.Expire()
	setAccountPassword(h.card, "admin", "Somebody-else2")
	h.reconcile()

	message := conditions.GetMessage(h.ats(), clusterv1.ReadyCondition)
	if strings.Contains(message, "outlet") || !strings.Contains(message, "card at "+h.card.URL()) {
		t.Fatalf("Ready message %q, want it to name the card", message)
	}
}

// The outputs are read with the rest of the observation, into status and
// gauges; a card that serves none is still observed, saying why.
func TestRackATSReportsItsOutputs(t *testing.T) {
	h := newATSHarness(t, rackATS())
	h.reconcile()
	ats := h.ats()
	if !conditions.IsTrue(ats, clusterv1.ReadyCondition) || len(ats.Status.Outputs) != 0 || !strings.Contains(ats.Status.OutputsMessage, "404") {
		t.Fatalf("without outputs: Ready %+v, outputs %+v, message %q", conditions.Get(ats, clusterv1.ReadyCondition), ats.Status.Outputs, ats.Status.OutputsMessage)
	}
	if n := testutil.CollectAndCount(rackATSOutputCurrent); n != 0 {
		t.Fatalf("%d output current series for a card that serves no outputs", n)
	}
	if got := h.gauge("input_current_amps", "1"); got != 0.5 {
		t.Fatalf("capt_rackats_input_current_amps{source=1} = %v", got)
	}

	h.card.Mu.Lock()
	h.card.ATS.Outputs = []map[string]any{{"current": 2.5, "voltage": 230.4, "apparentPower": 576.0}}
	h.card.Mu.Unlock()
	h.reconcile()
	ats = h.ats()
	want := infrav1.RackATSOutput{Output: 1, Current: "2.5", Voltage: "230.4", ApparentPower: "576", Detail: "apparentPower=576 current=2.5 voltage=230.4"}
	if len(ats.Status.Outputs) != 1 || ats.Status.Outputs[0] != want || ats.Status.OutputsMessage != "" {
		t.Fatalf("outputs %+v, message %q", ats.Status.Outputs, ats.Status.OutputsMessage)
	}
	for name, value := range map[string]float64{"output_current_amps": 2.5, "output_voltage_volts": 230.4, "output_apparent_power_va": 576} {
		if got := h.gauge(name, "1"); got != value {
			t.Fatalf("capt_rackats_%s{output=1} = %v, want %v", name, got, value)
		}
	}
	if n := testutil.CollectAndCount(rackATSOutputActivePower); n != 0 {
		t.Fatalf("%d active power series for an output that reports none", n)
	}

	forgetRackATSMetrics(testATS)
	if n := testutil.CollectAndCount(rackATSOutputCurrent); n != 0 {
		t.Fatalf("%d output series left for a forgotten RackATS", n)
	}
}
