// Package tailnet reads and manages devices through the Tailscale API with an
// OAuth client. The client's tags bound what it may change: Tailscale refuses
// a write to a device carrying none of them.
package tailnet

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const defaultBaseURL = "https://api.tailscale.com"

// Device is the subset of the API's device object the operator reads.
type Device struct {
	NodeID             string   `json:"nodeId"`
	Name               string   `json:"name"`
	Hostname           string   `json:"hostname"`
	Addresses          []string `json:"addresses"`
	Tags               []string `json:"tags"`
	Created            string   `json:"created"`
	LastSeen           string   `json:"lastSeen"`
	ConnectedToControl bool     `json:"connectedToControl"`
}

// ShortName is the first label of the device's MagicDNS name.
func (d Device) ShortName() string {
	name, _, _ := strings.Cut(d.Name, ".")
	return name
}

// IPv4 is the device's tailnet IPv4 address, empty when it has none.
func (d Device) IPv4() string {
	for _, a := range d.Addresses {
		if !strings.Contains(a, ":") {
			return a
		}
	}
	return ""
}

// CreatedAt parses Created, zero when absent or malformed.
func (d Device) CreatedAt() time.Time {
	return parseTime(d.Created)
}

// LastSeenAt parses LastSeen, zero when absent or malformed.
func (d Device) LastSeenAt() time.Time {
	return parseTime(d.LastSeen)
}

// HasTags reports whether the device carries every one of tags.
func (d Device) HasTags(tags []string) bool {
	for _, want := range tags {
		found := false
		for _, have := range d.Tags {
			if have == want {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}

func parseTime(s string) time.Time {
	if s == "" {
		return time.Time{}
	}
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil || t.Unix() <= 0 {
		return time.Time{}
	}
	return t
}

// Client talks to the Tailscale API.
type Client struct {
	ClientID     string
	ClientSecret string
	// Tailnet is the tailnet name, "-" for the credential's own.
	Tailnet string
	BaseURL string
	HTTP    *http.Client

	mu          sync.Mutex
	token       string
	tokenExpiry time.Time
}

func (c *Client) baseURL() string {
	if c.BaseURL != "" {
		return strings.TrimRight(c.BaseURL, "/")
	}
	return defaultBaseURL
}

func (c *Client) httpClient() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	return &http.Client{Timeout: 30 * time.Second}
}

func (c *Client) tailnet() string {
	if c.Tailnet != "" {
		return c.Tailnet
	}
	return "-"
}

// Devices lists every device on the tailnet.
func (c *Client) Devices(ctx context.Context) ([]Device, error) {
	var out struct {
		Devices []Device `json:"devices"`
	}
	path := "/api/v2/tailnet/" + url.PathEscape(c.tailnet()) + "/devices?fields=all"
	if err := c.do(ctx, http.MethodGet, path, nil, &out); err != nil {
		return nil, fmt.Errorf("list tailnet devices: %w", err)
	}
	return out.Devices, nil
}

// DeleteDevice removes a device from the tailnet.
func (c *Client) DeleteDevice(ctx context.Context, nodeID string) error {
	if err := c.do(ctx, http.MethodDelete, "/api/v2/device/"+url.PathEscape(nodeID), nil, nil); err != nil {
		return fmt.Errorf("delete tailnet device %s: %w", nodeID, err)
	}
	return nil
}

// RenameDevice sets a device's MagicDNS name.
func (c *Client) RenameDevice(ctx context.Context, nodeID, name string) error {
	body := map[string]string{"name": name}
	if err := c.do(ctx, http.MethodPost, "/api/v2/device/"+url.PathEscape(nodeID)+"/name", body, nil); err != nil {
		return fmt.Errorf("rename tailnet device %s to %s: %w", nodeID, name, err)
	}
	return nil
}

func (c *Client) do(ctx context.Context, method, path string, body, out any) error {
	token, err := c.accessToken(ctx)
	if err != nil {
		return err
	}
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(encoded)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL()+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.httpClient().Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	payload, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode == http.StatusUnauthorized {
		c.mu.Lock()
		c.token = ""
		c.mu.Unlock()
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("%s %s: HTTP %d: %s", method, path, resp.StatusCode, strings.TrimSpace(string(payload)))
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(payload, out)
}

// accessToken exchanges the OAuth client credentials for a bearer token and
// reuses it until shortly before it expires.
func (c *Client) accessToken(ctx context.Context) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.token != "" && time.Now().Before(c.tokenExpiry) {
		return c.token, nil
	}
	if c.ClientID == "" || c.ClientSecret == "" {
		return "", fmt.Errorf("no Tailscale OAuth client configured")
	}
	form := url.Values{
		"client_id":     {c.ClientID},
		"client_secret": {c.ClientSecret},
		"grant_type":    {"client_credentials"},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL()+"/api/v2/oauth/token", strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := c.httpClient().Do(req)
	if err != nil {
		return "", fmt.Errorf("exchange Tailscale OAuth client for a token: %w", err)
	}
	defer resp.Body.Close()
	payload, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("exchange Tailscale OAuth client for a token: HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(payload)))
	}
	var tok struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(payload, &tok); err != nil {
		return "", fmt.Errorf("decode Tailscale OAuth token: %w", err)
	}
	if tok.AccessToken == "" {
		return "", fmt.Errorf("the Tailscale OAuth token response carried no access_token")
	}
	lifetime := time.Duration(tok.ExpiresIn) * time.Second
	if lifetime <= 0 {
		lifetime = time.Hour
	}
	c.token = tok.AccessToken
	c.tokenExpiry = time.Now().Add(lifetime - time.Minute)
	return c.token, nil
}
