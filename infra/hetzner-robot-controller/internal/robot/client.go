// Package robot wraps the Hetzner Robot webservice API.
//
// We only need a tiny slice of the Robot surface: list our servers,
// look one up by ID. The rest of Robot — rescue, install, reboot —
// is caph's responsibility. This package keeps the SDK behind a
// small interface so the controller and tests can substitute a fake.
package robot

import (
	"context"
	"fmt"

	hrobot "github.com/syself/hrobot-go"
	hrobotmodels "github.com/syself/hrobot-go/models"
)

// Server is the minimal shape the controller needs from a Robot
// server entry. Renamed off `hrobotmodels.Server` so test fakes
// don't need to pull the SDK type in.
type Server struct {
	// Number is the Robot server ID (e.g. 2986829). caph uses this
	// to drive the Robot API for reboot / rescue / installimage.
	Number int

	// Name is the operator-set display name in the Robot panel.
	// Convention `tuist-bm-<env>-<n>` — the controller selects
	// servers whose Name starts with `tuist-bm-`.
	Name string

	// ServerIP is the v4 main IP. Useful for diagnostics; caph
	// rediscovers it from the Robot API itself, so the controller
	// doesn't propagate it onto the CR.
	ServerIP string

	// Cancelled reports whether the server is end-of-life (operator
	// has filed a cancellation in Robot). Cancelled servers may
	// still be in the inventory until the billing period ends, but
	// the controller should retire CRs for them so caph stops
	// trying to claim. Robot exposes this as `cancelled bool` plus
	// `paid_until` — we only look at the bool.
	Cancelled bool

	// Product is the box class (e.g. AX42-U). Surfaced for logs.
	Product string

	// Dc is the Hetzner datacenter ID (e.g. "FSN1-DC8"). Surfaced
	// for logs; caph also reads it.
	Dc string
}

// Client lists Hetzner Robot servers. The real implementation
// wraps hrobot-go; tests use FakeClient.
type Client interface {
	ListServers(ctx context.Context) ([]Server, error)
}

// HTTPClient is the upstream hrobot-go SDK shape we depend on,
// extracted so we can swap implementations in tests.
type HTTPClient interface {
	ServerGetList() ([]hrobotmodels.Server, error)
}

type sdkClient struct {
	upstream HTTPClient
}

// New returns a Client wired to Hetzner Robot.
func New(username, password string) Client {
	c := hrobot.NewBasicAuthClient(username, password)
	return &sdkClient{upstream: c}
}

// NewFromHTTPClient is the test seam for injecting a fake HTTPClient
// without going through Robot's HTTP basic-auth.
func NewFromHTTPClient(c HTTPClient) Client {
	return &sdkClient{upstream: c}
}

// ListServers returns every server in the operator's Robot account.
// The controller filters by name prefix; we don't push that filter
// into Robot because the API doesn't expose server-side filtering.
func (c *sdkClient) ListServers(ctx context.Context) ([]Server, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	raw, err := c.upstream.ServerGetList()
	if err != nil {
		return nil, fmt.Errorf("robot server list: %w", err)
	}
	out := make([]Server, 0, len(raw))
	for _, s := range raw {
		out = append(out, Server{
			Number:    s.ServerNumber,
			Name:      s.Name,
			ServerIP:  s.ServerIP,
			Cancelled: s.Cancelled,
			Product:   s.Product,
			Dc:        s.Dc,
		})
	}
	return out, nil
}

// FakeClient is the in-memory Client used by controller tests.
type FakeClient struct {
	Servers []Server
	Err     error
}

func (f *FakeClient) ListServers(ctx context.Context) ([]Server, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if f.Err != nil {
		return nil, f.Err
	}
	return append([]Server(nil), f.Servers...), nil
}
