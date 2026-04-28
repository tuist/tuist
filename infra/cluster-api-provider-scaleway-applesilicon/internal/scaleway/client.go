// Package scaleway wraps the bits of Scaleway's Apple Silicon API the
// CAPI provider needs: server CRUD, status polling, OS lookup.
//
// We rely on github.com/scaleway/scaleway-sdk-go for the underlying
// HTTP client. Authentication uses the standard Scaleway env vars
// (SCW_ACCESS_KEY / SCW_SECRET_KEY / SCW_DEFAULT_PROJECT_ID); the
// CAPI manager's Deployment mounts a Secret with these.
package scaleway

import (
	"context"
	"fmt"

	applesilicon "github.com/scaleway/scaleway-sdk-go/api/applesilicon/v1alpha1"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

// Client talks to Scaleway's Apple Silicon API. Construct with
// NewClient; in tests, the API field can be replaced with a fake.
type Client struct {
	API *applesilicon.API
}

// NewClient initializes a Scaleway client from the standard environment
// variables. Returns an error if credentials are missing.
func NewClient() (*Client, error) {
	cfg, err := scw.LoadConfig()
	if err != nil {
		// Fall back to env-only auth — that's how we run inside the
		// CAPI provider Deployment.
		client, err := scw.NewClient(scw.WithEnv())
		if err != nil {
			return nil, fmt.Errorf("scaleway client: %w", err)
		}
		return &Client{API: applesilicon.NewAPI(client)}, nil
	}
	profile, err := cfg.GetActiveProfile()
	if err != nil {
		return nil, fmt.Errorf("scaleway profile: %w", err)
	}
	client, err := scw.NewClient(scw.WithProfile(profile), scw.WithEnv())
	if err != nil {
		return nil, fmt.Errorf("scaleway client: %w", err)
	}
	return &Client{API: applesilicon.NewAPI(client)}, nil
}

// Server is the subset of fields the CAPI controller cares about.
type Server struct {
	ID           string
	IP           string
	Status       string
	SudoPassword string
	SSHUsername  string
}

// CreateServer orders a new Mac mini in `zone`. Blocks until Scaleway
// reports the server in a state past `starting`. The returned struct
// includes the one-time OS-default sudo password the controller stashes
// for break-glass SSH access; it isn't persisted in Scaleway after the
// initial provisioning window.
func (c *Client) CreateServer(ctx context.Context, name, zone, serverType, osName string) (*Server, error) {
	osID, err := c.resolveOSID(ctx, zone, osName)
	if err != nil {
		return nil, err
	}

	created, err := c.API.CreateServer(&applesilicon.CreateServerRequest{
		Zone: scw.Zone(zone),
		Name: name,
		Type: serverType,
		OsID: &osID,
	}, scw.WithContext(ctx))
	if err != nil {
		return nil, fmt.Errorf("create server: %w", err)
	}

	// Wait for the server to be ready (Scaleway calls this `ready`).
	final, err := c.API.WaitForServer(&applesilicon.WaitForServerRequest{
		ServerID: created.ID,
		Zone:     scw.Zone(zone),
	}, scw.WithContext(ctx))
	if err != nil {
		return nil, fmt.Errorf("wait for server: %w", err)
	}

	return scalewayServerToServer(final), nil
}

// GetServer fetches the current state of an existing server.
func (c *Client) GetServer(ctx context.Context, id, zone string) (*Server, error) {
	srv, err := c.API.GetServer(&applesilicon.GetServerRequest{
		ServerID: id,
		Zone:     scw.Zone(zone),
	}, scw.WithContext(ctx))
	if err != nil {
		return nil, err
	}
	return scalewayServerToServer(srv), nil
}

// DeleteServer terminates a Mac mini. Apple's licensing means we keep
// paying for the full 24h window, but the server itself is released
// back to Scaleway for the next tenant.
func (c *Client) DeleteServer(ctx context.Context, id, zone string) error {
	return c.API.DeleteServer(&applesilicon.DeleteServerRequest{
		ServerID: id,
		Zone:     scw.Zone(zone),
	}, scw.WithContext(ctx))
}

func (c *Client) resolveOSID(ctx context.Context, zone, name string) (string, error) {
	resp, err := c.API.ListOS(&applesilicon.ListOSRequest{
		Zone: scw.Zone(zone),
	}, scw.WithContext(ctx))
	if err != nil {
		return "", fmt.Errorf("list OS: %w", err)
	}
	for _, os := range resp.Os {
		if os.Name == name {
			return os.ID, nil
		}
	}
	return "", fmt.Errorf("OS %q not found in zone %s", name, zone)
}

func scalewayServerToServer(s *applesilicon.Server) *Server {
	out := &Server{
		ID:           s.ID,
		Status:       string(s.Status),
		SudoPassword: s.SudoPassword,
		SSHUsername:  s.SSHUsername,
	}
	if s.IP != nil {
		out.IP = s.IP.String()
	}
	return out
}
