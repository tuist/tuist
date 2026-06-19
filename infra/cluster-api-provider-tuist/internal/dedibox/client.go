// Package dedibox is the Scaleway Dedibox client the DediboxMachine reconciler
// talks to. Dedibox is managed through the project-scoped Scaleway API
// (api.scaleway.com, dedibox/v1) with IAM keys, the same auth + Project model
// Elastic Metal uses — NOT the legacy account-wide online.net token.
//
// The Project is the ENVIRONMENT BOUNDARY: an IAM key scoped to a project can
// only see and install that project's servers, so a staging manager can never
// adopt or reinstall a production box (and vice versa). That isolation is
// enforced by Scaleway IAM, not by a name we hope someone set on a bare box.
// Within a project, adoption keys on offer + datacenter (both intrinsic to a
// bare box and returned in the server list), deduped by the cluster-side
// claimed-server set the controller passes in.
package dedibox

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"net/http"
	"strings"

	scwdedibox "github.com/scaleway/scaleway-sdk-go/api/dedibox/v1"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

// dediboxZones are the Scaleway zones Dedibox is offered in. Adoption scans all
// of them (a fleet's datacenter is a console name like "DC2", which lives inside
// one of these zones); the matched server's own zone is then used for every
// follow-up call.
var dediboxZones = []scw.Zone{scw.ZoneFrPar1, scw.ZoneFrPar2, scw.ZoneNlAms1}

// API is the slice of the Scaleway Dedibox SDK the reconciler touches. An
// interface so tests drop in a fake; the concrete *scwdedibox.API satisfies it
// structurally.
type API interface {
	ListServers(req *scwdedibox.ListServersRequest, opts ...scw.RequestOption) (*scwdedibox.ListServersResponse, error)
	GetServer(req *scwdedibox.GetServerRequest, opts ...scw.RequestOption) (*scwdedibox.Server, error)
	ListOS(req *scwdedibox.ListOSRequest, opts ...scw.RequestOption) (*scwdedibox.ListOSResponse, error)
	GetServerDefaultPartitioning(req *scwdedibox.GetServerDefaultPartitioningRequest, opts ...scw.RequestOption) (*scwdedibox.ServerDefaultPartitioning, error)
	InstallServer(req *scwdedibox.InstallServerRequest, opts ...scw.RequestOption) (*scwdedibox.ServerInstall, error)
	GetServerInstall(req *scwdedibox.GetServerInstallRequest, opts ...scw.RequestOption) (*scwdedibox.ServerInstall, error)
}

// Client talks to the Scaleway Dedibox API, scoped to one project. Construct
// with NewClientFromEnv; in tests the API field takes a fake.
type Client struct {
	API       API
	ProjectID string
}

// NewClient builds a Client from an authenticated scw client; ProjectID is read
// from the client's default project so every list/install is project-scoped.
func NewClient(client *scw.Client) *Client {
	projectID, _ := client.GetDefaultProjectID()
	return &Client{API: scwdedibox.NewAPI(client), ProjectID: projectID}
}

// NewClientFromEnv builds a Client with the same env/profile Scaleway auth the
// Elastic Metal client uses (SCW_ACCESS_KEY / SCW_SECRET_KEY /
// SCW_DEFAULT_PROJECT_ID), synced per-env from the project-scoped IAM key. The
// project the key is scoped to is the environment boundary.
func NewClientFromEnv() (*Client, error) {
	if cfg, err := scw.LoadConfig(); err == nil {
		if profile, perr := cfg.GetActiveProfile(); perr == nil {
			client, cerr := scw.NewClient(scw.WithProfile(profile), scw.WithEnv())
			if cerr != nil {
				return nil, fmt.Errorf("scaleway client: %w", cerr)
			}
			return NewClient(client), nil
		}
	}
	client, err := scw.NewClient(scw.WithEnv())
	if err != nil {
		return nil, fmt.Errorf("scaleway client: %w", err)
	}
	return NewClient(client), nil
}

// IsNotFound reports whether err is a Scaleway 404 (resource gone).
func IsNotFound(err error) bool {
	var notFound *scw.ResourceNotFoundError
	if errors.As(err, &notFound) {
		return true
	}
	var respErr *scw.ResponseError
	if errors.As(err, &respErr) && respErr.StatusCode == http.StatusNotFound {
		return true
	}
	return false
}

// ProviderID is the foreign CAPI providerID for a Dedibox server,
// `dedibox://<zone>/<id>`. The non-Hetzner host keeps the Hetzner CCM from
// reaping the node, the same guard the Scaleway baremetal + OVH kinds use.
func ProviderID(zone string, id uint64) string {
	return fmt.Sprintf("dedibox://%s/%d", zone, id)
}

// Server is the reconciler's view of a Dedibox server, flattened from the SDK
// summary/detail shapes. Zone is a plain string so the controller never imports
// the Scaleway SDK.
type Server struct {
	ID         uint64
	Zone       string
	Hostname   string
	Offer      string
	Datacenter string
	ProjectID  string
	Installed  bool
	PublicIP   string
}

func serverFromSummary(s *scwdedibox.ServerSummary) *Server {
	return &Server{
		ID:         s.ID,
		Zone:       string(s.Zone),
		Hostname:   s.Hostname,
		Offer:      s.OfferName,
		Datacenter: s.DatacenterName,
		ProjectID:  s.ProjectID,
		Installed:  s.OsID != nil,
		PublicIP:   publicIPv4(s.Interfaces),
	}
}

func serverFromDetail(s *scwdedibox.Server) *Server {
	out := &Server{
		ID:        s.ID,
		Zone:      string(s.Zone),
		Hostname:  s.Hostname,
		ProjectID: s.ProjectID,
		Installed: s.Os != nil,
		PublicIP:  publicIPv4(s.Interfaces),
	}
	if s.Offer != nil {
		out.Offer = s.Offer.Name
	}
	if s.Location != nil {
		out.Datacenter = s.Location.DatacenterName
	}
	return out
}

// publicIPv4 returns the server's first public IPv4 address, or "". Prefers an
// address explicitly tagged public, falling back to any IPv4 (the semantic is
// occasionally unset on freshly delivered boxes).
func publicIPv4(ifaces []*scwdedibox.NetworkInterface) string {
	for _, iface := range ifaces {
		for _, ip := range iface.IPs {
			if ip.Version == scwdedibox.IPVersionIPv4 && ip.Semantic == scwdedibox.IPSemanticPublic && ip.Address != nil {
				return ip.Address.String()
			}
		}
	}
	for _, iface := range ifaces {
		for _, ip := range iface.IPs {
			if ip.Version == scwdedibox.IPVersionIPv4 && ip.Address != nil {
				return ip.Address.String()
			}
		}
	}
	return ""
}

// AdoptParams scopes which pre-ordered servers a fleet may claim WITHIN its
// project. The claim key is Offer + Datacenter, both intrinsic to a bare
// (not-yet-installed) box; HostnamePrefix is an optional extra filter for
// already-installed boxes.
type AdoptParams struct {
	// Datacenter the server must live in (the console name, e.g. "DC2"); empty
	// matches any datacenter in the project.
	Datacenter string
	// Offer the server must be (e.g. "Start-1-M-SSD"); empty matches any.
	Offer string
	// HostnamePrefix, when set, additionally constrains servers that already have
	// a hostname (installed boxes) to this prefix. A bare box has no hostname yet,
	// so it is never excluded by this filter.
	HostnamePrefix string
}

// FindAdoptableServer claims a pre-ordered server for the fleet: the first
// server in the client's project matching the (offer, datacenter) claim key that
// no sibling Machine has already claimed (claimed = the IDs on sibling CR
// statuses). It scans every Dedibox zone since a fleet is identified by console
// datacenter, not Scaleway zone. Returns nil when the pool is exhausted so the
// caller requeues and the operator pre-orders more capacity. Claim state lives
// cluster-side; the Project scoping makes a cross-environment claim impossible.
func (c *Client) FindAdoptableServer(ctx context.Context, p AdoptParams, claimed map[uint64]bool) (*Server, error) {
	for _, zone := range dediboxZones {
		resp, err := c.API.ListServers(&scwdedibox.ListServersRequest{
			Zone:      zone,
			ProjectID: &c.ProjectID,
		}, scw.WithContext(ctx), scw.WithAllPages())
		if err != nil {
			return nil, fmt.Errorf("list dedibox servers in %s: %w", zone, err)
		}
		for _, summary := range resp.Servers {
			if claimed[summary.ID] {
				continue
			}
			server := serverFromSummary(summary)
			if p.Datacenter != "" && !strings.EqualFold(server.Datacenter, p.Datacenter) {
				continue
			}
			if p.Offer != "" && !strings.EqualFold(server.Offer, p.Offer) {
				continue
			}
			if p.HostnamePrefix != "" && server.Hostname != "" && !strings.HasPrefix(server.Hostname, p.HostnamePrefix) {
				continue
			}
			return server, nil
		}
	}
	return nil, nil
}

// GetServer fetches the current detailed server state in its zone.
func (c *Client) GetServer(ctx context.Context, zone string, id uint64) (*Server, error) {
	s, err := c.API.GetServer(&scwdedibox.GetServerRequest{Zone: scw.Zone(zone), ServerID: id}, scw.WithContext(ctx))
	if err != nil {
		return nil, fmt.Errorf("get dedibox server %d: %w", id, err)
	}
	return serverFromDetail(s), nil
}

// OSChoice is the resolved install OS plus the flags that decide whether the
// install request must carry a user login / password.
type OSChoice struct {
	ID                    uint64
	RequiresUser          bool
	RequiresAdminPassword bool
}

// ResolveOS maps an `ubuntu_24.04`-style label to an installable OS on the
// server, matching the label's `_`-separated tokens (dots stripped on both
// sides so `24.04` matches `24.04`) against the OS name + version.
func (c *Client) ResolveOS(ctx context.Context, zone string, serverID uint64, osLabel string) (OSChoice, error) {
	resp, err := c.API.ListOS(&scwdedibox.ListOSRequest{
		Zone:      scw.Zone(zone),
		ServerID:  serverID,
		ProjectID: &c.ProjectID,
	}, scw.WithContext(ctx), scw.WithAllPages())
	if err != nil {
		return OSChoice{}, fmt.Errorf("list installable OS for server %d: %w", serverID, err)
	}
	tokens := strings.Split(strings.ToLower(osLabel), "_")
	for _, os := range resp.Os {
		name := strings.ReplaceAll(strings.ToLower(os.Name+" "+os.Version), ".", "")
		matched := true
		for _, t := range tokens {
			if t != "" && !strings.Contains(name, strings.ReplaceAll(t, ".", "")) {
				matched = false
				break
			}
		}
		if matched {
			return OSChoice{ID: os.ID, RequiresUser: os.RequiresUser, RequiresAdminPassword: os.RequiresAdminPassword}, nil
		}
	}
	return OSChoice{}, fmt.Errorf("no Dedibox OS matching label %q for server %d", osLabel, serverID)
}

// InstallParams is the desired OS install for a server.
type InstallParams struct {
	Zone      string
	ServerID  uint64
	OS        OSChoice
	Hostname  string
	UserLogin string
	// SSHKeyIDs are Scaleway SSH key IDs (the fleet key the credentials manager
	// already registered) authorized on the installed server.
	SSHKeyIDs []string
}

// StartInstall kicks off the OS install with the server's default partitioning,
// the resolved OS, hostname, and the fleet SSH key authorized. The install runs
// asynchronously; poll InstallState before bootstrapping. A user login (and a
// generated password / panel password) is included only when the OS requires
// it, since key-only installs reject unexpected credentials.
func (c *Client) StartInstall(ctx context.Context, p InstallParams) error {
	zone := scw.Zone(p.Zone)
	part, err := c.API.GetServerDefaultPartitioning(&scwdedibox.GetServerDefaultPartitioningRequest{
		Zone:     zone,
		ServerID: p.ServerID,
		OsID:     p.OS.ID,
	}, scw.WithContext(ctx))
	if err != nil {
		return fmt.Errorf("default partitioning for server %d: %w", p.ServerID, err)
	}

	req := &scwdedibox.InstallServerRequest{
		Zone:       zone,
		ServerID:   p.ServerID,
		OsID:       p.OS.ID,
		Hostname:   p.Hostname,
		SSHKeyIDs:  p.SSHKeyIDs,
		Partitions: toInstallPartitions(part.Partitions),
	}
	if p.OS.RequiresUser {
		req.UserLogin = scw.StringPtr(p.UserLogin)
		password, pwErr := randomPassword()
		if pwErr != nil {
			return pwErr
		}
		req.UserPassword = scw.StringPtr(password)
	}
	if p.OS.RequiresAdminPassword {
		password, pwErr := randomPassword()
		if pwErr != nil {
			return pwErr
		}
		req.PanelPassword = scw.StringPtr(password)
	}
	if _, err := c.API.InstallServer(req, scw.WithContext(ctx)); err != nil {
		return fmt.Errorf("start install on server %d: %w", p.ServerID, err)
	}
	return nil
}

func toInstallPartitions(parts []*scwdedibox.Partition) []*scwdedibox.InstallPartition {
	out := make([]*scwdedibox.InstallPartition, 0, len(parts))
	for _, p := range parts {
		out = append(out, &scwdedibox.InstallPartition{
			FileSystem: p.FileSystem,
			MountPoint: p.MountPoint,
			RaidLevel:  p.RaidLevel,
			Capacity:   p.Capacity,
			Connectors: p.Connectors,
		})
	}
	return out
}

// InstallState is the coarse install lifecycle the reconciler gates on.
type InstallState int

const (
	// InstallPending means no install has run yet (just-adopted bare box).
	InstallPending InstallState = iota
	// InstallRunning means the OS install is in progress.
	InstallRunning
	// InstallDone means the OS install finished and the box is bootable.
	InstallDone
	// InstallFailed means the install errored terminally.
	InstallFailed
)

// InstallState polls the server's install resource and maps it to the coarse
// lifecycle. `installed` is done; a missing install resource or `unknown` status
// falls back to "does the server carry an OS?" (installed-and-booted vs bare);
// everything else is in progress. The Dedibox install status has no terminal
// error state, so a wedged install surfaces as a stuck InstallRunning the
// controller's requeue/recovery handles, not InstallFailed.
func (c *Client) InstallState(ctx context.Context, zone string, serverID uint64) (InstallState, error) {
	z := scw.Zone(zone)
	inst, err := c.API.GetServerInstall(&scwdedibox.GetServerInstallRequest{Zone: z, ServerID: serverID}, scw.WithContext(ctx))
	if err != nil {
		if IsNotFound(err) {
			return c.installedOrPending(ctx, z, serverID)
		}
		return InstallPending, fmt.Errorf("get server install %d: %w", serverID, err)
	}
	switch inst.Status {
	case scwdedibox.ServerInstallStatusInstalled:
		return InstallDone, nil
	case scwdedibox.ServerInstallStatusUnknown, "":
		return c.installedOrPending(ctx, z, serverID)
	default:
		return InstallRunning, nil
	}
}

func (c *Client) installedOrPending(ctx context.Context, zone scw.Zone, serverID uint64) (InstallState, error) {
	s, err := c.API.GetServer(&scwdedibox.GetServerRequest{Zone: zone, ServerID: serverID}, scw.WithContext(ctx))
	if err != nil {
		return InstallPending, fmt.Errorf("get server %d: %w", serverID, err)
	}
	if s.Os != nil {
		return InstallDone, nil
	}
	return InstallPending, nil
}

// randomPassword returns a strong password for the rare OS that mandates one
// even on a key-based install. VERIFY the live OS password regex during staging
// bring-up; this mixes upper/lower/digits/symbol to satisfy common rules.
func randomPassword() (string, error) {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate password: %w", err)
	}
	for i := range b {
		b[i] = alphabet[int(b[i])%len(alphabet)]
	}
	return "Tuist8!" + string(b), nil
}
