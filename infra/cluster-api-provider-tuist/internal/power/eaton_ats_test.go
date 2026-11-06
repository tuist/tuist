package power

import (
	"context"
	"fmt"
	"reflect"
	"strings"
	"testing"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power/eatontest"
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

func atsAgainst(t *testing.T) (*eatontest.Card, *Eaton, Outlet) {
	t.Helper()
	card := eatontest.NewATS()
	t.Cleanup(card.Close)
	card.AddAccount(testUser, testPassword, eatontest.ProfileViewers)
	return card, &Eaton{}, Outlet{Driver: DriverEaton, Host: card.URL(), Username: testUser, Password: testPassword, TLSFingerprint: card.Fingerprint()}
}

// A preferred source under a known key in a form the driver cannot read is
// reported, like one under an unknown key, and the rest of the switch is
// still read.
func TestEatonATSReadsTheSwitchPastAPreferredSourceItCannotDecode(t *testing.T) {
	for _, value := range []any{"A", 0} {
		card, e, outlet := atsAgainst(t)
		card.Mu.Lock()
		card.ATS.Settings["preferredInput"] = value
		card.Mu.Unlock()

		ats, err := e.ATS(context.Background(), outlet)
		if err != nil {
			t.Fatalf("preferredInput %v: %v", value, err)
		}
		if ats.Preferred != 0 || ats.PreferredKey != "" || !strings.Contains(ats.PreferredUnrecognised, fmt.Sprintf("settings.preferredInput is %v", value)) {
			t.Fatalf("preferredInput %v: preferred %d under %q, unrecognised %q", value, ats.Preferred, ats.PreferredKey, ats.PreferredUnrecognised)
		}
		if active, err := ats.Active(); err != nil || active != 1 || len(ats.Inputs) != 2 {
			t.Fatalf("preferredInput %v: active %d, %v, %d inputs", value, active, err, len(ats.Inputs))
		}
	}
}

func TestEatonATSReadsItsOutputsEmbeddedOrApart(t *testing.T) {
	for _, apart := range []bool{false, true} {
		card, e, outlet := atsAgainst(t)
		card.Mu.Lock()
		card.ATS.Outputs = []map[string]any{{"current": 2.5, "voltage": 230.4, "activePower": 540.0, "apparentPower": 576.0, "powerFactor": 0.94}}
		card.ATS.OutputMeasuresApart = apart
		card.Mu.Unlock()

		ats, err := e.ATS(context.Background(), outlet)
		if err != nil {
			t.Fatalf("apart %t: %v", apart, err)
		}
		if ats.OutputsUnread != "" || len(ats.Outputs) != 1 {
			t.Fatalf("apart %t: outputs %+v, unread %q", apart, ats.Outputs, ats.OutputsUnread)
		}
		out := ats.Outputs[0]
		if out.Number != 1 || *out.Current != 2.5 || *out.Voltage != 230.4 || *out.ActivePower != 540 || *out.ApparentPower != 576 {
			t.Fatalf("apart %t: output %+v", apart, out)
		}
		if out.Detail() != "activePower=540 apparentPower=576 current=2.5 powerFactor=0.94 voltage=230.4" {
			t.Fatalf("apart %t: detail %q", apart, out.Detail())
		}
		if ats.Inputs[0].Current == nil || *ats.Inputs[0].Current != 0.5 {
			t.Fatalf("apart %t: input current %v", apart, ats.Inputs[0].Current)
		}
	}
}

// A card that serves no outputs is still read: only the outputs are missing,
// with what the card answered.
func TestEatonATSReadsTheSwitchWithoutOutputs(t *testing.T) {
	card, e, outlet := atsAgainst(t)
	ats, err := e.ATS(context.Background(), outlet)
	if err != nil {
		t.Fatalf("ATS: %v", err)
	}
	if len(ats.Outputs) != 0 || !strings.Contains(ats.OutputsUnread, "404") {
		t.Fatalf("outputs %+v, unread %q: want none, saying the card answered 404", ats.Outputs, ats.OutputsUnread)
	}
	if active, err := ats.Active(); err != nil || active != 1 || len(ats.Inputs) != 2 || ats.Preferred != 1 {
		t.Fatalf("active %d, %v, %d inputs, preferred %d", active, err, len(ats.Inputs), ats.Preferred)
	}

	card.Mu.Lock()
	card.ATS.Outputs = []map[string]any{{"current": "2.5 A"}}
	card.Mu.Unlock()
	ats, err = e.ATS(context.Background(), outlet)
	if err != nil {
		t.Fatalf("ATS: %v", err)
	}
	if len(ats.Outputs) != 1 || ats.Outputs[0].Current != nil || ats.Outputs[0].Detail() != "current=2.5 A" {
		t.Fatalf("outputs %+v: want the output, its unreadable current left out and kept verbatim", ats.Outputs)
	}
}

// An input field in a form the driver cannot read loses that field alone.
func TestEatonATSReadsTheSwitchPastAnOddInputField(t *testing.T) {
	card, e, outlet := atsAgainst(t)
	card.Mu.Lock()
	card.ATS.EditInput = func(n int, input map[string]any) {
		delete(input["status"].(map[string]any), "supply")
		if n == 2 {
			input["measures"].(map[string]any)["voltage"] = "231.1 V"
		}
	}
	card.Mu.Unlock()

	ats, err := e.ATS(context.Background(), outlet)
	if err != nil {
		t.Fatalf("ATS: %v", err)
	}
	if _, err := ats.Active(); err == nil || !strings.Contains(err.Error(), "status.supply") {
		t.Fatalf("Active = %v, want it to say no input reports status.supply", err)
	}
	if len(ats.Inputs) != 2 || ats.Inputs[0].Voltage == nil || ats.Inputs[1].Voltage != nil || ats.Preferred != 1 {
		t.Fatalf("inputs %+v, preferred %d: want both inputs, the readable voltage only, and the preferred source", ats.Inputs, ats.Preferred)
	}
	if state, _ := ats.Inputs[1].State(); state != ATSInputGood {
		t.Fatalf("input 2 is %s, want good from its status", state)
	}
}
