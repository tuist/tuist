package linux

import (
	"context"
	"encoding/json"
	"errors"
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
		want       int32
	}{
		{
			name: "a reading displaces the configured value",
			spec: 3000, discovered: 5000, want: 5000,
		},
		{
			name: "a lower reading displaces it too",
			spec: 5000, discovered: 1000, want: 1000,
		},
		{
			name: "no reading falls back to the configured value",
			spec: 3000, discovered: 0, want: 3000,
		},
		{
			name: "a reading below the floor is refused: it would strand the node",
			spec: 3000, discovered: 1, want: 3000,
		},
		{
			// No ceiling: a box faster than anything in the fleet today must be believed.
			name: "an unusually large reading is still used",
			spec: 3000, discovered: 500_000, want: 500_000,
		},
		{
			// Annotating must retire a reading already held, not just stop the next call.
			name:     "an annotated-off machine ignores a reading it already has",
			disabled: true, spec: 3000, discovered: 5000, want: 3000,
		},
		{
			name: "an unset spec with no reading advertises nothing",
			spec: 0, discovered: 0, want: 0,
		},
		{
			// Zeroing a resolved box's budget is how an operator withdraws it from
			// egress governance; a cached reading must not keep it enrolled.
			name: "an unset spec ignores a reading already cached",
			spec: 0, discovered: 5000, want: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := effectiveEgressMbps(tt.disabled, tt.spec, tt.discovered); got != tt.want {
				t.Fatalf("effectiveEgressMbps = %d, want %d", got, tt.want)
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

	r.reconcileEgressDiscovery(context.Background(), machine)

	if machine.Status.EgressMbps != 5000 || machine.Status.EgressTier != "improved" {
		t.Fatalf("status = %d %q, want 5000 \"improved\"", machine.Status.EgressMbps, machine.Status.EgressTier)
	}
	if machine.Status.EgressResolvedAt == nil {
		t.Fatal("EgressResolvedAt should be stamped after a successful read")
	}
	select {
	case <-recorder.Events:
	default:
		t.Fatal("a first reading should emit an event")
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

			r.reconcileEgressDiscovery(context.Background(), machine)

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

			r.reconcileEgressDiscovery(context.Background(), machine)

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
	r.reconcileEgressDiscovery(context.Background(), machine)
	r.reconcileEgressDiscovery(context.Background(), machine)

	if api.calls != 1 {
		t.Fatalf("OVH was called %d times, want 1: the second attempt should be backed off", api.calls)
	}
}

func TestReconcileEgressDiscoveryRetriesAfterTheBackoff(t *testing.T) {
	api := &fakeOVHAPI{err: errors.New("ovh is down")}
	r, _ := discoveryReconciler(api)
	machine := discoveryMachine()

	r.reconcileEgressDiscovery(context.Background(), machine)
	r.egressReadFailures.Store(machine.UID, time.Now().Add(-2*egressReadRetryInterval))
	r.reconcileEgressDiscovery(context.Background(), machine)

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

	r.reconcileEgressDiscovery(context.Background(), machine)

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

	r.reconcileEgressDiscovery(context.Background(), machine)

	if machine.Status.EgressMbps != 0 || machine.Status.EgressTier != "" {
		t.Fatalf("status = %d %q, want the previous box's reading dropped",
			machine.Status.EgressMbps, machine.Status.EgressTier)
	}
}
