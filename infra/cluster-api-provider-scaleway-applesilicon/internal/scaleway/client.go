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
	"sync"

	"github.com/google/uuid"
	applesilicon "github.com/scaleway/scaleway-sdk-go/api/applesilicon/v1alpha1"
	iam "github.com/scaleway/scaleway-sdk-go/api/iam/v1alpha1"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

// claimPendingPrefix marks a server that's mid-adoption — it has been
// renamed out of the operator's pool prefix but not yet to the final
// per-Machine `claimName`. Used by AdoptFromPool's two-phase claim to
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
	GetServer(req *applesilicon.GetServerRequest, opts ...scw.RequestOption) (*applesilicon.Server, error)
	ListServers(req *applesilicon.ListServersRequest, opts ...scw.RequestOption) (*applesilicon.ListServersResponse, error)
	UpdateServer(req *applesilicon.UpdateServerRequest, opts ...scw.RequestOption) (*applesilicon.Server, error)
	ReinstallServer(req *applesilicon.ReinstallServerRequest, opts ...scw.RequestOption) (*applesilicon.Server, error)
	RebootServer(req *applesilicon.RebootServerRequest, opts ...scw.RequestOption) (*applesilicon.Server, error)
}

// Client talks to Scaleway's Apple Silicon + IAM APIs. Construct with
// NewClient; in tests, the API fields can be replaced with fakes
// (see AppleSiliconAPI).
type Client struct {
	API AppleSiliconAPI
	IAM *iam.API

	// DefaultProjectID is the SCW_DEFAULT_PROJECT_ID the underlying
	// scw client was constructed with. Captured at NewClient time
	// so IAM calls that Scaleway strictly enforces project scope on
	// (notably ListSSHKeys / CreateSSHKey under a project-scoped
	// `SSHKeysFullAccess` policy) can include it explicitly. The
	// SDK won't back-fill it into IAM resource requests on its own —
	// without an explicit ProjectID, ListSSHKeys ends up asking for
	// org-wide list and Scaleway returns "insufficient permissions".
	DefaultProjectID string

	// adoptMu serializes AdoptFromPool and ReleaseToPool against each
	// other across all goroutines in this process. ReleaseToPool renames
	// a host into the pool prefix and only then requests the reinstall,
	// so between those two calls the host carries the pool prefix and is
	// still Status==ready; without holding this lock a concurrent
	// adoption scan could claim it in that window and then the reinstall
	// would wipe the freshly-claimed host. Scaleway's UpdateServer is not
	// conditional — two
	// concurrent rename calls against the same server both succeed,
	// last-write-wins — so per-call optimistic read-after-write
	// verification can't establish a "we own this server" invariant.
	// The controller is single-replica via leader election, so a
	// process-local mutex is sufficient: only the leader runs, and
	// the leader doesn't race itself once adoptions are serialized.
	// Adoption is rare (one acquisition per Machine bring-up) and
	// short (a few API calls); serializing it has no meaningful
	// throughput cost.
	adoptMu sync.Mutex
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
		projectID, _ := client.GetDefaultProjectID()
		return &Client{API: applesilicon.NewAPI(client), IAM: iam.NewAPI(client), DefaultProjectID: projectID}, nil
	}
	profile, err := cfg.GetActiveProfile()
	if err != nil {
		return nil, fmt.Errorf("scaleway profile: %w", err)
	}
	client, err := scw.NewClient(scw.WithProfile(profile), scw.WithEnv())
	if err != nil {
		return nil, fmt.Errorf("scaleway client: %w", err)
	}
	projectID, _ := client.GetDefaultProjectID()
	return &Client{API: applesilicon.NewAPI(client), IAM: iam.NewAPI(client), DefaultProjectID: projectID}, nil
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

	// Scope every IAM request to the env-default project. Scaleway
	// gates `iam:ListSSHKeys` under a project-scoped
	// `SSHKeysFullAccess` policy strictly: without an explicit
	// ProjectID filter, the listing is implicitly org-wide and gets
	// denied with `insufficient permissions: list ssh_key`. Bundle
	// the same filter into the create call so the new key lands in
	// the same project the existing fleet keys live in (matches the
	// AGENTS.md "project scope" convention for the IAM application).
	var projectIDFilter *string
	if c.DefaultProjectID != "" {
		p := c.DefaultProjectID
		projectIDFilter = &p
	}

	page := int32(1)
	pageSize := uint32(100)
	for {
		resp, err := c.IAM.ListSSHKeys(&iam.ListSSHKeysRequest{
			Name:      &name,
			ProjectID: projectIDFilter,
			Page:      &page,
			PageSize:  &pageSize,
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
		ProjectID: c.DefaultProjectID,
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
	ID   string
	Name string
	IP   string
	// Status is the Scaleway lifecycle phase (`ready`, `reinstalling`,
	// `rebooting`, …) as a raw string.
	Status       string
	SudoPassword string
	SSHUsername  string
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

// ListServers returns every Apple Silicon server the configured
// credentials can see in `zone`, reduced to the Server view. The
// Scaleway API has no server-side name filter, so it paginates the
// full list and the caller filters client-side — the project holds at
// most a few dozen hosts, so a full scan is cheap. Used by the
// orphan-reclaim sweep to diff live hosts against the CRs that own
// them.
func (c *Client) ListServers(ctx context.Context, zone string) ([]Server, error) {
	var out []Server
	page := int32(1)
	pageSize := uint32(100)
	for {
		resp, err := c.API.ListServers(&applesilicon.ListServersRequest{
			Zone:     scw.Zone(zone),
			Page:     &page,
			PageSize: &pageSize,
		}, scw.WithContext(ctx))
		if err != nil {
			return nil, fmt.Errorf("list servers in %s: %w", zone, err)
		}
		for _, s := range resp.Servers {
			out = append(out, *scalewayServerToServer(s))
		}
		if len(resp.Servers) < int(pageSize) {
			return out, nil
		}
		page++
	}
}

// IsPoolOrAdopting reports whether a Scaleway server name marks a host
// that is parked in the adopt pool (carries poolPrefix) or mid-adoption
// (carries the internal claim-pending marker). Either is
// controller-managed and must never be treated as stranded by the
// orphan-reclaim sweep — the claim-pending case especially, since that
// host is in the middle of being adopted by a live reconcile.
func IsPoolOrAdopting(name, poolPrefix string) bool {
	if poolPrefix != "" && strings.HasPrefix(name, poolPrefix) {
		return true
	}
	return strings.HasPrefix(name, claimPendingPrefix)
}

// ErrNoAvailableHost is returned by AdoptFromPool when no
// pre-ordered server in the project carries the configured pool
// prefix AND matches the requested spec (`type`/`os`/`zone`).
// Scaleway Mac mini lead times rule out auto-ordering on the hot
// path, so the controller treats this as a transient state —
// emit an event and requeue, expecting the operator to pre-order
// more capacity.
var ErrNoAvailableHost = errors.New("no available Apple Silicon host in pool")

// AdoptFromPool claims a pre-ordered server in `zone` whose
// Scaleway-side name starts with `poolPrefix`, matches
// (`serverType`, `osName`), and is `Delivered=true` +
// `Status=ready`. The rename to `claimName` IS the claim — it both
// removes the pool prefix (so the host no longer appears available)
// and makes the host findable on future reconciles via the existing
// name-based idempotency path (`findServerByName`).
//
// Concurrent claims are resolved by a process-local mutex
// (`adoptMu`). Scaleway's UpdateServer is not conditional — two
// renames to different target names against the same server both
// succeed, last-write-wins — so optimistic read-after-write
// verification alone can't prevent two reconciles from walking
// away with the same ServerID. The controller is single-replica
// via leader election, so serializing adoption inside the leader
// is sufficient; only one goroutine at a time enters this function.
//
// Within that serialized section, a two-phase rename also runs as
// defense-in-depth against external mutation (operator-driven
// rename via the Scaleway console mid-adoption, or a future
// multi-replica deployment that loses leader election between
// reconciles):
//
//  1. Pick a candidate. UpdateServer renames it to a per-call
//     marker `tuist-claim-pending-<uuid>`. GetServer the candidate
//     and confirm the marker survived.
//  2. UpdateServer to the final `claimName`.
//
// If between phase 1 and phase 2 some external actor renames the
// server, the verify GET reveals the foreign name and the
// candidate is skipped.
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
func (c *Client) AdoptFromPool(ctx context.Context, claimName, zone, serverType, osName, poolPrefix string) (*Server, error) {
	if poolPrefix == "" {
		return nil, fmt.Errorf("poolPrefix is required for adoption")
	}

	c.adoptMu.Lock()
	defer c.adoptMu.Unlock()

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
// rename described in AdoptFromPool.
//
// Returns:
//
//   - (*Server, nil)   — we won and promoted to claimName.
//   - (nil, nil)       — race lost or candidate vanished (404).
//     Caller should try another candidate. Triggered by a server
//     that disappears (deleted by an operator mid-scan) or whose
//     pending marker is overwritten between phase 1 and verify.
//   - (nil, error)     — Scaleway returned a non-404 error on
//     phase 1 / verify, or phase 2 promotion failed. The caller
//     should surface it as a real provisioning failure rather
//     than rolling on to "no available capacity" — a 403, 500, or
//     validation error means something operational is wrong and
//     pre-ordering more hosts won't help.
func (c *Client) tryTwoPhaseClaim(ctx context.Context, serverID, zone, pendingName, claimName string) (*Server, error) {
	// Phase 1: stake the candidate with our per-call marker.
	if _, err := c.API.UpdateServer(&applesilicon.UpdateServerRequest{
		ServerID: serverID,
		Zone:     scw.Zone(zone),
		Name:     &pendingName,
	}, scw.WithContext(ctx)); err != nil {
		// 404 means the candidate was deleted out from under us
		// between the list and our UpdateServer call (concurrent
		// operator action). That's recoverable — try the next
		// candidate. Every other Scaleway error (auth, validation,
		// outage) is operational and must surface, otherwise the
		// outer loop quietly downgrades it to ErrNoAvailableHost
		// and tells operators to pre-order capacity they already have.
		if IsNotFound(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("phase 1 rename of server %s to pending marker: %w", serverID, err)
	}

	// Verify the marker survived. With adoptMu held we won't race
	// ourselves, but an external rename (operator console, future
	// multi-replica deployment that lost leader election) can still
	// overwrite the marker — bail in that case rather than promote a
	// name we may not actually hold.
	verified, err := c.API.GetServer(&applesilicon.GetServerRequest{
		ServerID: serverID,
		Zone:     scw.Zone(zone),
	}, scw.WithContext(ctx))
	if err != nil {
		if IsNotFound(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("phase 1 verify of server %s: %w", serverID, err)
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

// RebootServer asks Scaleway to reboot the host. Fire-and-forget on
// the wire; the server transitions through `rebooting → ready` on its
// own (~1-2 min). Used as a cheap volatile-state clear before
// considering a host irrecoverable — clears in-memory PAM lockouts,
// sshd connection throttling, and other state that survives across
// failed SSH attempts but not across a clean boot.
func (c *Client) RebootServer(ctx context.Context, id, zone string) error {
	_, err := c.API.RebootServer(&applesilicon.RebootServerRequest{
		ServerID: id,
		Zone:     scw.Zone(zone),
	}, scw.WithContext(ctx))
	if err != nil {
		if IsNotFound(err) {
			return nil
		}
		// A reboot issued while the server is already mid-reboot/install
		// is harmless from our perspective; treat the typed transient
		// state error as success so callers aren't pushed into
		// secondary recovery for a no-op.
		if isTransientState(err) {
			return nil
		}
		return fmt.Errorf("reboot server %s: %w", id, err)
	}
	return nil
}

// ReleaseToPool returns a Mac mini to the adopt pool. Operator-
// driven physical destruction is intentionally separated from
// cluster-driven Machine churn: the 24h Apple-licensing floor makes
// destroy-and-recreate wildly expensive (you pay for the floor
// regardless of whether the host is in your cluster), and the
// operator already owns host capacity planning via the pre-order
// workflow. So "Machine deleted" means "host returned to the pool,
// freshly reinstalled, ready for the next adopt." Operators
// retiring a broken host do so out-of-band via the Scaleway console.
//
// Two-step:
//
//  1. Rename the server back into the pool namespace via
//     UpdateServer. The new name is `poolPrefix + uuid` — a fresh
//     UUID so we don't collide with any other pool host that's been
//     parked at the same name earlier in the host's lifetime, and
//     because AdoptFromPool scans on the prefix (the exact suffix
//     doesn't matter). Once renamed, the host is invisible to
//     `findServerByName(claimName)` lookups (the per-Machine name
//     is gone) and visible to future `AdoptFromPool` scans.
//
//  2. Trigger ReinstallServer, which wipes the disk and reimages
//     with the server type's default OS. Async on Scaleway's side
//     (~5-15 min on M2-L); we fire-and-forget because
//     AdoptFromPool already filters on `Delivered + Status == Ready`
//     and the host transitions through `reinstalling → ready` on
//     its own. Means: next adopt sees factory-default state — no
//     stale tart-kubelet config, no leftover Tailscale auth, no
//     cached secrets — so bootstrap doesn't need to be re-entrant.
//
// Idempotency: callers retry on error. Step 1 is safe to repeat —
// renaming to a different UUID just lands the host at a different
// pool name, both eligible for adoption. Step 2 returns a
// TransientStateError if the server is already mid-reinstall from a
// previous attempt; we swallow it as success. 404 on either step
// means the operator deleted the host out-of-band; also success.
func (c *Client) ReleaseToPool(ctx context.Context, id, zone, poolPrefix string) error {
	if poolPrefix == "" {
		return fmt.Errorf("ReleaseToPool: poolPrefix is required")
	}

	// Hold the adoption lock across the rename + reinstall request so an
	// AdoptFromPool scan can't claim the host in the window where it
	// already carries the pool prefix but the wipe hasn't been requested
	// yet. See the adoptMu field comment.
	c.adoptMu.Lock()
	defer c.adoptMu.Unlock()

	newName := poolPrefix + uuid.NewString()
	if _, err := c.API.UpdateServer(&applesilicon.UpdateServerRequest{
		ServerID: id,
		Zone:     scw.Zone(zone),
		Name:     &newName,
	}, scw.WithContext(ctx)); err != nil {
		if IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("rename server %s into pool: %w", id, err)
	}

	if _, err := c.API.ReinstallServer(&applesilicon.ReinstallServerRequest{
		ServerID: id,
		Zone:     scw.Zone(zone),
	}, scw.WithContext(ctx)); err != nil {
		if IsNotFound(err) {
			return nil
		}
		if isTransientState(err) {
			// Server is already in `reinstalling` (or some other
			// transient phase) from a prior reconcile attempt or an
			// out-of-band operator action. Either way the reinstall is
			// in flight and we don't need to kick off another one.
			return nil
		}
		return fmt.Errorf("reinstall server %s: %w", id, err)
	}

	return nil
}

// isTransientState detects scaleway-sdk-go's typed
// `*scw.TransientStateError`, which the SDK returns when a request
// can't proceed because the resource is in a transitional phase
// (`reinstalling`, `deleting`, …). The SDK parses this into its own
// concrete type inside hasResponseError, so checking *ResponseError
// alone misses it.
func isTransientState(err error) bool {
	var transientErr *scw.TransientStateError
	return errors.As(err, &transientErr)
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

// SealedSecretMarker is the literal placeholder macOS Tahoe writes when
// the OS-managed auto-login credential is sealed (e.g., immediately
// after a fresh adopt or while the server is rebooting). Scaleway
// surfaces it verbatim through both `sudo_password` and `vnc_url` while
// the seal is in effect — the string is not a usable password.
const SealedSecretMarker = "<sealed>"

func scalewayServerToServer(s *applesilicon.Server) *Server {
	out := &Server{
		ID:           s.ID,
		Name:         s.Name,
		Status:       string(s.Status),
		SudoPassword: s.SudoPassword,
		SSHUsername:  s.SSHUsername,
	}
	if s.IP != nil {
		out.IP = s.IP.String()
	}
	// Scaleway either populates `sudo_password` directly (one-time
	// CreateServer response, or transient post-adopt windows) or
	// returns the literal `<sealed>` marker while the OS-level seal is
	// in effect. The `vnc_url` field carries the same OS-default
	// credentials as `vnc://<ssh_username>:<password>@<ip>:<port>` and
	// is surfaced on every GET — pull the password from there when the
	// top-level field isn't directly usable.
	if out.SudoPassword == "" || out.SudoPassword == SealedSecretMarker {
		out.SudoPassword = passwordFromVncURL(s.VncURL)
	}
	// `vnc_url` itself can carry the sealed marker either as the whole
	// string (URL parsing returns no userinfo → empty above) or as the
	// embedded password component (URL parsing succeeds → marker comes
	// through verbatim). Reject the marker so downstream code never
	// hands `<sealed>` to sudo.
	if out.SudoPassword == SealedSecretMarker {
		out.SudoPassword = ""
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
