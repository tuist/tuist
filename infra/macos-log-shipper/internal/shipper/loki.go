package shipper

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"sync"
	"time"
)

// ErrRejected marks a push Loki refused for a reason retrying cannot fix: a
// malformed body, a label the tenant disallows, or — the case that actually
// happens here — entries older than the tenant's accepted window, which is
// what a shipper catching up after a long outage produces. The caller drops
// the batch and advances rather than retrying forever behind lines that will
// never be accepted.
var ErrRejected = errors.New("loki rejected the batch")

// Client pushes batches to a Loki-compatible /loki/api/v1/push endpoint.
//
// No credentials: the endpoint is the in-cluster Alloy receiver reached over
// the tailnet, and the tailnet ACL is the access control. Alloy holds the
// Grafana Cloud token and forwards, so a Mac mini never carries one.
type Client struct {
	URL     string
	once    sync.Once
	http    *http.Client
	initErr error
}

func NewClient(endpoint string, timeout time.Duration) (*Client, error) {
	parsed, err := url.Parse(endpoint)
	if err != nil || parsed.Hostname() == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return nil, errors.New("invalid log receiver URL")
	}
	client := &Client{URL: endpoint}
	client.once.Do(func() { client.http, client.initErr = NewHTTPClient(timeout) })
	return client, client.initErr
}

func (c *Client) httpClient() (*http.Client, error) {
	c.once.Do(func() { c.http, c.initErr = certificateTrustClient(nil, nil) })
	return c.http, c.initErr
}

func (c *Client) CloseIdleConnections() {
	client, err := c.httpClient()
	if err == nil {
		client.CloseIdleConnections()
	}
}

type pushRequest struct {
	Streams []pushStream `json:"streams"`
}

type pushStream struct {
	Stream map[string]string `json:"stream"`
	Values [][2]string       `json:"values"`
}

// buildPush groups entries into one stream per level, because level is the
// only label that varies within a batch. Streams carry the base labels plus
// their level.
func buildPush(base map[string]string, entries []Entry) pushRequest {
	byLevel := map[string][]Entry{}
	for _, entry := range entries {
		byLevel[entry.Level] = append(byLevel[entry.Level], entry)
	}
	levels := make([]string, 0, len(byLevel))
	for level := range byLevel {
		levels = append(levels, level)
	}
	sort.Strings(levels)

	req := pushRequest{Streams: make([]pushStream, 0, len(levels))}
	for _, level := range levels {
		labels := make(map[string]string, len(base)+1)
		for k, v := range base {
			labels[k] = v
		}
		labels["level"] = level

		values := make([][2]string, 0, len(byLevel[level]))
		for _, entry := range byLevel[level] {
			values = append(values, [2]string{
				strconv.FormatInt(entry.Timestamp.UnixNano(), 10),
				entry.Line,
			})
		}
		req.Streams = append(req.Streams, pushStream{Stream: labels, Values: values})
	}
	return req
}

// Push sends one batch. It returns ErrRejected (wrapped) when the batch must be
// dropped and a plain error when it is worth retrying.
func (c *Client) Push(ctx context.Context, base map[string]string, entries []Entry) error {
	if len(entries) == 0 {
		return nil
	}
	body, err := json.Marshal(buildPush(base, entries))
	if err != nil {
		return fmt.Errorf("%w: invalid push body", ErrRejected)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.URL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("%w: invalid request", ErrRejected)
	}
	req.Header.Set("Content-Type", "application/json")

	client, err := c.httpClient()
	if err != nil {
		return privatePushFailure(err)
	}
	resp, err := client.Do(req)
	if err != nil {
		return privatePushFailure(err)
	}
	defer resp.Body.Close()
	// Drain so the connection is reusable; the response body is a short error
	// string at most.
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 2048))

	switch {
	case resp.StatusCode >= 200 && resp.StatusCode < 300:
		return nil
	case resp.StatusCode == http.StatusTooManyRequests, resp.StatusCode >= 500:
		return fmt.Errorf("log push failed: HTTP status %d", resp.StatusCode)
	default:
		return fmt.Errorf("%w: HTTP status %d", ErrRejected, resp.StatusCode)
	}
}

// Backoff bounds how long a retry loop waits between attempts.
type Backoff struct {
	Initial time.Duration
	Max     time.Duration
}

// Next returns the delay after `attempt` consecutive failures (attempt 0 is the
// first retry).
func (b Backoff) Next(attempt int) time.Duration {
	delay := b.Initial
	for i := 0; i < attempt && delay < b.Max; i++ {
		delay *= 2
	}
	if delay > b.Max {
		return b.Max
	}
	return delay
}
