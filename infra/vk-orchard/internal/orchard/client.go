// Package orchard wraps the Orchard control-plane HTTP API used by the
// Virtual Kubelet provider to manage Tart VMs across the macOS fleet.
//
// The shape mirrors Tuist.Runners.OrchardClient in the Elixir codebase
// (server/lib/tuist/runners/orchard_client.ex) — the same set of REST
// endpoints, just written in Go so the VK provider can be a self-contained
// binary inside the cluster.
package orchard

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

// Client talks to an Orchard controller. Authentication uses HTTP basic
// with a service account name + token, the same pair Orchard's docs and
// the Elixir client use.
type Client struct {
	BaseURL              string
	ServiceAccountName   string
	ServiceAccountToken  string
	HTTPClient           *http.Client
}

// NewClient returns a Client backed by a default *http.Client with sane
// timeouts. Callers can swap HTTPClient for tests.
func NewClient(baseURL, name, token string) *Client {
	return &Client{
		BaseURL:             baseURL,
		ServiceAccountName:  name,
		ServiceAccountToken: token,
		HTTPClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// VM is the subset of Orchard's VM resource the VK provider reads/writes.
// Orchard's full schema is wider; we model only what we need to translate
// between Pod and VM state.
type VM struct {
	Name          string            `json:"name"`
	Image         string            `json:"image"`
	CPU           int               `json:"cpu,omitempty"`
	Memory        int               `json:"memory,omitempty"`
	Status        string            `json:"status,omitempty"`
	StatusMessage string            `json:"status_message,omitempty"`
	Worker        string            `json:"worker,omitempty"`
	StartupScript string            `json:"startup_script,omitempty"`
	UserData      string            `json:"user_data,omitempty"`
	Labels        map[string]string `json:"labels,omitempty"`
	CreatedAt     time.Time         `json:"created_at,omitempty"`
	StartedAt     *time.Time        `json:"started_at,omitempty"`
}

// CreateVM POSTs /v1/vms. Returns the created VM (including any
// server-assigned fields like worker placement).
func (c *Client) CreateVM(ctx context.Context, vm VM) (*VM, error) {
	var out VM
	if err := c.do(ctx, http.MethodPost, "/v1/vms", vm, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// GetVM GETs /v1/vms/{name}. Returns ErrNotFound when the VM doesn't exist.
func (c *Client) GetVM(ctx context.Context, name string) (*VM, error) {
	var out VM
	if err := c.do(ctx, http.MethodGet, "/v1/vms/"+url.PathEscape(name), nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// DeleteVM DELETEs /v1/vms/{name}. Returns nil on success or when the VM
// is already gone (404 is treated as success — VM removal is idempotent
// from the VK provider's perspective).
func (c *Client) DeleteVM(ctx context.Context, name string) error {
	err := c.do(ctx, http.MethodDelete, "/v1/vms/"+url.PathEscape(name), nil, nil)
	if err == ErrNotFound {
		return nil
	}
	return err
}

// ListVMs GETs /v1/vms. Used at provider startup to resync state and on
// every node-status tick to compute capacity utilization.
func (c *Client) ListVMs(ctx context.Context) ([]VM, error) {
	var out []VM
	if err := c.do(ctx, http.MethodGet, "/v1/vms", nil, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// Worker is the subset of Orchard's worker (Mac mini host) we care about
// for capacity planning.
type Worker struct {
	Name      string            `json:"name"`
	CPU       int               `json:"cpu"`
	Memory    int               `json:"memory"`
	Status    string            `json:"status"`
	Labels    map[string]string `json:"labels,omitempty"`
	UpdatedAt time.Time         `json:"updated_at,omitempty"`
}

// ListWorkers GETs /v1/workers. The provider sums these to compute the
// virtual node's reported capacity.
func (c *Client) ListWorkers(ctx context.Context) ([]Worker, error) {
	var out []Worker
	if err := c.do(ctx, http.MethodGet, "/v1/workers", nil, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// StreamLogs returns a reader that streams the VM's combined stdout/stderr.
// Backs `kubectl logs` / `kubectl logs -f`. The caller is responsible for
// closing the returned ReadCloser.
//
// Orchard's log endpoint is expected to support a `follow=true` query
// param for tailing; if absent, the call returns a one-shot snapshot.
func (c *Client) StreamLogs(ctx context.Context, name string, follow bool) (io.ReadCloser, error) {
	path := "/v1/vms/" + url.PathEscape(name) + "/logs"
	if follow {
		path += "?follow=true"
	}
	req, err := c.newRequest(ctx, http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode == http.StatusNotFound {
		_ = resp.Body.Close()
		return nil, ErrNotFound
	}
	if resp.StatusCode >= 400 {
		body, _ := io.ReadAll(resp.Body)
		_ = resp.Body.Close()
		return nil, fmt.Errorf("orchard logs: status %d: %s", resp.StatusCode, string(body))
	}
	return resp.Body, nil
}

// ErrNotFound is returned when Orchard responds with 404. Callers map it
// to the equivalent k8s outcome (Pod not found, VM already deleted).
var ErrNotFound = fmt.Errorf("orchard: not found")

func (c *Client) do(ctx context.Context, method, path string, body, out any) error {
	req, err := c.newRequest(ctx, method, path, body)
	if err != nil {
		return err
	}

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("orchard %s %s: %w", method, path, err)
	}
	defer resp.Body.Close()

	switch {
	case resp.StatusCode == http.StatusNotFound:
		return ErrNotFound
	case resp.StatusCode == http.StatusNoContent:
		return nil
	case resp.StatusCode >= 200 && resp.StatusCode < 300:
		if out == nil {
			return nil
		}
		return json.NewDecoder(resp.Body).Decode(out)
	default:
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("orchard %s %s: status %d: %s",
			method, path, resp.StatusCode, string(respBody))
	}
}

func (c *Client) newRequest(ctx context.Context, method, path string, body any) (*http.Request, error) {
	var reader io.Reader
	if body != nil {
		buf, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("marshal body: %w", err)
		}
		reader = bytes.NewReader(buf)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.BaseURL+path, reader)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if c.ServiceAccountName != "" || c.ServiceAccountToken != "" {
		req.SetBasicAuth(c.ServiceAccountName, c.ServiceAccountToken)
	}
	return req, nil
}
