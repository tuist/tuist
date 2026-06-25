// Package dedibox is the Scaleway Dedibox client the DediboxMachine reconciler
// talks to. It speaks the project-scoped Scaleway Dedibox API
// (api.scaleway.com/dedibox/v1, IAM secret key as X-Auth-Token) over RAW HTTP:
// the scaleway-sdk-go beta dedibox client receives correct 200 responses but
// silently fails to decode them, so we issue the requests ourselves and reuse
// only the SDK's response structs (which unmarshal correctly).
//
// Every Dedibox in an organization lives in its DEFAULT project — Scaleway does
// not allow assigning a Dedibox to another project — so the project cannot be
// the environment boundary the way it can for Elastic Metal. Instead each
// pre-ordered box is stamped with a per-fleet TAG, and the reconciler adopts
// only boxes carrying its fleet's tag (the Dedibox analog of the OVH
// display-name prefix). The credential is therefore the default project's IAM
// key, shared across environments; the tag is what scopes the pool.
package dedibox

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	scwdedibox "github.com/scaleway/scaleway-sdk-go/api/dedibox/v1"
)

const defaultBaseURL = "https://api.scaleway.com"

// dediboxZones are the Scaleway zones Dedibox is offered in. Adoption scans all
// of them (a fleet's datacenter is a console name like "DC2", which lives inside
// one of these zones); the matched server's own zone is used for follow-up calls.
var dediboxZones = []string{"fr-par-1", "fr-par-2", "nl-ams-1"}

// apiError carries the Scaleway HTTP status so a 404 reads as "gone".
type apiError struct {
	status int
	body   string
}

func (e *apiError) Error() string {
	return fmt.Sprintf("scaleway dedibox API %d: %s", e.status, e.body)
}

// IsNotFound reports whether err is a Scaleway 404.
func IsNotFound(err error) bool {
	var apiErr *apiError
	if errors.As(err, &apiErr) {
		return apiErr.status == http.StatusNotFound
	}
	return false
}

// transport is the slice of HTTP behaviour the client needs; a fake implements
// it in tests, the real one is net/http + X-Auth-Token auth.
type transport interface {
	get(ctx context.Context, path string, query url.Values, out any) error
	post(ctx context.Context, path string, body, out any) error
}

// Client talks to the Scaleway Dedibox API, scoped to one project. Construct
// with NewClientFromEnv; in tests the transport field takes a fake.
type Client struct {
	t         transport
	ProjectID string
}

// NewClientFromEnv builds a Client from DEDIBOX_SCW_SECRET_KEY (a Scaleway IAM
// secret key with DediboxFullAccess on the DEFAULT project, where every Dedibox
// in the org lives) and DEDIBOX_SCW_PROJECT_ID (that default project's id, used
// for the required project_id filter). These are distinct from the per-env
// SCW_* creds the macOS/Elastic Metal reconcilers use, since those are scoped to
// a non-default project that cannot see any Dedibox. DEDIBOX_API_URL overrides
// the endpoint for tests.
func NewClientFromEnv() (*Client, error) {
	secret := os.Getenv("DEDIBOX_SCW_SECRET_KEY")
	if secret == "" {
		return nil, fmt.Errorf("DEDIBOX_SCW_SECRET_KEY is unset")
	}
	project := os.Getenv("DEDIBOX_SCW_PROJECT_ID")
	if project == "" {
		return nil, fmt.Errorf("DEDIBOX_SCW_PROJECT_ID is unset")
	}
	base := os.Getenv("DEDIBOX_API_URL")
	if base == "" {
		base = defaultBaseURL
	}
	return &Client{
		t: &httpTransport{
			base:   strings.TrimRight(base, "/"),
			token:  secret,
			client: &http.Client{Timeout: 30 * time.Second},
		},
		ProjectID: project,
	}, nil
}

// ProviderID is the foreign CAPI providerID for a Dedibox server,
// `dedibox://<zone>/<id>`. The non-Hetzner host keeps the Hetzner CCM from
// reaping the node, the same guard the Scaleway baremetal + OVH kinds use.
func ProviderID(zone string, id uint64) string {
	return fmt.Sprintf("dedibox://%s/%d", zone, id)
}

// Server is the reconciler's view of a Dedibox server, flattened from the SDK
// summary/detail shapes.
type Server struct {
	ID         uint64
	Zone       string
	Hostname   string
	Offer      string
	Datacenter string
	ProjectID  string
	Installed  bool
	PublicIP   string
	Tags       []string
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
		Tags:      s.Tags,
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
// address tagged public, falling back to any IPv4 (the semantic is occasionally
// unset on freshly delivered boxes).
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

// AdoptParams scopes which pre-ordered servers a fleet may claim. Tag is the
// environment boundary (all Dedibox share the default project); Offer +
// Datacenter narrow within it.
type AdoptParams struct {
	// Tag the server must carry to belong to this fleet's pool (e.g.
	// "tuist-kura-staging"). The operator stamps it on each pre-ordered box; the
	// reconciler never adopts a box without it. Empty disables the tag filter
	// (unsafe — only for a single-tenant project).
	Tag string
	// Datacenter the server must live in (the console name, e.g. "DC2"); empty
	// matches any datacenter.
	Datacenter string
	// Offer the server must be (e.g. "Start-1-M-SSD"); empty matches any.
	Offer string
	// HostnamePrefix, when set, additionally constrains servers whose hostname is
	// not the default sd-<id>.dedibox.fr to this prefix. Rarely needed; the tag is
	// the primary marker.
	HostnamePrefix string
}

// FindAdoptableServer claims a pre-ordered server for the fleet: the first
// server in the project matching Tag + Offer + Datacenter that no sibling
// Machine has already claimed (claimed = the IDs on sibling CR statuses). The
// server-list summary omits tags, so a candidate matching offer + datacenter is
// confirmed against its tags via GetServer. Returns nil when the pool is
// exhausted so the caller requeues and the operator pre-orders more capacity.
func (c *Client) FindAdoptableServer(ctx context.Context, p AdoptParams, claimed map[uint64]bool) (*Server, error) {
	for _, zone := range dediboxZones {
		summaries, err := c.listServers(ctx, zone)
		if err != nil {
			return nil, fmt.Errorf("list dedibox servers in %s: %w", zone, err)
		}
		for _, summary := range summaries {
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
			if p.Tag != "" {
				full, getErr := c.GetServer(ctx, zone, summary.ID)
				if getErr != nil {
					return nil, getErr
				}
				if !hasTag(full.Tags, p.Tag) {
					continue
				}
				return full, nil
			}
			return server, nil
		}
	}
	return nil, nil
}

func hasTag(tags []string, want string) bool {
	for _, t := range tags {
		if t == want {
			return true
		}
	}
	return false
}

func (c *Client) listServers(ctx context.Context, zone string) ([]*scwdedibox.ServerSummary, error) {
	q := url.Values{}
	q.Set("project_id", c.ProjectID)
	q.Set("page_size", "100")
	var resp scwdedibox.ListServersResponse
	if err := c.t.get(ctx, "/dedibox/v1/zones/"+zone+"/servers", q, &resp); err != nil {
		return nil, err
	}
	return resp.Servers, nil
}

// GetServer fetches the current detailed server state in its zone.
func (c *Client) GetServer(ctx context.Context, zone string, id uint64) (*Server, error) {
	var s scwdedibox.Server
	if err := c.t.get(ctx, fmt.Sprintf("/dedibox/v1/zones/%s/servers/%d", zone, id), nil, &s); err != nil {
		return nil, fmt.Errorf("get dedibox server %d: %w", id, err)
	}
	return serverFromDetail(&s), nil
}

// RegisterSSHKey registers publicKey as a Scaleway IAM SSH key named `name` in
// the Dedibox project (c.ProjectID), returning its ID; idempotent by public key.
// Every Dedibox lives in the org's default project and a Dedibox install only
// accepts SSH keys from the server's own project — so the fleet bootstrap key
// must be registered here, not in the per-env project the shared Scaleway client
// uses for the macOS/Elastic Metal kinds. Reuses the same X-Auth-Token transport.
func (c *Client) RegisterSSHKey(ctx context.Context, name, publicKey string) (string, error) {
	want := strings.TrimSpace(publicKey)
	q := url.Values{}
	q.Set("name", name)
	q.Set("project_id", c.ProjectID)
	q.Set("page_size", "100")
	var list struct {
		SSHKeys []struct {
			ID        string `json:"id"`
			PublicKey string `json:"public_key"`
		} `json:"ssh_keys"`
	}
	if err := c.t.get(ctx, "/iam/v1alpha1/ssh-keys", q, &list); err != nil {
		return "", fmt.Errorf("list IAM ssh keys: %w", err)
	}
	for _, k := range list.SSHKeys {
		if strings.TrimSpace(k.PublicKey) == want {
			return k.ID, nil
		}
	}
	var created struct {
		ID string `json:"id"`
	}
	body := map[string]string{"name": name, "public_key": publicKey, "project_id": c.ProjectID}
	if err := c.t.post(ctx, "/iam/v1alpha1/ssh-keys", body, &created); err != nil {
		return "", fmt.Errorf("create IAM ssh key: %w", err)
	}
	return created.ID, nil
}

// OSChoice is the resolved install OS plus the flags that decide how the install
// request is shaped: whether it must carry a user login / password, whether it
// accepts SSH keys at all, and whether it supports a custom partitioning layout.
type OSChoice struct {
	ID                      uint64
	RequiresUser            bool
	RequiresPanelPassword   bool
	AllowSSHKeys            bool
	AllowCustomPartitioning bool
}

// ResolveOS maps an `ubuntu_24.04`-style label to an installable OS on the
// server, matching the label's `_`-separated tokens (dots stripped on both
// sides so `24.04` matches `24.04`) against the OS name + version.
func (c *Client) ResolveOS(ctx context.Context, zone string, serverID uint64, osLabel string) (OSChoice, error) {
	q := url.Values{}
	q.Set("project_id", c.ProjectID)
	q.Set("server_id", strconv.FormatUint(serverID, 10))
	q.Set("page_size", "100")
	var resp scwdedibox.ListOSResponse
	if err := c.t.get(ctx, "/dedibox/v1/zones/"+zone+"/os", q, &resp); err != nil {
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
			return OSChoice{
				ID:                      os.ID,
				RequiresUser:            os.RequiresUser,
				RequiresPanelPassword:   os.RequiresPanelPassword,
				AllowSSHKeys:            os.AllowSSHKeys,
				AllowCustomPartitioning: os.AllowCustomPartitioning,
			}, nil
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
	// UserPassword, when set, is the login password the install assigns the
	// created user. Prep sets a known value so it can configure passwordless sudo
	// over SSH after the install (the install grants only password sudo); empty
	// falls back to a discarded random password.
	UserPassword string
	// SSHKeyIDs are Scaleway SSH key IDs (the fleet key the credentials manager
	// already registered) authorized on the installed server.
	SSHKeyIDs []string
}

// installBody is the JSON body for POST .../install.
type installBody struct {
	OsID          uint64                         `json:"os_id"`
	Hostname      string                         `json:"hostname"`
	UserLogin     string                         `json:"user_login,omitempty"`
	UserPassword  string                         `json:"user_password,omitempty"`
	RootPassword  string                         `json:"root_password,omitempty"`
	PanelPassword string                         `json:"panel_password,omitempty"`
	Partitions    []*scwdedibox.InstallPartition `json:"partitions,omitempty"`
	SSHKeyIDs     []string                       `json:"ssh_key_ids"`
}

// StartInstall kicks off the OS install with the resolved OS, hostname, and the
// fleet SSH key authorized. The install runs asynchronously; poll InstallState
// before bootstrapping. Default partitioning is fetched and passed only when the
// OS supports a custom layout (otherwise the endpoint 400s and the API applies
// its own default); a user login (and a generated password) is included only
// when the OS requires one. Fails fast on an OS that does not accept SSH keys,
// since the self-join depends on key auth.
func (c *Client) StartInstall(ctx context.Context, p InstallParams) error {
	if !p.OS.AllowSSHKeys {
		return fmt.Errorf("Dedibox OS %d does not allow SSH-key installs (self-join needs key auth)", p.OS.ID)
	}

	body := installBody{
		OsID:      p.OS.ID,
		Hostname:  p.Hostname,
		SSHKeyIDs: p.SSHKeyIDs,
	}
	if p.OS.AllowCustomPartitioning {
		var part scwdedibox.ServerDefaultPartitioning
		if err := c.t.get(ctx, fmt.Sprintf("/dedibox/v1/zones/%s/servers/%d/partitioning/%d", p.Zone, p.ServerID, p.OS.ID), nil, &part); err != nil {
			return fmt.Errorf("default partitioning for server %d: %w", p.ServerID, err)
		}
		body.Partitions = toInstallPartitions(part.Partitions)
	}
	// A user-login OS (e.g. Ubuntu) locks root and grants the created user sudo,
	// so the install API rejects a root_password ("should be blank") and takes
	// only the user credentials; a root-login OS takes the root password instead.
	// Send exactly one, keyed on RequiresUser.
	if p.OS.RequiresUser {
		body.UserLogin = p.UserLogin
		userPassword := p.UserPassword
		if userPassword == "" {
			pw, pwErr := randomPassword()
			if pwErr != nil {
				return pwErr
			}
			userPassword = pw
		}
		body.UserPassword = userPassword
	} else {
		rootPassword, rpErr := randomPassword()
		if rpErr != nil {
			return rpErr
		}
		body.RootPassword = rootPassword
	}
	if p.OS.RequiresPanelPassword {
		password, pwErr := randomPassword()
		if pwErr != nil {
			return pwErr
		}
		body.PanelPassword = password
	}
	if err := c.t.post(ctx, fmt.Sprintf("/dedibox/v1/zones/%s/servers/%d/install", p.Zone, p.ServerID), body, nil); err != nil {
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
	var inst scwdedibox.ServerInstall
	err := c.t.get(ctx, fmt.Sprintf("/dedibox/v1/zones/%s/servers/%d/install", zone, serverID), nil, &inst)
	if err != nil {
		if IsNotFound(err) {
			return c.installedOrPending(ctx, zone, serverID)
		}
		return InstallPending, fmt.Errorf("get server install %d: %w", serverID, err)
	}
	switch inst.Status {
	case scwdedibox.ServerInstallStatusInstalled:
		return InstallDone, nil
	case scwdedibox.ServerInstallStatusUnknown, "":
		return c.installedOrPending(ctx, zone, serverID)
	default:
		return InstallRunning, nil
	}
}

func (c *Client) installedOrPending(ctx context.Context, zone string, serverID uint64) (InstallState, error) {
	s, err := c.GetServer(ctx, zone, serverID)
	if err != nil {
		return InstallPending, err
	}
	if s.Installed {
		return InstallDone, nil
	}
	return InstallPending, nil
}

// randomPassword returns a strong alphanumeric password for the OS install
// fields an OS mandates even on a key-based install. The Dedibox install API
// caps passwords at 15 characters and rejects non-alphanumeric ones, so this is
// 14 mixed-case alphanumerics (no symbols).
func randomPassword() (string, error) {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
	b := make([]byte, 14)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate password: %w", err)
	}
	for i := range b {
		b[i] = alphabet[int(b[i])%len(alphabet)]
	}
	return string(b), nil
}

// httpTransport is the real net/http implementation of transport with
// X-Auth-Token (Scaleway IAM secret key) auth.
type httpTransport struct {
	base   string
	token  string
	client *http.Client
}

func (h *httpTransport) get(ctx context.Context, path string, query url.Values, out any) error {
	u := h.base + path
	if len(query) > 0 {
		u += "?" + query.Encode()
	}
	return h.do(ctx, http.MethodGet, u, nil, out)
}

func (h *httpTransport) post(ctx context.Context, path string, body, out any) error {
	return h.do(ctx, http.MethodPost, h.base+path, body, out)
}

func (h *httpTransport) do(ctx context.Context, method, fullURL string, body, out any) error {
	var reader io.Reader
	if body != nil {
		buf, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(buf)
	}
	req, err := http.NewRequestWithContext(ctx, method, fullURL, reader)
	if err != nil {
		return err
	}
	req.Header.Set("X-Auth-Token", h.token)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := h.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	payload, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return &apiError{status: resp.StatusCode, body: string(payload)}
	}
	if out != nil && len(payload) > 0 {
		return json.Unmarshal(payload, out)
	}
	return nil
}
