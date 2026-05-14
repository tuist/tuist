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
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/google/uuid"
	applesilicon "github.com/scaleway/scaleway-sdk-go/api/applesilicon/v1alpha1"
	iam "github.com/scaleway/scaleway-sdk-go/api/iam/v1alpha1"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

// claimPendingPrefix marks a server that's mid-adoption — it has been
// renamed out of the operator's pool prefix but not yet to the final
// per-Machine `claimName`. Used by AdoptByPrefix's two-phase claim to
// detect race losers (their pending name has been overwritten by
// someone else's) and to let subsequent reconciles re-adopt orphans
// from a controller crash between the two phases.
const claimPendingPrefix = "tuist-claim-pending-"

// AppleSiliconAPI is the slice of the Scaleway SDK's
// `applesilicon.API` surface the CAPI provider touches. Declared as
// an interface so tests can drop in a fake without needing the real
// SDK + HTTP client. The concrete `*applesilicon.API` satisfies it
// via Go's structural typing — no adapter required.
type AppleSiliconAPI interface {
	CreateServer(req *applesilicon.CreateServerRequest, opts ...scw.RequestOption) (*applesilicon.Server, error)
	GetServer(req *applesilicon.GetServerRequest, opts ...scw.RequestOption) (*applesilicon.Server, error)
	ListServers(req *applesilicon.ListServersRequest, opts ...scw.RequestOption) (*applesilicon.ListServersResponse, error)
	UpdateServer(req *applesilicon.UpdateServerRequest, opts ...scw.RequestOption) (*applesilicon.Server, error)
	DeleteServer(req *applesilicon.DeleteServerRequest, opts ...scw.RequestOption) error
	WaitForServer(req *applesilicon.WaitForServerRequest, opts ...scw.RequestOption) (*applesilicon.Server, error)
	ListOS(req *applesilicon.ListOSRequest, opts ...scw.RequestOption) (*applesilicon.ListOSResponse, error)
}

// Client talks to Scaleway's Apple Silicon + IAM APIs. Construct with
// NewClient; in tests, the API fields can be replaced with fakes
// (see AppleSiliconAPI).
type Client struct {
	API AppleSiliconAPI
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

// ErrNoAvailableHost is returned by AdoptByPrefix when no
// pre-ordered server in the project carries the configured pool
// prefix AND matches the requested spec (`type`/`os`/`zone`).
// Scaleway Mac mini lead times rule out auto-ordering on the hot
// path, so the controller treats this as a transient state —
// emit an event and requeue, expecting the operator to pre-order
// more capacity.
var ErrNoAvailableHost = errors.New("no available Apple Silicon host in pool")

// AdoptByPrefix claims a pre-ordered server in `zone` whose
// Scaleway-side name starts with `poolPrefix`, matches
// (`serverType`, `osName`), and is `Delivered=true` +
// `Status=ready`. The rename to `claimName` IS the claim — it both
// removes the pool prefix (so the host no longer appears available)
// and makes the host findable on future reconciles via the existing
// name-based idempotency path (`findServerByName`).
//
// Concurrent reconciles racing the same pool host are resolved via
// a two-phase claim:
//
//  1. Pick a candidate. UpdateServer renames it to a per-reconcile
//     marker `tuist-claim-pending-<uuid>`. Each reconcile generates
//     its own uuid, so two reconciles racing the same host write
//     two distinct names — one of the two writes lands last.
//  2. GetServer the candidate immediately. If `Name` still matches
//     OUR marker, no one else's rename has landed after ours and we
//     have the only outstanding claim. Promote with a second
//     UpdateServer to `claimName`. If `Name` reflects somebody
//     else's marker (or any unexpected value), the race is lost —
//     skip the candidate and let the loop pick another.
//
// Why two phases instead of renaming straight to `claimName`: every
// concurrent UpdateServer with a *different* target name succeeds
// against Scaleway (no name-conflict response on differing targets),
// so a single-step rename allows two Machines to both walk away with
// the same ServerID, which is what we hit on the May 14 production
// roll (multiple ScalewayAppleSiliconMachine CRs sharing one
// ProviderID).
//
// Recovery from a crash between phases: if the controller exits
// after phase 1, the server is stuck at `tuist-claim-pending-<uuid>`
// outside any pool prefix. Subsequent scans treat any name carrying
// `claimPendingPrefix` as eligible — same two-phase dance applies,
// so the next reconcile re-adopts the orphan cleanly.
//
// Why a rename and not a Scaleway tag? The Apple Silicon API
// doesn't expose tags. Naming is the only mutable, queryable
// signal we have.
func (c *Client) AdoptByPrefix(ctx context.Context, claimName, zone, serverType, osName, poolPrefix string) (*Server, error) {
	if poolPrefix == "" {
		return nil, fmt.Errorf("poolPrefix is required for adoption")
	}

	// Idempotent rediscovery: if a previous reconcile completed phase 2
	// for this Machine but its `status.serverID` patch was lost (process
	// crash, conflicted optimistic write), the host already has the
	// final claimName. Check by name first so the next reconcile picks
	// the already-claimed host back up without burning a second host.
	if existing, err := c.findServerByName(ctx, claimName, zone); err != nil {
		return nil, fmt.Errorf("lookup existing claim %q: %w", claimName, err)
	} else if existing != nil {
		return scalewayServerToServer(existing), nil
	}

	pendingName := claimPendingPrefix + uuid.NewString()

	page := int32(1)
	pageSize := uint32(100)
	for {
		resp, err := c.API.ListServers(&applesilicon.ListServersRequest{
			Zone:     scw.Zone(zone),
			Page:     &page,
			PageSize: &pageSize,
		}, scw.WithContext(ctx))
		if err != nil {
			return nil, fmt.Errorf("list servers: %w", err)
		}

		for _, s := range resp.Servers {
			// Eligible candidates: untouched pool hosts AND
			// claim-pending orphans from a prior crashed reconcile.
			// Orphans are safe to re-adopt because the two-phase dance
			// below guarantees only one reconcile can promote the
			// pending name.
			eligible := strings.HasPrefix(s.Name, poolPrefix) ||
				strings.HasPrefix(s.Name, claimPendingPrefix)
			if !eligible {
				continue
			}
			if !s.Delivered || s.Status != applesilicon.ServerStatusReady {
				continue
			}
			if s.Type != serverType {
				continue
			}
			if s.Os == nil || s.Os.Name != osName {
				continue
			}

			claimed, err := c.tryTwoPhaseClaim(ctx, s.ID, zone, pendingName, claimName)
			if err != nil {
				return nil, err
			}
			if claimed == nil {
				// Lost the phase-1 race; another reconcile got there
				// after us. Try the next candidate.
				continue
			}
			return claimed, nil
		}

		if len(resp.Servers) < int(pageSize) {
			return nil, ErrNoAvailableHost
		}
		page++
	}
}

// tryTwoPhaseClaim attempts to claim `serverID` via the two-phase
// rename described in AdoptByPrefix.
//
// Returns:
//
//   - (*Server, nil)   — we won the race and promoted to claimName.
//   - (nil, nil)       — lost the race; caller should try another
//     candidate. Phase 1 either failed transiently or our pending
//     marker was overwritten before phase 2.
//   - (nil, error)     — phase 2 promotion failed after phase 1
//     succeeded, which leaves the server in pendingName. The caller
//     should requeue; on the next reconcile this server is matched
//     as a claim-pending orphan and re-adopted.
func (c *Client) tryTwoPhaseClaim(ctx context.Context, serverID, zone, pendingName, claimName string) (*Server, error) {
	// Phase 1: stake the candidate with our per-reconcile marker.
	if _, err := c.API.UpdateServer(&applesilicon.UpdateServerRequest{
		ServerID: serverID,
		Zone:     scw.Zone(zone),
		Name:     &pendingName,
	}, scw.WithContext(ctx)); err != nil {
		// Treat a 404 as race-lost (someone else claimed and then we
		// raced a delete; rare but recoverable). All other errors
		// abort the candidate — the caller's outer loop will move on.
		return nil, nil
	}

	// Verify the marker survived. A concurrent reconcile that also
	// wrote a pending name for this serverID after ours would show
	// its own marker here; if so we lost the race.
	verified, err := c.API.GetServer(&applesilicon.GetServerRequest{
		ServerID: serverID,
		Zone:     scw.Zone(zone),
	}, scw.WithContext(ctx))
	if err != nil {
		// Can't confirm we own the marker — safest is to skip rather
		// than promote a name we may not actually hold.
		return nil, nil
	}
	if verified.Name != pendingName {
		return nil, nil
	}

	// Phase 2: promote pending marker to the final claimName.
	promoted, err := c.API.UpdateServer(&applesilicon.UpdateServerRequest{
		ServerID: serverID,
		Zone:     scw.Zone(zone),
		Name:     &claimName,
	}, scw.WithContext(ctx))
	if err != nil {
		return nil, fmt.Errorf("promote claim from %q to %q on server %s: %w",
			pendingName, claimName, serverID, err)
	}
	return scalewayServerToServer(promoted), nil
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

// DeleteServer terminates a Mac mini. Apple's licensing enforces a
// 24h floor — DeleteServer fails with HTTP 412 inside that window.
// When that happens we fall back to UpdateServer with
// `schedule_deletion=true`, which queues the delete for the floor
// expiry. Scaleway keeps billing through the floor either way.
//
// 404 from Scaleway means the server is already gone (manual delete,
// scheduled-deletion already executed, or a previous reconcile that
// completed but crashed before the patch landed). Treated as success
// so the finalizer comes off and the CR can be GC'd; without this the
// reconcile loops forever and the Mac mini billing keeps running on
// any sibling server we haven't pruned.
func (c *Client) DeleteServer(ctx context.Context, id, zone string) error {
	err := c.API.DeleteServer(&applesilicon.DeleteServerRequest{
		ServerID: id,
		Zone:     scw.Zone(zone),
	}, scw.WithContext(ctx))
	if err == nil {
		return nil
	}
	if IsNotFound(err) {
		return nil
	}
	if !isPreconditionFailed(err) {
		return err
	}
	scheduled := true
	_, updateErr := c.API.UpdateServer(&applesilicon.UpdateServerRequest{
		ServerID:         id,
		Zone:             scw.Zone(zone),
		ScheduleDeletion: &scheduled,
	}, scw.WithContext(ctx))
	if updateErr != nil {
		if IsNotFound(updateErr) {
			return nil
		}
		return fmt.Errorf("schedule deletion (after immediate delete failed with %v): %w", err, updateErr)
	}
	return nil
}

// isPreconditionFailed detects Scaleway's HTTP 412 — typically the
// 24h Apple-licensing floor on DeleteServer.
func isPreconditionFailed(err error) bool {
	var scwErr *scw.ResponseError
	if errors.As(err, &scwErr) {
		return scwErr.StatusCode == http.StatusPreconditionFailed
	}
	return false
}

// IsNotFound returns true for Scaleway's 404 responses. Exposed so the
// reconciler's delete path can distinguish "already gone" (clear the
// finalizer, succeed) from genuine API errors (requeue).
func IsNotFound(err error) bool {
	if err == nil {
		return false
	}
	var notFound *scw.ResourceNotFoundError
	if errors.As(err, &notFound) {
		return true
	}
	var scwErr *scw.ResponseError
	if errors.As(err, &scwErr) {
		return scwErr.StatusCode == http.StatusNotFound
	}
	return false
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
	// Scaleway only populates `sudo_password` on the CreateServer
	// response — once that one-time window closes, every subsequent
	// GET/list returns an empty `sudo_password`. Hosts adopted from
	// the pre-ordered pool never go through CreateServer, so without
	// this fallback the controller stages an empty password into the
	// bootstrap Secret and `enableAutoLogin` either silently skips
	// (writing nothing) or writes a kcpassword whose plaintext is
	// just the cipher key padding — either way Aqua never comes up
	// and `tart run` fails forever.
	//
	// The `vnc_url` field embeds the same OS-default credentials as
	// `vnc://<ssh_username>:<password>@<ip>:<port>`. It's surfaced on
	// every GET, including for adopted servers, and verified out-of-
	// band to authenticate the m1 macOS user. Pull the password from
	// there when `sudo_password` is empty.
	if out.SudoPassword == "" {
		out.SudoPassword = passwordFromVncURL(s.VncURL)
	}
	return out
}

// passwordFromVncURL extracts the password embedded in a Scaleway
// Apple Silicon `vnc_url` of the form
// `vnc://<user>:<password>@<host>:<port>`. Returns "" if the URL is
// empty, malformed, or doesn't carry user-info. Special characters in
// the password are percent-decoded by `url.Parse` so callers receive
// the raw plaintext.
func passwordFromVncURL(raw string) string {
	if raw == "" {
		return ""
	}
	u, err := url.Parse(raw)
	if err != nil || u.User == nil {
		return ""
	}
	pwd, ok := u.User.Password()
	if !ok {
		return ""
	}
	return pwd
}
