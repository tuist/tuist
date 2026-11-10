package redfish

import (
	"context"
	"fmt"
)

const (
	networkProtocolPath = "/redfish/v1/Managers/Self/NetworkProtocol"
	// sidebandPath is the BMC's NC-SI interface. It shares the host's LAN
	// port 2 and takes a DHCP lease of its own there; eth0 is the dedicated
	// management port.
	sidebandPath = "/redfish/v1/Managers/Self/EthernetInterfaces/eth1"
)

// The BMC settings of BMCBaseline.
const (
	SSDP     = "SSDP"
	Sideband = "Sideband"
)

// BMCBaseline is the BMC's own exposure: it announces nothing with SSDP and
// is reachable only on its management port. SNMP is not in it: this BMC
// keeps SNMP on and its versions read-only, and with no community and no
// account enabled for SNMP it answers nothing.
var BMCBaseline = []Setting{
	{Attribute: SSDP, Want: false, What: "SSDP: off"},
	{Attribute: Sideband, Want: false, What: "NC-SI sideband on LAN port 2: off"},
}

// CheckBMC compares the BMC's settings with baseline.
func (c *Client) CheckBMC(ctx context.Context, baseline []Setting) ([]Drift, error) {
	var protocols struct {
		SSDP struct{ ProtocolEnabled bool }
	}
	if err := c.Get(ctx, networkProtocolPath, &protocols); err != nil {
		return nil, err
	}
	var sideband struct{ InterfaceEnabled bool }
	if err := c.Get(ctx, sidebandPath, &sideband); err != nil {
		return nil, err
	}
	have := map[string]any{SSDP: protocols.SSDP.ProtocolEnabled, Sideband: sideband.InterfaceEnabled}
	var drift []Drift
	for _, s := range baseline {
		if fmt.Sprint(have[s.Attribute]) != fmt.Sprint(s.Want) {
			drift = append(drift, Drift{Setting: s, Have: have[s.Attribute]})
		}
	}
	return drift, nil
}

// ApplyBMC writes what drifted from the BMC baseline, one resource at a time:
// the BMC refuses a write that sets a value it already has. It takes the
// sideband down a few seconds after it answers.
func (c *Client) ApplyBMC(ctx context.Context, drift []Drift) error {
	for _, d := range drift {
		var err error
		switch d.Attribute {
		case SSDP:
			err = c.Patch(ctx, networkProtocolPath, map[string]any{"SSDP": map[string]any{"ProtocolEnabled": d.Want}})
		case Sideband:
			err = c.Patch(ctx, sidebandPath, map[string]any{"InterfaceEnabled": d.Want})
		default:
			err = fmt.Errorf("%s is not a BMC setting", d.Attribute)
		}
		if err != nil {
			return err
		}
	}
	return nil
}
