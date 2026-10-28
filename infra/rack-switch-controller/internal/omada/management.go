package omada

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
)

// Management interface address modes.
const (
	IPModeStatic = 0
	IPModeDHCP   = 1
)

// ManagementIP is the IPv4 block of a switch's interface on a network.
type ManagementIP struct {
	Mode         int    `json:"mode"`
	IP           string `json:"ip"`
	Netmask      string `json:"netmask"`
	Gateway      string `json:"gateway"`
	Fallback     bool   `json:"fallback"`
	FallbackIP   string `json:"fallbackIp"`
	FallbackMask string `json:"fallbackMask"`
}

// StaticIP is a static address block. The controller refuses the block
// without the fallback fields; these are the switch's factory fallback,
// switched off.
func StaticIP(address, netmask, gateway string) ManagementIP {
	return ManagementIP{
		Mode:         IPModeStatic,
		IP:           address,
		Netmask:      netmask,
		Gateway:      gateway,
		Fallback:     false,
		FallbackIP:   "192.168.0.1",
		FallbackMask: "255.255.255.0",
	}
}

// SwitchNetwork is one of a switch's interfaces as the controller returns it:
// {id, vlan, mvlan, name, ip, ipv6Enable, ipv6, mode, status}. It is kept as
// read, so a write sends back every field it does not change.
type SwitchNetwork map[string]any

// ID is the interface's id, which a write is addressed to.
func (n SwitchNetwork) ID() string {
	id, _ := n["id"].(string)
	return id
}

// Management is whether this is the switch's management interface.
func (n SwitchNetwork) Management() bool {
	mvlan, _ := n["mvlan"].(bool)
	return mvlan
}

// VLAN is the interface's VLAN.
func (n SwitchNetwork) VLAN() int {
	vlan, _ := n["vlan"].(float64)
	return int(vlan)
}

// IP is the interface's IPv4 block.
func (n SwitchNetwork) IP() ManagementIP {
	var ip ManagementIP
	raw, _ := json.Marshal(n["ip"])
	_ = json.Unmarshal(raw, &ip)
	return ip
}

// SwitchNetworks lists the switch's interfaces, the management one carrying
// mvlan true.
func (c *Client) SwitchNetworks(ctx context.Context, siteID, mac string) ([]SwitchNetwork, error) {
	return listPages[SwitchNetwork](ctx, c, switchPath(siteID, mac, "/networks"), 20)
}

// SetInterfaceIP writes an interface's IPv4 block. The rest of the interface
// goes back as it was read, less its status. The switch keeps its connection
// to the controller across the change when the gateway is its path to it.
func (c *Client) SetInterfaceIP(ctx context.Context, siteID, mac string, network SwitchNetwork, ip ManagementIP) error {
	if network.ID() == "" {
		return fmt.Errorf("the switch's interface on VLAN %d carries no id", network.VLAN())
	}
	body := make(map[string]any, len(network))
	for k, v := range network {
		body[k] = v
	}
	delete(body, "status")
	body["ip"] = ip
	return c.call(ctx, http.MethodPost, switchPath(siteID, mac, "/networks/"+network.ID()), body, nil)
}
