package eatontest

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
)

// Source states the fake switch models, in the controller's vocabulary.
const (
	SourceGood       = "good"
	SourceDerated    = "derated"
	SourceOutOfRange = "outOfRange"
	SourceMissing    = "missing"
)

// ATS is a transfer switch behind a Network-M2 card: powerDistributions/1
// with specifications.type "ats", two inputs, and a settings object holding
// the preferred source under PreferredKey. Which resources and keys a real
// EATS16N serves is not documented; this follows the collections' UPS model.
type ATS struct {
	Model    string
	Serial   string
	Firmware string
	// Type is specifications.type; "ats" unless a test makes it something
	// else.
	Type string
	// Sources are source 1 and source 2, by index 0 and 1.
	Sources [2]Source
	// Active is the source powering the load, 0 for neither.
	Active int
	// PreferredKey is the settings key the preferred source is stored under,
	// as a number.
	PreferredKey string
	Settings     map[string]any
	// Transfers counts every change of Active.
	Transfers int
	// EditInput, when set, changes an input as served, for a card that
	// reports one oddly.
	EditInput func(n int, input map[string]any)
}

// Source is one input of the switch.
type Source struct {
	State     string
	Voltage   float64
	Frequency float64
}

// NewATS starts a factory-fresh Network-M2 card in an EATS16N: both sources
// good, source 1 preferred and powering the load.
func NewATS() *Card {
	c := New(0)
	c.Mu.Lock()
	defer c.Mu.Unlock()
	c.Product, c.ModelNumber, c.Firmware, c.Serial = "Network-M2", "NETWORK-M2", "3.1.12", "G212A01234"
	c.ATS = &ATS{
		Model: "Eaton ATS 16", Serial: "GA1234567", Firmware: "00.00.0009", Type: "ats",
		Sources:      [2]Source{{State: SourceGood, Voltage: 229.3, Frequency: 50}, {State: SourceGood, Voltage: 231.1, Frequency: 50}},
		Active:       1,
		PreferredKey: "preferredInput",
		Settings: map[string]any{
			"preferredInput": 1, "sensitivityMode": "normal sensitivity", "transferMode": "standard",
			"nominalVoltage": 230, "audibleAlarm": "enabled",
		},
	}
	return c
}

// SetSource changes a source's state, and the switch transfers as an ATS
// does: to the preferred source whenever it can power the load, otherwise to
// the other one, otherwise to neither.
func (c *Card) SetSource(n int, state string, voltage float64) {
	c.Mu.Lock()
	defer c.Mu.Unlock()
	c.ATS.Sources[n-1].State, c.ATS.Sources[n-1].Voltage = state, voltage
	c.ATS.transfer()
}

// ActiveSource reads which source powers the load.
func (c *Card) ActiveSource() int {
	c.Mu.Lock()
	defer c.Mu.Unlock()
	return c.ATS.Active
}

// PreferredSource reads the preferred source from the settings.
func (c *Card) PreferredSource() int {
	c.Mu.Lock()
	defer c.Mu.Unlock()
	return c.ATS.preferred()
}

// SetPreferredSource changes the preferred source as a person at the web UI
// would, without the controller.
func (c *Card) SetPreferredSource(n int) {
	c.Mu.Lock()
	defer c.Mu.Unlock()
	c.ATS.Settings[c.ATS.PreferredKey] = n
	c.ATS.transfer()
}

func (a *ATS) preferred() int {
	switch v := a.Settings[a.PreferredKey].(type) {
	case int:
		return v
	case float64:
		return int(v)
	}
	return 0
}

func (a *ATS) transfer() {
	usable := func(n int) bool {
		s := a.Sources[n-1].State
		return s == SourceGood || s == SourceDerated
	}
	preferred := a.preferred()
	if preferred != 1 && preferred != 2 {
		preferred = 1
	}
	other := 3 - preferred
	next := 0
	switch {
	case usable(preferred):
		next = preferred
	case usable(other):
		next = other
	}
	if next != a.Active {
		a.Active = next
		a.Transfers++
	}
}

func (c *Card) serveATS(w http.ResponseWriter, r *http.Request, path string, admin bool) bool {
	a := c.ATS
	switch {
	case r.Method == http.MethodGet && path == "/powerDistributions/1":
		body, _ := json.Marshal(map[string]any{
			"@id": api + "/powerDistributions/1", "id": "1",
			"identification": map[string]any{"model": a.Model, "productName": a.Model, "serialNumber": a.Serial,
				"firmwareVersion": a.Firmware, "manufacturer": "EATON", "partNumber": "EATS16N"},
			"specifications": map[string]any{"type": a.Type},
			"settings":       a.Settings,
			"inputs":         map[string]any{"@id": api + "/powerDistributions/1/inputs"},
		})
		answer(w, http.StatusOK, string(body))
	case r.Method == http.MethodGet && path == "/powerDistributions/1/inputs":
		fmt.Fprintf(w, `{"@id":"%[1]s/powerDistributions/1/inputs","members@count":2,"members":[{"@id":"%[1]s/powerDistributions/1/inputs/1"},{"@id":"%[1]s/powerDistributions/1/inputs/2"}]}`, api)
	case r.Method == http.MethodGet && strings.HasPrefix(path, "/powerDistributions/1/inputs/"):
		n, err := strconv.Atoi(strings.TrimPrefix(path, "/powerDistributions/1/inputs/"))
		if err != nil || n < 1 || n > 2 {
			answer(w, http.StatusNotFound, `{"code":"NotFound"}`)
			return true
		}
		body, _ := json.Marshal(a.input(n))
		answer(w, http.StatusOK, string(body))
	case r.Method == http.MethodGet && path == "/powerDistributions/1/settings":
		body, _ := json.Marshal(a.Settings)
		answer(w, http.StatusOK, string(body))
	case r.Method == http.MethodPut && path == "/powerDistributions/1/settings":
		if !admin {
			answer(w, http.StatusForbidden, `{"code":"NotAuthorized"}`)
			return true
		}
		var settings map[string]any
		if err := json.NewDecoder(r.Body).Decode(&settings); err != nil {
			answer(w, http.StatusBadRequest, `{"code":"InvalidParameter"}`)
			return true
		}
		if v, ok := settings[a.PreferredKey].(float64); !ok || (v != 1 && v != 2) {
			answer(w, http.StatusBadRequest, `{"code":"InvalidParameter"}`)
			return true
		}
		a.Settings = settings
		a.transfer()
		c.Writes = append(c.Writes, "ats settings")
		answer(w, http.StatusOK, "null")
	default:
		return false
	}
	return true
}

// input renders one input the way the collections' UPS inputs look.
func (a *ATS) input(n int) map[string]any {
	s := a.Sources[n-1]
	status := map[string]any{
		"operating": "in service", "health": "ok", "frequencyOutOfRange": false, "inRange": true,
		"internalFailure": false, "supplied": true, "supply": a.Active == n,
		"voltageOutOfRange": false, "voltageTooHigh": false, "voltageTooLow": false, "wiringFault": false,
	}
	switch s.State {
	case SourceDerated:
		status["health"] = "warning"
	case SourceOutOfRange:
		status["health"], status["inRange"], status["voltageOutOfRange"], status["voltageTooLow"] = "warning", false, true, true
	case SourceMissing:
		status["health"], status["inRange"], status["supplied"] = "critical", false, false
	}
	input := map[string]any{
		"@id": fmt.Sprintf("%s/powerDistributions/1/inputs/%d", api, n), "id": strconv.Itoa(n),
		"identification": map[string]any{"physicalName": fmt.Sprintf("Source %d", n)},
		"measures":       map[string]any{"voltage": s.Voltage, "frequency": s.Frequency, "current": 0.5},
		"status":         status,
	}
	if a.EditInput != nil {
		a.EditInput(n, input)
	}
	return input
}
