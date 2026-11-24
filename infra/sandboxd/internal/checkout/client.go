package checkout

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// Client reaches the node's runner-cache agent through its node-local Service.
// The agent authorizes the daemon by its Pod: PodName must be this daemon's,
// and the request must come from that Pod's address.
type Client struct {
	// URL is the agent's base URL, e.g. http://runner-cache-volumes.tuist-runners.svc.cluster.local:8090.
	URL     string
	PodName string
	HTTP    *http.Client
}

// NewHTTPClient bounds connecting and the agent's first answer; the transfers
// themselves are bounded by their contexts.
func NewHTTPClient() *http.Client {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	transport.DialContext = (&net.Dialer{Timeout: 5 * time.Second}).DialContext
	transport.ResponseHeaderTimeout = time.Minute
	return &http.Client{Transport: transport}
}

// agentRequest is the JSON the agent reads first on every endpoint; an export
// follows it, after a newline, with its tar stream.
type agentRequest struct {
	PodName string  `json:"pod_name"`
	Grant   any     `json:"grant"`
	Held    []int64 `json:"held,omitempty"`
}

func (c *Client) request(ctx context.Context, path string, grant any, held []int64, body io.Reader) (*http.Response, error) {
	head, err := json.Marshal(agentRequest{PodName: c.PodName, Grant: grant, Held: held})
	if err != nil {
		return nil, err
	}
	payload := io.Reader(bytes.NewReader(head))
	if body != nil {
		payload = io.MultiReader(bytes.NewReader(append(head, '\n')), body)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimSuffix(c.URL, "/")+path, payload)
	if err != nil {
		return nil, err
	}
	if body == nil {
		req.Header.Set("Content-Type", "application/json")
	} else {
		req.Header.Set("Content-Type", "application/octet-stream")
	}
	client := c.HTTP
	if client == nil {
		client = NewHTTPClient()
	}
	return client.Do(req)
}

func (c *Client) Seed(ctx context.Context, grant protocol.CheckoutGrant) (io.ReadCloser, error) {
	resp, err := c.request(ctx, "/sandbox-checkout/seed", grant, nil, nil)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode == http.StatusOK {
		return resp.Body, nil
	}
	defer resp.Body.Close()
	reason := agentError(resp.Body)
	if resp.StatusCode == http.StatusNotFound && reason == "cold" {
		return nil, ErrCold
	}
	return nil, fmt.Errorf("checkout agent answered %d: %s", resp.StatusCode, reason)
}

func (c *Client) Export(ctx context.Context, grant protocol.CheckoutGrant, export io.Reader) error {
	resp, err := c.request(ctx, "/sandbox-checkout/export", grant, nil, export)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusAccepted {
		return nil
	}
	return fmt.Errorf("checkout agent answered %d: %s", resp.StatusCode, agentError(resp.Body))
}

// CacheImage copies the master the node's agent lends for a saved cache volume
// head into dst, which must not exist, as a sparse file of at most maxBytes,
// and returns its generation: the head's, or an older one of its lineage when
// the node keeps only that. When the agent would lend a generation in held it
// copies nothing and answers false. ErrCold means the node holds no master of
// the lineage.
func (c *Client) CacheImage(ctx context.Context, grant protocol.CacheGrant, held []int64, dst string, maxBytes int64) (int64, bool, error) {
	resp, err := c.request(ctx, "/sandbox-cache/image", grant, held, nil)
	if err != nil {
		return 0, false, err
	}
	defer resp.Body.Close()
	// An agent older than the header lends only the head itself.
	generation := grant.BaseGeneration
	if header := resp.Header.Get(cacheGenerationHeader); header != "" {
		if generation, err = strconv.ParseInt(header, 10, 64); err != nil {
			return 0, false, fmt.Errorf("runner-cache agent named generation %q", header)
		}
	}
	switch resp.StatusCode {
	case http.StatusOK:
		return generation, true, cachevolumes.ReceiveImage(ctx, resp.Body, dst, maxBytes)
	case http.StatusNoContent:
		return generation, false, nil
	}
	reason := agentError(resp.Body)
	if resp.StatusCode == http.StatusNotFound && reason == "cold" {
		return 0, false, ErrCold
	}
	return 0, false, fmt.Errorf("runner-cache agent answered %d: %s", resp.StatusCode, reason)
}

// cacheGenerationHeader names the generation the agent lent (the agent's
// sandboxCacheGeneration).
const cacheGenerationHeader = "Tuist-Cache-Generation"

func agentError(body io.Reader) string {
	var answer struct {
		Error string `json:"error"`
	}
	if json.NewDecoder(io.LimitReader(body, 4096)).Decode(&answer) != nil || answer.Error == "" {
		return "unknown"
	}
	if len(answer.Error) > 200 {
		return answer.Error[:200]
	}
	return answer.Error
}
