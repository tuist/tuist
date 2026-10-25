package picos

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
)

// Engine converges PicOS switches. Every write is a `commit confirmed`, and
// it is confirmed only after a fresh connection reads the switch back as
// written; anything else leaves the switch to roll itself back.
type Engine struct {
	Dialer Dialer
	// ConfirmAfter is the rollback timer of every write.
	ConfirmAfter time.Duration

	mu      sync.Mutex
	clients map[string]*Client
	// unconfirmed holds the switches with a commit confirmed this engine wrote
	// and could not confirm. A read cannot tell a pending commit from a
	// confirmed one, so without this a switch would look converged until its
	// timer rolled the change back.
	unconfirmed map[string]bool
}

// Report is what a converge found and did.
type Report struct {
	// Changes are the lines written and confirmed.
	Changes []string
	// Drift is what still differs from the spec afterwards.
	Drift []string
	// HostKey is the fingerprint the switch presented.
	HostKey string
}

func (e *Engine) client(address, pin string) *Client {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.clients == nil {
		e.clients = map[string]*Client{}
	}
	c := e.clients[address]
	if c == nil || c.Pin != pin {
		if c != nil {
			c.Close()
		}
		c = &Client{Dialer: e.Dialer, Address: address, Pin: pin}
		e.clients[address] = c
	}
	return c
}

// Forget drops a switch's connections, as after it is deleted.
func (e *Engine) Forget(address string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if c := e.clients[address]; c != nil {
		c.Close()
		delete(e.clients, address)
	}
}

var hostnamePattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$`)

func (e *Engine) observe(ctx context.Context, c *Client) ([]Item, error) {
	data, err := c.RunningConfig(ctx, Filter)
	if err != nil {
		return nil, err
	}
	return Observed(data)
}

// Converge compares the switch with rs's config and, when apply is set,
// writes the difference. pin is the host key the switch must present; empty
// accepts the first and reports it.
func (e *Engine) Converge(ctx context.Context, rs *v1alpha1.RackSwitch, pin string, apply bool) (Report, error) {
	if cfg := rs.Spec.Config; cfg != nil && cfg.Hostname != "" && !hostnamePattern.MatchString(cfg.Hostname) {
		return Report{}, fmt.Errorf("hostname %q is not one PicOS takes", cfg.Hostname)
	}
	desired, err := Desired(rs.Spec.Config)
	if err != nil {
		return Report{}, err
	}
	c := e.client(rs.Spec.ManagementAddress, pin)
	observed, err := e.observe(ctx, c)
	report := Report{HostKey: c.HostKey()}
	if err != nil {
		return report, err
	}
	lines := Difference(observed, desired, Owned)
	if e.isUnconfirmed(c.Address) {
		if len(lines) > 0 {
			report.Drift = lines
			return report, fmt.Errorf("an earlier write is unconfirmed and does not match the spec; leaving it to roll back")
		}
		if _, err := c.RunCLI(ctx, []string{"configure", "commit"}); err != nil {
			return report, fmt.Errorf("confirming an earlier write: %w", err)
		}
		e.setUnconfirmed(c.Address, false)
		report.Changes = []string{"commit (confirming an earlier write)"}
		return report, nil
	}
	if !apply || len(lines) == 0 {
		report.Drift = lines
		return report, nil
	}

	seconds := int(e.ConfirmAfter / time.Second)
	if _, err := c.RunCLI(ctx, append(append([]string{"configure"}, lines...), "commit confirmed "+strconv.Itoa(seconds))); err != nil {
		return report, fmt.Errorf("writing %d lines: %w", len(lines), err)
	}
	e.setUnconfirmed(c.Address, true)

	// A change that cut the controller off cannot be confirmed from here, so
	// the read that decides goes over new connections.
	c.Close()
	after, err := e.observe(ctx, c)
	if err != nil {
		return report, fmt.Errorf("reading back after the commit, which rolls back in %ds unless confirmed: %w", seconds, err)
	}
	if left := Difference(after, desired, Owned); len(left) > 0 {
		report.Drift = left
		return report, fmt.Errorf("the switch did not read back as written (%s); leaving it to roll back in %ds", strings.Join(left, "; "), seconds)
	}
	if _, err := c.RunCLI(ctx, []string{"configure", "commit"}); err != nil {
		return report, fmt.Errorf("confirming the commit, which rolls back in %ds: %w", seconds, err)
	}
	e.setUnconfirmed(c.Address, false)
	report.Changes = lines
	return report, nil
}

// Adopt is the first connection to a switch: it accepts the host key the
// switch presents, sets admin's password, which the zero-touch bootstrap left
// random, and returns the key to pin.
func (e *Engine) Adopt(ctx context.Context, address, adminPassword string) (string, error) {
	if err := e.SetPassword(ctx, address, "", "admin", adminPassword); err != nil {
		return "", err
	}
	return e.client(address, "").HostKey(), nil
}

// passwordLine matches what pica_sh echoes back of a password line.
var passwordLine = regexp.MustCompile(`plain-text-password \S+`)

// SetPassword sets a local user's password, confirmed the same way as any
// other write. pica_sh echoes every line, so nothing it prints is returned.
func (e *Engine) SetPassword(ctx context.Context, address, pin, user, password string) error {
	if strings.ContainsAny(password, " '\";\n") || password == "" {
		return errors.New("the password has a space, quote, semicolon or newline, or is empty")
	}
	c := e.client(address, pin)
	seconds := int(e.ConfirmAfter / time.Second)
	_, err := c.RunCLI(ctx, []string{"configure", "set system login user " + user + " authentication plain-text-password " + password, "commit confirmed " + strconv.Itoa(seconds)})
	if err != nil {
		var refused *CLIError
		if errors.As(err, &refused) {
			return fmt.Errorf("the switch refused the password change: %s", passwordLine.ReplaceAllString(refused.Output, "plain-text-password <redacted>"))
		}
		return fmt.Errorf("setting %s's password: %s", user, passwordLine.ReplaceAllString(err.Error(), "plain-text-password <redacted>"))
	}
	c.Close()
	if _, err := e.observe(ctx, c); err != nil {
		return fmt.Errorf("reading back after the password change, which rolls back in %ds: %w", seconds, err)
	}
	if _, err := c.RunCLI(ctx, []string{"configure", "commit"}); err != nil {
		return fmt.Errorf("confirming the password change: %w", err)
	}
	return nil
}

func (e *Engine) isUnconfirmed(address string) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.unconfirmed[address]
}

func (e *Engine) setUnconfirmed(address string, pending bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.unconfirmed == nil {
		e.unconfirmed = map[string]bool{}
	}
	if pending {
		e.unconfirmed[address] = true
	} else {
		delete(e.unconfirmed, address)
	}
}
