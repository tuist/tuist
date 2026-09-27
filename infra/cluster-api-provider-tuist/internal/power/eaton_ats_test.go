package power

import (
	"reflect"
	"testing"
)

func TestEatonSourceIsReadAndWrittenInTheCardsForm(t *testing.T) {
	cases := []struct {
		read    any
		want    int
		written any
	}{
		{read: float64(1), want: 1, written: 2},
		{read: "source 2", want: 2, written: "source 1"},
		{read: "input1", want: 1, written: "input2"},
		{read: map[string]any{"@id": "/rest/mbdetnrs/2.0/powerDistributions/1/inputs/2"}, want: 2,
			written: map[string]any{"@id": "/rest/mbdetnrs/2.0/powerDistributions/1/inputs/1"}},
	}
	for _, tc := range cases {
		got, err := decodeEatonSource(tc.read)
		if err != nil || got != tc.want {
			t.Fatalf("decode %v = %d, %v; want %d", tc.read, got, err, tc.want)
		}
		written, err := encodeEatonSource(tc.read, 3-tc.want)
		if err != nil || !reflect.DeepEqual(written, tc.written) {
			t.Fatalf("encode %d in the form of %v = %v, %v; want %v", 3-tc.want, tc.read, written, err, tc.written)
		}
	}
	for _, bad := range []any{float64(3), "source A", nil, true} {
		if _, err := decodeEatonSource(bad); err == nil {
			t.Fatalf("decoded %v as a source", bad)
		}
	}
}

func TestEatonATSInputState(t *testing.T) {
	yes, no := true, false
	zero, volts := 0.0, 229.0
	cases := map[string]struct {
		in   EatonATSInput
		want string
	}{
		"good":          {EatonATSInput{Supplied: &yes, InRange: &yes, Health: "ok", Voltage: &volts}, ATSInputGood},
		"derated":       {EatonATSInput{Supplied: &yes, InRange: &yes, Health: "warning", Voltage: &volts}, ATSInputDerated},
		"out of range":  {EatonATSInput{Supplied: &yes, InRange: &no, Health: "warning", Voltage: &volts}, ATSInputOutOfRange},
		"flagged low":   {EatonATSInput{Supplied: &yes, Health: "warning", Status: map[string]any{"voltageTooLow": true}}, ATSInputOutOfRange},
		"not supplied":  {EatonATSInput{Supplied: &no, Health: "critical"}, ATSInputMissing},
		"no voltage":    {EatonATSInput{Health: "ok", Voltage: &zero}, ATSInputMissing},
		"unknown words": {EatonATSInput{Supplied: &yes, InRange: &yes, Health: "degraded"}, ATSInputUnknown},
	}
	for name, tc := range cases {
		if got, _ := tc.in.State(); got != tc.want {
			t.Fatalf("%s: state = %s, want %s", name, got, tc.want)
		}
	}
}

func TestEatonATSActiveSource(t *testing.T) {
	yes, no := true, false
	ats := EatonATS{Inputs: []EatonATSInput{{Number: 1, Supplying: &no}, {Number: 2, Supplying: &yes}}}
	if n, err := ats.Active(); err != nil || n != 2 {
		t.Fatalf("active = %d, %v", n, err)
	}
	ats.Inputs[0].Supplying = &yes
	if _, err := ats.Active(); err == nil {
		t.Fatal("two inputs supplying the load read as one")
	}
}
