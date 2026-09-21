// Package redfishprobe is a PROBE, not a driver.
//
// It exists to answer one question before any hardware is bought: does a
// Redfish BMC fit behind the power.Driver interface without bending it, and
// what does a BIOS-attribute write actually look like on the AMI MegaRAC
// firmware the candidate board ships. It is deliberately not registered in
// power.NewRegistry, so nothing in the controller can reach it. The production
// driver gets written after the pilot answers the questions in
// docs/rack-x86-redfish-support.md, because its shape depends on those answers.
//
// What this can be run against today, with no board:
//   - sushy-tools (sushy-emulator), which serves the STANDARD shape:
//     Systems/{id}/BIOS and Systems/{id}/BIOS/Settings, and applies pending
//     attributes on a reset.
//   - the fake in redfish_test.go, which serves the shape the vendor
//     documentation describes instead: Systems/{id}/Bios/SD, an ETag
//     precondition on the PATCH, and a boot override that is refused on
//     Systems/{id} and redirected to Systems/{id}/SD.
//
// Neither is evidence about the board. An emulator implements the spec; the
// whole pilot question is where this vendor's firmware departs from it.
package redfishprobe

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

// DriverRedfish is the name a future driver would register under.
const DriverRedfish = "redfish"

// Probe speaks Redfish to one BMC.
//
// It implements power.Driver over power.Outlet without a new address type:
// Outlet already carries an endpoint, a driver-specific id and credentials,
// which is exactly a BMC host, a ComputerSystem id and a BMC account. Whether
// that stays true once the pilot reports is question 11 in the design doc.
//
// Outlet.Outlet is the ComputerSystem id. AMI MegaRAC answers to "Self";
// other implementations use "1" or "System.Embedded.1". Empty defaults to
// "Self".
type Probe struct {
	HTTP *http.Client

	// InsecureSkipVerify accepts the BMC's self-signed certificate. A BMC
	// ships one by default and there is no CA behind it, so a probe that
	// refused it could not talk to the thing it is probing. A production
	// driver must not keep this: pinning is question 9.
	InsecureSkipVerify bool
}

var _ power.Driver = (*Probe)(nil)

// State implements power.Driver by reading ComputerSystem.PowerState.
func (p *Probe) State(ctx context.Context, o power.Outlet) (power.State, error) {
	var system struct {
		PowerState string `json:"PowerState"`
	}
	if _, err := p.call(ctx, o, http.MethodGet, p.systemPath(o), nil, nil, &system); err != nil {
		return power.StateUnknown, err
	}
	switch system.PowerState {
	case "On":
		return power.StateOn, nil
	case "Off":
		return power.StateOff, nil
	case "":
		return power.StateUnknown, fmt.Errorf("redfish %s returned no PowerState", p.systemPath(o))
	default:
		// PoweringOn / PoweringOff / Paused are real Redfish values and none
		// of them are a settled state. Reporting Unknown keeps power.Cycle
		// from reading a mid-transition host as successfully powered off.
		return power.StateUnknown, nil
	}
}

// Set implements power.Driver via ComputerSystem.Reset.
//
// Off is ForceOff rather than GracefulShutdown. Set is documented as
// converging, and a graceful request to a wedged host is exactly the case the
// caller is trying to recover from: it would return success and leave the
// machine running. Whether a future driver should try graceful first and fall
// back is question 5.
func (p *Probe) Set(ctx context.Context, o power.Outlet, on bool) error {
	state, err := p.State(ctx, o)
	if err != nil {
		return err
	}
	// Reset is not idempotent the way an outlet switch is: POSTing On to a
	// running system is an error on some implementations, so converge here
	// rather than relying on the BMC to tolerate it.
	if (on && state == power.StateOn) || (!on && state == power.StateOff) {
		return nil
	}

	resetType := "ForceOff"
	if on {
		resetType = "On"
	}
	body := map[string]string{"ResetType": resetType}
	_, err = p.call(ctx, o, http.MethodPost,
		p.systemPath(o)+"/Actions/ComputerSystem.Reset", nil, body, nil)
	return err
}

// BiosAttributes reads the current BIOS attributes and the registry that
// decodes them. This is pilot question 1: whether Attributes is populated at
// all, and question 3: whether AttributeRegistry names a version-stamped
// registry the names are only valid against.
func (p *Probe) BiosAttributes(ctx context.Context, o power.Outlet) (registry string, attributes map[string]any, err error) {
	var bios struct {
		AttributeRegistry string         `json:"AttributeRegistry"`
		Attributes        map[string]any `json:"Attributes"`
	}
	if _, err := p.call(ctx, o, http.MethodGet, p.systemPath(o)+"/Bios", nil, nil, &bios); err != nil {
		return "", nil, err
	}
	return bios.AttributeRegistry, bios.Attributes, nil
}

// StageBiosAttributes writes attributes to the pending-settings resource. It
// does not reboot: staging and applying are separate on every implementation,
// and the pilot times them separately.
//
// Two paths are tried because the documentation for this BMC family describes
// a resource the Redfish specification does not have. The standard is
// Bios/Settings; AMI MegaRAC, per ASRock Rack's own documentation and the
// Ironic bug filed against these boards, uses Bios/SD. The order is
// standard-first so that a board which turns out to be conformant is not
// recorded as needing a workaround. Which one answers is pilot question 4.
func (p *Probe) StageBiosAttributes(ctx context.Context, o power.Outlet, attributes map[string]any) (path string, err error) {
	body := map[string]any{"Attributes": attributes}
	var firstErr error
	for _, candidate := range []string{
		p.systemPath(o) + "/Bios/Settings",
		p.systemPath(o) + "/Bios/SD",
	} {
		etag, err := p.etag(ctx, o, candidate)
		if err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		headers := http.Header{}
		if etag != "" {
			// MegaRAC enforces a precondition on this PATCH. Sending the ETag
			// we just read is the only way through; a driver that omits it
			// gets a 412 that reads like a permissions problem.
			headers.Set("If-Match", etag)
		}
		if _, err := p.call(ctx, o, http.MethodPatch, candidate, headers, body, nil); err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		return candidate, nil
	}
	return "", firstErr
}

// etag reads a resource and returns its ETag header, empty when it has none.
func (p *Probe) etag(ctx context.Context, o power.Outlet, path string) (string, error) {
	header, err := p.call(ctx, o, http.MethodGet, path, nil, nil, nil)
	if err != nil {
		return "", err
	}
	return header.Get("ETag"), nil
}

func (p *Probe) systemPath(o power.Outlet) string {
	id := strings.TrimSpace(o.Outlet)
	if id == "" {
		id = "Self"
	}
	return "/redfish/v1/Systems/" + id
}

// call issues one request with HTTP Basic authentication.
//
// Basic rather than a SessionService token: it is one request instead of
// three, every Redfish service is required to accept it, and it is what a
// working third-party client for these boards uses. Whether the BMC rate
// limits or audit-logs it differently from a session is question 9.
func (p *Probe) call(ctx context.Context, o power.Outlet, method, path string, headers http.Header, body, out any) (http.Header, error) {
	endpoint, err := p.endpoint(o, path)
	if err != nil {
		return nil, err
	}

	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("encode body for %s: %w", endpoint, err)
		}
		reader = bytes.NewReader(encoded)
	}

	req, err := http.NewRequestWithContext(ctx, method, endpoint, reader)
	if err != nil {
		return nil, fmt.Errorf("build request for %s: %w", endpoint, err)
	}
	for key, values := range headers {
		for _, value := range values {
			req.Header.Add(key, value)
		}
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if o.Username != "" || o.Password != "" {
		req.SetBasicAuth(o.Username, o.Password)
	}

	resp, err := p.client().Do(req)
	if err != nil {
		return nil, fmt.Errorf("call %s: %w", endpoint, err)
	}
	defer resp.Body.Close()

	payload, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", endpoint, err)
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		// The body is kept in the error on purpose. This firmware answers a
		// refused boot-override write with the URI it wants instead, and that
		// string is the finding, not noise.
		return resp.Header, fmt.Errorf("%s %s: %s: %s",
			method, endpoint, resp.Status, strings.TrimSpace(string(payload)))
	}
	if out == nil || len(payload) == 0 {
		return resp.Header, nil
	}
	if err := json.Unmarshal(payload, out); err != nil {
		return resp.Header, fmt.Errorf("decode %s: %w", endpoint, err)
	}
	return resp.Header, nil
}

// endpoint builds an absolute URL, defaulting a bare host to HTTPS.
//
// This is where the probe departs from Shelly's Outlet.endpoint, which
// defaults to plain HTTP. A BMC serves Redfish over TLS and redirects port 80,
// and a driver that guessed HTTP would send Basic credentials in the clear on
// the first request of every reconcile.
func (p *Probe) endpoint(o power.Outlet, path string) (string, error) {
	host := strings.TrimSpace(o.Host)
	if host == "" {
		return "", fmt.Errorf("redfish outlet has no host")
	}
	if !strings.Contains(host, "://") {
		host = "https://" + host
	}
	base, err := url.Parse(host)
	if err != nil {
		return "", fmt.Errorf("parse redfish host %q: %w", o.Host, err)
	}
	if base.Host == "" {
		return "", fmt.Errorf("redfish host %q has no host part", o.Host)
	}
	return (&url.URL{Scheme: base.Scheme, Host: base.Host, Path: path}).String(), nil
}

func (p *Probe) client() *http.Client {
	if p.HTTP != nil {
		return p.HTTP
	}
	if !p.InsecureSkipVerify {
		return http.DefaultClient
	}
	return &http.Client{
		Transport: &http.Transport{
			//nolint:gosec // A BMC's factory certificate is self-signed and this is a probe; see question 9.
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
	}
}
