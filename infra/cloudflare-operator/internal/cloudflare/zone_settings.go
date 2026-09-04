package cloudflare

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
)

// ZoneSetting is one entry of a zone's per-setting configuration
// (challenge_ttl, ssl, security_level, always_use_https, etc). The
// operator reads and writes settings one at a time by id, which is
// idempotent and requires no client-side state.
type ZoneSetting struct {
	ID         string          `json:"id"`
	Value      json.RawMessage `json:"value"`
	ModifiedOn string          `json:"modified_on,omitempty"`
	Editable   bool            `json:"editable,omitempty"`
}

// GetZoneSetting fetches one setting by id (e.g. "challenge_ttl",
// "ssl"). Returns (nil, nil) when Cloudflare returns 404, which
// happens when a zone's plan does not expose the setting.
func (c *Client) GetZoneSetting(ctx context.Context, zoneID, settingID string) (*ZoneSetting, error) {
	path := fmt.Sprintf("/zones/%s/settings/%s", zoneID, settingID)
	var wrapper struct {
		Result ZoneSetting `json:"result"`
	}
	if _, err := c.do(ctx, http.MethodGet, path, nil, &wrapper); err != nil {
		if IsNotFound(err) {
			return nil, nil
		}
		return nil, err
	}
	return &wrapper.Result, nil
}

// UpdateZoneSetting sets one setting's value. Cloudflare's PATCH
// endpoint expects a body of {"value": <json>}. The value is passed
// through as raw JSON so the caller can hand in numbers, strings, or
// objects without the client caring which one applies to which setting.
func (c *Client) UpdateZoneSetting(ctx context.Context, zoneID, settingID string, value json.RawMessage) (*ZoneSetting, error) {
	path := fmt.Sprintf("/zones/%s/settings/%s", zoneID, settingID)
	body := map[string]json.RawMessage{"value": value}
	var wrapper struct {
		Result ZoneSetting `json:"result"`
	}
	if _, err := c.do(ctx, http.MethodPatch, path, body, &wrapper); err != nil {
		return nil, err
	}
	return &wrapper.Result, nil
}
