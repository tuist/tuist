package scaling

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

// SandboxAllocation grants an upper bound, not a request to reserve warm memory.
// The server expires grants after 15 seconds and binds them to the daemon Pod.
type SandboxAllocation struct {
	Node        string    `json:"node"`
	Pod         string    `json:"pod"`
	ObservedAt  time.Time `json:"observed_at"`
	MemoryBytes int64     `json:"memory_bytes"`
	FreeBytes   int64     `json:"free_bytes"`
	Reclaim     bool      `json:"reclaim"`
}

func (c *Client) PublishSandboxAllocation(ctx context.Context, allocation SandboxAllocation) error {
	u, err := url.Parse(c.BaseURL)
	if err != nil {
		return err
	}
	u.Path = "/api/internal/sandboxes/allocation"
	u.RawQuery = ""
	token, err := c.readToken()
	if err != nil {
		return err
	}
	body, err := json.Marshal(allocation)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u.String(), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	httpClient := c.HTTPClient
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 5 * time.Second}
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	// Drain a bounded response for connection reuse; never log credentials.
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusNoContent {
		return fmt.Errorf("sandbox allocation: HTTP %d", resp.StatusCode)
	}
	return nil
}
