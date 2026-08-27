package linux

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/tools/record"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
)

func machineWithDisableAnnotation(value string) *infrav1.OVHDedicatedMachine {
	machine := &infrav1.OVHDedicatedMachine{}
	machine.Annotations = map[string]string{DisableEgressDiscoveryAnnotation: value}
	return machine
}

func TestEgressDiscoveryDisabled(t *testing.T) {
	if egressDiscoveryDisabled(&infrav1.OVHDedicatedMachine{}) {
		t.Error("a machine with no annotations should be discovered")
	}
	other := &infrav1.OVHDedicatedMachine{}
	other.Annotations = map[string]string{"tuist.dev/something-else": "true"}
	if egressDiscoveryDisabled(other) {
		t.Error("an unrelated annotation should not disable discovery")
	}

	// Presence is the whole signal: no spelling to get wrong, no "false" to explain.
	for _, value := range []string{"", " ", "true", "false", "off", "yes", "whatever"} {
		if !egressDiscoveryDisabled(machineWithDisableAnnotation(value)) {
			t.Errorf("annotation present with value %q should disable discovery", value)
		}
	}
}

func TestEffectiveEgressMbps(t *testing.T) {
	tests := []struct {
		name       string
		disabled   bool
		spec       int32
		discovered int32
		floor      int32
		override   int32
		want       int32
		wantSource string
	}{
		{
			name: "a reading above the floor is applied",
			spec: 3000, discovered: 5000, floor: 3000, want: 5000, wantSource: egressSourceDiscovery,
		},
		{
			// The ratchet: once the node advertises 5000, a later 4000 reading must
			// not walk it back down on the controller's own authority.
			name: "a reading below what the node advertises is not applied",
			spec: 3000, discovered: 4000, floor: 5000, want: 5000, wantSource: egressSourceDiscovery,
		},
		{
			// A held floor above the configured budget came from an earlier reading,
			// and must not report as configured or the next reconcile would mistake
			// it for a stale pin.
			name: "a held floor still reports discovery",
			spec: 3000, discovered: 0, floor: 5000, want: 5000, wantSource: egressSourceDiscovery,
		},
		{
			name: "a reading equal to the floor is applied",
			spec: 3000, discovered: 3000, floor: 3000, want: 3000, wantSource: egressSourceDiscovery,
		},
		{
			name: "no reading falls back to the configured budget",
			spec: 3000, discovered: 0, floor: 3000, want: 3000, wantSource: egressSourceConfigured,
		},
		{
			// No plausibility band: a decode yielding 1 after a response-shape change
			// is refused by the floor like any other low reading, and surfaced as a
			// reduction rather than quietly dropped.
			name: "a nonsense reading is refused by the floor like any other",
			spec: 3000, discovered: 1, floor: 3000, want: 3000, wantSource: egressSourceConfigured,
		},
		{
			// No ceiling: a box faster than anything in the fleet today must be believed.
			name: "an unusually large reading is still used",
			spec: 3000, discovered: 500_000, floor: 3000, want: 500_000, wantSource: egressSourceDiscovery,
		},
		{
			name: "a pin wins over a reading, downward",
			spec: 3000, discovered: 5000, floor: 5000, override: 500, want: 500, wantSource: egressSourceManual,
		},
		{
			// Upward too: the pin is the most deliberate signal there is, and the
			// raise direction is otherwise only reachable by changing the template.
			name: "a pin wins over a reading, upward",
			spec: 3000, discovered: 1000, floor: 3000, override: 8000, want: 8000, wantSource: egressSourceManual,
		},
		{
			name:     "a pin wins over a disabled machine",
			disabled: true, spec: 3000, discovered: 5000, floor: 3000, override: 500, want: 500, wantSource: egressSourceManual,
		},
		{
			// The one case where the annotation contradicts the spec rather than
			// refining it: it opts a withdrawn machine back into governance.
			name: "a pin wins over a withdrawn machine",
			spec: 0, discovered: 0, floor: 0, override: 500, want: 500, wantSource: egressSourceManual,
		},
		{
			// Explicit human decisions apply directly, downward included — the
			// ratchet only holds against the controller's own readings.
			name:     "an annotated machine drops to its configured budget",
			disabled: true, spec: 3000, discovered: 5000, floor: 5000, want: 3000, wantSource: egressSourceConfigured,
		},
		{
			name: "an unset spec with no reading advertises nothing",
			spec: 0, discovered: 0, floor: 0, want: 0, wantSource: egressSourceConfigured,
		},
		{
			name: "an unset spec withdraws the machine even from a held floor",
			spec: 0, discovered: 5000, floor: 5000, want: 0, wantSource: egressSourceConfigured,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, source := effectiveEgressMbps(tt.disabled, tt.spec, tt.discovered, tt.floor, tt.override)
			if got != tt.want || source != tt.wantSource {
				t.Fatalf("effectiveEgressMbps = %d %q, want %d %q", got, source, tt.want, tt.wantSource)
			}
		})
	}
}

func TestEgressDiscoveryDue(t *testing.T) {
	now := time.Date(2026, 8, 26, 12, 0, 0, 0, time.UTC)

	resolved := func(at time.Time, service string) *infrav1.OVHDedicatedMachine {
		machine := discoveryMachine()
		stamp := metav1.NewTime(at)
		machine.Status.EgressResolvedAt = &stamp
		machine.Status.EgressResolvedServiceName = service
		return machine
	}

	if !egressDiscoveryDue(discoveryMachine(), now) {
		t.Error("a machine that has never been resolved should be due")
	}
	if egressDiscoveryDue(resolved(now.Add(-time.Hour), "ns1.ip-1-2-3.us"), now) {
		t.Error("a reading an hour old should not be due")
	}
	if !egressDiscoveryDue(resolved(now.Add(-25*time.Hour), "ns1.ip-1-2-3.us"), now) {
		t.Error("a reading a day old should be due")
	}
	// Re-adoption swaps the box under the machine; the reading describes the old one.
	if !egressDiscoveryDue(resolved(now.Add(-time.Hour), "ns9.ip-9-9-9.us"), now) {
		t.Error("a reading taken from another service should be due")
	}
}

// fakeOVHAPI stands in for go-ovh's client. ovh.Client.API is an interface whose
// methods are all exported, so the fake is constructible from this package.
type fakeOVHAPI struct {
	body  any
	err   error
	calls int
}

func (f *fakeOVHAPI) GetWithContext(_ context.Context, _ string, res any) error {
	f.calls++
	if f.err != nil {
		return f.err
	}
	encoded, err := json.Marshal(f.body)
	if err != nil {
		return err
	}
	return json.Unmarshal(encoded, res)
}

func (f *fakeOVHAPI) PostWithContext(_ context.Context, _ string, _, _ any) error { return nil }
func (f *fakeOVHAPI) PutWithContext(_ context.Context, _ string, _, _ any) error  { return nil }
func (f *fakeOVHAPI) DeleteWithContext(_ context.Context, _ string, _ any) error  { return nil }

func egressBody(mbps int64, unit, tier string) map[string]any {
	return map[string]any{"bandwidth": map[string]any{
		"OvhToInternet": map[string]any{"unit": unit, "value": mbps},
		"type":          tier,
	}}
}

func discoveryMachine() *infrav1.OVHDedicatedMachine {
	machine := &infrav1.OVHDedicatedMachine{}
	machine.UID = "machine-uid"
	machine.Spec.EgressBudgetMbps = 3000
	machine.Status.ServiceName = "ns1.ip-1-2-3.us"
	return machine
}

func discoveryReconciler(api *fakeOVHAPI) (*OVHDedicatedMachineReconciler, *record.FakeRecorder) {
	recorder := record.NewFakeRecorder(10)
	return &OVHDedicatedMachineReconciler{
		OVHClient: &ovh.Client{API: api},
		Recorder:  recorder,
	}, recorder
}

func TestReconcileEgressDiscoveryRecordsAReading(t *testing.T) {
	api := &fakeOVHAPI{body: egressBody(5000, "Mbps", "improved")}
	r, recorder := discoveryReconciler(api)
	machine := discoveryMachine()

	r.reconcileEgressDiscovery(context.Background(), machine, machine.Spec.EgressBudgetMbps)

	if machine.Status.EgressMbps != 5000 || machine.Status.EgressTier != "improved" {
		t.Fatalf("status = %d %q, want 5000 \"improved\"", machine.Status.EgressMbps, machine.Status.EgressTier)
	}
	if machine.Status.EgressResolvedAt == nil {
		t.Fatal("EgressResolvedAt should be stamped after a successful read")
	}
	// Reading and evented are separate concerns: whether the node's budget moves is
	// the caller's decision, so discovery itself raises nothing.
	select {
	case event := <-recorder.Events:
		t.Fatalf("reading raised %q; events belong to a budget change", event)
	default:
	}
}

func TestReconcileEgressDiscoverySkipsWhatItMustNotRead(t *testing.T) {
	annotated := discoveryMachine()
	annotated.Annotations = map[string]string{DisableEgressDiscoveryAnnotation: ""}

	unconfigured := discoveryMachine()
	unconfigured.Spec.EgressBudgetMbps = 0

	unadopted := discoveryMachine()
	unadopted.Status.ServiceName = ""

	fresh := discoveryMachine()
	resolved := metav1.NewTime(time.Now().Add(-time.Hour))
	fresh.Status.EgressResolvedAt = &resolved
	fresh.Status.EgressResolvedServiceName = fresh.Status.ServiceName

	for name, machine := range map[string]*infrav1.OVHDedicatedMachine{
		"annotated out":           annotated,
		"no configured budget":    unconfigured,
		"not adopted yet":         unadopted,
		"read again inside a day": fresh,
	} {
		t.Run(name, func(t *testing.T) {
			api := &fakeOVHAPI{body: egressBody(5000, "Mbps", "improved")}
			r, _ := discoveryReconciler(api)

			r.reconcileEgressDiscovery(context.Background(), machine, machine.Spec.EgressBudgetMbps)

			if api.calls != 0 {
				t.Fatalf("OVH was called %d times, want 0", api.calls)
			}
		})
	}
}

func TestReconcileEgressDiscoveryKeepsTheLastReading(t *testing.T) {
	// The two ways a read can stop being useful must both leave the cached value
	// alone: falling back to the spec value could advertise well above the wire.
	for name, api := range map[string]*fakeOVHAPI{
		"a failed call":      {err: errors.New("ovh is down")},
		"an unusable answer": {body: map[string]any{"connection": map[string]any{"unit": "Mbps", "value": 25000}}},
	} {
		t.Run(name, func(t *testing.T) {
			r, _ := discoveryReconciler(api)
			machine := discoveryMachine()
			machine.Status.EgressMbps = 1000
			machine.Status.EgressTier = "included"
			machine.Status.EgressResolvedServiceName = machine.Status.ServiceName

			r.reconcileEgressDiscovery(context.Background(), machine, machine.Spec.EgressBudgetMbps)

			if machine.Status.EgressMbps != 1000 || machine.Status.EgressTier != "included" {
				t.Fatalf("status = %d %q, want the previous 1000 \"included\"",
					machine.Status.EgressMbps, machine.Status.EgressTier)
			}
		})
	}
}

func TestReconcileEgressDiscoveryBacksOffAFailingRead(t *testing.T) {
	api := &fakeOVHAPI{err: errors.New("ovh is down")}
	r, _ := discoveryReconciler(api)
	machine := discoveryMachine()

	// A failed read leaves EgressResolvedAt unstamped, so without the retry floor
	// a machine requeuing every 20s would call OVH every 20s.
	r.reconcileEgressDiscovery(context.Background(), machine, machine.Spec.EgressBudgetMbps)
	r.reconcileEgressDiscovery(context.Background(), machine, machine.Spec.EgressBudgetMbps)

	if api.calls != 1 {
		t.Fatalf("OVH was called %d times, want 1: the second attempt should be backed off", api.calls)
	}
}

func TestReconcileEgressDiscoveryRetriesAfterTheBackoff(t *testing.T) {
	api := &fakeOVHAPI{err: errors.New("ovh is down")}
	r, _ := discoveryReconciler(api)
	machine := discoveryMachine()

	r.reconcileEgressDiscovery(context.Background(), machine, machine.Spec.EgressBudgetMbps)
	r.egressReadFailures.Store(machine.UID, time.Now().Add(-2*egressReadRetryInterval))
	r.reconcileEgressDiscovery(context.Background(), machine, machine.Spec.EgressBudgetMbps)

	if api.calls != 2 {
		t.Fatalf("OVH was called %d times, want 2: the floor should have expired", api.calls)
	}
}

func TestReconcileEgressDiscoveryReportsAnUnusableAnswerEveryRefresh(t *testing.T) {
	// An unreadable box reports the same zero every day and an unresolved machine
	// holds zero too, so this must not be gated on the value having changed.
	api := &fakeOVHAPI{body: map[string]any{"bandwidth": nil}}
	r, _ := discoveryReconciler(api)
	machine := discoveryMachine()

	r.reconcileEgressDiscovery(context.Background(), machine, machine.Spec.EgressBudgetMbps)

	if machine.Status.EgressResolvedAt == nil {
		t.Fatal("an unusable answer should still stamp EgressResolvedAt, so it retries daily not per tick")
	}
	if machine.Status.EgressMbps != 0 {
		t.Fatalf("EgressMbps = %d, want 0 for a machine that never resolved", machine.Status.EgressMbps)
	}
}

func TestReconcileEgressDiscoveryDropsAnotherBoxesReading(t *testing.T) {
	// The paths that keep the last value when a read fails or is unusable must not
	// preserve a reading taken from a box this machine no longer holds.
	api := &fakeOVHAPI{err: errors.New("ovh is down")}
	r, _ := discoveryReconciler(api)
	machine := discoveryMachine()
	machine.Status.EgressMbps = 1000
	machine.Status.EgressTier = "included"
	machine.Status.EgressResolvedServiceName = "ns9.ip-9-9-9.us"

	r.reconcileEgressDiscovery(context.Background(), machine, machine.Spec.EgressBudgetMbps)

	if machine.Status.EgressMbps != 0 || machine.Status.EgressTier != "" {
		t.Fatalf("status = %d %q, want the previous box's reading dropped",
			machine.Status.EgressMbps, machine.Status.EgressTier)
	}
}

func TestReconcileEgressDiscoveryRecordsAReductionWithoutApplyingIt(t *testing.T) {
	api := &fakeOVHAPI{body: egressBody(1000, "Mbps", "included")}
	r, recorder := discoveryReconciler(api)
	machine := discoveryMachine() // configured at 3000

	r.reconcileEgressDiscovery(context.Background(), machine, machine.Spec.EgressBudgetMbps)

	// The reading is recorded — the reported metric and any later decision to accept
	// it are built on that — but it must not rate the node, and it must not raise an
	// event: nothing on the node changed.
	if machine.Status.EgressMbps != 1000 {
		t.Fatalf("status = %d, want the reading recorded as 1000", machine.Status.EgressMbps)
	}
	if got, _ := effectiveEgressMbps(false, machine.Spec.EgressBudgetMbps, cachedEgressMbps(machine), 3000, 0); got != 3000 {
		t.Fatalf("advertised = %d, want the configured 3000", got)
	}
	select {
	case event := <-recorder.Events:
		t.Fatalf("a refused reading raised %q; the budget did not move", event)
	default:
	}
}

func TestEgressFloor(t *testing.T) {
	ratcheted := func() *infrav1.OVHDedicatedMachine {
		machine := discoveryMachine() // configured at 3000
		machine.Status.EgressSource = egressSourceDiscovery
		return machine
	}

	if got := egressFloor(ratcheted(), 0); got != 3000 {
		t.Errorf("floor with nothing advertised = %d, want the configured 3000", got)
	}
	if got := egressFloor(ratcheted(), 5000); got != 5000 {
		t.Errorf("floor with 5000 advertised = %d, want 5000: the node must not walk back down", got)
	}
	if got := egressFloor(ratcheted(), 1000); got != 3000 {
		t.Errorf("floor with 1000 advertised = %d, want the configured 3000", got)
	}

	// A pin still in place: the floor is irrelevant (the pin wins outright) but must
	// not be computed from a value the operator typed either.
	pinned := ratcheted()
	pinned.Status.EgressSource = egressSourceManual
	pinned.Annotations = map[string]string{EgressOverrideAnnotation: "8000"}
	if got := egressFloor(pinned, 8000); got != 8000 {
		t.Errorf("floor while pinned = %d, want 8000", got)
	}

	// The pin has just been removed. Its value is still what the node advertises,
	// and carrying it into the ratchet would strand the node there forever.
	unpinned := ratcheted()
	unpinned.Status.EgressSource = egressSourceManual
	if got := egressFloor(unpinned, 8000); got != 3000 {
		t.Errorf("floor after a pin was removed = %d, want the configured 3000", got)
	}

	// No recorded source — a machine upgraded from a build without the field, or
	// one the controller has not acted on yet. What the node carries is held rather
	// than dropped: it cannot be a stale pin, since pins postdate the field, and
	// holding is the conservative direction.
	unknown := discoveryMachine()
	if got := egressFloor(unknown, 5000); got != 5000 {
		t.Errorf("floor with no recorded source = %d, want the advertised 5000 held", got)
	}
	if got := egressFloor(unknown, 0); got != 3000 {
		t.Errorf("floor with no recorded source and nothing advertised = %d, want 3000", got)
	}
}

func TestEgressOverrideMbps(t *testing.T) {
	for _, tt := range []struct {
		annotation string
		set        bool
		want       int32
	}{
		{annotation: "500", set: true, want: 500},
		{annotation: " 500 ", set: true, want: 500},
		{want: 0},
		// Ignored rather than treated as zero: zero would withdraw the machine from
		// egress governance, a far larger action than the annotation asked for.
		{annotation: "0", set: true, want: 0},
		{annotation: "-100", set: true, want: 0},
		{annotation: "lots", set: true, want: 0},
		{annotation: "", set: true, want: 0},
	} {
		machine := &infrav1.OVHDedicatedMachine{}
		if tt.set {
			machine.Annotations = map[string]string{EgressOverrideAnnotation: tt.annotation}
		}
		if got := egressOverrideMbps(machine); got != tt.want {
			t.Errorf("egressOverrideMbps(%q) = %d, want %d", tt.annotation, got, tt.want)
		}
	}
}

// TestEgressLifecycle walks the sequence an operator actually goes through:
// discovery raises the node, a low reading is held back, a pin takes it down, the
// budget is lowered to match, and the pin comes off — which must land on the
// reading rather than springing back to a stale floor.
func TestEgressLifecycle(t *testing.T) {
	machine := discoveryMachine() // configured at 3000
	advertised := int32(0)        // what the node carries between steps

	step := func(name string, discovered int32) (int32, string) {
		t.Helper()
		machine.Status.EgressMbps = discovered
		floor := egressFloor(machine, advertised)
		value, source := effectiveEgressMbps(egressDiscoveryDisabled(machine),
			machine.Spec.EgressBudgetMbps, discovered, floor, egressOverrideMbps(machine))
		machine.Status.EgressSource = source
		advertised = value
		t.Logf("%s -> %d (%s)", name, value, source)
		return value, source
	}

	if value, source := step("first reading of 5000", 5000); value != 5000 || source != egressSourceDiscovery {
		t.Fatalf("first reading = %d %q, want 5000 discovery", value, source)
	}
	if value, source := step("steady state", 5000); value != 5000 || source != egressSourceDiscovery {
		t.Fatalf("steady state = %d %q, want 5000 discovery", value, source)
	}
	if value, source := step("OVH drops to 4000", 4000); value != 5000 || source != egressSourceDiscovery {
		t.Fatalf("after a lower reading = %d %q, want the ratchet to hold 5000", value, source)
	}

	machine.Annotations = map[string]string{EgressOverrideAnnotation: "1000"}
	if value, source := step("operator pins 1000", 4000); value != 1000 || source != egressSourceManual {
		t.Fatalf("pinned = %d %q, want 1000 manual", value, source)
	}

	machine.Spec.EgressBudgetMbps = 1000
	if value, source := step("budget lowered to match, pin still on", 1000); value != 1000 || source != egressSourceManual {
		t.Fatalf("pinned after lowering the budget = %d %q, want 1000 manual", value, source)
	}

	delete(machine.Annotations, EgressOverrideAnnotation)
	if value, source := step("pin removed", 1000); value != 1000 || source != egressSourceDiscovery {
		t.Fatalf("unpinned = %d %q, want the node to land on the 1000 reading", value, source)
	}
	if value, source := step("steady state again", 1000); value != 1000 || source != egressSourceDiscovery {
		t.Fatalf("settled = %d %q, want 1000 discovery", value, source)
	}
}

// The runbook's order matters: unpinning without lowering the budget first hands
// the node back to the configured value, which is the over-commit the pin was
// hiding. Pinned here to keep that documented rather than discovered in an incident.
func TestEgressUnpinningWithoutLoweringTheBudgetSpringsBack(t *testing.T) {
	machine := discoveryMachine() // configured at 3000
	machine.Status.EgressSource = egressSourceManual
	advertised := int32(1000) // the node is carrying a pin of 1000

	floor := egressFloor(machine, advertised)
	value, source := effectiveEgressMbps(false, machine.Spec.EgressBudgetMbps, 1000, floor, egressOverrideMbps(machine))

	if value != 3000 || source != egressSourceConfigured {
		t.Fatalf("unpinned with the budget untouched = %d %q, want the configured 3000", value, source)
	}
}

func TestCachedEgressMbps(t *testing.T) {
	machine := discoveryMachine()
	machine.Status.EgressMbps = 5000
	machine.Status.EgressResolvedServiceName = machine.Status.ServiceName
	if got := cachedEgressMbps(machine); got != 5000 {
		t.Errorf("cached reading for the current box = %d, want 5000", got)
	}

	// Re-adopted onto another server: the reading describes a box this machine no
	// longer holds, so no path may rate the new one from it.
	machine.Status.ServiceName = "ns9.ip-9-9-9.us"
	if got := cachedEgressMbps(machine); got != 0 {
		t.Errorf("cached reading from another box = %d, want 0", got)
	}

	// An operator clearing serviceName to force re-adoption is the unbounded case:
	// discovery returns early, so nothing else would ever invalidate the reading.
	machine.Status.ServiceName = ""
	if got := cachedEgressMbps(machine); got != 0 {
		t.Errorf("cached reading with no service = %d, want 0", got)
	}
}

func TestEgressFloorHoldsForANeverResolvedMachine(t *testing.T) {
	// No recorded service is not a mismatch: every machine looks like this on the
	// first reconcile after the fields ship, and resetting them all would drop any
	// node whose advertised budget sits above its configured one.
	machine := discoveryMachine()
	machine.Status.EgressSource = egressSourceDiscovery

	if got := egressFloor(machine, 5000); got != 5000 {
		t.Fatalf("floor for a never-resolved machine = %d, want the advertised 5000 held", got)
	}
}

func TestEgressFloorResetsOnReAdoption(t *testing.T) {
	// The node still advertises the previous box's 5000 — our extended resource
	// survives a kubelet re-registration by design — so dropping the reading alone
	// would leave the floor holding the new box up at a number it cannot serve.
	machine := discoveryMachine()
	machine.Status.EgressSource = egressSourceDiscovery
	machine.Status.EgressResolvedServiceName = "ns9.ip-9-9-9.us"

	if got := egressFloor(machine, 5000); got != 3000 {
		t.Fatalf("floor after re-adoption = %d, want the configured 3000", got)
	}
}

// The backoff window is the path the drop used to sit behind: a failed read arms a
// 10-minute floor, and a machine re-adopted inside it would keep the previous box's
// reading in status, in the reported metric, and — before cachedEgressMbps — on the
// new box's node.
func TestReconcileEgressDiscoveryDropsAStaleReadingWhileBackedOff(t *testing.T) {
	api := &fakeOVHAPI{err: errors.New("ovh is down")}
	r, _ := discoveryReconciler(api)
	machine := discoveryMachine()
	machine.Status.EgressMbps = 5000
	machine.Status.EgressTier = "improved"
	machine.Status.EgressResolvedServiceName = machine.Status.ServiceName

	r.reconcileEgressDiscovery(context.Background(), machine, 3000) // fails, arms the backoff

	machine.Status.ServiceName = "ns9.ip-9-9-9.us" // re-adopted onto another box
	r.reconcileEgressDiscovery(context.Background(), machine, 3000)

	if api.calls != 1 {
		t.Fatalf("OVH was called %d times, want 1: the second attempt is backed off", api.calls)
	}
	if machine.Status.EgressMbps != 0 || machine.Status.EgressTier != "" {
		t.Fatalf("status = %d %q, want the previous box's reading dropped even while backed off",
			machine.Status.EgressMbps, machine.Status.EgressTier)
	}
	if got := cachedEgressMbps(machine); got != 0 {
		t.Fatalf("cached reading = %d, want 0 for a box this machine no longer holds", got)
	}
}

func TestResolvedEgressReading(t *testing.T) {
	// The only question is whether OVH gave us a number; how plausible it is, the
	// floor decides.
	for mbps, want := range map[int32]bool{0: false, -1: false, 1: true, 25: true, 5000: true} {
		if got := resolvedEgressReading(mbps); got != want {
			t.Errorf("resolvedEgressReading(%d) = %v, want %v", mbps, got, want)
		}
	}
}

func TestRecordEgressBudgetChange(t *testing.T) {
	machine := discoveryMachine()

	for _, tt := range []struct {
		name       string
		from, to   int32
		source     string
		wantEvent  string
		wantAbsent bool
	}{
		{name: "unchanged raises nothing", from: 3000, to: 3000, source: egressSourceDiscovery, wantAbsent: true},
		{name: "first budget", from: 0, to: 3000, source: egressSourceConfigured, wantEvent: "EgressBudgetIncreased"},
		{name: "raised by a reading", from: 3000, to: 5000, source: egressSourceDiscovery, wantEvent: "EgressBudgetIncreased"},
		{name: "reduced by a pin", from: 5000, to: 1000, source: egressSourceManual, wantEvent: "EgressBudgetReduced"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			recorder := record.NewFakeRecorder(10)
			r := &OVHDedicatedMachineReconciler{Recorder: recorder}

			r.recordEgressBudgetChange(machine, tt.from, tt.to, tt.source)

			select {
			case event := <-recorder.Events:
				if tt.wantAbsent {
					t.Fatalf("raised %q, want no event", event)
				}
				if !strings.Contains(event, tt.wantEvent) {
					t.Fatalf("event = %q, want %q", event, tt.wantEvent)
				}
				// The remedy is a three-move runbook, and naming one move sends
				// people to do the one that is inert on its own.
				if strings.Contains(event, "lower spec") {
					t.Fatalf("event = %q, should not prescribe a remedy", event)
				}
			default:
				if !tt.wantAbsent {
					t.Fatalf("no event raised, want %q", tt.wantEvent)
				}
			}
		})
	}
}

// Lowering the configured budget on its own is inert, which is why no event may
// prescribe it: the floor is max(advertised, spec), so the edit moves the side of
// the max that is not binding and the node stays exactly where it was.
func TestLoweringTheBudgetAloneDoesNotReduceTheNode(t *testing.T) {
	machine := discoveryMachine() // configured at 3000
	machine.Status.EgressSource = egressSourceDiscovery
	machine.Status.EgressMbps = 1000 // OVH now reports 1000
	machine.Status.EgressResolvedServiceName = machine.Status.ServiceName
	advertised := int32(5000) // the node was raised by an earlier reading

	machine.Spec.EgressBudgetMbps = 1000 // the operator lowers the budget

	floor := egressFloor(machine, advertised)
	value, source := effectiveEgressMbps(false, machine.Spec.EgressBudgetMbps,
		cachedEgressMbps(machine), floor, egressOverrideMbps(machine))

	if value != 5000 || source != egressSourceDiscovery {
		t.Fatalf("after lowering the budget = %d %q, want the node unchanged at 5000: "+
			"accepting a reduction is pin, lower, unpin", value, source)
	}
}
