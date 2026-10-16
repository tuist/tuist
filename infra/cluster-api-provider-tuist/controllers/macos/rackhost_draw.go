package macos

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

const (
	// HostDrawingCondition reports whether the host draws power from its
	// outlet, as the outlet's meter reads it (see power.Classify). False with
	// PoweredOffAtOutlet is a mini plugged in and off, which only someone at
	// the rack can start.
	HostDrawingCondition clusterv1.ConditionType = "HostDrawing"

	HostDrawingReason        = "Drawing"
	PoweredOffAtOutletReason = "PoweredOffAtOutlet"
	NoLoadOnOutletReason     = "NoLoadOnOutlet"
	OutletOffReason          = "OutletOff"
	OutletDrawUnknownReason  = "OutletDrawUnknown"
)

var (
	rackHostOutletActivePowerGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackhost_outlet_active_power_watts",
		Help: "Active power the RackHost's outlet meter read on the last reconcile, in watts. No series when the outlet could not be read or has no meter. Labels: host, site.",
	}, []string{"host", "site"})

	rackHostOutletApparentPowerGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackhost_outlet_apparent_power_va",
		Help: "Apparent power the RackHost's outlet meter read on the last reconcile, in volt-amperes. A mini plugged in and off reads a few VA at under 1 W active; an empty outlet reads 0. Labels: host, site.",
	}, []string{"host", "site"})

	rackHostOutletCurrentGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackhost_outlet_current_amps",
		Help: "RMS current the RackHost's outlet meter read on the last reconcile, in amperes. Labels: host, site.",
	}, []string{"host", "site"})

	rackHostPoweredOffAtOutletGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackhost_powered_off_at_outlet",
		Help: "1 when the RackHost's outlet is on and its mini is plugged in and powered off, which needs its power button pressed; 0 when the meter says otherwise. No series when the meter could not tell. Labels: host, site.",
	}, []string{"host", "site"})
)

func init() {
	metrics.Registry.MustRegister(rackHostOutletActivePowerGauge, rackHostOutletApparentPowerGauge,
		rackHostOutletCurrentGauge, rackHostPoweredOffAtOutletGauge)
}

// outletDraw reads the outlet's meter and classifies it with its state.
func outletDraw(ctx context.Context, driver power.Driver, outlet power.Outlet, state power.State) (power.Draw, power.Measures, error) {
	m, err := power.ReadMeasures(ctx, driver, outlet)
	if err != nil {
		return power.DrawUnknown, power.Measures{}, err
	}
	return power.Classify(state, m), m, nil
}

// observeDraw records the outlet's meter on the host: its reading in status,
// and what it means in HostDrawing. An outlet of a RackPDU is read from the
// PDU's status, which its controller fills for every outlet on the card; an
// endpoint of the host's own is read here.
func (r *RackHostReconciler) observeDraw(ctx context.Context, host *infrav1.RackHost, driver power.Driver, outlet power.Outlet, state power.State) {
	var m power.Measures
	var err error
	if onRackPDU(host) {
		state, m, err = r.pduOutletReading(ctx, host)
	} else {
		m, err = power.ReadMeasures(ctx, driver, outlet)
	}
	if err != nil {
		host.Status.OutletDraw = nil
		if errors.Is(err, power.ErrMeasuresUnsupported) {
			conditions.MarkUnknown(host, HostDrawingCondition, OutletDrawUnknownReason, "%s has no meter: %v", outlet, err)
			return
		}
		conditions.MarkUnknown(host, HostDrawingCondition, OutletDrawUnknownReason, "could not read %s's meter: %v", outlet, err)
		return
	}
	host.Status.OutletDraw = outletDrawStatus(m)
	draw := power.Classify(state, m)

	wasPoweredOff := conditions.GetReason(host, HostDrawingCondition) == PoweredOffAtOutletReason
	switch draw {
	case power.DrawDrawing:
		conditions.MarkTrue(host, HostDrawingCondition)
	case power.DrawPoweredOff:
		conditions.MarkFalse(host, HostDrawingCondition, PoweredOffAtOutletReason, clusterv1.ConditionSeverityWarning,
			"%s reads %s: the mini is plugged in and powered off. Press its power button: an outlet cycle starts a mini only once bootstrap has set `pmset autorestart 1`, which a new one has never had", outlet, m)
		if !wasPoweredOff {
			r.Recorder.Eventf(host, corev1.EventTypeWarning, PoweredOffAtOutletReason,
				"Plugged in and powered off (%s); press the power button", m)
		}
	case power.DrawNoLoad:
		conditions.MarkFalse(host, HostDrawingCondition, NoLoadOnOutletReason, clusterv1.ConditionSeverityWarning,
			"%s reads %s: nothing is plugged into it, or the host is on another outlet", outlet, m)
	case power.DrawOutletOff:
		conditions.MarkFalse(host, HostDrawingCondition, OutletOffReason, clusterv1.ConditionSeverityInfo,
			"%s is switched off", outlet)
	default:
		conditions.MarkUnknown(host, HostDrawingCondition, OutletDrawUnknownReason,
			"%s reads %s, which does not tell an off mini from an empty outlet", outlet, m)
	}
}

// onRackPDU reports a host whose outlet is one of a RackPDU's.
func onRackPDU(host *infrav1.RackHost) bool {
	return host.Spec.Power != nil && host.Spec.Power.PDU != ""
}

// rackPDUOutletReadingMaxAge is how old a RackPDU's reading of its outlets may
// be for a host to use it: three of its controller's resyncs, past which the
// card has stopped being read.
const rackPDUOutletReadingMaxAge = 3 * rackPDUResyncInterval

// pduOutletReading is the host's outlet as its RackPDU's status last read it.
func (r *RackHostReconciler) pduOutletReading(ctx context.Context, host *infrav1.RackHost) (power.State, power.Measures, error) {
	name, number := host.Spec.Power.PDU, host.Spec.Power.Outlet
	pdu := &infrav1.RackPDU{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: host.Namespace, Name: name}, pdu); err != nil {
		return power.StateUnknown, power.Measures{}, err
	}
	if at := pdu.Status.OutletsReadAt; at == nil || time.Since(at.Time) > rackPDUOutletReadingMaxAge {
		return power.StateUnknown, power.Measures{}, fmt.Errorf("RackPDU %s has not read its outlets in the last %s", name, rackPDUOutletReadingMaxAge)
	}
	n, _ := strconv.Atoi(number)
	state, m, ok := rackPDUOutletReading(pdu, n)
	switch {
	case !ok:
		return power.StateUnknown, power.Measures{}, fmt.Errorf("RackPDU %s reports no outlet %s", name, number)
	case m.ActivePower == nil && m.ApparentPower == nil:
		return power.StateUnknown, power.Measures{}, fmt.Errorf("RackPDU %s could not read outlet %s's meter", name, number)
	}
	return state, m, nil
}

// markOutletDrawUnread drops the reading of an outlet that could not be read.
func markOutletDrawUnread(host *infrav1.RackHost) {
	host.Status.OutletDraw = nil
	conditions.MarkUnknown(host, HostDrawingCondition, OutletDrawUnknownReason, "the outlet could not be read")
}

func outletDrawStatus(m power.Measures) *infrav1.OutletDraw {
	return &infrav1.OutletDraw{
		ActivePowerWatts: measureQuantity(m.ActivePower),
		ApparentPowerVA:  measureQuantity(m.ApparentPower),
		CurrentAmps:      measureQuantity(m.Current),
	}
}

// measureQuantity keeps a reading to the milli-unit, finer than a G4 meter
// resolves.
func measureQuantity(v *float64) *resource.Quantity {
	if v == nil {
		return nil
	}
	return resource.NewMilliQuantity(int64(math.Round(*v*1000)), resource.DecimalSI)
}

func recordRackHostDrawMetrics(host *infrav1.RackHost, labels []string) {
	var draw infrav1.OutletDraw
	if host.Status.OutletDraw != nil {
		draw = *host.Status.OutletDraw
	}
	for _, reading := range []struct {
		gauge *prometheus.GaugeVec
		value *resource.Quantity
	}{
		{rackHostOutletActivePowerGauge, draw.ActivePowerWatts},
		{rackHostOutletApparentPowerGauge, draw.ApparentPowerVA},
		{rackHostOutletCurrentGauge, draw.CurrentAmps},
	} {
		if reading.value == nil {
			reading.gauge.DeletePartialMatch(prometheus.Labels{"host": host.Name})
			continue
		}
		reading.gauge.WithLabelValues(labels...).Set(quantityFloat(*reading.value))
	}

	cond := conditions.Get(host, HostDrawingCondition)
	if cond == nil || cond.Status == corev1.ConditionUnknown {
		rackHostPoweredOffAtOutletGauge.DeletePartialMatch(prometheus.Labels{"host": host.Name})
		return
	}
	rackHostPoweredOffAtOutletGauge.WithLabelValues(labels...).Set(boolGauge(cond.Reason == PoweredOffAtOutletReason))
}
