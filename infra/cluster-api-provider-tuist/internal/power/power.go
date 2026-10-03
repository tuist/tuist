// Package power switches the outlets the rack's Mac minis are plugged into.
//
// On Apple silicon an outlet is a reboot button: the machines power on when
// mains is applied, and every fleet host runs `pmset autorestart 1`, so cutting
// and restoring an outlet is a full cold boot with nobody at a console. That is
// the whole reason this package exists: a rack host has no provider API to
// reboot it and no BMC to talk to, so every other machine kind's recovery path
// (call the provider, or release the box and claim a different one) has no
// analog here. Without an outlet the only repair for a wedged host is a human
// in Berlin.
//
// Nothing in here is Mac-specific; it is deliberately a thin, boring switch
// abstraction so that adding the rack's real switched PDUs later is a new
// Driver rather than a change to the machine controller.
package power

import (
	"context"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"time"
)

// State is an outlet's observed power state.
type State string

const (
	StateOn  State = "On"
	StateOff State = "Off"
	// StateUnknown is what a caller gets when the outlet could not be read:
	// the endpoint was unreachable, answered something unparseable, or the host
	// has no outlet configured at all. It is deliberately a value rather than
	// an error-only condition so status can carry "we do not know" instead of
	// implying Off, which would read as a deliberate shutdown.
	StateUnknown State = "Unknown"
)

// Outlet addresses one switched outlet on one endpoint.
type Outlet struct {
	// Driver names the backend (see Drivers).
	Driver string
	// Host is the endpoint, as `host`, `host:port`, or a full `scheme://host`.
	// A bare value is dialled over plain HTTP: these live on a management
	// segment, and the devices in question ship self-signed certificates that
	// would need their own trust plumbing to be worth anything.
	Host string
	// Outlet identifies the outlet on that endpoint; driver-specific.
	Outlet string
	// Username / Password authenticate to the endpoint. Empty means the
	// endpoint is unauthenticated.
	Username string
	Password string
}

func (o Outlet) String() string {
	return fmt.Sprintf("%s outlet %s on %s", o.Driver, o.Outlet, o.Host)
}

// Driver is one power backend.
//
// Implementations must be safe for concurrent use and must honour the context:
// the machine reconciler calls these inline on a reconcile, so a hung PDU has
// to surface as a timeout rather than as a stalled worker.
type Driver interface {
	// State reads the outlet's current state.
	State(ctx context.Context, o Outlet) (State, error)
	// Set switches the outlet on or off. Setting an outlet to the state it is
	// already in must succeed rather than error: callers use it to converge,
	// not to toggle.
	Set(ctx context.Context, o Outlet, on bool) error
}

// Registry resolves a driver name to its implementation.
type Registry struct {
	drivers map[string]Driver
}

// NewRegistry returns the drivers this build supports. One HTTP client is
// shared across every driver so a rack's worth of outlets on one PDU reuses
// connections instead of handshaking per reconcile.
func NewRegistry() *Registry {
	httpClient := &http.Client{
		// Generous next to a LAN round trip, tight next to a reconcile: a PDU
		// that has stopped answering must fail the step, not hold the worker.
		// Callers still pass a context, which wins when it is shorter.
		Timeout: 15 * time.Second,
	}
	return NewRegistryWith(map[string]Driver{
		DriverShelly: &Shelly{HTTP: httpClient},
	})
}

// NewRegistryWith builds a registry over an explicit driver set. Production
// goes through NewRegistry; this is the seam that lets a caller substitute a
// driver, which is how the machine reconciler's power-cycle recovery ladder is
// exercised without a plug on the bench.
func NewRegistryWith(drivers map[string]Driver) *Registry {
	return &Registry{drivers: drivers}
}

// Get resolves a driver by name. An empty name resolves to the Shelly driver,
// matching the CRD's default, so a host whose outlet predates a future driver
// field keeps working.
func (r *Registry) Get(name string) (Driver, error) {
	if name == "" {
		name = DriverShelly
	}
	d, ok := r.drivers[name]
	if !ok {
		return nil, fmt.Errorf("unknown power driver %q (have: %s)", name, strings.Join(r.Names(), ", "))
	}
	return d, nil
}

// Names lists the registered driver names, sorted.
func (r *Registry) Names() []string {
	names := make([]string, 0, len(r.drivers))
	for n := range r.drivers {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

// Cycle powers an outlet off, waits, and powers it back on.
//
// Driver-independent on purpose. Several devices expose a native "cycle" verb,
// and none of them agree on how long it holds the outlet down, which is the
// one parameter that matters, because an Apple silicon mini that loses power
// for less than a few seconds can come back without the PSU having discharged,
// leaving it in exactly the wedged state the cycle was meant to clear. Driving
// off/settle/on ourselves makes that interval explicit and identical across
// backends.
//
// The off is verified before the on. A cycle that silently failed to cut power
// would return success while the host kept running, and the caller would then
// wait out a boot that never happened and count the recovery as attempted.
func Cycle(ctx context.Context, d Driver, o Outlet, settle time.Duration) error {
	if err := d.Set(ctx, o, false); err != nil {
		return fmt.Errorf("power off %s: %w", o, err)
	}
	state, err := d.State(ctx, o)
	if err != nil {
		return fmt.Errorf("verify %s powered off: %w", o, err)
	}
	if state != StateOff {
		return fmt.Errorf("%s did not power off (reads %s); refusing to report a cycle that never cut power", o, state)
	}

	select {
	case <-ctx.Done():
		// Leave the outlet off rather than racing a half-applied cycle: the
		// next reconcile re-runs this and the Set(on) below is idempotent, so
		// a host stuck off is recovered rather than stranded.
		return fmt.Errorf("cycle %s interrupted while powered off: %w", o, ctx.Err())
	case <-time.After(settle):
	}

	if err := d.Set(ctx, o, true); err != nil {
		return fmt.Errorf("power on %s: %w", o, err)
	}
	return nil
}
