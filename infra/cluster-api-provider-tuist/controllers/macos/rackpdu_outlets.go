package macos

import (
	"context"
	"errors"
	"strconv"

	"github.com/prometheus/client_golang/prometheus"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

var (
	rackPDUOutletOnGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackpdu_outlet_on",
		Help: "1 when the PDU's outlet is switched on, 0 when off, as the RackPDU controller last read it. No series when the card did not say. Labels: pdu, site, outlet.",
	}, []string{"pdu", "site", "outlet"})

	rackPDUOutletActivePowerGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackpdu_outlet_active_power_watts",
		Help: "Active power on the PDU's outlet, whatever is plugged into it, in watts. No series when the meter could not be read. Labels: pdu, site, outlet.",
	}, []string{"pdu", "site", "outlet"})

	rackPDUOutletApparentPowerGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackpdu_outlet_apparent_power_va",
		Help: "Apparent power on the PDU's outlet, in volt-amperes. 0 on an empty outlet; a few VA at under 1 W active is a load plugged in and off. Labels: pdu, site, outlet.",
	}, []string{"pdu", "site", "outlet"})

	rackPDUOutletCurrentGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackpdu_outlet_current_amps",
		Help: "RMS current on the PDU's outlet, in amperes. Labels: pdu, site, outlet.",
	}, []string{"pdu", "site", "outlet"})

	rackPDUOutletGauges = []*prometheus.GaugeVec{rackPDUOutletOnGauge, rackPDUOutletActivePowerGauge, rackPDUOutletApparentPowerGauge, rackPDUOutletCurrentGauge}
)

func init() {
	for _, g := range rackPDUOutletGauges {
		metrics.Registry.MustRegister(g)
	}
}

// readOutlets records every outlet's switch state and meter in status. A meter
// that cannot be read leaves that outlet's reading unset; it fails nothing
// else, since power through the card does not depend on it.
func (r *RackPDUReconciler) readOutlets(ctx context.Context, pdu *infrav1.RackPDU, secret *corev1.Secret, eaton *power.Eaton, settings []power.EatonOutletSettings) {
	card := r.cardOutlet(pdu, secret)
	outlets := make([]infrav1.RackPDUOutlet, 0, len(settings))
	var unread []string
	var lastErr error
	for _, s := range settings {
		outlet := infrav1.RackPDUOutlet{Number: s.Number, State: string(power.StateUnknown)}
		switch {
		case s.On == nil:
		case *s.On:
			outlet.State = string(power.StateOn)
		default:
			outlet.State = string(power.StateOff)
		}
		card.Outlet = strconv.Itoa(s.Number)
		m, err := eaton.Measures(ctx, card)
		switch {
		case err == nil:
			outlet.OutletDraw = *outletDrawStatus(m)
		case !errors.Is(err, power.ErrMeasuresUnsupported):
			unread, lastErr = append(unread, card.Outlet), err
		}
		outlets = append(outlets, outlet)
	}
	if lastErr != nil {
		log.FromContext(ctx).Error(lastErr, "read outlet meters", "pdu", pdu.Name, "outlets", unread)
	}
	now := metav1.Now()
	pdu.Status.Outlets = outlets
	pdu.Status.OutletsReadAt = &now
}

// forgetOutlets drops readings a failed read of the card can no longer vouch
// for.
func forgetOutlets(pdu *infrav1.RackPDU) {
	pdu.Status.Outlets = nil
	pdu.Status.OutletsReadAt = nil
}

// rackPDUOutletReading is outlet n's state and meter in its RackPDU's status.
func rackPDUOutletReading(pdu *infrav1.RackPDU, n int) (power.State, power.Measures, bool) {
	for _, o := range pdu.Status.Outlets {
		if o.Number != n {
			continue
		}
		return power.State(o.State), power.Measures{
			ActivePower:   quantityMeasure(o.ActivePowerWatts),
			ApparentPower: quantityMeasure(o.ApparentPowerVA),
			Current:       quantityMeasure(o.CurrentAmps),
		}, true
	}
	return power.StateUnknown, power.Measures{}, false
}

func quantityMeasure(q *resource.Quantity) *float64 {
	if q == nil {
		return nil
	}
	v := quantityFloat(*q)
	return &v
}

// quantityFloat is a reading kept to the milli-unit, exactly.
func quantityFloat(q resource.Quantity) float64 {
	return float64(q.MilliValue()) / 1000
}

func recordRackPDUOutletMetrics(pdu *infrav1.RackPDU) {
	for _, g := range rackPDUOutletGauges {
		g.DeletePartialMatch(prometheus.Labels{"pdu": pdu.Name})
	}
	for _, o := range pdu.Status.Outlets {
		labels := []string{pdu.Name, pdu.Spec.Site, strconv.Itoa(o.Number)}
		if s := power.State(o.State); s == power.StateOn || s == power.StateOff {
			rackPDUOutletOnGauge.WithLabelValues(labels...).Set(boolGauge(s == power.StateOn))
		}
		for _, reading := range []struct {
			gauge *prometheus.GaugeVec
			value *resource.Quantity
		}{
			{rackPDUOutletActivePowerGauge, o.ActivePowerWatts},
			{rackPDUOutletApparentPowerGauge, o.ApparentPowerVA},
			{rackPDUOutletCurrentGauge, o.CurrentAmps},
		} {
			if reading.value != nil {
				reading.gauge.WithLabelValues(labels...).Set(quantityFloat(*reading.value))
			}
		}
	}
}
