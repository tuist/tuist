package redfishprobe

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

// No board exists. These fakes are written from vendor documentation, not from
// captured traffic, so what they prove is that the probe handles the shapes
// those documents describe, not that the board serves them. That is the point:
// the pilot's first session runs this probe against real firmware and the
// interesting result is whichever of these two fakes turns out to be wrong.
//
// standardBMC serves the Redfish specification, which is also what
// sushy-emulator serves. megaracBMC serves the deviations ASRock Rack's own
// documentation and Ironic bug 2073518 describe: BIOS writes go to Bios/SD
// rather than Bios/Settings, the PATCH carries an ETag precondition, and a
// boot-override write to Systems/Self is refused with the URI it wants
// instead.

const biosRegistry = "BiosAttributeRegistryA5335.en-US.3.2.1"

type bmc struct {
	mu sync.Mutex

	powerState string
	current    map[string]any
	pending    map[string]any

	// megarac selects the vendor shape over the specification's.
	megarac bool

	resets   []string
	patched  []string
	etagSent []string
}

func newBMC(megarac bool) *bmc {
	return &bmc{
		powerState: "On",
		megarac:    megarac,
		current:    map[string]any{"NWSK000": "NWSK000Disabled", "NWSK001": "NWSK001Disabled"},
		pending:    map[string]any{},
	}
}

func (b *bmc) settingsPath() string {
	if b.megarac {
		return "/redfish/v1/Systems/Self/Bios/SD"
	}
	return "/redfish/v1/Systems/Self/Bios/Settings"
}

func (b *bmc) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b.mu.Lock()
		defer b.mu.Unlock()

		if user, pass, ok := r.BasicAuth(); !ok || user != "admin" || pass != "secret" {
			w.Header().Set("WWW-Authenticate", `Basic realm="RedfishService"`)
			w.WriteHeader(http.StatusUnauthorized)
			return
		}

		switch {
		case r.URL.Path == "/redfish/v1/Systems/Self" && r.Method == http.MethodGet:
			writeJSON(w, map[string]any{
				"Id":                 "Self",
				"PowerState":         b.powerState,
				"PowerRestorePolicy": "AlwaysOff",
				"Boot":               map[string]any{"BootSourceOverrideTarget": "None"},
			})

		case r.URL.Path == "/redfish/v1/Systems/Self" && r.Method == http.MethodPatch:
			if b.megarac {
				// Verbatim from Ironic bug 2073518.
				http.Error(w, "Support of this Operation for Boot Properties is moved to "+
					"FutureState URI(/redfish/v1/Systems/Self/SD)", http.StatusBadRequest)
				return
			}
			w.WriteHeader(http.StatusNoContent)

		case r.URL.Path == "/redfish/v1/Systems/Self/Actions/ComputerSystem.Reset":
			var body struct {
				ResetType string `json:"ResetType"`
			}
			_ = json.NewDecoder(r.Body).Decode(&body)
			b.resets = append(b.resets, body.ResetType)
			switch body.ResetType {
			case "On":
				b.powerState = "On"
			case "ForceOff", "GracefulShutdown":
				b.powerState = "Off"
			case "ForceRestart":
				b.powerState = "On"
			default:
				http.Error(w, "unsupported ResetType", http.StatusBadRequest)
				return
			}
			w.WriteHeader(http.StatusNoContent)

		case r.URL.Path == "/redfish/v1/Systems/Self/Bios" && r.Method == http.MethodGet:
			writeJSON(w, map[string]any{
				"Id":                "BIOS",
				"AttributeRegistry": biosRegistry,
				"Attributes":        b.current,
			})

		case r.URL.Path == b.settingsPath():
			w.Header().Set("ETag", `"1710949541"`)
			switch r.Method {
			case http.MethodGet:
				writeJSON(w, map[string]any{"Attributes": b.pending})
			case http.MethodPatch:
				if b.megarac && r.Header.Get("If-Match") == "" {
					http.Error(w, "precondition required", http.StatusPreconditionFailed)
					return
				}
				b.etagSent = append(b.etagSent, r.Header.Get("If-Match"))
				var body struct {
					Attributes map[string]any `json:"Attributes"`
				}
				_ = json.NewDecoder(r.Body).Decode(&body)
				for k, v := range body.Attributes {
					b.pending[k] = v
				}
				b.patched = append(b.patched, r.URL.Path)
				w.WriteHeader(http.StatusNoContent)
			default:
				http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			}

		default:
			http.Error(w, "resource not found", http.StatusNotFound)
		}
	})
}

func writeJSON(w http.ResponseWriter, body map[string]any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(body)
}

func serve(t *testing.T, b *bmc) power.Outlet {
	t.Helper()
	server := httptest.NewServer(b.handler())
	t.Cleanup(server.Close)
	return power.Outlet{
		Driver:   DriverRedfish,
		Host:     server.URL,
		Outlet:   "Self",
		Username: "admin",
		Password: "secret",
	}
}

func TestStateReadsPowerState(t *testing.T) {
	b := newBMC(true)
	outlet := serve(t, b)
	probe := &Probe{}

	state, err := probe.State(context.Background(), outlet)
	if err != nil {
		t.Fatalf("State: %v", err)
	}
	if state != power.StateOn {
		t.Fatalf("State = %s, want On", state)
	}

	b.mu.Lock()
	b.powerState = "PoweringOff"
	b.mu.Unlock()

	state, err = probe.State(context.Background(), outlet)
	if err != nil {
		t.Fatalf("State: %v", err)
	}
	// A transitional state must not read as Off, or power.Cycle would treat a
	// machine that is still shutting down as proof the cut succeeded.
	if state != power.StateUnknown {
		t.Fatalf("State during PoweringOff = %s, want Unknown", state)
	}
}

func TestSetConverges(t *testing.T) {
	b := newBMC(true)
	outlet := serve(t, b)
	probe := &Probe{}

	if err := probe.Set(context.Background(), outlet, true); err != nil {
		t.Fatalf("Set(on) on a running system: %v", err)
	}
	b.mu.Lock()
	resets := len(b.resets)
	b.mu.Unlock()
	if resets != 0 {
		t.Fatalf("Set(on) issued %d resets against an already-on system, want 0", resets)
	}

	if err := probe.Set(context.Background(), outlet, false); err != nil {
		t.Fatalf("Set(off): %v", err)
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	if len(b.resets) != 1 || b.resets[0] != "ForceOff" {
		t.Fatalf("resets = %v, want [ForceOff]", b.resets)
	}
}

func TestCycleDrivesTheProbe(t *testing.T) {
	b := newBMC(true)
	outlet := serve(t, b)

	if err := power.Cycle(context.Background(), &Probe{}, outlet, time.Millisecond); err != nil {
		t.Fatalf("Cycle: %v", err)
	}

	b.mu.Lock()
	defer b.mu.Unlock()
	if len(b.resets) != 2 || b.resets[0] != "ForceOff" || b.resets[1] != "On" {
		t.Fatalf("resets = %v, want [ForceOff On]", b.resets)
	}
	if b.powerState != "On" {
		t.Fatalf("power state after cycle = %s, want On", b.powerState)
	}
}

func TestBiosAttributesCarryTheRegistry(t *testing.T) {
	outlet := serve(t, newBMC(true))

	registry, attributes, err := (&Probe{}).BiosAttributes(context.Background(), outlet)
	if err != nil {
		t.Fatalf("BiosAttributes: %v", err)
	}
	// The registry is version-stamped, which is the whole reason attribute
	// names cannot be hardcoded in a driver.
	if registry != biosRegistry {
		t.Fatalf("registry = %q, want %q", registry, biosRegistry)
	}
	if attributes["NWSK000"] != "NWSK000Disabled" {
		t.Fatalf("attributes = %v, want NWSK000 present", attributes)
	}
}

func TestStageFallsBackToTheVendorResource(t *testing.T) {
	b := newBMC(true)
	outlet := serve(t, b)

	path, err := (&Probe{}).StageBiosAttributes(context.Background(), outlet,
		map[string]any{"NWSK000": "NWSK000Enabled"})
	if err != nil {
		t.Fatalf("StageBiosAttributes: %v", err)
	}
	if !strings.HasSuffix(path, "/Bios/SD") {
		t.Fatalf("staged at %q, want the Bios/SD resource", path)
	}

	b.mu.Lock()
	defer b.mu.Unlock()
	if b.pending["NWSK000"] != "NWSK000Enabled" {
		t.Fatalf("pending = %v, want the staged attribute", b.pending)
	}
	if b.current["NWSK000"] != "NWSK000Disabled" {
		t.Fatalf("current = %v, want it unchanged until a reboot applies it", b.current)
	}
	if len(b.etagSent) != 1 || b.etagSent[0] == "" {
		t.Fatalf("If-Match headers = %v, want the ETag read back from the resource", b.etagSent)
	}
}

func TestStagePrefersTheStandardResource(t *testing.T) {
	b := newBMC(false)
	outlet := serve(t, b)

	path, err := (&Probe{}).StageBiosAttributes(context.Background(), outlet,
		map[string]any{"NWSK000": "NWSK000Enabled"})
	if err != nil {
		t.Fatalf("StageBiosAttributes: %v", err)
	}
	// A conformant board must not be recorded as needing the workaround.
	if !strings.HasSuffix(path, "/Bios/Settings") {
		t.Fatalf("staged at %q, want the standard Bios/Settings resource", path)
	}
}

func TestBootOverrideRefusalCarriesTheVendorURI(t *testing.T) {
	outlet := serve(t, newBMC(true))

	_, err := (&Probe{}).call(context.Background(), outlet, http.MethodPatch,
		"/redfish/v1/Systems/Self", nil,
		map[string]any{"Boot": map[string]any{"BootSourceOverrideTarget": "Pxe"}}, nil)
	if err == nil {
		t.Fatal("PATCH of the boot override succeeded; the MegaRAC fake should refuse it")
	}
	// The refusal names the resource that would have worked. A driver that
	// discarded the body would lose the only clue the firmware gives.
	if !strings.Contains(err.Error(), "/redfish/v1/Systems/Self/SD") {
		t.Fatalf("error %q does not carry the FutureState URI", err)
	}
}

func TestCredentialsAreRequired(t *testing.T) {
	outlet := serve(t, newBMC(true))
	outlet.Password = "wrong"

	if _, err := (&Probe{}).State(context.Background(), outlet); err == nil {
		t.Fatal("State with a wrong password succeeded")
	}
}
