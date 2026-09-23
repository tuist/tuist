// Package converge is what the reconciler and the one-shot apply command both
// run against the Omada controller: the site settings the switches depend on,
// adoption, and writing a switch's configuration.
package converge

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
)

// Gates switch steps on one at a time, as each is verified on a switch's
// running configuration. The command's flags default the management address
// on and the rest off.
type Gates struct {
	VLANs                bool
	LAGs                 bool
	PortSpanningTree     bool
	ManagementAddressing bool
	SiteServices         bool
}

// Engine converges switches in one Omada site.
type Engine struct {
	Omada *omada.Client
	// The Omada site the switches are adopted into.
	Site string
	// The address the controller tells adopted switches to connect back to:
	// its tailnet IP, since the switches have no resolver for MagicDNS names.
	ControllerAddress string
	Gates             Gates
}

// Change is one write the engine made.
type Change struct {
	Subject string
	From    string
	To      string
	Note    string
}

func (c Change) String() string {
	s := c.Subject + ": "
	if c.From != "" {
		s += c.From + " -> "
	}
	s += c.To
	if c.Note != "" {
		s += " (" + c.Note + ")"
	}
	return s
}

// SiteID resolves the engine's site.
func (e *Engine) SiteID(ctx context.Context) (string, error) {
	return e.Omada.SiteID(ctx, e.Site)
}

// EnsureSite brings the settings every switch in the site depends on to what
// they should be, writing only what differs: the address switches connect
// back to, SSH on, and the device account.
func (e *Engine) EnsureSite(ctx context.Context, siteID string, account omada.Login) ([]Change, error) {
	var changes []Change

	host, err := e.Omada.DeviceHost(ctx)
	if err != nil {
		return changes, err
	}
	if host != e.ControllerAddress {
		if err := e.Omada.SetDeviceHost(ctx, e.ControllerAddress); err != nil {
			return changes, err
		}
		changes = append(changes, Change{Subject: "device host", From: host, To: e.ControllerAddress})
	}

	// The controller pushes the site's SSH setting to every switch it adopts,
	// and it starts disabled. The fleet verifies over SSH, so it stays on.
	ssh, err := e.Omada.SiteSSH(ctx, siteID)
	if err != nil {
		return changes, err
	}
	if enabled, _ := ssh["sshEnable"].(bool); !enabled || number(ssh["sshServerPort"]) != 22 {
		if ssh == nil {
			ssh = map[string]any{}
		}
		ssh["sshEnable"] = true
		ssh["sshServerPort"] = 22
		if err := e.Omada.SetSiteSSH(ctx, siteID, ssh); err != nil {
			return changes, err
		}
		changes = append(changes, Change{Subject: "site SSH", To: "on, port 22"})
	}

	current, err := e.Omada.DeviceAccount(ctx, siteID)
	if err != nil {
		return changes, err
	}
	if current != account {
		if err := e.Omada.SetDeviceAccount(ctx, siteID, account); err != nil {
			return changes, err
		}
		changes = append(changes, Change{Subject: "device account", To: "the configured login", Note: "replaces every adopted switch's login"})
	}
	return changes, nil
}

// Find returns the site's device with this MAC, or nil when the controller
// does not list it.
func (e *Engine) Find(ctx context.Context, siteID, mac string) (*omada.Device, error) {
	want := omada.ControllerMAC(mac)
	devices, err := e.Omada.Devices(ctx, siteID)
	if err != nil {
		return nil, err
	}
	for i := range devices {
		if strings.EqualFold(devices[i].MAC, want) {
			return &devices[i], nil
		}
	}
	pending, err := e.Omada.PendingDevices(ctx, siteID)
	if err != nil {
		return nil, err
	}
	for i := range pending {
		if strings.EqualFold(pending[i].MAC, want) {
			return &pending[i], nil
		}
	}
	return nil, nil
}

// LoginKind is which login an adoption attempt used.
type LoginKind string

const (
	LoginDeviceAccount LoginKind = "the site's device account"
	LoginFactory       LoginKind = "the factory login"
)

// AdoptTimeout is how long an attempt may take before it counts as failed.
const AdoptTimeout = 5 * time.Minute

// Attempt is an adoption in progress.
type Attempt struct {
	Login     LoginKind
	StartedAt time.Time
	// Whether the device has shown a state other than "adoption failed"
	// since the request. A failure from an earlier attempt stays on the
	// device until the controller picks the new request up.
	Moved bool
}

// AdoptionOutcome is where an adoption stands after a step.
type AdoptionOutcome int

const (
	AdoptionWaiting AdoptionOutcome = iota
	AdoptionFailed
	AdoptionManagedByOthers
)

// Note is something worth telling an operator about, as an event or a line of
// output.
type Note struct {
	Reason  string
	Message string
	Warning bool
}

// Adoption is the result of one adoption step.
type Adoption struct {
	Outcome AdoptionOutcome
	// The attempt in progress, nil once the outcome is final.
	Attempt *Attempt
	Notes   []Note
}

// Adopt takes one step of adopting a device that is not connected: it starts
// an attempt with the device account, falls back to the factory login when
// that fails, and otherwise reports where the attempt stands. The caller
// polls, and treats the device as adopted once it shows as connected.
func (e *Engine) Adopt(ctx context.Context, siteID string, dev omada.Device, attempt *Attempt, creds Credentials, now time.Time) (Adoption, error) {
	if dev.Detail() == omada.DetailManagedByOthers {
		return Adoption{Outcome: AdoptionManagedByOthers, Notes: []Note{{
			Reason: "ManagedByOthers", Message: "the switch is managed by another controller", Warning: true,
		}}}, nil
	}
	if attempt == nil {
		return e.startAdopt(ctx, siteID, dev, LoginDeviceAccount, creds, now)
	}

	failed := ""
	switch {
	case now.Sub(attempt.StartedAt) > AdoptTimeout:
		failed = fmt.Sprintf("adopting with %s did not connect within %s", attempt.Login, AdoptTimeout)
	case dev.Detail() == omada.DetailAdoptionFailed && attempt.Moved:
		failed = fmt.Sprintf("the controller reports adopting with %s failed", attempt.Login)
	case dev.Detail() == omada.DetailAdoptionFailed:
	default:
		next := *attempt
		next.Moved = true
		attempt = &next
	}
	if failed == "" {
		return Adoption{Outcome: AdoptionWaiting, Attempt: attempt}, nil
	}
	if attempt.Login == LoginDeviceAccount {
		result, err := e.startAdopt(ctx, siteID, dev, LoginFactory, creds, now)
		result.Notes = append([]Note{{Reason: "AdoptionRetried", Message: failed + "; trying the factory login", Warning: true}}, result.Notes...)
		return result, err
	}
	return Adoption{Outcome: AdoptionFailed, Notes: []Note{{Reason: "AdoptionFailed", Message: failed, Warning: true}}}, nil
}

func (e *Engine) startAdopt(ctx context.Context, siteID string, dev omada.Device, kind LoginKind, creds Credentials, now time.Time) (Adoption, error) {
	login := creds.DeviceAccount
	if kind == LoginFactory {
		login = creds.FactoryLogin
	}
	if err := e.Omada.StartAdopt(ctx, siteID, dev.MAC, login); err != nil {
		var apiErr *omada.Error
		if !errors.As(err, &apiErr) {
			return Adoption{}, err
		}
		refused := fmt.Sprintf("the controller refused adopting with %s: %s", kind, apiErr.Message)
		if kind == LoginDeviceAccount {
			result, err := e.startAdopt(ctx, siteID, dev, LoginFactory, creds, now)
			result.Notes = append([]Note{{Reason: "AdoptionRetried", Message: refused + "; trying the factory login", Warning: true}}, result.Notes...)
			return result, err
		}
		return Adoption{Outcome: AdoptionFailed, Notes: []Note{{Reason: "AdoptionFailed", Message: refused, Warning: true}}}, nil
	}
	return Adoption{
		Outcome: AdoptionWaiting,
		Attempt: &Attempt{Login: kind, StartedAt: now},
		Notes:   []Note{{Reason: "AdoptionStarted", Message: "adopting with " + string(kind)}},
	}, nil
}

func number(v any) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	default:
		return -1
	}
}
