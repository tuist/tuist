package checkout

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"

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

// agentRequest is the JSON the agent reads first on both endpoints; an export
// follows it, after a newline, with its tar stream.
type agentRequest struct {
	PodName string                 `json:"pod_name"`
	Grant   protocol.CheckoutGrant `json:"grant"`
}

func (c *Client) request(ctx context.Context, path string, grant protocol.CheckoutGrant, body io.Reader) (*http.Response, error) {
	head, err := json.Marshal(agentRequest{PodName: c.PodName, Grant: grant})
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
	resp, err := c.request(ctx, "/sandbox-checkout/seed", grant, nil)
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
	resp, err := c.request(ctx, "/sandbox-checkout/export", grant, export)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusAccepted {
		return nil
	}
	return fmt.Errorf("checkout agent answered %d: %s", resp.StatusCode, agentError(resp.Body))
}

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
