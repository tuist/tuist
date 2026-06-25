package podmetrics

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"time"
)

// DefaultSATokenPath is the in-cluster mount point for the controller
// Pod's projected ServiceAccount token. The Tuist server validates it
// via TokenReview and gates on the runners-controller SA, the same
// auth as `pods/stopped`.
const DefaultSATokenPath = "/var/run/secrets/kubernetes.io/serviceaccount/token"

// Sample is one machine-metrics snapshot for a runner Pod, matching the
// server ingest contract. Every field but Timestamp is optional
// server-side (defaults to 0), so a platform that can't measure a
// dimension just sends 0.
type Sample struct {
	Timestamp        float64 `json:"timestamp"` // epoch seconds
	CPUUsagePercent  float64 `json:"cpu_usage_percent"`
	CPUIOWaitPercent float64 `json:"cpu_iowait_percent"`
	MemoryUsedBytes  int64   `json:"memory_used_bytes"`
	MemoryTotalBytes int64   `json:"memory_total_bytes"`
	NetworkBytesIn   int64   `json:"network_bytes_in"`
	NetworkBytesOut  int64   `json:"network_bytes_out"`
	DiskUsedBytes    int64   `json:"disk_used_bytes"`
	DiskTotalBytes   int64   `json:"disk_total_bytes"`
}

type metricsRequest struct {
	Samples []Sample `json:"samples"`
}

// Client POSTs machine-metrics batches to the Tuist server. Like the
// sessions client it re-reads its SA token per call, since projected
// tokens rotate.
type Client struct {
	// BaseURL points at `/api/internal/runners` on the Tuist server;
	// the `/pods/<name>/metrics` suffix is appended per call.
	BaseURL string

	// TokenPath defaults to DefaultSATokenPath; tests override it.
	TokenPath string

	// HTTPClient defaults to a 5-second-timeout client.
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

// Report posts a batch of samples for podName. The server resolves the
// Pod to its live claim's job; an unclaimed Pod is a 204 no-op, so it
// is safe to report for every running runner Pod. Delivery is
// at-least-once — the server's ReplacingMergeTree collapses re-posted
// samples on (workflow_job_id, timestamp).
func (c *Client) Report(ctx context.Context, podName string, samples []Sample) error {
	if c.BaseURL == "" {
		return fmt.Errorf("podmetrics: base URL not set")
	}
	if podName == "" {
		return fmt.Errorf("podmetrics: pod name required")
	}
	if len(samples) == 0 {
		return nil
	}

	body, err := json.Marshal(metricsRequest{Samples: samples})
	if err != nil {
		return fmt.Errorf("podmetrics: encode request: %w", err)
	}

	token, err := c.readToken()
	if err != nil {
		return fmt.Errorf("podmetrics: read SA token: %w", err)
	}

	endpoint := c.BaseURL + "/pods/" + url.PathEscape(podName) + "/metrics"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("podmetrics: build request: %w", err)
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
		return fmt.Errorf("podmetrics: HTTP request: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if resp.StatusCode == http.StatusNoContent || resp.StatusCode == http.StatusOK {
		return nil
	}
	return fmt.Errorf("podmetrics: HTTP %d: %s", resp.StatusCode, string(respBody))
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
