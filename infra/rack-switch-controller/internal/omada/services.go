package omada

// The site-wide services, measured on 6.3.0.45: LLDP is nested as
// {"lldp": {"enable": ...}}, and SNMP is switched by snmpV1V2CEnable and
// snmpV3Enable beside its location and contact. SNMP is read-modify-write of
// the object the controller returns, so a field this file does not name is
// sent back as it was read.

import (
	"context"
	"net/http"
	"strings"
)

// LLDPEnabled is whether the site runs LLDP.
func (c *Client) LLDPEnabled(ctx context.Context, siteID string) (bool, error) {
	var setting struct {
		LLDP struct {
			Enable bool `json:"enable"`
		} `json:"lldp"`
	}
	err := c.call(ctx, http.MethodGet, sitePath(siteID, "/lldp"), nil, &setting)
	return setting.LLDP.Enable, err
}

// SetLLDP turns the site's LLDP on or off.
func (c *Client) SetLLDP(ctx context.Context, siteID string, enabled bool) error {
	body := map[string]any{"lldp": map[string]any{"enable": enabled}}
	return c.call(ctx, http.MethodPatch, sitePath(siteID, "/lldp"), body, nil)
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
