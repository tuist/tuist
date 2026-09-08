package power

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

// DriverShelly speaks to Shelly relays and smart plugs.
const DriverShelly = "shelly"

// Shelly drives a Shelly switch over its local HTTP API.
//
// It is the BER1 prototype's PDU stand-in: a single-outlet plug validating the
// power path before the rack's switched 3-phase PDUs exist, but it is also a
// real answer for a small deployment, so it is implemented properly rather than
// as a placeholder.
//
// Two generations of firmware are in the wild and they share no endpoint:
// Gen2+ (Plus/Pro, and everything Shelly currently sells) exposes a JSON-RPC
// surface at /rpc, while Gen1 exposes /relay/<id>. Which one a given plug
// speaks is a property of the hardware someone bought, not a deployment
// decision, so this probes rather than making it a config field: Gen2 first,
// Gen1 on a 404. Getting that wrong is not subtle: the wrong endpoint 404s
// immediately, so the probe costs one extra request on Gen1 hardware and
// nothing on Gen2.
type Shelly struct {
	HTTP *http.Client
}

// gen2Status is the subset of Switch.GetStatus we read.
type gen2Status struct {
	Output *bool `json:"output"`
}

// gen1Relay is the subset of /relay/<id> we read.
type gen1Relay struct {
	IsOn *bool `json:"ison"`
}

// State implements Driver.
func (s *Shelly) State(ctx context.Context, o Outlet) (State, error) {
	channel := o.channel()

	var g2 gen2Status
	found, err := s.call(ctx, o, "/rpc/Switch.GetStatus", url.Values{"id": {channel}}, &g2)
	switch {
	case err != nil:
		return StateUnknown, err
	case found:
		if g2.Output == nil {
			return StateUnknown, fmt.Errorf("shelly Switch.GetStatus for channel %s returned no output field", channel)
		}
		return stateOf(*g2.Output), nil
	}

	var g1 gen1Relay
	found, err = s.call(ctx, o, "/relay/"+channel, nil, &g1)
	switch {
	case err != nil:
		return StateUnknown, err
	case !found:
		return StateUnknown, fmt.Errorf("shelly at %s has neither /rpc/Switch.GetStatus nor /relay/%s; not a switch, or channel %s does not exist", o.Host, channel, channel)
	case g1.IsOn == nil:
		return StateUnknown, fmt.Errorf("shelly /relay/%s returned no ison field", channel)
	}
	return stateOf(*g1.IsOn), nil
}

// Set implements Driver.
func (s *Shelly) Set(ctx context.Context, o Outlet, on bool) error {
	channel := o.channel()

	// Gen2 answers with {"was_on":bool}; we do not read it. The previous state
	// is not the question: Set converges, and the caller that cares about the
	// result reads State back (Cycle does exactly that).
	found, err := s.call(ctx, o, "/rpc/Switch.Set",
		url.Values{"id": {channel}, "on": {boolParam(on)}}, nil)
	switch {
	case err != nil:
		return err
	case found:
		return nil
	}

	found, err = s.call(ctx, o, "/relay/"+channel, url.Values{"turn": {turnParam(on)}}, nil)
	switch {
	case err != nil:
		return err
	case !found:
		return fmt.Errorf("shelly at %s has neither /rpc/Switch.Set nor /relay/%s; not a switch, or channel %s does not exist", o.Host, channel, channel)
	}
	return nil
}

// call issues one GET and decodes the body into out (when non-nil).
//
// The bool reports whether the endpoint EXISTS: false for a 404, which is how
// the generation probe distinguishes "this firmware does not have this API"
// from "this request failed". Every other non-2xx is an error, so an
// authentication failure or a device fault surfaces instead of being read as a
// wrong-generation guess and retried against the other endpoint.
func (s *Shelly) call(ctx context.Context, o Outlet, path string, query url.Values, out any) (bool, error) {
	endpoint, err := o.endpoint(path, query)
	if err != nil {
		return false, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return false, fmt.Errorf("build request for %s: %w", endpoint, err)
	}

	resp, err := s.do(req, o)
	if err != nil {
		return false, fmt.Errorf("call %s: %w", endpoint, err)
	}
	defer resp.Body.Close()

	// Cap the read: a device answering with something enormous is a device
	// fault, and this runs inline on a reconcile.
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return false, fmt.Errorf("read %s: %w", endpoint, err)
	}

	if resp.StatusCode == http.StatusNotFound {
		return false, nil
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return false, fmt.Errorf("%s: %s: %s", endpoint, resp.Status, strings.TrimSpace(string(body)))
	}
	if out == nil {
		return true, nil
	}
	if err := json.Unmarshal(body, out); err != nil {
		return false, fmt.Errorf("decode %s: %w", endpoint, err)
	}
	return true, nil
}

// do sends the request, answering an HTTP 401 challenge when the outlet
// carries credentials. Gen2 firmware challenges with Digest and Gen1 with
// Basic; rather than deciding by generation, which would couple auth to the
// endpoint probe and get it wrong on mixed firmware: this answers whichever
// scheme the device actually asked for.
func (s *Shelly) do(req *http.Request, o Outlet) (*http.Response, error) {
	client := s.HTTP
	if client == nil {
		client = http.DefaultClient
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusUnauthorized || o.Password == "" {
		return resp, nil
	}

	challenge := resp.Header.Get("WWW-Authenticate")
	// The body is drained and closed so the connection can be reused for the
	// authenticated retry rather than being torn down.
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<20))
	resp.Body.Close()

	retry := req.Clone(req.Context())
	username := o.Username
	if username == "" {
		// Shelly Gen2 fixes the username at `admin` and its own UI does not
		// ask for one, so a Secret carrying only a password is the normal
		// shape rather than a misconfiguration.
		username = "admin"
	}
	if err := authorize(retry, challenge, username, o.Password); err != nil {
		return nil, err
	}
	return client.Do(retry)
}

// channel is the Shelly switch/relay index. Empty means the single-channel
// case, which every Shelly numbers 0.
func (o Outlet) channel() string {
	if o.Outlet == "" {
		return "0"
	}
	return o.Outlet
}

// endpoint builds the absolute URL for a path on this outlet's host,
// defaulting a bare host to plain HTTP.
func (o Outlet) endpoint(path string, query url.Values) (string, error) {
	host := strings.TrimSpace(o.Host)
	if host == "" {
		return "", fmt.Errorf("power outlet has no host")
	}
	if !strings.Contains(host, "://") {
		host = "http://" + host
	}
	base, err := url.Parse(host)
	if err != nil {
		return "", fmt.Errorf("parse power host %q: %w", o.Host, err)
	}
	if base.Host == "" {
		return "", fmt.Errorf("power host %q has no host part", o.Host)
	}
	// Discard anything past the origin. The field is documented as an
	// endpoint, and silently honouring a path someone put there would build
	// URLs like /foo/rpc/Switch.Set that 404 into the wrong-generation branch.
	origin := &url.URL{Scheme: base.Scheme, Host: base.Host, Path: path}
	if len(query) > 0 {
		origin.RawQuery = query.Encode()
	}
	return origin.String(), nil
}

func stateOf(on bool) State {
	if on {
		return StateOn
	}
	return StateOff
}

func boolParam(on bool) string {
	if on {
		return "true"
	}
	return "false"
}

func turnParam(on bool) string {
	if on {
		return "on"
	}
	return "off"
}
