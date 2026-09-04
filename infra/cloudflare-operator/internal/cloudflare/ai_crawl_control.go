package cloudflare

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
)

// AICrawlControlConfig is the zone-level AI Crawl Control
// configuration. Cloudflare's public API for this product is newer and
// less stable than the Rulesets API, so the operator sends the config
// through as a raw JSON payload the CRD owner supplies. That way the
// operator does not lock in a schema that shifts under it: the CRD
// carries whatever Cloudflare's API accepts today, and drift-detection
// is a byte-level comparison of what we set against what Cloudflare
// returns.
type AICrawlControlConfig struct {
	// Config is the raw configuration Cloudflare stores. Contents match
	// Cloudflare's AI Crawl Control API body verbatim.
	Config json.RawMessage `json:"config"`
}

// GetAICrawlControl fetches the zone's current AI Crawl Control
// configuration. Endpoint verified at first deploy; if Cloudflare has
// moved it, update the path here (single place).
func (c *Client) GetAICrawlControl(ctx context.Context, zoneID string) (json.RawMessage, error) {
	path := fmt.Sprintf("/zones/%s/ai_crawl_control", zoneID)
	var wrapper struct {
		Result json.RawMessage `json:"result"`
	}
	if _, err := c.do(ctx, http.MethodGet, path, nil, &wrapper); err != nil {
		if IsNotFound(err) {
			return nil, nil
		}
		return nil, err
	}
	return wrapper.Result, nil
}

// UpdateAICrawlControl PUTs the desired AI Crawl Control configuration.
// The operator does not try to interpret the payload; the CRD owner
// is responsible for what goes inside.
func (c *Client) UpdateAICrawlControl(ctx context.Context, zoneID string, config json.RawMessage) (json.RawMessage, error) {
	path := fmt.Sprintf("/zones/%s/ai_crawl_control", zoneID)
	var wrapper struct {
		Result json.RawMessage `json:"result"`
	}
	if _, err := c.do(ctx, http.MethodPut, path, config, &wrapper); err != nil {
		return nil, err
	}
	return wrapper.Result, nil
}
