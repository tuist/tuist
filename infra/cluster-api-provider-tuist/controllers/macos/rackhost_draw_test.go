package macos

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/client-go/tools/record"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

// meteredPowerDriver is a stubPowerDriver whose outlet has a meter.
type meteredPowerDriver struct {
	*stubPowerDriver
	measures power.Measures
	err      error
}

func (d *meteredPowerDriver) Measures(context.Context, power.Outlet) (power.Measures, error) {
	return d.measures, d.err
}

func reading(active, apparent float64) power.Measures {
	return power.Measures{ActivePower: &active, ApparentPower: &apparent}
}

// The readings below are ber1-pdu-b's on 2026-10-14 (see power.Classify).
var (
	runningMini    = reading(38, 41)
	poweredOffMini = reading(0.1, 4.6)
	emptyOutlet    = reading(0, 0)
)

func drainEvents(r record.EventRecorder) []string {
	var events []string
	for {
		select {
		case e := <-r.(*record.FakeRecorder).Events:
			events = append(events, e)
		default:
			return events
		}
	}
}

func eventsWith(events []string, reason string) int {
	n := 0
	for _, e := range events {
		if strings.Contains(e, " "+reason+" ") {
			n++
		}
	}
	return n
}

func TestReconcileRecordsTheOutletsDraw(t *testing.T) {
	driver := &meteredPowerDriver{stubPowerDriver: &stubPowerDriver{on: true}, measures: runningMini}
	r := newRackHostReconciler(t, nil, rackHost("draw-running"))
	r.Power = registryWithShelly(driver)

	reconcileHost(t, r, "draw-running")

	host := readHost(t, r, "draw-running")
	if host.Status.OutletDraw == nil || host.Status.OutletDraw.ActivePowerWatts.String() != "38" || host.Status.OutletDraw.ApparentPowerVA.String() != "41" {
		t.Fatalf("OutletDraw = %+v, want 38 W and 41 VA", host.Status.OutletDraw)
	}
	if cond := conditionOf(host, HostDrawingCondition); cond == nil || cond.Status != corev1.ConditionTrue {
		t.Fatalf("HostDrawing = %+v, want True", cond)
	}
	if got := testutil.ToFloat64(rackHostOutletActivePowerGauge.WithLabelValues("draw-running", "ber1")); got != 38 {
		t.Fatalf("active power gauge = %v, want 38", got)
	}
	if got := testutil.ToFloat64(rackHostOutletApparentPowerGauge.WithLabelValues("draw-running", "ber1")); got != 41 {
		t.Fatalf("apparent power gauge = %v, want 41", got)
	}
	if got := testutil.ToFloat64(rackHostPoweredOffAtOutletGauge.WithLabelValues("draw-running", "ber1")); got != 0 {
		t.Fatalf("powered-off gauge = %v, want 0", got)
	}
}

// ber1-runner-b04 to b09 sat in this state for two and a half days on
// 2026-10-14, bootstrapping and cycling in a loop that could never start them.
func TestAMiniPluggedInAndOffAsksForItsPowerButtonOnce(t *testing.T) {
	driver := &meteredPowerDriver{stubPowerDriver: &stubPowerDriver{on: true}, measures: poweredOffMini}
	r := newRackHostReconciler(t, nil, rackHost("draw-off"))
	r.Power = registryWithShelly(driver)

	reconcileHost(t, r, "draw-off")
	reconcileHost(t, r, "draw-off")

	host := readHost(t, r, "draw-off")
	cond := conditionOf(host, HostDrawingCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != PoweredOffAtOutletReason {
		t.Fatalf("HostDrawing = %+v, want False/%s", cond, PoweredOffAtOutletReason)
	}
	if !strings.Contains(cond.Message, "power button") {
		t.Fatalf("message %q does not say what to do", cond.Message)
	}
	if n := eventsWith(drainEvents(r.Recorder), PoweredOffAtOutletReason); n != 1 {
		t.Fatalf("%d %s events over two reconciles, want 1", n, PoweredOffAtOutletReason)
	}
	if got := testutil.ToFloat64(rackHostPoweredOffAtOutletGauge.WithLabelValues("draw-off", "ber1")); got != 1 {
		t.Fatalf("powered-off gauge = %v, want 1", got)
	}
}

func TestAnEmptyOutletReadsAsNoLoad(t *testing.T) {
	driver := &meteredPowerDriver{stubPowerDriver: &stubPowerDriver{on: true}, measures: emptyOutlet}
	r := newRackHostReconciler(t, nil, rackHost("draw-empty"))
	r.Power = registryWithShelly(driver)

	reconcileHost(t, r, "draw-empty")

	cond := conditionOf(readHost(t, r, "draw-empty"), HostDrawingCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != NoLoadOnOutletReason {
		t.Fatalf("HostDrawing = %+v, want False/%s", cond, NoLoadOnOutletReason)
	}
}

// A switched-off outlet reads zero whatever is plugged in, so it says nothing
// about the mini.
func TestASwitchedOffOutletIsNotReadAsEmpty(t *testing.T) {
	driver := &meteredPowerDriver{stubPowerDriver: &stubPowerDriver{on: false}, measures: emptyOutlet}
	r := newRackHostReconciler(t, nil, rackHost("draw-switched-off"))
	r.Power = registryWithShelly(driver)

	reconcileHost(t, r, "draw-switched-off")

	cond := conditionOf(readHost(t, r, "draw-switched-off"), HostDrawingCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != OutletOffReason {
		t.Fatalf("HostDrawing = %+v, want False/%s", cond, OutletOffReason)
	}
}

func TestAnOutletWithoutAMeterLeavesTheDrawUnknown(t *testing.T) {
	r := newRackHostReconciler(t, &stubPowerDriver{on: true}, rackHost("draw-unmetered"))

	reconcileHost(t, r, "draw-unmetered")

	host := readHost(t, r, "draw-unmetered")
	if host.Status.OutletDraw != nil {
		t.Fatalf("OutletDraw = %+v, want none", host.Status.OutletDraw)
	}
	if cond := conditionOf(host, HostDrawingCondition); cond == nil || cond.Status != corev1.ConditionUnknown {
		t.Fatalf("HostDrawing = %+v, want Unknown", cond)
	}
	for name, gauge := range map[string]*prometheus.GaugeVec{
		"active power": rackHostOutletActivePowerGauge,
		"powered off":  rackHostPoweredOffAtOutletGauge,
	} {
		if n := seriesFor(gauge, "draw-unmetered"); n != 0 {
			t.Fatalf("%s gauge has %d series for an unmetered outlet, want none", name, n)
		}
	}
}

// seriesFor counts a host's series by deleting them, so it goes last in a test.
func seriesFor(gauge *prometheus.GaugeVec, host string) int {
	return gauge.DeletePartialMatch(prometheus.Labels{"host": host})
}

// A reading that disappears takes its value with it, rather than leaving the
// last one standing.
func TestAFailedMeterReadDropsTheLastReading(t *testing.T) {
	driver := &meteredPowerDriver{stubPowerDriver: &stubPowerDriver{on: true}, measures: runningMini}
	r := newRackHostReconciler(t, nil, rackHost("draw-lost"))
	r.Power = registryWithShelly(driver)
	reconcileHost(t, r, "draw-lost")

	driver.err = errors.New("dial 192.168.0.16:443: i/o timeout")
	reconcileHost(t, r, "draw-lost")

	host := readHost(t, r, "draw-lost")
	if host.Status.OutletDraw != nil {
		t.Fatalf("OutletDraw = %+v after a failed read, want none", host.Status.OutletDraw)
	}
	if cond := conditionOf(host, HostDrawingCondition); cond == nil || cond.Status != corev1.ConditionUnknown {
		t.Fatalf("HostDrawing = %+v, want Unknown", cond)
	}
	if n := seriesFor(rackHostOutletActivePowerGauge, "draw-lost"); n != 0 {
		t.Fatalf("active power gauge kept %d series after a failed read", n)
	}
}

// --- bootstrap recovery -----------------------------------------------------

func TestBootstrapRecoveryDoesNotCycleAMiniThatIsPoweredOff(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.BootstrapAttempts = 2
	})
	host := rackHost("mini-01")
	r := newRackReconciler(t, host, machine)
	driver := &meteredPowerDriver{stubPowerDriver: &stubPowerDriver{on: true}, measures: poweredOffMini}
	r.Power = registryWithShelly(driver)

	r.handleBootstrapFailure(context.Background(), machine, host, errors.New("SSH not available after 5m"))

	if got := driver.recorded(); len(got) != 0 {
		t.Fatalf("outlet calls = %v; a cycle cannot start a mini without autorestart", got)
	}
	if machine.Status.BootstrapRebootIssued {
		t.Fatal("BootstrapRebootIssued set without a cycle; a mini started later would never get one")
	}
	if n := eventsWith(drainEvents(r.Recorder), "PowerButtonNeeded"); n != 1 {
		t.Fatalf("%d PowerButtonNeeded events, want 1", n)
	}
}

func TestBootstrapRecoveryCyclesAMiniThatIsDrawing(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.BootstrapAttempts = 2
	})
	host := rackHost("mini-01")
	r := newRackReconciler(t, host, machine)
	driver := &meteredPowerDriver{stubPowerDriver: &stubPowerDriver{on: true}, measures: runningMini}
	r.Power = registryWithShelly(driver)

	r.handleBootstrapFailure(context.Background(), machine, host, errors.New("ssh wedged"))

	if got := driver.recorded(); len(got) != 2 {
		t.Fatalf("outlet calls = %v, want an off then an on", got)
	}
	if !machine.Status.BootstrapRebootIssued {
		t.Fatal("BootstrapRebootIssued not set after the cycle")
	}
}

// A meter that cannot be read is no reason to withhold the only remote
// recovery a rack host has.
func TestBootstrapRecoveryCyclesWhenTheMeterCannotBeRead(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.BootstrapAttempts = 2
	})
	host := rackHost("mini-01")
	r := newRackReconciler(t, host, machine)
	driver := &meteredPowerDriver{stubPowerDriver: &stubPowerDriver{on: true}, err: errors.New("i/o timeout")}
	r.Power = registryWithShelly(driver)

	r.handleBootstrapFailure(context.Background(), machine, host, errors.New("ssh wedged"))

	if got := driver.recorded(); len(got) != 2 {
		t.Fatalf("outlet calls = %v, want an off then an on", got)
	}
}
