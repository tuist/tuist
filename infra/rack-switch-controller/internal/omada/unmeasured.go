package omada

// Calls in this file follow the controller's API document and have not met
// hardware: the paths exist on 6.3.0.45, the field names are unconfirmed.
// Each is read-modify-write of the object the controller returns, so a field
// this file does not name is sent back as it was read.

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

// LLDPEnableField is the field of the site's LLDP setting that switches it.
const LLDPEnableField = "enable"

// LLDP is the site's LLDP setting.
func (c *Client) LLDP(ctx context.Context, siteID string) (map[string]any, error) {
	var setting map[string]any
	err := c.call(ctx, http.MethodGet, sitePath(siteID, "/lldp"), nil, &setting)
	return setting, err
}

// SetLLDP writes the site's LLDP setting.
func (c *Client) SetLLDP(ctx context.Context, siteID string, setting map[string]any) error {
	return c.call(ctx, http.MethodPatch, sitePath(siteID, "/lldp"), setting, nil)
}

// SNMP is the site's SNMP service setting.
func (c *Client) SNMP(ctx context.Context, siteID string) (map[string]any, error) {
	var setting map[string]any
	err := c.call(ctx, http.MethodGet, sitePath(siteID, "/setting/service/snmp"), nil, &setting)
	return setting, err
}

// SetSNMP writes the site's SNMP service setting.
func (c *Client) SetSNMP(ctx context.Context, siteID string, setting map[string]any) error {
	return c.call(ctx, http.MethodPatch, sitePath(siteID, "/setting/service/snmp"), setting, nil)
}

// SNMPEnableFields are the boolean fields of an SNMP setting that switch a
// version of the service on: every top-level boolean whose name ends in
// "Enable", or is "enable".
func SNMPEnableFields(setting map[string]any) []string {
	var fields []string
	for key, value := range setting {
		if _, ok := value.(bool); !ok {
			continue
		}
		if key == "enable" || strings.HasSuffix(key, "Enable") {
			fields = append(fields, key)
		}
	}
	return fields
}

// SwitchNetworks is the switch's per-network interface list, one entry per
// site network it carries, with its address on that network.
func (c *Client) SwitchNetworks(ctx context.Context, siteID, mac string) ([]map[string]any, error) {
	var raw json.RawMessage
	if err := c.call(ctx, http.MethodGet, switchPath(siteID, mac, "/networks"), nil, &raw); err != nil {
		return nil, err
	}
	var entries []map[string]any
	if err := json.Unmarshal(raw, &entries); err == nil {
		return entries, nil
	}
	var paged struct {
		Data []map[string]any `json:"data"`
	}
	if err := json.Unmarshal(raw, &paged); err != nil {
		return nil, fmt.Errorf("GET switch networks: unrecognised result: %w", err)
	}
	return paged.Data, nil
}

// SetSwitchNetwork writes the switch's interface on one site network.
func (c *Client) SetSwitchNetwork(ctx context.Context, siteID, mac, networkID string, entry map[string]any) error {
	return c.call(ctx, http.MethodPost, switchPath(siteID, mac, "/networks/"+networkID), entry, nil)
}
