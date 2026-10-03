package power

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"path"
	"sort"
	"strconv"
	"strings"
)

// An Eaton transfer switch (EATS16N and its family) behind a Network-M2 or
// Network-M3 card is powerDistributions/1 of the same REST API a Rack PDU G4
// serves, with specifications.type "ats" and two inputs. Eaton's published
// Postman collections document that model for a UPS; the ATS resources below
// follow it and are not captured from a real switch.

// eatonATSPreferredKeys are the settings keys the preferred source is
// recognised under. None is documented; a card that uses another reports
// its settings' keys instead.
var eatonATSPreferredKeys = []string{"preferredInput", "preferredSource", "preferredInputSource"}

// EatonUnsupportedError is a card that answered, but not as the device the
// driver expected (Want: "transfer switch" when empty). Seen is what it
// answered instead.
type EatonUnsupportedError struct {
	Want string
	Seen string
}

func (e *EatonUnsupportedError) Error() string {
	want := e.Want
	if want == "" {
		want = "transfer switch"
	}
	return "not an Eaton " + want + " this driver knows: " + e.Seen
}

// EatonDistribution is powerDistributions/1 as the card names it: its model
// and specifications.type, "pdu" on a Rack PDU and "ats" on a transfer
// switch in Eaton's collections.
type EatonDistribution struct {
	Model string
	Type  string
}

// Distribution reads what powerDistributions/1 is, which tells a PDU's card
// from a transfer switch's. A card without one is unsupported.
func (s *EatonSession) Distribution(ctx context.Context) (EatonDistribution, error) {
	var d struct {
		Identification struct {
			Model       string `json:"model"`
			ProductName string `json:"productName"`
		} `json:"identification"`
		Specifications struct {
			Type string `json:"type"`
		} `json:"specifications"`
	}
	if err := s.get(ctx, "/powerDistributions/1", &d); err != nil {
		var status *EatonHTTPError
		if errors.As(err, &status) && status.Status == http.StatusNotFound {
			return EatonDistribution{}, &EatonUnsupportedError{Want: "device", Seen: "the card has no powerDistributions/1: " + status.Body}
		}
		return EatonDistribution{}, err
	}
	model := d.Identification.Model
	if model == "" {
		model = d.Identification.ProductName
	}
	return EatonDistribution{Model: model, Type: d.Specifications.Type}, nil
}

// EatonATS is a transfer switch as its card reports it.
type EatonATS struct {
	// Card is the management card's identification.
	Card EatonIdentity

	// Model, Serial and Firmware are the switch's own.
	Model    string
	Serial   string
	Firmware string

	Inputs []EatonATSInput

	// Preferred is the preferred source, 1 or 2, and 0 when the settings
	// carry no key the driver recognises.
	Preferred int
	// PreferredKey is the settings key Preferred was read from.
	PreferredKey string
	// Settings is the switch's settings object, written back whole with a
	// changed preferred source.
	Settings map[string]any
}

// SettingsKeys lists the settings object's keys, sorted.
func (a EatonATS) SettingsKeys() []string {
	keys := make([]string, 0, len(a.Settings))
	for k := range a.Settings {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// Active is the source powering the load: the one input whose status.supply
// is true. It is 0 when none is, and an error when both claim it.
func (a EatonATS) Active() (int, error) {
	active := 0
	for _, in := range a.Inputs {
		if in.Supplying == nil || !*in.Supplying {
			continue
		}
		if active != 0 {
			return 0, fmt.Errorf("inputs %d and %d both report status.supply", active, in.Number)
		}
		active = in.Number
	}
	return active, nil
}

// EatonATSInput is one input as the card reports it.
type EatonATSInput struct {
	Number int
	// Supplying is status.supply: whether this input powers the load.
	Supplying *bool
	// Supplied is status.supplied: whether the input has power.
	Supplied  *bool
	Health    string
	InRange   *bool
	Voltage   *float64
	Frequency *float64
	// Status is the input's status object, verbatim.
	Status map[string]any
}

// ATS input states, as the RackATS controller names them.
const (
	ATSInputGood       = "good"
	ATSInputDerated    = "derated"
	ATSInputOutOfRange = "outOfRange"
	ATSInputMissing    = "missing"
	ATSInputUnknown    = "unknown"
)

// State judges the input from its status, and says what it read. An input
// without power is missing; one whose voltage or frequency is out of range is
// out of range; one in range whose health is a warning is derated, which is
// the only warning a switch raises on an input in range.
func (in EatonATSInput) State() (string, string) {
	detail := in.detail()
	flag := func(name string) bool {
		v, _ := in.Status[name].(bool)
		return v
	}
	switch {
	case in.Supplied != nil && !*in.Supplied:
		return ATSInputMissing, detail
	case in.Voltage != nil && *in.Voltage == 0:
		return ATSInputMissing, detail
	case flag("voltageOutOfRange") || flag("frequencyOutOfRange") || flag("voltageTooLow") || flag("voltageTooHigh"),
		in.InRange != nil && !*in.InRange:
		return ATSInputOutOfRange, detail
	case flag("voltageInDeratedRange") || flag("deratedRange"):
		return ATSInputDerated, detail
	case in.Health == "ok":
		return ATSInputGood, detail
	case in.Health == "warning":
		return ATSInputDerated, detail
	}
	return ATSInputUnknown, detail
}

func (in EatonATSInput) detail() string {
	keys := make([]string, 0, len(in.Status))
	for k := range in.Status {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf("%s=%v", k, in.Status[k]))
	}
	return strings.Join(parts, " ")
}

// ATS reads the transfer switch through the driver's session, as o's
// account.
func (e *Eaton) ATS(ctx context.Context, o Outlet) (EatonATS, error) {
	return eatonATS(ctx, func(ctx context.Context, path string, out any) error {
		return e.call(ctx, o, http.MethodGet, path, out)
	})
}

// ATS reads the transfer switch as the session's account.
func (s *EatonSession) ATS(ctx context.Context) (EatonATS, error) {
	return eatonATS(ctx, s.get)
}

// SetATSPreferredSource writes the switch's settings object back whole with
// the preferred source set to n, in the form the card reported it in.
func (s *EatonSession) SetATSPreferredSource(ctx context.Context, ats EatonATS, n int) error {
	if ats.PreferredKey == "" {
		return &EatonUnsupportedError{Seen: fmt.Sprintf("its settings carry no preferred source under %s; they have %s",
			strings.Join(eatonATSPreferredKeys, ", "), strings.Join(ats.SettingsKeys(), ", "))}
	}
	encoded, err := encodeEatonSource(ats.Settings[ats.PreferredKey], n)
	if err != nil {
		return err
	}
	settings := make(map[string]any, len(ats.Settings))
	for k, v := range ats.Settings {
		settings[k] = v
	}
	settings[ats.PreferredKey] = encoded
	return s.request(ctx, http.MethodPut, "/powerDistributions/1/settings", settings, false, nil)
}

func eatonATS(ctx context.Context, get eatonGetter) (EatonATS, error) {
	var distribution struct {
		Identification struct {
			Model           string `json:"model"`
			ProductName     string `json:"productName"`
			SerialNumber    string `json:"serialNumber"`
			FirmwareVersion string `json:"firmwareVersion"`
		} `json:"identification"`
		Specifications struct {
			Type string `json:"type"`
		} `json:"specifications"`
	}
	if err := get(ctx, "/powerDistributions/1", &distribution); err != nil {
		var status *EatonHTTPError
		if errors.As(err, &status) && status.Status == http.StatusNotFound {
			return EatonATS{}, &EatonUnsupportedError{Seen: "the card has no powerDistributions/1: " + status.Body}
		}
		return EatonATS{}, err
	}
	model := distribution.Identification.Model
	if model == "" {
		model = distribution.Identification.ProductName
	}
	if distribution.Specifications.Type != "ats" {
		return EatonATS{}, &EatonUnsupportedError{Seen: fmt.Sprintf("powerDistributions/1 is %q with specifications.type %q, not \"ats\"", model, distribution.Specifications.Type)}
	}
	ats := EatonATS{Model: model, Serial: distribution.Identification.SerialNumber, Firmware: distribution.Identification.FirmwareVersion}

	var list struct {
		Members []struct {
			ID string `json:"@id"`
		} `json:"members"`
	}
	if err := get(ctx, "/powerDistributions/1/inputs", &list); err != nil {
		return EatonATS{}, err
	}
	if len(list.Members) != 2 {
		return EatonATS{}, &EatonUnsupportedError{Seen: fmt.Sprintf("%q lists %d inputs, not 2", model, len(list.Members))}
	}
	sawSupply := false
	for _, member := range list.Members {
		n, err := strconv.Atoi(path.Base(member.ID))
		if err != nil || n < 1 || n > 2 {
			return EatonATS{}, &EatonUnsupportedError{Seen: fmt.Sprintf("input %q is not numbered 1 or 2", member.ID)}
		}
		var input struct {
			Measures struct {
				Voltage   *float64 `json:"voltage"`
				Frequency *float64 `json:"frequency"`
			} `json:"measures"`
			Status map[string]any `json:"status"`
		}
		if err := get(ctx, fmt.Sprintf("/powerDistributions/1/inputs/%d", n), &input); err != nil {
			return EatonATS{}, err
		}
		in := EatonATSInput{Number: n, Voltage: input.Measures.Voltage, Frequency: input.Measures.Frequency, Status: input.Status}
		if v, ok := input.Status["supply"].(bool); ok {
			in.Supplying = &v
			sawSupply = true
		}
		if v, ok := input.Status["supplied"].(bool); ok {
			in.Supplied = &v
		}
		if v, ok := input.Status["inRange"].(bool); ok {
			in.InRange = &v
		}
		in.Health, _ = input.Status["health"].(string)
		ats.Inputs = append(ats.Inputs, in)
	}
	sort.Slice(ats.Inputs, func(i, j int) bool { return ats.Inputs[i].Number < ats.Inputs[j].Number })
	if !sawSupply {
		return EatonATS{}, &EatonUnsupportedError{Seen: fmt.Sprintf("neither input of %q reports status.supply, so which one powers the load cannot be read: %s", model, ats.Inputs[0].detail())}
	}

	if err := get(ctx, "/powerDistributions/1/settings", &ats.Settings); err != nil {
		return EatonATS{}, err
	}
	for _, key := range eatonATSPreferredKeys {
		value, ok := ats.Settings[key]
		if !ok {
			continue
		}
		n, err := decodeEatonSource(value)
		if err != nil {
			return EatonATS{}, &EatonUnsupportedError{Seen: fmt.Sprintf("settings.%s is %v: %v", key, value, err)}
		}
		ats.Preferred, ats.PreferredKey = n, key
		break
	}

	identity, err := eatonIdentification(ctx, get)
	if err != nil {
		return EatonATS{}, err
	}
	ats.Card = identity
	return ats, nil
}

// decodeEatonSource reads a source as a number, as a string ending in its
// number ("source 1", ".../inputs/2"), or as a reference object with an @id.
func decodeEatonSource(v any) (int, error) {
	switch value := v.(type) {
	case float64:
		if value == 1 || value == 2 {
			return int(value), nil
		}
	case string:
		value = strings.TrimSpace(value)
		if value != "" {
			switch value[len(value)-1] {
			case '1':
				return 1, nil
			case '2':
				return 2, nil
			}
		}
	case map[string]any:
		if id, ok := value["@id"].(string); ok {
			return decodeEatonSource(id)
		}
	}
	return 0, fmt.Errorf("not a source 1 or 2")
}

// encodeEatonSource writes n in the form the card reported current in.
func encodeEatonSource(current any, n int) (any, error) {
	switch value := current.(type) {
	case float64:
		return n, nil
	case string:
		trimmed := strings.TrimSpace(value)
		return trimmed[:len(trimmed)-1] + strconv.Itoa(n), nil
	case map[string]any:
		id, _ := value["@id"].(string)
		out := make(map[string]any, len(value))
		for k, v := range value {
			out[k] = v
		}
		trimmed := strings.TrimSpace(id)
		out["@id"] = trimmed[:len(trimmed)-1] + strconv.Itoa(n)
		return out, nil
	}
	return nil, fmt.Errorf("cannot write a source in the form %v", current)
}
