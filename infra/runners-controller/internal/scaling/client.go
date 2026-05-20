package scaling

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"time"
)

// DefaultSATokenPath is the in-cluster mount point for the
// controller Pod's projected ServiceAccount token. The Tuist
// server validates it via TokenReview.
const DefaultSATokenPath = "/var/run/secrets/kubernetes.io/serviceaccount/token"

// Client fetches scaling signals from the Tuist server. The
// controller reads its SA token from `TokenPath` on every call
// — projected tokens rotate, and re-reading is cheaper than
// invalidating and refreshing on stale-token errors.
type Client struct {
	// BaseURL is the full URL to /api/internal/runners/desired_replicas
	// — i.e. with the path included. The fleet query param is
	// appended per request.
	BaseURL string

	// TokenPath defaults to DefaultSATokenPath; tests can override.
	TokenPath string

	// HTTPClient defaults to a 5-second-timeout client. Tests can
	// override to inject a mock RoundTripper.
	HTTPClient *http.Client
}

// NewClient returns a Client with sensible defaults.
func NewClient(baseURL string) *Client {
	return &Client{
		BaseURL:   baseURL,
		TokenPath: DefaultSATokenPath,
		HTTPClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

// Signals fetches the load signals for `fleet` from the server.
// Returns the parsed body on 200 or an error otherwise — the
// reconciler treats any error as "no fresh signal" and leaves
// replicas unchanged (anti-thrash).
func (c *Client) Signals(ctx context.Context, fleet string) (*Signals, error) {
	if c.BaseURL == "" {
		return nil, fmt.Errorf("scaling: base URL not set")
	}
	if fleet == "" {
		return nil, fmt.Errorf("scaling: fleet name required")
	}

	token, err := c.readToken()
	if err != nil {
		return nil, fmt.Errorf("scaling: read SA token: %w", err)
	}

	u, err := url.Parse(c.BaseURL)
	if err != nil {
		return nil, fmt.Errorf("scaling: parse base URL: %w", err)
	}
	q := u.Query()
	q.Set("fleet", fleet)
	u.RawQuery = q.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, fmt.Errorf("scaling: build request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", "application/json")

	httpClient := c.HTTPClient
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("scaling: HTTP request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("scaling: read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("scaling: HTTP %d: %s", resp.StatusCode, string(body))
	}

	var signals Signals
	if err := json.Unmarshal(body, &signals); err != nil {
		return nil, fmt.Errorf("scaling: decode response: %w", err)
	}
	return &signals, nil
}

func (c *Client) readToken() (string, error) {
	path := c.TokenPath
	if path == "" {
		path = DefaultSATokenPath
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return string(data), nil
}
