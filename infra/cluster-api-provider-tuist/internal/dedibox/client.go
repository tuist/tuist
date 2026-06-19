// Package dedibox is the Scaleway Dedibox (online.net) dedicated-server client
// the DediboxMachine reconciler talks to. Dedibox is the online.net product
// line, so its API is the online.net REST API (https://api.online.net/api/v1,
// Bearer-token auth), distinct from both go-ovh and the Scaleway SDK. There is
// no official Go SDK, so this is a thin HTTP wrapper over the slice of the API
// the machine lifecycle needs: list + adopt a pre-ordered server, register the
// bootstrap SSH key, kick off the OS install and poll it, and read the public
// IP for the SSH self-join.
//
// Shape mirrors the OVH client (customer-facing public box, adopt-by-prefix,
// cluster-side claim, monthly contract so release does not terminate). The
// exact endpoint paths and response fields below are coded to the documented
// online.net v1 API but flagged VERIFY where the public docs are thin; confirm
// them against a live Dedibox account during staging bring-up.
package dedibox

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

const defaultBaseURL = "https://api.online.net/api/v1"

// apiError carries the online.net HTTP status so callers can treat a 404 as
// "gone" rather than a hard error.
type apiError struct {
	status int
	body   string
}

func (e *apiError) Error() string { return fmt.Sprintf("online.net API %d: %s", e.status, e.body) }

// IsNotFound reports whether err is an online.net 404.
func IsNotFound(err error) bool {
	var apiErr *apiError
	if errors.As(err, &apiErr) {
		return apiErr.status == http.StatusNotFound
	}
	return false
}

// transport is the slice of HTTP behaviour the client needs; a fake implements
// it in tests, the real one is net/http + Bearer auth.
type transport interface {
	get(ctx context.Context, path string, out any) error
	post(ctx context.Context, path string, body, out any) error
}

// Client talks to the online.net Dedibox API. Construct with NewClientFromEnv;
// in tests the transport field takes a fake.
type Client struct {
	t transport
}

// NewClientFromEnv builds a Client from DEDIBOX_API_TOKEN (the online.net API
// Bearer token), which the chart syncs from the per-env 1Password DEDIBOX_API
// item via ESO once Dedibox is enabled for an env. ONLINE_API_BASE_URL
// overrides the endpoint (tests / mock).
func NewClientFromEnv() (*Client, error) {
	token := os.Getenv("DEDIBOX_API_TOKEN")
	if token == "" {
		return nil, fmt.Errorf("DEDIBOX_API_TOKEN is unset")
	}
	base := os.Getenv("ONLINE_API_BASE_URL")
	if base == "" {
		base = defaultBaseURL
	}
	return &Client{t: &httpTransport{
		base:   strings.TrimRight(base, "/"),
		token:  token,
		client: &http.Client{Timeout: 30 * time.Second},
	}}, nil
}

// ProviderID is the foreign CAPI providerID for a Dedibox server,
// `dedibox://<datacenter>/<server-id>`. The non-Hetzner host keeps the Hetzner
// CCM from reaping the node, the same guard the Scaleway + OVH kinds use.
func ProviderID(datacenter string, id int) string {
	return fmt.Sprintf("dedibox://%s/%d", datacenter, id)
}

// Server is the subset of GET /server/{id} the reconciler reads.
type Server struct {
	ID         int        `json:"id"`
	Hostname   string     `json:"hostname"`
	Offer      string     `json:"offer"`
	Datacenter string     `json:"datacenter"` // VERIFY: may be nested under `location`
	IP         []ServerIP `json:"ip"`
	BootMode   string     `json:"boot_mode"` // "normal" once installed, "rescue" during install
	OS         *ServerOS  `json:"os"`
}

// ServerIP is one address on the server; type distinguishes public from the
// RPN private address.
type ServerIP struct {
	Address string `json:"address"`
	Type    string `json:"type"` // "public" | "private"
}

// ServerOS is the installed OS, nil on a bare server.
type ServerOS struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

// PublicIPv4 returns the server's first public address, or "".
func (s *Server) PublicIPv4() string {
	for _, ip := range s.IP {
		if ip.Type == "public" && ip.Address != "" {
			return ip.Address
		}
	}
	return ""
}

// AdoptParams scopes which pre-ordered servers a fleet may claim.
type AdoptParams struct {
	// Datacenter the server must live in (e.g. "dc3", "ams1"); empty matches any.
	Datacenter string
	// HostnamePrefix the server's hostname must start with to be considered part
	// of this fleet's pre-ordered pool.
	HostnamePrefix string
}

// ListServers returns every dedicated-server ID on the account. online.net list
// endpoints return an array of resource hrefs (e.g. "/api/v1/server/12345"); we
// parse the trailing ID. VERIFY the href shape on a live account.
func (c *Client) ListServers(ctx context.Context) ([]int, error) {
	var hrefs []string
	if err := c.t.get(ctx, "/server", &hrefs); err != nil {
		return nil, fmt.Errorf("list dedibox servers: %w", err)
	}
	ids := make([]int, 0, len(hrefs))
	for _, h := range hrefs {
		seg := h[strings.LastIndex(h, "/")+1:]
		if id, convErr := strconv.Atoi(seg); convErr == nil {
			ids = append(ids, id)
		}
	}
	return ids, nil
}

// GetServer fetches the current server state.
func (c *Client) GetServer(ctx context.Context, id int) (*Server, error) {
	server := &Server{}
	if err := c.t.get(ctx, fmt.Sprintf("/server/%d", id), server); err != nil {
		return nil, fmt.Errorf("get dedibox server %d: %w", id, err)
	}
	return server, nil
}

// FindAdoptableServer claims a pre-ordered server for the fleet: the first
// server whose hostname starts with the prefix (and datacenter matches, if set)
// that no sibling Machine has already claimed (claimed = the IDs on sibling CR
// statuses). Returns nil when the pool is exhausted so the caller requeues and
// the operator pre-orders more capacity. Claim state lives cluster-side, the
// same as the OVH kind.
func (c *Client) FindAdoptableServer(ctx context.Context, p AdoptParams, claimed map[int]bool) (*Server, error) {
	ids, err := c.ListServers(ctx)
	if err != nil {
		return nil, err
	}
	for _, id := range ids {
		if claimed[id] {
			continue
		}
		server, getErr := c.GetServer(ctx, id)
		if getErr != nil {
			return nil, getErr
		}
		if p.Datacenter != "" && !strings.EqualFold(server.Datacenter, p.Datacenter) {
			continue
		}
		if p.HostnamePrefix != "" && !strings.HasPrefix(server.Hostname, p.HostnamePrefix) {
			continue
		}
		return server, nil
	}
	return nil, nil
}

// EnsureSSHKey registers the bootstrap public key in /user/key/ssh if absent, so
// the OS install can authorize it. Idempotent on the key's description/name.
func (c *Client) EnsureSSHKey(ctx context.Context, name, publicKey string) error {
	var keys []struct {
		Description string `json:"description"`
		Key         string `json:"key"`
	}
	if err := c.t.get(ctx, "/user/key/ssh", &keys); err != nil {
		return fmt.Errorf("list ssh keys: %w", err)
	}
	for _, k := range keys {
		if k.Description == name || strings.TrimSpace(k.Key) == strings.TrimSpace(publicKey) {
			return nil
		}
	}
	body := map[string]any{"description": name, "key": publicKey}
	if err := c.t.post(ctx, "/user/key/ssh", body, nil); err != nil {
		return fmt.Errorf("register ssh key %q: %w", name, err)
	}
	return nil
}

// ResolveOSID maps an `ubuntu_24.04`-style label to an online.net OS id the
// server supports, matching the label's `_`-separated tokens against the
// installable OS list case-insensitively. GET /server/install/{id} returns the
// server's installable templates. VERIFY the response shape on a live account.
func (c *Client) ResolveOSID(ctx context.Context, serverID int, osLabel string) (int, error) {
	var resp struct {
		OS []struct {
			ID      int    `json:"id"`
			Name    string `json:"name"`
			Version string `json:"version"`
		} `json:"os"`
	}
	if err := c.t.get(ctx, fmt.Sprintf("/server/install/%d", serverID), &resp); err != nil {
		return 0, fmt.Errorf("list installable OS for server %d: %w", serverID, err)
	}
	tokens := strings.Split(strings.ToLower(osLabel), "_")
	for _, os := range resp.OS {
		name := strings.ToLower(os.Name + " " + os.Version)
		matched := true
		for _, t := range tokens {
			if t != "" && !strings.Contains(name, strings.ReplaceAll(t, ".", "")) {
				matched = false
				break
			}
		}
		if matched {
			return os.ID, nil
		}
	}
	return 0, fmt.Errorf("no Dedibox OS matching label %q for server %d", osLabel, serverID)
}

// InstallParams is the desired OS install for a server.
type InstallParams struct {
	OSID       int
	Hostname   string
	SSHKeyName string
}

// StartInstall kicks off the OS install with the resolved OS, hostname, and the
// fleet SSH key authorized. The install runs asynchronously (the box reboots
// into the installer); poll InstallState before bootstrapping.
func (c *Client) StartInstall(ctx context.Context, serverID int, p InstallParams) error {
	body := map[string]any{
		"os_id":    p.OSID,
		"hostname": p.Hostname,
		"ssh_keys": []string{p.SSHKeyName},
	}
	if err := c.t.post(ctx, fmt.Sprintf("/server/install/%d", serverID), body, nil); err != nil {
		return fmt.Errorf("start install on server %d: %w", serverID, err)
	}
	return nil
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

// InstallState polls the server's install endpoint and maps it to the coarse
// lifecycle. online.net reports a per-server install with a status/progress;
// a 404 (no install resource) on an OS-bearing, normal-boot server means Done.
// VERIFY the status strings on a live account.
func (c *Client) InstallState(ctx context.Context, serverID int) (InstallState, error) {
	var resp struct {
		Status   string `json:"status"`   // VERIFY: e.g. "installing" | "completed" | "error"
		Progress int    `json:"progress"` // 0..100
	}
	err := c.t.get(ctx, fmt.Sprintf("/server/install/%d", serverID), &resp)
	if err != nil {
		if IsNotFound(err) {
			// No active install resource: installed-and-booted if the server
			// carries an OS in normal boot mode, otherwise never installed.
			server, getErr := c.GetServer(ctx, serverID)
			if getErr != nil {
				return InstallPending, getErr
			}
			if server.OS != nil && server.BootMode == "normal" {
				return InstallDone, nil
			}
			return InstallPending, nil
		}
		return InstallPending, err
	}
	switch strings.ToLower(resp.Status) {
	case "completed", "done", "":
		if resp.Progress >= 100 || resp.Status != "" {
			return InstallDone, nil
		}
		return InstallRunning, nil
	case "error", "failed":
		return InstallFailed, nil
	default:
		return InstallRunning, nil
	}
}

// httpTransport is the real net/http implementation of transport with Bearer
// auth against the online.net base URL.
type httpTransport struct {
	base   string
	token  string
	client *http.Client
}

func (h *httpTransport) get(ctx context.Context, path string, out any) error {
	return h.do(ctx, http.MethodGet, path, nil, out)
}

func (h *httpTransport) post(ctx context.Context, path string, body, out any) error {
	return h.do(ctx, http.MethodPost, path, body, out)
}

func (h *httpTransport) do(ctx context.Context, method, path string, body, out any) error {
	var reader io.Reader
	if body != nil {
		buf, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(buf)
	}
	req, err := http.NewRequestWithContext(ctx, method, h.base+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+h.token)
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
