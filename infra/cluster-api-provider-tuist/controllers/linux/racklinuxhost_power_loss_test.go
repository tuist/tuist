package linux

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/device-management-toolkit/go-wsman-messages/v2/pkg/wsman/cim/power"
	"github.com/prometheus/client_golang/prometheus/testutil"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/event"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// fakeAMTPower is a host's AMT: it reports state, or readErr, to a read, and
// records each power change.
type fakeAMTPower struct {
	state   string
	readErr error
	reads   int
	changes []powerCall
}

func (f *fakeAMTPower) power(_ context.Context, via *infrav1.RackLinuxHost, address string, _ amtCredentials, change amtPowerChange) (amtResponse, error) {
	if change.read {
		f.reads++
		if f.readErr != nil {
			return amtResponse{}, f.readErr
		}
		return amtResponse{PowerState: f.state}, nil
	}
	f.changes = append(f.changes, powerCall{via: via.Name, address: address, state: change.state, netboot: change.netboot})
	return amtResponse{}, nil
}

func newPowerLossHarness(t *testing.T, host *infrav1.RackLinuxHost, state string) (*installHarness, *fakeAMTPower) {
	t.Helper()
	h, _ := newPowerHarness(t, host, otherConnectedEdge(), amtSecret("Stored-Pa55!"))
	amt := &fakeAMTPower{state: state}
	h.r.AMTPower = amt.power
	return h, amt
}

// A host that drops off the tailnet is read from AMT at once, as whatever took
// it off may have taken its power: after a power loss an MS-01 whose firmware
// does not restore stays off. One that should be on is powered on.
func TestRackPowerPowersOnAHostAPowerLossLeftOff(t *testing.T) {
	h, amt := newPowerLossHarness(t, activatedAMTEdge(""), rackPowerOn)
	got := h.reconcile(t, edgeUUID)
	if got.Status.Power.Source != powerSourceTailnet {
		t.Fatalf("power %+v, want it from the tailnet", got.Status.Power)
	}

	h.api.devices[0].ConnectedToControl = false
	amt.state = rackPowerOff
	h.now = installEpoch.Add(time.Minute)
	drainEvents(h)
	got = h.reconcile(t, edgeUUID)

	if len(amt.changes) != 1 || amt.changes[0].state != power.PowerOn || amt.changes[0].via != "ber1-edge-b" {
		t.Fatalf("power changes %+v, want the host powered on through the other edge", amt.changes)
	}
	if p := got.Status.Power; p.State != rackPowerOff || p.Source != powerSourceAMT || p.Changes != 1 {
		t.Fatalf("power %+v", p)
	}
	if c := conditions.Get(got, PowerCondition); c == nil || c.Status != "False" || c.Reason != "PowerChanging" {
		t.Fatalf("condition %+v", c)
	}
	evented := false
	for _, e := range drainEvents(h) {
		evented = evented || (strings.Contains(e, "PowerChanged") && strings.Contains(e, "it was off"))
	}
	if !evented {
		t.Fatal("no event says the host was found off and powered on")
	}
}

// Power-ons that do not take are spaced further apart each time, and the
// condition warns from the third. Once the host is on, the count starts over.
func TestRackPowerBacksOffPowerOnsThatDoNotTake(t *testing.T) {
	h, amt := newPowerLossHarness(t, activatedAMTEdge(""), rackPowerOff)
	h.api.devices[0].ConnectedToControl = false

	for _, step := range []struct {
		at      time.Duration
		changes int
	}{
		{0, 1},
		{4 * time.Minute, 1}, {5 * time.Minute, 2},
		{14 * time.Minute, 2}, {15 * time.Minute, 3},
		{34 * time.Minute, 3}, {35 * time.Minute, 4},
		{36 * time.Minute, 4},
	} {
		h.now = installEpoch.Add(step.at)
		h.reconcile(t, edgeUUID)
		if len(amt.changes) != step.changes {
			t.Fatalf("at +%s: %d power changes, want %d", step.at, len(amt.changes), step.changes)
		}
	}
	got := h.reconcile(t, edgeUUID)
	if got.Status.Power.Changes != 4 {
		t.Fatalf("changes %d, want 4", got.Status.Power.Changes)
	}
	if c := conditions.Get(got, PowerCondition); c == nil || c.Severity != clusterv1.ConditionSeverityWarning || !strings.Contains(c.Message, "after 4 power change(s)") {
		t.Fatalf("condition %+v, want a warning", c)
	}

	amt.state = rackPowerOn
	h.now = installEpoch.Add(45 * time.Minute)
	got = h.reconcile(t, edgeUUID)
	if len(amt.changes) != 4 || got.Status.Power.State != rackPowerOn || got.Status.Power.Changes != 0 || !conditions.IsTrue(got, PowerCondition) {
		t.Fatalf("changes %d, power %+v, condition %+v", len(amt.changes), got.Status.Power, conditions.Get(got, PowerCondition))
	}
}

func TestRackPowerChangeWaitIsCapped(t *testing.T) {
	r := &RackLinuxHostReconciler{}
	host := activatedAMTEdge("")
	host.Status.AMT.LastPowerAction = &infrav1.RackLinuxHostAMTPowerAction{Action: "on", At: metav1.NewTime(installEpoch)}
	host.Status.Power = &infrav1.RackLinuxHostPowerStatus{Changes: 40}

	if got := r.powerChangeWait(host, installEpoch); got != amtPowerChangeBackoffMax {
		t.Fatalf("wait %s, want %s", got, amtPowerChangeBackoffMax)
	}
}

// A host deliberately powered off (spec.online false) is left off.
func TestRackPowerLeavesAHostThatShouldBeOffOff(t *testing.T) {
	host := activatedAMTEdge("")
	host.Spec.Online = false
	h, amt := newPowerLossHarness(t, host, rackPowerOff)
	h.api.devices[0].ConnectedToControl = false

	got := h.reconcile(t, edgeUUID)

	if len(amt.changes) != 0 || !conditions.IsTrue(got, PowerCondition) {
		t.Fatalf("power changes %+v, condition %+v", amt.changes, conditions.Get(got, PowerCondition))
	}
}

// A reboot takes the host off the tailnet and through off. It is not powered
// on in the middle of it.
func TestRackPowerWaitsOutARebootBeforePoweringOn(t *testing.T) {
	host := activatedAMTEdge("")
	host.Status.AMT.LastPowerAction = &infrav1.RackLinuxHostAMTPowerAction{Action: "cycle", At: metav1.NewTime(installEpoch.Add(-time.Minute))}
	h, amt := newPowerLossHarness(t, host, rackPowerOff)
	h.api.devices[0].ConnectedToControl = false

	got := h.reconcile(t, edgeUUID)
	if len(amt.changes) != 0 {
		t.Fatalf("power changes %+v during a reboot", amt.changes)
	}
	if c := conditions.Get(got, PowerCondition); c == nil || c.Reason != "WaitingForReboot" {
		t.Fatalf("condition %+v", c)
	}

	h.now = installEpoch.Add(amtPowerChangeBackoff)
	h.reconcile(t, edgeUUID)
	if len(amt.changes) != 1 || amt.changes[0].state != power.PowerOn {
		t.Fatalf("power changes %+v, want the host powered on once the reboot had its time", amt.changes)
	}
}

// AMT reports no address while it sees no link, and keeps the static one the
// operator gave it, so a host whose last read had none is reached there.
func TestRackPowerReachesAMTAtItsStaticAddressWhileItReportsNone(t *testing.T) {
	host := activatedAMTEdge("")
	host.Status.AMT.Address = "0.0.0.0"
	host.Status.AMT.AssignedAddress = "192.168.50.19/24"
	h, amt := newPowerLossHarness(t, host, rackPowerOff)
	h.api.devices[0].ConnectedToControl = false

	h.reconcile(t, edgeUUID)

	if len(amt.changes) != 1 || amt.changes[0].address != "192.168.50.19" {
		t.Fatalf("power changes %+v, want AMT asked at its static address", amt.changes)
	}
}

// A host off the tailnet whose AMT cannot be asked is reported, so a host left
// off after a power loss does not go unnoticed.
func TestRackPowerReportsAHostItCannotPowerOn(t *testing.T) {
	host := activatedAMTEdge("")
	host.Status.AMT.ControlMode = "pre-provisioning"
	h, amt := newPowerLossHarness(t, host, rackPowerOff)
	h.api.devices[0].ConnectedToControl = false

	got := h.reconcile(t, edgeUUID)

	if len(amt.changes) != 0 || amt.reads != 0 {
		t.Fatalf("asked a pre-provisioned AMT: %d reads, changes %+v", amt.reads, amt.changes)
	}
	if c := conditions.Get(got, PowerCondition); c == nil || c.Reason != "CannotPowerOn" {
		t.Fatalf("condition %+v", c)
	}
}

// PowerReachable says whether the host could be powered on through AMT if it
// lost power now.
func TestRackPowerReachable(t *testing.T) {
	for _, tc := range []struct {
		name   string
		change func(*infrav1.RackLinuxHost)
		err    error
		reason string
	}{
		{name: "reachable"},
		{name: "not activated", change: func(h *infrav1.RackLinuxHost) { h.Status.AMT.ControlMode = "pre-provisioning" }, reason: "AMTNotActivated"},
		{name: "no link", change: func(h *infrav1.RackLinuxHost) {
			h.Status.AMT.Link = "down"
			h.Status.AMT.Address = "0.0.0.0"
			h.Status.AMT.AssignedAddress = "192.168.50.19/24"
		}, reason: "AMTLinkDown"},
		{name: "unreachable", err: errors.New("dial tcp 192.168.50.112:16993: i/o timeout"), reason: "AMTUnreachable"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			host := activatedAMTEdge("")
			if tc.change != nil {
				tc.change(host)
			}
			h, amt := newPowerLossHarness(t, host, rackPowerOn)
			amt.readErr = tc.err

			got := h.reconcile(t, edgeUUID)

			c := conditions.Get(got, PowerReachableCondition)
			gauge := testutil.ToFloat64(rackLinuxHostPowerReachableGauge.WithLabelValues("ber1-edge", "ber1"))
			if tc.reason == "" {
				if c == nil || c.Status != "True" || gauge != 1 {
					t.Fatalf("condition %+v, gauge %v; want reachable", c, gauge)
				}
				return
			}
			if c == nil || c.Status != "False" || c.Reason != tc.reason || gauge != 0 {
				t.Fatalf("condition %+v, gauge %v; want %s", c, gauge, tc.reason)
			}
			if !conditions.IsTrue(got, PowerCondition) {
				t.Fatalf("a host on the tailnet reported %+v", conditions.Get(got, PowerCondition))
			}
		})
	}
}

// An edge that comes onto the tailnet is the way to its site's AMT, so the
// site's other hosts are looked at again at once.
func TestRackPowerLooksAtTheSiteAgainWhenAnEdgeJoins(t *testing.T) {
	store := otherEdge("ber1-store-a", rackTestNamespace, "ber1", "storage", false)
	elsewhere := otherEdge("ber2-store-a", rackTestNamespace, "ber2", "storage", false)
	h := newInstallHarness(t, edgeHost(), store, elsewhere)

	edge := edgeHost()
	requests := h.r.siteHostsOfEdge(context.Background(), edge)
	if len(requests) != 1 || requests[0].Name != "ber1-store-a" {
		t.Fatalf("requests %+v, want the edge's site's other host", requests)
	}

	joined := edgeJoinedTailnet()
	off, on := edgeHost(), edgeHost()
	on.Status.Tailnet = &infrav1.RackLinuxHostTailnetStatus{Connected: true}
	off.Status.Tailnet = &infrav1.RackLinuxHostTailnetStatus{Connected: false}
	if !joined.Update(event.UpdateEvent{ObjectOld: off, ObjectNew: on}) {
		t.Fatal("an edge joining the tailnet woke nothing")
	}
	if joined.Update(event.UpdateEvent{ObjectOld: on, ObjectNew: on.DeepCopy()}) || joined.Update(event.UpdateEvent{ObjectOld: on, ObjectNew: off}) {
		t.Fatal("an edge that did not just join woke its site")
	}
	storeOn := store.DeepCopy()
	storeOn.Status.Tailnet.Connected = true
	if joined.Update(event.UpdateEvent{ObjectOld: store, ObjectNew: storeOn}) {
		t.Fatal("a host that is not an edge woke its site")
	}
}
