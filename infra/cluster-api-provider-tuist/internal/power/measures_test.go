package power

import (
	"context"
	"errors"
	"testing"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power/eatontest"
)

func watts(v float64) *float64 { return &v }

// The readings are ber1-pdu-b's on 2026-10-14: outlets 6 to 11 with minis
// plugged in and never started, outlet 12 empty, and running and sleeping
// minis on the others.
func TestClassifyTellsAnOffMiniFromAnEmptyOutletAndARunningOne(t *testing.T) {
	cases := []struct {
		name  string
		state State
		m     Measures
		want  Draw
	}{
		{"empty outlet", StateOn, Measures{ActivePower: watts(0), ApparentPower: watts(0)}, DrawNoLoad},
		{"plugged in, never started", StateOn, Measures{ActivePower: watts(0.1), ApparentPower: watts(4.6)}, DrawPoweredOff},
		{"plugged in, off, larger filter", StateOn, Measures{ActivePower: watts(0.1), ApparentPower: watts(6.2)}, DrawPoweredOff},
		{"asleep", StateOn, Measures{ActivePower: watts(2.4), ApparentPower: watts(7)}, DrawDrawing},
		{"running", StateOn, Measures{ActivePower: watts(38), ApparentPower: watts(41)}, DrawDrawing},
		{"switched off", StateOff, Measures{ActivePower: watts(0), ApparentPower: watts(0)}, DrawOutletOff},
		{"unreadable outlet", StateUnknown, Measures{ActivePower: watts(38), ApparentPower: watts(41)}, DrawUnknown},
		{"no apparent power and no draw", StateOn, Measures{ActivePower: watts(0.1)}, DrawUnknown},
		{"no apparent power, drawing", StateOn, Measures{ActivePower: watts(11.4)}, DrawDrawing},
		{"no meter", StateOn, Measures{}, DrawUnknown},
	}
	for _, c := range cases {
		if got := Classify(c.state, c.m); got != c.want {
			t.Errorf("%s: Classify(%s, %s) = %s, want %s", c.name, c.state, c.m, got, c.want)
		}
	}
}

func TestEatonReadsMeasuresOnTheDriversSession(t *testing.T) {
	card, e, outlet := eatonAgainst(t, 2)
	card.Mu.Lock()
	card.Outlets[1].Load = &eatontest.Load{ActivePower: 0.1, ApparentPower: 4.6, Current: 0.02}
	card.Mu.Unlock()

	if _, err := e.State(context.Background(), outlet); err != nil {
		t.Fatalf("State: %v", err)
	}
	m, err := ReadMeasures(context.Background(), e, outlet)
	if err != nil {
		t.Fatalf("ReadMeasures: %v", err)
	}
	if m.ActivePower == nil || *m.ActivePower != 0.1 || m.ApparentPower == nil || *m.ApparentPower != 4.6 || m.Current == nil || *m.Current != 0.02 {
		t.Fatalf("measures = %s, want 0.1 W, 4.6 VA, 0.02 A", m)
	}
	if n := logins(card); n != 1 {
		t.Fatalf("logged in %d times, want 1: the card allows one session per user", n)
	}
}

func TestEatonMeasuresOfAnEmptyOutletReadZero(t *testing.T) {
	_, e, outlet := eatonAgainst(t, 1)

	m, err := e.Measures(context.Background(), outlet)
	if err != nil {
		t.Fatalf("Measures: %v", err)
	}
	if got := Classify(StateOn, m); got != DrawNoLoad {
		t.Fatalf("Classify(%s) = %s, want NoLoad", m, got)
	}
}

func TestEatonMeasuresOfAnUnknownOutletAreUnsupported(t *testing.T) {
	_, e, outlet := eatonAgainst(t, 1)
	outlet.Outlet = "7"

	if _, err := e.Measures(context.Background(), outlet); !errors.Is(err, ErrMeasuresUnsupported) {
		t.Fatalf("Measures of an outlet the card does not have = %v, want ErrMeasuresUnsupported", err)
	}
}

func TestShellyGen2MeasuresActivePowerOnly(t *testing.T) {
	s, outlet := shellyAgainst(t, newGen2Plug(map[string]bool{"0": true}).handler())

	m, err := ReadMeasures(context.Background(), s, outlet)
	if err != nil {
		t.Fatalf("ReadMeasures: %v", err)
	}
	if m.ActivePower == nil || *m.ActivePower != 11.4 || m.ApparentPower != nil {
		t.Fatalf("measures = %s, want 11.4 W and no apparent power", m)
	}
}

func TestShellyGen1MeasuresAreUnsupported(t *testing.T) {
	s, outlet := shellyAgainst(t, (&gen1Plug{on: map[string]bool{"0": true}}).handler())

	if _, err := s.Measures(context.Background(), outlet); !errors.Is(err, ErrMeasuresUnsupported) {
		t.Fatalf("Measures on Gen1 = %v, want ErrMeasuresUnsupported", err)
	}
}

type unmeteredDriver struct{}

func (unmeteredDriver) State(context.Context, Outlet) (State, error) { return StateOn, nil }
func (unmeteredDriver) Set(context.Context, Outlet, bool) error      { return nil }

func TestReadMeasuresOfADriverWithoutAMeterIsUnsupported(t *testing.T) {
	if _, err := ReadMeasures(context.Background(), unmeteredDriver{}, Outlet{}); !errors.Is(err, ErrMeasuresUnsupported) {
		t.Fatalf("ReadMeasures = %v, want ErrMeasuresUnsupported", err)
	}
}
