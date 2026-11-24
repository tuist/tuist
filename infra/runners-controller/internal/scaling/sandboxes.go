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
	// CPUFreeMilli is the node's allocatable CPU no Pod requests, with the
	// daemon counted at the CPU the kubelet allocated it: room its CPU
	// request can grow into at once.
	CPUFreeMilli int64 `json:"cpu_free_milli"`
	// CPUReclaimableMilli is the CPU idle warm runners on the node hold. A
	// growth into it is deferred by the kubelet until the autoscaler retires
	// them, as for memory; a deferred resize holds up the daemon's memory
	// growths with it, and the server lowers a growth that stops fitting.
	CPUReclaimableMilli int64 `json:"cpu_reclaimable_milli"`
	Reclaim             bool  `json:"reclaim"`
	// WarmBytes is the carve-out a remote execution worker is kept at while
	// this grant is fresh: its share of the fleet-wide floor. 0 for other
	// daemons, and from controllers that predate it.
	WarmBytes int64 `json:"warm_bytes,omitempty"`
	// SiblingMemoryBytes is the memory this grant counted the host's other
	// carve-out at (the agent daemon or the remote execution worker). The
	// server takes what that carve-out grew by since off this grant, so the
	// two cannot grow into the same free memory between observations. Nil
	// when the host runs only one carve-out.
	SiblingMemoryBytes *int64 `json:"sibling_memory_bytes,omitempty"`
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
