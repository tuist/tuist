package omada

import (
	"context"
	"fmt"
	"net/http"
)

// Port is one entry of a switch's portList. The list does not echo a port's
// VLAN or spanning-tree override, only whether it has one.
type Port struct {
	Port                  int    `json:"port"`
	Name                  string `json:"name"`
	ProfileID             string `json:"profileId"`
	ProfileName           string `json:"profileName"`
	ProfileOverrideEnable bool   `json:"profileOverrideEnable"`
	LAGPort               bool   `json:"lagPort"`
	LAGID                 *int   `json:"lagId"`
	Status                int    `json:"status"`
}

// Spanning-tree modes as the loopback block encodes them.
const (
	STPOff  = 0
	STPSTP  = 1
	STPRSTP = 2
	STPMSTP = 3
)

// Loopback is a switch's loopback-detection and spanning-tree block. The
// controller replaces it whole and cannot return it for a standalone switch.
type Loopback struct {
	LoopbackDetectEnable bool `json:"loopbackDetectEnable"`
	STP                  int  `json:"stp"`
	Priority             int  `json:"priority"`
	HelloTime            int  `json:"helloTime"`
	MaxAge               int  `json:"maxAge"`
	ForwardDelay         int  `json:"forwardDelay"`
	TxHoldCount          int  `json:"txHoldCount"`
}

// DefaultLoopback is the block rack:omada apply writes: loop detection on, as
// the controller itself sets it, and the firmware's spanning-tree defaults,
// since the render sets none of the timers.
func DefaultLoopback(stp int) Loopback {
	return Loopback{
		LoopbackDetectEnable: true,
		STP:                  stp,
		Priority:             32768,
		HelloTime:            2,
		MaxAge:               20,
		ForwardDelay:         15,
		TxHoldCount:          5,
	}
}

// PortVLANs is the VLAN membership a port carries in place of its profile's.
type PortVLANs struct {
	NativeNetworkID  string
	TaggedNetworkIDs []string
}

// PortOverride is what a port carries in place of its profile's. A nil field
// follows the profile.
type PortOverride struct {
	VLANs        *PortVLANs
	SpanningTree *bool
}

// LACP is the only aggregation the controller accepted on an SX3832: a static
// LAG (lagType 1), or none given, answered "General error".
const lagTypeLACP = 2

func switchPath(siteID, mac, rest string) string {
	return sitePath(siteID, "/switches/"+ControllerMAC(mac)+rest)
}

// SwitchName is the switch's hostname.
func (c *Client) SwitchName(ctx context.Context, siteID, mac string) (string, error) {
	var general struct {
		Name string `json:"name"`
	}
	err := c.call(ctx, http.MethodGet, switchPath(siteID, mac, "/general-config"), nil, &general)
	return general.Name, err
}

// SetSwitchName sets the switch's hostname.
func (c *Client) SetSwitchName(ctx context.Context, siteID, mac, name string) error {
	return c.call(ctx, http.MethodPatch, switchPath(siteID, mac, "/general-config"), map[string]string{"name": name}, nil)
}

// SwitchPorts is the switch's portList.
func (c *Client) SwitchPorts(ctx context.Context, siteID, mac string) ([]Port, error) {
	var detail struct {
		PortList []Port `json:"portList"`
	}
	err := c.call(ctx, http.MethodGet, switchPath(siteID, mac, ""), nil, &detail)
	return detail.PortList, err
}

func portPath(siteID, mac string, port int) string {
	return switchPath(siteID, mac, fmt.Sprintf("/ports/%d", port))
}

// SetPortName sets a port's description. The controller takes a change to
// one port only with that port's current profileId.
func (c *Client) SetPortName(ctx context.Context, siteID, mac string, port Port, name string) error {
	body := map[string]any{"name": name, "profileId": port.ProfileID}
	return c.call(ctx, http.MethodPatch, portPath(siteID, mac, port.Port), body, nil)
}

// SetLoopback replaces the switch's loopback and spanning-tree block.
func (c *Client) SetLoopback(ctx context.Context, siteID, mac string, loopback Loopback) error {
	return c.call(ctx, http.MethodPut, switchPath(siteID, mac, "/config/loopback"), loopback, nil)
}

// OverridePort gives a port its own VLAN membership, spanning-tree setting or
// both in place of its profile's. name is the port's description, which the
// controller wants on every change to a port.
func (c *Client) OverridePort(ctx context.Context, siteID, mac string, port Port, name string, override PortOverride) error {
	body := map[string]any{"name": name, "profileId": port.ProfileID, "profileOverrideEnable": true}
	if v := override.VLANs; v != nil {
		tagged := v.TaggedNetworkIDs
		if tagged == nil {
			tagged = []string{}
		}
		body["profileVlanOverrideEnable"] = true
		body["nativeNetworkId"] = v.NativeNetworkID
		body["networkTagsSetting"] = 2
		body["tagNetworkIds"] = tagged
		body["untagNetworkIds"] = []string{}
	}
	if override.SpanningTree != nil {
		body["spanningTreeEnable"] = *override.SpanningTree
	}
	return c.call(ctx, http.MethodPatch, portPath(siteID, mac, port.Port), body, nil)
}

// FollowProfile returns a port to its profile. profileVlanOverrideEnable is
// left out: the controller refuses it false on a port whose profile is "All".
func (c *Client) FollowProfile(ctx context.Context, siteID, mac string, port Port, name string) error {
	body := map[string]any{"name": name, "profileId": port.ProfileID, "profileOverrideEnable": false}
	return c.call(ctx, http.MethodPatch, portPath(siteID, mac, port.Port), body, nil)
}

// CreateLAG aggregates ports into an LACP group, through the port endpoint of
// its first member. Its members then carry name as their description, and
// cannot be changed through the port endpoint until the group is deleted.
func (c *Client) CreateLAG(ctx context.Context, siteID, mac string, first Port, name string, lagID int, ports []int) error {
	body := map[string]any{
		"name":                  name,
		"profileId":             first.ProfileID,
		"profileOverrideEnable": false,
		"operation":             "aggregating",
		"lagSetting":            map[string]any{"lagId": lagID, "ports": ports, "lagType": lagTypeLACP},
	}
	return c.call(ctx, http.MethodPatch, portPath(siteID, mac, first.Port), body, nil)
}

// DeleteLAG deletes a link aggregation group; its members return to their
// own "Port<n>" descriptions.
func (c *Client) DeleteLAG(ctx context.Context, siteID, mac string, lagID int) error {
	return c.call(ctx, http.MethodDelete, switchPath(siteID, mac, fmt.Sprintf("/lags/%d", lagID)), nil, nil)
}
