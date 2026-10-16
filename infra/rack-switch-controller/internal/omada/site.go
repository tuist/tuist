package omada

import (
	"context"
	"fmt"
	"net/http"
	"strings"
)

// Login is a switch login: the site's device account, or a switch's own.
type Login struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type site struct {
	Name   string `json:"name"`
	SiteID string `json:"siteId"`
}

// SiteID is the id of the site with this name.
func (c *Client) SiteID(ctx context.Context, name string) (string, error) {
	sites, err := list[site](ctx, c, "/sites")
	if err != nil {
		return "", err
	}
	names := make([]string, 0, len(sites))
	for _, s := range sites {
		if s.Name == name {
			return s.SiteID, nil
		}
		names = append(names, s.Name)
	}
	return "", fmt.Errorf("the controller has no site named %q; it has: %s", name, strings.Join(names, ", "))
}

// DeviceHost is the address the controller tells adopted switches to connect
// back to, or "" when it advertises none.
func (c *Client) DeviceHost(ctx context.Context) (string, error) {
	var general struct {
		DeviceManage struct {
			DeviceHostEnable bool   `json:"deviceHostEnable"`
			DeviceHost       string `json:"deviceHost"`
		} `json:"deviceManage"`
	}
	if err := c.call(ctx, http.MethodGet, "/controller/setting/general", nil, &general); err != nil {
		return "", err
	}
	if !general.DeviceManage.DeviceHostEnable {
		return "", nil
	}
	return general.DeviceManage.DeviceHost, nil
}

// SetDeviceHost makes the controller advertise address for device management.
func (c *Client) SetDeviceHost(ctx context.Context, address string) error {
	body := map[string]any{"deviceManage": map[string]any{"deviceHostEnable": true, "deviceHost": address}}
	return c.call(ctx, http.MethodPatch, "/controller/setting/general", body, nil)
}

// SiteSSH is the site's SSH setting, which the controller pushes to every
// switch it adopts.
func (c *Client) SiteSSH(ctx context.Context, siteID string) (map[string]any, error) {
	var setting map[string]any
	if err := c.call(ctx, http.MethodGet, sitePath(siteID, "/ssh"), nil, &setting); err != nil {
		return nil, err
	}
	return setting, nil
}

// SetSiteSSH replaces the site's SSH setting.
func (c *Client) SetSiteSSH(ctx context.Context, siteID string, setting map[string]any) error {
	return c.call(ctx, http.MethodPut, sitePath(siteID, "/ssh"), setting, nil)
}

// DeviceAccount is the login the controller gives every switch it adopts in
// the site.
func (c *Client) DeviceAccount(ctx context.Context, siteID string) (Login, error) {
	var login Login
	err := c.call(ctx, http.MethodGet, sitePath(siteID, "/device-account"), nil, &login)
	return login, err
}

// SetDeviceAccount replaces the site's device account, which replaces the
// login of every switch adopted in the site.
func (c *Client) SetDeviceAccount(ctx context.Context, siteID string, login Login) error {
	return c.call(ctx, http.MethodPut, sitePath(siteID, "/device-account"), login, nil)
}
