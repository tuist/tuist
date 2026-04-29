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
	"strings"

	applesilicon "github.com/scaleway/scaleway-sdk-go/api/applesilicon/v1alpha1"
	iam "github.com/scaleway/scaleway-sdk-go/api/iam/v1alpha1"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

// Client talks to Scaleway's Apple Silicon + IAM APIs. Construct with
// NewClient; in tests, the API fields can be replaced with fakes.
type Client struct {
	API *applesilicon.API
	IAM *iam.API
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
		return &Client{API: applesilicon.NewAPI(client), IAM: iam.NewAPI(client)}, nil
	}
	profile, err := cfg.GetActiveProfile()
	if err != nil {
		return nil, fmt.Errorf("scaleway profile: %w", err)
	}
	client, err := scw.NewClient(scw.WithProfile(profile), scw.WithEnv())
	if err != nil {
		return nil, fmt.Errorf("scaleway client: %w", err)
	}
	return &Client{API: applesilicon.NewAPI(client), IAM: iam.NewAPI(client)}, nil
}

// EnsureSSHKey registers `publicKey` with Scaleway under `name`.
// Returns the Scaleway-side SSH key ID. If a key with the same name
// already exists but its public-key bytes don't match `publicKey`, the
// stale registration is deleted and replaced — otherwise we'd silently
// pair a fresh cluster-side private key with a different pubkey on
// Scaleway, which is exactly the kind of split-brain that locks every
// SSH bootstrap out (see staging incident 2026-04-29).
func (c *Client) EnsureSSHKey(ctx context.Context, name, publicKey string) (string, error) {
	wantPub := normalizePubKey(publicKey)

	page := int32(1)
	pageSize := uint32(100)
	for {
		resp, err := c.IAM.ListSSHKeys(&iam.ListSSHKeysRequest{
			Name:     &name,
			Page:     &page,
			PageSize: &pageSize,
		}, scw.WithContext(ctx))
		if err != nil {
			return "", fmt.Errorf("list ssh keys: %w", err)
		}
		for _, k := range resp.SSHKeys {
			if k.Name != name {
				continue
			}
			if normalizePubKey(k.PublicKey) == wantPub {
				return k.ID, nil
			}
			// Same name, different pubkey — replace.
			if err := c.IAM.DeleteSSHKey(&iam.DeleteSSHKeyRequest{
				SSHKeyID: k.ID,
			}, scw.WithContext(ctx)); err != nil {
				return "", fmt.Errorf("delete stale ssh key %s: %w", k.ID, err)
			}
		}
		if uint64(uint32(page))*uint64(pageSize) >= uint64(resp.TotalCount) {
			break
		}
		page++
	}

	created, err := c.IAM.CreateSSHKey(&iam.CreateSSHKeyRequest{
		Name:      name,
		PublicKey: publicKey,
	}, scw.WithContext(ctx))
	if err != nil {
		return "", fmt.Errorf("create ssh key: %w", err)
	}
	return created.ID, nil
}

// normalizePubKey reduces an OpenSSH public-key string to its base64
// blob so we can compare across CR/LF + trailing-comment differences.
func normalizePubKey(pub string) string {
	fields := strings.Fields(pub)
	if len(fields) >= 2 {
		return fields[0] + " " + fields[1]
	}
	return strings.TrimSpace(pub)
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
//
// Idempotent on `name`: if a server with the given name already exists
// in the project we adopt it instead of creating a duplicate. This
// matters because CreateServer + WaitForServer can take 3-5min total,
// long enough for the parent reconcile context to time out and trigger
// a retry that would otherwise re-call CreateServer (and burn another
// 24h of Apple licensing on a server we won't end up using).
func (c *Client) CreateServer(ctx context.Context, name, zone, serverType, osName string) (*Server, error) {
	if existing, err := c.findServerByName(ctx, name, zone); err != nil {
		return nil, fmt.Errorf("lookup existing server: %w", err)
	} else if existing != nil {
		// Adopt the in-flight server. WaitForServer is idempotent — it
		// just polls until state==ready, fine to call on a server that
		// already finished provisioning.
		final, err := c.API.WaitForServer(&applesilicon.WaitForServerRequest{
			ServerID: existing.ID,
			Zone:     scw.Zone(zone),
		}, scw.WithContext(ctx))
		if err != nil {
			return nil, fmt.Errorf("wait for existing server: %w", err)
		}
		return scalewayServerToServer(final), nil
	}

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

// findServerByName returns the first server in the zone whose name
// matches `name`. Returns (nil, nil) when no match exists. The
// Scaleway ListServers API doesn't accept a name filter so we paginate
// the full list and match client-side; the project rarely has more
// than a handful of servers so this is fine.
func (c *Client) findServerByName(ctx context.Context, name, zone string) (*applesilicon.Server, error) {
	page := int32(1)
	pageSize := uint32(100)
	for {
		resp, err := c.API.ListServers(&applesilicon.ListServersRequest{
			Zone:     scw.Zone(zone),
			Page:     &page,
			PageSize: &pageSize,
		}, scw.WithContext(ctx))
		if err != nil {
			return nil, err
		}
		for _, s := range resp.Servers {
			if s.Name == name {
				return s, nil
			}
		}
		if len(resp.Servers) < int(pageSize) {
			return nil, nil
		}
		page++
	}
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
