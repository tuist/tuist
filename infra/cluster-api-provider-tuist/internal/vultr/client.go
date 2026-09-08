// Package vultr is the Vultr bare-metal client the VultrMachine reconciler talks
// to. It covers the small slice of the /v2/bare-metals API the machine lifecycle
// needs: find and adopt a pre-ordered server by tag, read its address and state,
// mark it into or out of the pool, and reinstall it on release.
//
// A hand-rolled net/http client rather than a vendored SDK: six endpoints, all
// plain JSON, against an API that is already a dependency risk we would rather
// keep legible than large.
//
// Three deliberate differences from the OVH client, all forced by what the API
// does and does not offer (measured 2026-09-07, see
// docs/vultr-baremetal-support.md):
//
//   - Adoption is by TAG. `GET /v2/bare-metals` filters server-side on label,
//     tag and region, but the label filter matches EXACTLY: the label
//     `tuist-kura-vultr-production` returns nothing for a box labelled
//     `tuist-kura-vultr-production-sa-west`. There is no server-side equivalent
//     of OVH's displayName prefix, so the fleet marker is a tag, which is also
//     one query rather than a list plus a per-box lookup.
//   - The install takes no storage plan. OVH and Dedibox both accept a
//     partitioning block; Vultr's reinstall accepts an optional hostname and
//     nothing else. The layout the cluster gates on therefore cannot come from
//     the install, and the reconciler converts the box afterwards.
//   - No delete. Tearing the CR down must not destroy the box; release is
//     reinstall plus untag, leaving the machine in the pool.
package vultr

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const defaultBaseURL = "https://api.vultr.com/v2"

// doer is the slice of *http.Client the client touches, so tests drop in a fake.
type doer interface {
	Do(req *http.Request) (*http.Response, error)
}

// Client talks to Vultr's /v2/bare-metals API. Construct with NewClientFromEnv;
// in tests HTTP and BaseURL take fakes.
type Client struct {
	HTTP    doer
	BaseURL string
	APIKey  string
}

// NewClientFromEnv builds a Client from VULTR_API_KEY, synced into the operator
// Deployment from the ESO VULTR_API secret. The reconciler is gated on that
// variable in cmd/manager, so an env without Vultr credentials simply does not
// register the Vultr controller.
func NewClientFromEnv() (*Client, error) {
	key := strings.TrimSpace(os.Getenv("VULTR_API_KEY"))
	if key == "" {
		return nil, fmt.Errorf("VULTR_API_KEY is empty")
	}
	base := strings.TrimSpace(os.Getenv("VULTR_API_BASE"))
	if base == "" {
		base = defaultBaseURL
	}
	return &Client{
		HTTP:    &http.Client{Timeout: 30 * time.Second},
		BaseURL: strings.TrimSuffix(base, "/"),
		APIKey:  key,
	}, nil
}

// Server is the subset of a bare-metal object the lifecycle reads.
type Server struct {
	ID          string   `json:"id"`
	Label       string   `json:"label"`
	Tags        []string `json:"tags"`
	Region      string   `json:"region"`
	Plan        string   `json:"plan"`
	OS          string   `json:"os"`
	OSID        int32    `json:"os_id"`
	MainIP      string   `json:"main_ip"`
	Status      string   `json:"status"`
	PowerStatus string   `json:"power_status"`
}

// AdoptParams narrows which pre-ordered box a fleet may claim. Tag is the
// environment boundary: one account holds every env's boxes, and region and plan
// repeat across envs.
type AdoptParams struct {
	Tag    string
	Region string
	Plan   string
}

// InstallState is how far a reinstall has got.
type InstallState string

const (
	// InstallRunning is Vultr's `pending`: the box is being reimaged.
	InstallRunning InstallState = "running"
	// InstallSettled is Vultr's `active`. It does NOT mean the box is reachable:
	// measured on a real reinstall, status returned to `active` about 86 seconds
	// before SSH answered, and for the first minute after the request it is still
	// the OLD system answering. Callers must gate on a fresh system (SSH plus a
	// small uptime), never on this alone.
	InstallSettled InstallState = "settled"
	// InstallUnknown is any other status Vultr reports.
	InstallUnknown InstallState = "unknown"
)

func (c *Client) do(ctx context.Context, method, path string, query url.Values, body, out any) error {
	var rdr io.Reader
	if body != nil {
		buf, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("encode %s %s: %w", method, path, err)
		}
		rdr = bytes.NewReader(buf)
	}
	endpoint := c.BaseURL + path
	if len(query) > 0 {
		endpoint += "?" + query.Encode()
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, rdr)
	if err != nil {
		return fmt.Errorf("build %s %s: %w", method, path, err)
	}
	req.Header.Set("Authorization", "Bearer "+c.APIKey)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return fmt.Errorf("%s %s: %w", method, path, err)
	}
	defer func() { _ = resp.Body.Close() }()

	payload, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read %s %s: %w", method, path, err)
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		// The IP allowlist is the failure worth naming: Vultr gates keys on a
		// source-IP ACL the other providers have no equivalent of, an empty ACL
		// rejects every caller, and the message carries the address it saw. A bare
		// "401" would send an operator looking at the key instead.
		return fmt.Errorf("%s %s: HTTP %d: %s", method, path, resp.StatusCode, strings.TrimSpace(string(payload)))
	}
	if out == nil || len(payload) == 0 {
		return nil
	}
	if err := json.Unmarshal(payload, out); err != nil {
		return fmt.Errorf("decode %s %s: %w", method, path, err)
	}
	return nil
}

// ListServers returns every bare-metal box carrying the given tag, filtered
// server-side. An empty tag lists the whole account.
func (c *Client) ListServers(ctx context.Context, tag string) ([]Server, error) {
	q := url.Values{}
	if tag != "" {
		q.Set("tag", tag)
	}
	var out struct {
		BareMetals []Server `json:"bare_metals"`
	}
	if err := c.do(ctx, http.MethodGet, "/bare-metals", q, nil, &out); err != nil {
		return nil, err
	}
	return out.BareMetals, nil
}

// GetServer reads one box.
func (c *Client) GetServer(ctx context.Context, id string) (*Server, error) {
	var out struct {
		BareMetal Server `json:"bare_metal"`
	}
	if err := c.do(ctx, http.MethodGet, "/bare-metals/"+url.PathEscape(id), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out.BareMetal, nil
}

// FindAdoptableServer returns the first pre-ordered box matching the fleet's
// tag, region and plan that no other Machine has claimed, or nil when the pool
// is empty. The tag does the env scoping and is applied server-side; region and
// plan are cheap local checks on the result.
func (c *Client) FindAdoptableServer(ctx context.Context, p AdoptParams, claimed map[string]bool) (*Server, error) {
	servers, err := c.ListServers(ctx, p.Tag)
	if err != nil {
		return nil, err
	}
	for i := range servers {
		s := servers[i]
		if claimed[s.ID] {
			continue
		}
		if p.Region != "" && !strings.EqualFold(s.Region, p.Region) {
			continue
		}
		// Plan is an exact match rather than a prefix: the plans differ in whether
		// their disks are NVMe or SSD, and a cache adopting the SSD variant of the
		// same core count would be a silent downgrade.
		if p.Plan != "" && !strings.EqualFold(s.Plan, p.Plan) {
			continue
		}
		return &s, nil
	}
	return nil, nil
}

// SetTags replaces a box's tags, which is how it is marked into or out of a
// fleet's pool. Returns 202; the change is visible to a tag-filtered list
// immediately.
func (c *Client) SetTags(ctx context.Context, id string, tags []string) error {
	if tags == nil {
		tags = []string{}
	}
	return c.do(ctx, http.MethodPatch, "/bare-metals/"+url.PathEscape(id),
		nil, map[string]any{"tags": tags}, nil)
}

// StartInstall reinstalls the box, optionally renaming it. There is no OS or
// storage argument: it reimages whatever the box already carries, which is why
// the caller has to convert the disk layout afterwards.
func (c *Client) StartInstall(ctx context.Context, id, hostname string) error {
	body := map[string]any{}
	if hostname != "" {
		body["hostname"] = hostname
	}
	return c.do(ctx, http.MethodPost, "/bare-metals/"+url.PathEscape(id)+"/reinstall", nil, body, nil)
}

// InstallState reports how far a reinstall has got. See InstallSettled: it is
// not a readiness signal, and the response to StartInstall itself still reports
// the pre-transition state, so this has to be polled rather than inferred.
func (c *Client) InstallState(ctx context.Context, id string) (InstallState, error) {
	s, err := c.GetServer(ctx, id)
	if err != nil {
		return InstallUnknown, err
	}
	switch strings.ToLower(s.Status) {
	case "pending":
		return InstallRunning, nil
	case "active":
		return InstallSettled, nil
	default:
		return InstallUnknown, nil
	}
}
