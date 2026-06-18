// Package ovh is the OVHcloud dedicated-server client the OVHDedicatedMachine
// reconciler talks to. It wraps the official go-ovh REST client with the small
// slice of the /dedicated/server API the machine lifecycle needs: list + adopt
// a pre-ordered server, register the bootstrap SSH key, kick off the OS
// install and poll it, and read the public IP for the SSH self-join.
//
// Two deliberate differences from the Scaleway bare-metal client:
//
//   - No inline order. OVH ordering is a multi-step cart/checkout/payment flow,
//     so the operator pre-orders capacity and the controller adopts a free,
//     not-yet-installed box by display-name prefix — the same pattern the Apple
//     Silicon kind uses, not the Elastic Metal find-or-create.
//   - No delete. An OVH dedicated server is a monthly contract, not an
//     on-demand box; tearing the CR down must not terminate the contract (that
//     is an operator-driven, end-of-life action). Release therefore lives in
//     the controller as "drop the Node + identity" with the physical server
//     left intact, so there is no DeleteServer here.
package ovh

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/ovh/go-ovh/ovh"
)

// httpAPI is the slice of go-ovh's *ovh.Client the client touches. An interface
// so tests drop in a fake; the concrete *ovh.Client satisfies it structurally.
type httpAPI interface {
	GetWithContext(ctx context.Context, url string, resType any) error
	PostWithContext(ctx context.Context, url string, reqBody, resType any) error
	PutWithContext(ctx context.Context, url string, reqBody, resType any) error
	DeleteWithContext(ctx context.Context, url string, resType any) error
}

// Client talks to OVHcloud's /dedicated/server + /me APIs. Construct with
// NewClientFromEnv; in tests the API field takes a fake.
type Client struct {
	API httpAPI
}

// NewClientFromEnv builds a Client from the standard OVH credential env vars
// (OVH_ENDPOINT, OVH_APPLICATION_KEY, OVH_APPLICATION_SECRET, OVH_CONSUMER_KEY).
// Wiring those into the operator Deployment (an ESO-synced OVH_API secret) lands
// with the chart's OVH enablement, not in this PR; until then the reconciler
// stays dormant behind the OVH_APPLICATION_KEY gate in cmd/manager.
func NewClientFromEnv() (*Client, error) {
	api, err := ovh.NewDefaultClient()
	if err != nil {
		return nil, fmt.Errorf("ovh client: %w", err)
	}
	return &Client{API: api}, nil
}

// ProviderID is the foreign CAPI providerID for an OVH dedicated server,
// `ovh://<datacenter>/<service-name>`. The non-Hetzner host keeps the Hetzner
// CCM from reaping the node, same guard the Scaleway kinds use.
func ProviderID(datacenter, serviceName string) string {
	return fmt.Sprintf("ovh://%s/%s", datacenter, serviceName)
}

// Server is the subset of the /dedicated/server/{serviceName} resource the
// reconciler reads. OVH returns more fields; only these are decoded.
type Server struct {
	// Name is the OVH service name (e.g. nsXXXXXX.ip-A-B-C.eu) — the stable id
	// for every other call.
	Name string `json:"name"`
	// Datacenter is the OVH region code (vin, hil, gra, rbx, ...).
	Datacenter string `json:"datacenter"`
	// IP is the server's main public IPv4, used for the bootstrap SSH.
	IP string `json:"ip"`
	// State is the server lifecycle ("ok", "error", "hacked", ...).
	State string `json:"state"`
	// CommercialRange is the offer family (e.g. "Advance-3-2024"); adoption can
	// filter on it so a fleet only claims boxes of the intended shape.
	CommercialRange string `json:"commercialRange"`
	// Reverse is the editable rDNS, used as the adoption display-name signal.
	Reverse string `json:"reverse"`
}

// AdoptParams scopes which pre-ordered servers a fleet may claim.
type AdoptParams struct {
	// Datacenter the server must live in (required — composes the providerID
	// and keeps a region's fleet in-region).
	Datacenter string
	// Offer, when set, restricts adoption to servers whose CommercialRange
	// contains it (case-insensitive token match, e.g. "advance-3").
	Offer string
	// DisplayNamePrefix the server's reverse must start with to be considered
	// part of this fleet's pre-ordered pool.
	DisplayNamePrefix string
}

// ListServers returns every dedicated-server service name on the account.
func (c *Client) ListServers(ctx context.Context) ([]string, error) {
	var names []string
	if err := c.API.GetWithContext(ctx, "/dedicated/server", &names); err != nil {
		return nil, fmt.Errorf("list dedicated servers: %w", err)
	}
	return names, nil
}

// GetServer fetches the current server state.
func (c *Client) GetServer(ctx context.Context, serviceName string) (*Server, error) {
	server := &Server{}
	if err := c.API.GetWithContext(ctx, "/dedicated/server/"+serviceName, server); err != nil {
		return nil, fmt.Errorf("get dedicated server %s: %w", serviceName, err)
	}
	return server, nil
}

// FindAdoptableServer scans the account for a pre-ordered server matching the
// fleet's datacenter/offer/display-name prefix that no live Machine has already
// claimed (claimed is the set of service names already on sibling CRs' status),
// and returns it. Returns nil when the pool is exhausted so the caller requeues
// and waits for the operator to pre-order more capacity. Claim state lives
// cluster-side (the CR's status), not OVH-side: the controller records the
// service name as soon as it adopts, so a restart re-finds it via GetServer
// instead of double-claiming.
func (c *Client) FindAdoptableServer(ctx context.Context, p AdoptParams, claimed map[string]bool) (*Server, error) {
	names, err := c.ListServers(ctx)
	if err != nil {
		return nil, err
	}
	offer := strings.ToLower(p.Offer)
	for _, name := range names {
		if claimed[name] {
			continue
		}
		server, err := c.GetServer(ctx, name)
		if err != nil {
			return nil, err
		}
		if !strings.EqualFold(server.Datacenter, p.Datacenter) {
			continue
		}
		if p.DisplayNamePrefix != "" && !strings.HasPrefix(server.Reverse, p.DisplayNamePrefix) {
			continue
		}
		if offer != "" && !strings.Contains(strings.ToLower(server.CommercialRange), offer) {
			continue
		}
		return server, nil
	}
	return nil, nil
}

// EnsureSSHKey registers the bootstrap public key under the given name in
// /me/sshKey if it is not already there, so the OS install can authorize it.
// Idempotent: an existing key of the same name is left as-is.
func (c *Client) EnsureSSHKey(ctx context.Context, keyName, publicKey string) error {
	var names []string
	if err := c.API.GetWithContext(ctx, "/me/sshKey", &names); err != nil {
		return fmt.Errorf("list ssh keys: %w", err)
	}
	for _, n := range names {
		if n == keyName {
			return nil
		}
	}
	body := map[string]any{"keyName": keyName, "key": publicKey}
	if err := c.API.PostWithContext(ctx, "/me/sshKey", body, nil); err != nil {
		return fmt.Errorf("register ssh key %q: %w", keyName, err)
	}
	return nil
}

// ResolveTemplate maps an `ubuntu_24.04`-style label to a concrete OVH install
// template the server supports, matching the label's `_`-separated tokens
// against the compatible-template names case-insensitively (e.g. ubuntu_24.04 ->
// "ubuntu2404-server_64"). Mirrors the Scaleway bare-metal resolveOS so the
// chart can stay on stable labels instead of pinning OVH template names.
func (c *Client) ResolveTemplate(ctx context.Context, serviceName, osLabel string) (string, error) {
	var compat struct {
		OVH      []string `json:"ovh"`
		Personal []string `json:"personal"`
	}
	if err := c.API.GetWithContext(ctx, "/dedicated/server/"+serviceName+"/install/compatibleTemplates", &compat); err != nil {
		return "", fmt.Errorf("list compatible templates for %s: %w", serviceName, err)
	}
	tokens := strings.Split(strings.ToLower(osLabel), "_")
	for _, name := range append(append([]string{}, compat.Personal...), compat.OVH...) {
		lname := strings.ToLower(name)
		matched := true
		for _, t := range tokens {
			if t != "" && !strings.Contains(lname, strings.ReplaceAll(t, ".", "")) {
				matched = false
				break
			}
		}
		if matched {
			return name, nil
		}
	}
	return "", fmt.Errorf("no OVH install template matching label %q for server %s", osLabel, serviceName)
}

// InstallParams is the desired OS install for a server.
type InstallParams struct {
	TemplateName string
	Hostname     string
	SSHKeyName   string
}

// StartInstall kicks off the OS (re)install with the resolved template,
// hostname, and the bootstrap SSH key authorized. The install runs
// asynchronously (~20-40 min); poll InstallState before bootstrapping.
func (c *Client) StartInstall(ctx context.Context, serviceName string, p InstallParams) error {
	body := map[string]any{
		"templateName": p.TemplateName,
		"details": map[string]any{
			"customHostname": p.Hostname,
			"sshKeyName":     p.SSHKeyName,
		},
	}
	if err := c.API.PostWithContext(ctx, "/dedicated/server/"+serviceName+"/install/start", body, nil); err != nil {
		return fmt.Errorf("start install on %s: %w", serviceName, err)
	}
	return nil
}

// InstallState is the coarse install lifecycle the reconciler gates on.
type InstallState int

const (
	// InstallPending means no install has started yet (just-adopted box).
	InstallPending InstallState = iota
	// InstallRunning means the OS install is in progress.
	InstallRunning
	// InstallDone means the OS install finished and the box is bootable.
	InstallDone
	// InstallFailed means the install errored terminally.
	InstallFailed
)

// installTask is the subset of /dedicated/server/{name}/task/{id} we read.
type installTask struct {
	Function string `json:"function"`
	Status   string `json:"status"`
}

// InstallState polls the server's most recent install task and maps it to the
// coarse lifecycle. OVH models the install as a task whose function is one of
// the (re)install variants; its status walks todo -> doing -> done (or
// problem/error/cancelled on failure). No install task yet means Pending.
func (c *Client) InstallState(ctx context.Context, serviceName string) (InstallState, error) {
	var ids []int64
	if err := c.API.GetWithContext(ctx, "/dedicated/server/"+serviceName+"/task", &ids); err != nil {
		return InstallPending, fmt.Errorf("list tasks for %s: %w", serviceName, err)
	}
	latest := InstallPending
	var latestID int64 = -1
	for _, id := range ids {
		task := &installTask{}
		if err := c.API.GetWithContext(ctx, fmt.Sprintf("/dedicated/server/%s/task/%d", serviceName, id), task); err != nil {
			if IsNotFound(err) {
				continue
			}
			return InstallPending, fmt.Errorf("get task %d for %s: %w", id, serviceName, err)
		}
		if !isInstallFunction(task.Function) {
			continue
		}
		if id <= latestID {
			continue
		}
		latestID = id
		latest = mapTaskStatus(task.Status)
	}
	return latest, nil
}

// isInstallFunction reports whether a task function is one of OVH's OS-install
// variants (the names differ across template generations).
func isInstallFunction(fn string) bool {
	f := strings.ToLower(fn)
	return strings.Contains(f, "install") || strings.Contains(f, "reinstall")
}

func mapTaskStatus(status string) InstallState {
	switch strings.ToLower(status) {
	case "done":
		return InstallDone
	case "problem", "error", "cancelled", "customererror", "ovherror":
		return InstallFailed
	default: // todo, doing, init, waitingAck, ...
		return InstallRunning
	}
}

// IsNotFound reports whether err is an OVH 404, so callers can treat an absent
// server/task as gone rather than a hard error.
func IsNotFound(err error) bool {
	var apiErr *ovh.APIError
	if errors.As(err, &apiErr) {
		return apiErr.Code == 404
	}
	return false
}
