package macos

import (
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power/eatontest"
)

// The PDU feeds more than minis (its ToR, an edge, a storage node), and none
// of those declares an outlet, so every outlet is read whatever is on it.
func TestRackPDURecordsEveryOutletsStateAndDraw(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.card.Mu.Lock()
	h.card.Outlets[1].Load = &eatontest.Load{ActivePower: 38, ApparentPower: 41, Current: 0.18}
	h.card.Outlets[2].Load = &eatontest.Load{ActivePower: 0.1, ApparentPower: 4.6, Current: 0.02}
	h.card.Outlets[4].Load = &eatontest.Load{ActivePower: 38, ApparentPower: 41, Current: 0.18}
	h.card.Outlets[4].On = false
	h.card.Mu.Unlock()

	h.reconcile()
	h.reconcile()

	pdu := h.pdu()
	if pdu.Status.OutletsReadAt == nil || len(pdu.Status.Outlets) != 4 {
		t.Fatalf("outlets = %+v read at %v, want all 4", pdu.Status.Outlets, pdu.Status.OutletsReadAt)
	}
	for _, want := range []struct {
		number          int
		state           power.State
		active, current string
	}{
		{1, power.StateOn, "38", "180m"},
		{2, power.StateOn, "100m", "20m"},
		{3, power.StateOn, "0", "0"},
		{4, power.StateOff, "0", "0"},
	} {
		got := pdu.Status.Outlets[want.number-1]
		if got.Number != want.number || got.State != string(want.state) || got.ActivePowerWatts == nil ||
			got.ActivePowerWatts.String() != want.active || got.CurrentAmps.String() != want.current {
			t.Fatalf("outlet %d = %+v, want %s at %s W and %s A", want.number, got, want.state, want.active, want.current)
		}
	}
	if got := testutil.ToFloat64(rackPDUOutletApparentPowerGauge.WithLabelValues("ber1-pdu-b", "ber1", "2")); got != 4.6 {
		t.Fatalf("apparent power gauge of outlet 2 = %v, want 4.6", got)
	}
	if got := testutil.ToFloat64(rackPDUOutletOnGauge.WithLabelValues("ber1-pdu-b", "ber1", "4")); got != 0 {
		t.Fatalf("on gauge of outlet 4 = %v, want 0", got)
	}
	// Reading the meters is the controller account's: its one session.
	if n := h.card.OpenSessions(); n != 1 {
		t.Fatalf("%d sessions open on the card, want only the controller account's", n)
	}
}

func TestRackPDUForgetsItsOutletsWhenTheCardStopsAnswering(t *testing.T) {
	h := newPDUHarness(t, rackPDU())
	h.reconcile()
	h.reconcile()
	if len(h.pdu().Status.Outlets) == 0 {
		t.Fatal("no outlets read from a reachable card")
	}

	h.card.Close()
	h.reconcile()

	pdu := h.pdu()
	if pdu.Status.Outlets != nil || pdu.Status.OutletsReadAt != nil {
		t.Fatalf("outlets = %+v read at %v after the card stopped answering, want none", pdu.Status.Outlets, pdu.Status.OutletsReadAt)
	}
	if n := rackPDUOutletActivePowerGauge.DeletePartialMatch(map[string]string{"pdu": "ber1-pdu-b"}); n != 0 {
		t.Fatalf("%d active power series kept for a card that stopped answering", n)
	}
}

// pduWithOutlet3 is a Ready RackPDU whose status read outlet 3 at readAt.
func pduWithOutlet3(m power.Measures, readAt time.Time) *infrav1.RackPDU {
	pdu := readyPDU(true)
	pdu.Status.Outlets = []infrav1.RackPDUOutlet{{Number: 3, State: string(power.StateOn), OutletDraw: *outletDrawStatus(m)}}
	pdu.Status.OutletsReadAt = &metav1.Time{Time: readAt}
	return pdu
}

// A host on a RackPDU takes its draw from the PDU's status: its driver is not
// metered here, and it is not asked to be.
func TestAHostOnARackPDUReadsItsDrawFromThePDU(t *testing.T) {
	r := newRackHostReconciler(t, nil, pduHost("mini-01"), pduWithOutlet3(poweredOffMini, time.Now()), pduCredentials())
	r.Power = eatonRegistry(&stubPowerDriver{on: true})

	reconcileHost(t, r, "mini-01")

	host := readHost(t, r, "mini-01")
	cond := conditionOf(host, HostDrawingCondition)
	if cond == nil || cond.Reason != PoweredOffAtOutletReason {
		t.Fatalf("HostDrawing = %+v, want %s from the PDU's reading", cond, PoweredOffAtOutletReason)
	}
	if host.Status.OutletDraw == nil || host.Status.OutletDraw.ApparentPowerVA.String() != "4600m" {
		t.Fatalf("OutletDraw = %+v, want the PDU's 4.6 VA", host.Status.OutletDraw)
	}
}

// A PDU whose controller stopped reading the card says nothing current about
// the host.
func TestAHostIgnoresAStaleRackPDUReading(t *testing.T) {
	stale := time.Now().Add(-rackPDUOutletReadingMaxAge - time.Minute)
	r := newRackHostReconciler(t, nil, pduHost("mini-01"), pduWithOutlet3(poweredOffMini, stale), pduCredentials())
	r.Power = eatonRegistry(&stubPowerDriver{on: true})

	reconcileHost(t, r, "mini-01")

	host := readHost(t, r, "mini-01")
	if cond := conditionOf(host, HostDrawingCondition); cond == nil || cond.Status != corev1.ConditionUnknown {
		t.Fatalf("HostDrawing = %+v, want Unknown for a stale reading", cond)
	}
	if host.Status.OutletDraw != nil {
		t.Fatalf("OutletDraw = %+v, want none from a stale reading", host.Status.OutletDraw)
	}
}

// On 2026-10-15 five hosts' own outlet reads failed for three minutes while
// ber1-pdu-b's reading of the same outlets stayed current, and their
// HostDrawing went Unknown with it.
func TestAFailedOutletReadKeepsTheRackPDUsReading(t *testing.T) {
	r := newRackHostReconciler(t, nil, pduHost("mini-01"), pduWithOutlet3(runningMini, time.Now()), pduCredentials())
	r.Power = eatonRegistry(erroringDriver{})

	reconcileHost(t, r, "mini-01")

	host := readHost(t, r, "mini-01")
	if cond := conditionOf(host, PowerReachableCondition); cond == nil || cond.Status != corev1.ConditionFalse {
		t.Fatalf("PowerReachable = %+v, want False for a failed read", cond)
	}
	if cond := conditionOf(host, HostDrawingCondition); cond == nil || cond.Status != corev1.ConditionTrue {
		t.Fatalf("HostDrawing = %+v, want True from the PDU's reading", cond)
	}
	if host.Status.OutletDraw == nil || host.Status.OutletDraw.ActivePowerWatts.String() != "38" {
		t.Fatalf("OutletDraw = %+v, want the PDU's 38 W", host.Status.OutletDraw)
	}
}

// An outlet of the host's own has no other reading to fall back on.
func TestAFailedReadOfAnOutletOfItsOwnLeavesTheDrawUnknown(t *testing.T) {
	r := newRackHostReconciler(t, erroringDriver{}, rackHost("mini-01"))

	reconcileHost(t, r, "mini-01")

	host := readHost(t, r, "mini-01")
	if cond := conditionOf(host, HostDrawingCondition); cond == nil || cond.Status != corev1.ConditionUnknown {
		t.Fatalf("HostDrawing = %+v, want Unknown", cond)
	}
	if host.Status.OutletDraw != nil {
		t.Fatalf("OutletDraw = %+v, want none", host.Status.OutletDraw)
	}
}
