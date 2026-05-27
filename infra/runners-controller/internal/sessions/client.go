// Package sessions ships Pod-lifecycle signals to the Tuist server's
// `/api/internal/runners/pods/*` endpoints, which drive the per-Pod
// billing record in `Tuist.Runners.RunnerSessions`.
//
// The controller is the authoritative source for these signals
// because K8s's terminal-phase transitions (and the
// `containerStatuses[].state.terminated.finishedAt` timestamp
// underneath them) are the closest signal to "the runner Pod
// actually stopped running" — and unlike the GitHub
// `workflow_job.completed` webhook, they aren't subject to
// delivery delays that could extend a billed window past the
// customer's actual runtime.
package sessions

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

// DefaultSATokenPath is the in-cluster mount point for the
// controller Pod's projected ServiceAccount token. The Tuist
// server validates it via TokenReview.
const DefaultSATokenPath = "/var/run/secrets/kubernetes.io/serviceaccount/token"

// Client posts Pod-lifecycle events to the Tuist server. The
// controller re-reads its SA token from `TokenPath` on every call
// — projected tokens rotate, and re-reading is cheaper than
// invalidating and refreshing on stale-token errors.
type Client struct {
	// BaseURL points at `/api/internal/runners` on the Tuist
	// server (the parent path; the per-action suffix is appended
	// by each method). E.g. https://tuist.dev/api/internal/runners
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

// StoppedRequest is the JSON body the server expects on
// `POST /api/internal/runners/pods/stopped`.
type StoppedRequest struct {
	PodName string    `json:"pod_name"`
	EndedAt time.Time `json:"ended_at"`
}

// Stopped reports that a Pod has stopped running. `endedAt` should
// be the K8s `containerStatuses[runner].state.terminated.finishedAt`
// — the moment the container process exited. The server's close
// path is idempotent and biased toward under-bill on re-delivery,
// so retrying on transient errors is safe.
func (c *Client) Stopped(ctx context.Context, podName string, endedAt time.Time) error {
	if c.BaseURL == "" {
		return fmt.Errorf("sessions: base URL not set")
	}
	if podName == "" {
		return fmt.Errorf("sessions: pod name required")
	}

	body, err := json.Marshal(StoppedRequest{PodName: podName, EndedAt: endedAt})
	if err != nil {
		return fmt.Errorf("sessions: encode request: %w", err)
	}

	token, err := c.readToken()
	if err != nil {
		return fmt.Errorf("sessions: read SA token: %w", err)
	}

	url := c.BaseURL + "/pods/stopped"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("sessions: build request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	httpClient := c.HTTPClient
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("sessions: HTTP request: %w", err)
	}
	defer resp.Body.Close()

	// Drain the body up to a small cap so the connection can be
	// reused. The server returns 204 on success with an empty body.
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))

	// 204 = closed; 200 + body = also OK (defensive — server's
	// current contract is 204 but a future revision might return
	// the closed session for telemetry).
	if resp.StatusCode == http.StatusNoContent || resp.StatusCode == http.StatusOK {
		return nil
	}

	return fmt.Errorf("sessions: HTTP %d: %s", resp.StatusCode, string(respBody))
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
