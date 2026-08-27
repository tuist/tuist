package linux

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/client/interceptor"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
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
			// A held floor with a reading behind it is an earlier reading of the same
			// box, so "discovery" is the truth.
			name: "a held floor with a reading behind it reports discovery",
			spec: 3000, discovered: 4000, floor: 5000, want: 5000, wantSource: egressSourceDiscovery,
		},
		{
			// With no reading, the floor is whatever the node was already carrying.
			// Calling that "discovery" would claim OVH backing for a number no reading
			// supports — the shape an operator hand-lowering spec.egressBudgetMbps on a
			// live CR leaves behind.
			name: "a held floor with no reading behind it reports held",
			spec: 3000, discovered: 0, floor: 5000, want: 5000, wantSource: egressSourceHeld,
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
			// A pin refines the spec, it does not contradict it. Opting a withdrawn
			// machine in would be the one irreversible thing the annotation can do:
			// ReconcileNodeEgressCapacity would write the key and nothing would ever
			// remove it, so removing the annotation would leave the node advertising
			// the operator's number for good.
			name: "a pin does not opt a withdrawn machine back in",
			spec: 0, discovered: 0, floor: 0, override: 500, want: 0, wantSource: egressSourceConfigured,
		},
		{
			// Same for a machine that already holds a reading: zero is answered
			// before the pin, so no path re-enters governance through the annotation.
			name: "a pin does not opt a withdrawn machine in over a held floor",
			spec: 0, discovered: 5000, floor: 5000, override: 500, want: 0, wantSource: egressSourceConfigured,
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

	// A pin does not opt a zero-budget machine into governance, so it must not make
	// one worth reading either — otherwise the box costs OVH calls to produce a
	// reading nothing may rate it from.
	unconfiguredPinned := discoveryMachine()
	unconfiguredPinned.Spec.EgressBudgetMbps = 0
	unconfiguredPinned.Annotations = map[string]string{EgressOverrideAnnotation: "500"}

	unadopted := discoveryMachine()
	unadopted.Status.ServiceName = ""

	fresh := discoveryMachine()
	resolved := metav1.NewTime(time.Now().Add(-time.Hour))
	fresh.Status.EgressResolvedAt = &resolved
	fresh.Status.EgressResolvedServiceName = fresh.Status.ServiceName

	for name, machine := range map[string]*infrav1.OVHDedicatedMachine{
		"annotated out":                    annotated,
		"no configured budget":             unconfigured,
		"no configured budget, but pinned": unconfiguredPinned,
		"not adopted yet":                  unadopted,
		"read again inside a day":          fresh,
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

// A machine the discovery guards skip still gets its stale reading dropped. Those
// guards all return, so a reset placed behind them would keep the previous box's
// number in status — and in the reported metric — for as long as the machine is
// skipped, which for an annotated-out or zero-budget box is indefinitely.
func TestReconcileEgressDiscoveryDropsAStaleReadingOnSkippedMachines(t *testing.T) {
	annotated := discoveryMachine()
	annotated.Name = "ovh-annotated"
	annotated.Annotations = map[string]string{DisableEgressDiscoveryAnnotation: ""}

	unconfigured := discoveryMachine()
	unconfigured.Name = "ovh-unconfigured"
	unconfigured.Spec.EgressBudgetMbps = 0

	unadopted := discoveryMachine()
	unadopted.Name = "ovh-unadopted"
	unadopted.Status.ServiceName = "" // an operator forcing re-adoption

	for name, machine := range map[string]*infrav1.OVHDedicatedMachine{
		"annotated out":        annotated,
		"no configured budget": unconfigured,
		"serviceName cleared":  unadopted,
	} {
		t.Run(name, func(t *testing.T) {
			// A reading from the box this machine used to hold.
			machine.Status.EgressMbps = 5000
			machine.Status.EgressTier = "improved"
			machine.Status.EgressResolvedServiceName = "ns9.ip-9-9-9.us"
			recordEgressReported(machine.Name, "fleet", "ns9.ip-9-9-9.us", "improved", 5000)
			t.Cleanup(func() { forgetEgressMetrics(machine.Name) })

			api := &fakeOVHAPI{body: egressBody(1000, "Mbps", "included")}
			r, _ := discoveryReconciler(api)

			r.reconcileEgressDiscovery(context.Background(), machine, machine.Spec.EgressBudgetMbps)

			if api.calls != 0 {
				t.Fatalf("OVH was called %d times, want 0: the machine is skipped", api.calls)
			}
			if machine.Status.EgressMbps != 0 || machine.Status.EgressTier != "" {
				t.Fatalf("status = %d %q, want the previous box's reading dropped",
					machine.Status.EgressMbps, machine.Status.EgressTier)
			}
			if left := egressReportedGauge.DeletePartialMatch(
				prometheus.Labels{"node": machine.Name}); left != 0 {
				t.Errorf("reported metric still had %d series naming the previous box", left)
			}
		})
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

// egressLifecycle drives the real reconcileNodeEgress against a fake apiserver, so
// each step asserts on the Node's capacity rather than on a return value. The
// ordering inside that function is load-bearing — the floor is read before the
// source is written, and the source is written only after the capacity patch lands —
// and a test that reimplements the sequence cannot catch that ordering changing.
type egressLifecycle struct {
	t       *testing.T
	machine *infrav1.OVHDedicatedMachine
	client  client.Client
	api     *fakeOVHAPI
	r       *OVHDedicatedMachineReconciler
}

func newEgressLifecycle(t *testing.T) *egressLifecycle {
	t.Helper()
	machine := discoveryMachine() // configured at 3000
	machine.Name = "ovh-lifecycle"
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: machine.Name}}
	cl := fake.NewClientBuilder().WithScheme(egressScheme(t)).
		WithObjects(node).WithStatusSubresource(node).Build()
	api := &fakeOVHAPI{}
	r, _ := discoveryReconciler(api)
	r.Client = cl
	t.Cleanup(func() { forgetEgressMetrics(machine.Name) })
	return &egressLifecycle{t: t, machine: machine, client: cl, api: api, r: r}
}

// reports is what OVH will answer on the next reconcile, with the cached reading
// marked due so the reconcile actually goes and asks.
func (l *egressLifecycle) reports(mbps int64) {
	l.api.body = egressBody(mbps, "Mbps", "improved")
	l.machine.Status.EgressResolvedAt = nil
}

// step runs one reconcile and reports what the Node advertises afterwards.
func (l *egressLifecycle) step(name string) (int32, string) {
	l.t.Helper()
	node := &corev1.Node{}
	if err := l.client.Get(context.Background(), types.NamespacedName{Name: l.machine.Name}, node); err != nil {
		l.t.Fatalf("%s: get node: %v", name, err)
	}
	if err := l.r.reconcileNodeEgress(context.Background(), l.machine, node); err != nil {
		l.t.Fatalf("%s: %v", name, err)
	}
	advertised := advertisedNodeMbps(l.t, l.client, l.machine.Name)
	l.t.Logf("%s -> node advertises %d (%s)", name, advertised, l.machine.Status.EgressSource)
	return advertised, l.machine.Status.EgressSource
}

func (l *egressLifecycle) want(name string, mbps int32, source string) {
	l.t.Helper()
	gotMbps, gotSource := l.step(name)
	if gotMbps != mbps || gotSource != source {
		l.t.Fatalf("%s: node advertises %d (%s), want %d (%s)", name, gotMbps, gotSource, mbps, source)
	}
}

// TestEgressLifecycle walks the sequence an operator actually goes through:
// discovery raises the node, a low reading is held back, a pin takes it down, the
// budget is lowered to match, and the pin comes off — which must land on the
// reading rather than springing back to a stale floor.
func TestEgressLifecycle(t *testing.T) {
	l := newEgressLifecycle(t)

	l.reports(5000)
	l.want("first reading of 5000", 5000, egressSourceDiscovery)
	l.want("steady state", 5000, egressSourceDiscovery)

	// The ratchet: a lower reading is recorded but must not walk the node back down
	// on the controller's own authority.
	l.reports(4000)
	l.want("OVH drops to 4000", 5000, egressSourceDiscovery)

	// The reduction is confirmed at 1000, and accepting it is three moves.
	l.reports(1000)
	l.machine.Annotations = map[string]string{EgressOverrideAnnotation: "1000"}
	l.want("operator pins 1000", 1000, egressSourceManual)

	l.machine.Spec.EgressBudgetMbps = 1000
	l.want("budget lowered to match, pin still on", 1000, egressSourceManual)

	delete(l.machine.Annotations, EgressOverrideAnnotation)
	l.want("pin removed", 1000, egressSourceDiscovery)
	l.want("steady state again", 1000, egressSourceDiscovery)
}

// The release only has work to do when the pin sat ABOVE the configured budget:
// that is the case where the ratchet, anchored on what the node advertises, would
// otherwise hold the node at a number a human typed and never let go. Both other
// lifecycle paths pin at or below the budget, where the reset is inert and a broken
// ordering still produces the right answer — so this is the case that actually
// guards status.egressSource being read before it is written.
func TestEgressPinAboveTheBudgetIsReleasedCleanly(t *testing.T) {
	l := newEgressLifecycle(t) // configured at 3000

	l.reports(3000)
	l.want("settled on the configured budget", 3000, egressSourceDiscovery)

	l.machine.Annotations = map[string]string{EgressOverrideAnnotation: "8000"}
	l.want("operator pins 8000, above the budget", 8000, egressSourceManual)

	// Without the one-reconcile reset the floor would be max(8000, 3000) and the
	// node would stay at 8000 for good, labelled as though a reading supported it.
	delete(l.machine.Annotations, EgressOverrideAnnotation)
	l.want("pin removed", 3000, egressSourceDiscovery)
	l.want("steady state", 3000, egressSourceDiscovery)
}

// The runbook's order matters: unpinning without lowering the budget first hands
// the node back to the configured value, which is the over-commit the pin was
// hiding. Pinned here to keep that documented rather than discovered in an incident.
func TestEgressUnpinningWithoutLoweringTheBudgetSpringsBack(t *testing.T) {
	l := newEgressLifecycle(t) // configured at 3000

	l.reports(1000)
	l.machine.Annotations = map[string]string{EgressOverrideAnnotation: "1000"}
	l.want("operator pins 1000", 1000, egressSourceManual)

	// The budget is left at 3000, which is the mistake.
	delete(l.machine.Annotations, EgressOverrideAnnotation)
	l.want("pin removed with the budget untouched", 3000, egressSourceConfigured)
}

// Zeroing the budget stops the controller managing the capacity key; it does not
// remove it, because ReconcileNodeEgressCapacity has no path that does. Withdrawing
// a live box means deleting the machine, which deletes its Node. Asserted against
// the Node so the limitation is executable rather than a paragraph in AGENTS.md.
func TestReconcileNodeEgressCannotWithdrawANodeItAlreadyRated(t *testing.T) {
	l := newEgressLifecycle(t)

	l.reports(5000)
	l.want("rated at 5000", 5000, egressSourceDiscovery)

	l.machine.Spec.EgressBudgetMbps = 0
	l.want("budget zeroed", 5000, egressSourceConfigured)
}

// A released box must stop reporting a budget nothing is advertising any more.
// reconcileDelete calls this once the CR is going away.
func TestForgetEgressMetricsDropsEveryNodeSeries(t *testing.T) {
	const node = "ovh-forgotten"
	recordEgressBudgets(node, "fleet", 3000, 5000, egressSourceDiscovery)
	recordEgressReported(node, "fleet", "ns1.ip-1-2-3.us", "improved", 5000)

	forgetEgressMetrics(node)

	for name, gauge := range map[string]*prometheus.GaugeVec{
		"reported":   egressReportedGauge,
		"configured": egressConfiguredGauge,
		"advertised": egressAdvertisedGauge,
	} {
		if left := gauge.DeletePartialMatch(prometheus.Labels{"node": node}); left != 0 {
			t.Errorf("%s still had %d series for a released box", name, left)
		}
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
		// The helper does not write a non-positive budget and cannot remove the key,
		// so the node keeps what it had. Reporting a reduction to zero would claim a
		// change that never landed — the thing raising on the change was meant to stop.
		{name: "a withdrawn machine raises nothing", from: 5000, to: 0, source: egressSourceConfigured, wantAbsent: true},
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

// egressScheme is the minimum for a fake client that carries a Node and a machine.
func egressScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	return scheme
}

// nodeAdvertising is a Node already carrying an egress budget, which is what the
// ratchet anchors on.
func nodeAdvertising(name string, mbps int64) *corev1.Node {
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: name}}
	node.Status.Capacity = corev1.ResourceList{
		shared.EgressMbpsResource: *resource.NewQuantity(mbps, resource.DecimalSI),
	}
	return node
}

// unpinnedMachine is the state right after an operator removes a pin: the source
// still says a human decided the last budget, and the node still carries their
// number, while a lower reading from OVH sits in status.
func unpinnedMachine() *infrav1.OVHDedicatedMachine {
	machine := discoveryMachine() // configured at 3000
	machine.Name = "ovh-1"
	machine.Status.EgressSource = egressSourceManual
	machine.Status.EgressMbps = 5000
	machine.Status.EgressResolvedServiceName = machine.Status.ServiceName
	resolved := metav1.NewTime(time.Now())
	machine.Status.EgressResolvedAt = &resolved
	return machine
}

func advertisedNodeMbps(t *testing.T, cl client.Client, name string) int32 {
	t.Helper()
	node := &corev1.Node{}
	if err := cl.Get(context.Background(), types.NamespacedName{Name: name}, node); err != nil {
		t.Fatalf("get node: %v", err)
	}
	return shared.NodeEgressMbps(node)
}

// The pin release is a one-shot: it fires while status.egressSource says "manual"
// and ends when the new source is recorded. Recording it on a reconcile whose
// capacity patch failed would spend the reset without moving the node, and from the
// next reconcile the ratchet anchors on the pin's value and holds it there for good.
func TestReconcileNodeEgressKeepsThePinReleaseWhenTheNodeWriteFails(t *testing.T) {
	scheme := egressScheme(t)
	machine := unpinnedMachine()
	node := nodeAdvertising(machine.Name, 8000)

	failing := fake.NewClientBuilder().WithScheme(scheme).WithObjects(node).
		WithStatusSubresource(node).
		WithInterceptorFuncs(interceptor.Funcs{
			SubResourcePatch: func(context.Context, client.Client, string, client.Object, client.Patch, ...client.SubResourcePatchOption) error {
				return errors.New("apiserver said no")
			},
		}).Build()
	r, _ := discoveryReconciler(&fakeOVHAPI{err: errors.New("not read on this path")})
	r.Client = failing

	if err := r.reconcileNodeEgress(context.Background(), machine, node.DeepCopy()); err == nil {
		t.Fatal("a failed capacity patch should surface as an error")
	}
	if machine.Status.EgressSource != egressSourceManual {
		t.Fatalf("EgressSource = %q, want it left at %q so the next reconcile retries the release",
			machine.Status.EgressSource, egressSourceManual)
	}

	// The retry, against a working apiserver, lands on the reading rather than the
	// removed pin's 8000.
	working := fake.NewClientBuilder().WithScheme(scheme).WithObjects(node).WithStatusSubresource(node).Build()
	r.Client = working
	fresh := &corev1.Node{}
	if err := working.Get(context.Background(), types.NamespacedName{Name: machine.Name}, fresh); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileNodeEgress(context.Background(), machine, fresh); err != nil {
		t.Fatalf("retry: %v", err)
	}
	if got := advertisedNodeMbps(t, working, machine.Name); got != 5000 {
		t.Fatalf("node advertises %d, want the 5000 reading rather than the removed pin's 8000", got)
	}
	if machine.Status.EgressSource != egressSourceDiscovery {
		t.Fatalf("EgressSource = %q, want %q once the node carries the new budget",
			machine.Status.EgressSource, egressSourceDiscovery)
	}
}
