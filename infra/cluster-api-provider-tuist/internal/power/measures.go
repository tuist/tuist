package power

import (
	"context"
	"errors"
	"fmt"
)

// ErrMeasuresUnsupported is a driver, or a device, whose outlets have no meter.
var ErrMeasuresUnsupported = errors.New("the outlet reports no power measures")

// Measures is what an outlet's meter reads. A nil field is one the device does
// not report.
type Measures struct {
	// ActivePower is the real power drawn, in watts.
	ActivePower *float64
	// ApparentPower is the product of RMS voltage and current, in volt-amperes.
	// Unlike ActivePower it is not near zero for a load that is plugged in and
	// off: a PSU's input filter draws reactive current with no real power.
	ApparentPower *float64
	// Current is the RMS current, in amperes.
	Current *float64
}

func (m Measures) String() string {
	return fmt.Sprintf("%s W active, %s VA apparent, %s A", formatMeasure(m.ActivePower), formatMeasure(m.ApparentPower), formatMeasure(m.Current))
}

func formatMeasure(v *float64) string {
	if v == nil {
		return "unknown"
	}
	return fmt.Sprintf("%.1f", *v)
}

// Meter is a Driver whose outlets are metered.
type Meter interface {
	// Measures reads the outlet's meter. A device without one answers
	// ErrMeasuresUnsupported.
	Measures(ctx context.Context, o Outlet) (Measures, error)
}

// ReadMeasures reads o's meter through d, and ErrMeasuresUnsupported when d is
// not a Meter.
func ReadMeasures(ctx context.Context, d Driver, o Outlet) (Measures, error) {
	m, ok := d.(Meter)
	if !ok {
		return Measures{}, ErrMeasuresUnsupported
	}
	return m.Measures(ctx, o)
}

// Draw is what an outlet's meter says about the load plugged into it.
type Draw string

const (
	// DrawUnknown is an outlet whose meter could not be read, or reported too
	// little to tell the cases below apart.
	DrawUnknown Draw = "Unknown"
	// DrawOutletOff is an outlet switched off, which reads zero whatever is
	// plugged into it.
	DrawOutletOff Draw = "OutletOff"
	// DrawNoLoad is an outlet that is on with nothing plugged into it.
	DrawNoLoad Draw = "NoLoad"
	// DrawPoweredOff is an outlet that is on with a cord plugged in and the
	// machine on the other end off.
	DrawPoweredOff Draw = "PoweredOff"
	// DrawDrawing is an outlet whose load is running, or asleep.
	DrawDrawing Draw = "Drawing"
)

// The thresholds come from ber1-pdu-b's outlet meters (Eaton Rack PDU G4) on
// 2026-10-14:
//
//   - An empty outlet reads exactly 0 W and 0 VA.
//   - A Mac mini plugged in and off reads about 0.1 W and 4 to 6 VA: its PSU's
//     input filter, with no real load behind it.
//   - A sleeping mini reads 2 to 3 W, and a running one 20 to 55 W.
//
// So 1 VA separates an empty outlet from a cord, and 1 W separates an off
// mini from a sleeping one, each with several times the meter's resolution
// to spare on both sides.
const (
	// NoLoadApparentPowerVA is the apparent power below which nothing is
	// plugged into an outlet.
	NoLoadApparentPowerVA = 1.0
	// PoweredOffActivePowerW is the active power below which a plugged-in
	// load is off.
	PoweredOffActivePowerW = 1.0
)

// Classify reads an outlet's state and meter as a Draw.
func Classify(state State, m Measures) Draw {
	switch state {
	case StateOn:
	case StateOff:
		return DrawOutletOff
	default:
		return DrawUnknown
	}
	active, apparent := m.ActivePower, m.ApparentPower
	switch {
	case active != nil && *active >= PoweredOffActivePowerW:
		return DrawDrawing
	case apparent == nil:
		// Without apparent power, an off load and no load both read 0 W.
		return DrawUnknown
	case *apparent < NoLoadApparentPowerVA:
		return DrawNoLoad
	case active != nil:
		return DrawPoweredOff
	}
	return DrawUnknown
}
