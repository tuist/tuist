package shadow

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

type Client struct {
	URL        string
	TokenPath  string
	HTTPClient *http.Client
}

func NewClient(url string) *Client {
	return &Client{URL: url, TokenPath: scaling.DefaultSATokenPath, HTTPClient: &http.Client{Timeout: 5 * time.Second,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse },
	}}
}

func (c *Client) Snapshot(ctx context.Context) (Snapshot, error) {
	var snapshot Snapshot
	token, err := os.ReadFile(c.TokenPath)
	if err != nil {
		return snapshot, fmt.Errorf("read controller token: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.URL, nil)
	if err != nil {
		return snapshot, fmt.Errorf("build snapshot request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	req.Header.Set("Accept", "application/json")
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return snapshot, fmt.Errorf("fetch snapshot: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return snapshot, fmt.Errorf("snapshot HTTP %d", resp.StatusCode)
	}
	const maxBytes = 8 << 20
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxBytes+1))
	if err != nil {
		return snapshot, fmt.Errorf("read snapshot: %w", err)
	}
	if len(body) > maxBytes {
		return snapshot, fmt.Errorf("snapshot response exceeds bound")
	}
	if err := json.Unmarshal(body, &snapshot); err != nil {
		return snapshot, fmt.Errorf("decode snapshot: %w", err)
	}
	return snapshot, nil
}
