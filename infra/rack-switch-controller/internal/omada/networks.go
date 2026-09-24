package omada

import (
	"context"
	"net/http"
)

// LANNetwork is a site network. The site's management network is "Default",
// VLAN 1, purpose 1.
type LANNetwork struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	VLAN        int    `json:"vlan"`
	Purpose     int    `json:"purpose"`
	Application int    `json:"application"`
}

// LANProfile is a port profile. A port follows its profile unless it
// overrides it. The controller's defaults are "All", "Default" and
// "Disable"; "All" carries every site network tagged although its
// tagNetworkIds is empty.
type LANProfile struct {
	ID                 string   `json:"id"`
	Name               string   `json:"name"`
	NativeNetworkID    string   `json:"nativeNetworkId"`
	TagNetworkIDs      []string `json:"tagNetworkIds"`
	UntagNetworkIDs    []string `json:"untagNetworkIds"`
	SpanningTreeEnable bool     `json:"spanningTreeEnable"`
}

// ProfileAll is the default profile, which carries every site network.
const ProfileAll = "All"

// LANNetworks lists the site's networks.
func (c *Client) LANNetworks(ctx context.Context, siteID string) ([]LANNetwork, error) {
	return list[LANNetwork](ctx, c, sitePath(siteID, "/lan-networks"))
}

// CreateLANNetwork adds a VLAN to the site and returns its network id. Every
// port whose profile is "All" then carries it tagged.
func (c *Client) CreateLANNetwork(ctx context.Context, siteID, name string, vlan int) (string, error) {
	body := map[string]any{"name": name, "purpose": 0, "vlan": vlan, "igmpSnoopEnable": false, "application": 1}
	var created struct {
		ID string `json:"id"`
	}
	err := c.call(ctx, http.MethodPost, sitePath(siteID, "/lan-networks"), body, &created)
	return created.ID, err
}

// LANProfiles lists the site's port profiles.
func (c *Client) LANProfiles(ctx context.Context, siteID string) ([]LANProfile, error) {
	return list[LANProfile](ctx, c, sitePath(siteID, "/lan-profiles"))
}
