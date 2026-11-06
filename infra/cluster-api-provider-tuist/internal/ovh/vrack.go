package ovh

import (
	"context"
	"fmt"
	"net"
	"net/url"
	"slices"
)

// EnsureVRack attaches a single private NIC without changing public interfaces
// or moving an interface out of another vRack. Attachment is asynchronous; the
// caller must wait for a subsequent read to confirm it before configuring Linux.
func (c *Client) EnsureVRack(ctx context.Context, serviceName, vrackID string) (mac string, ready bool, err error) {
	base := "/dedicated/server/" + url.PathEscape(serviceName)
	var macs []string
	if err := c.API.GetWithContext(ctx, base+"/networkInterfaceController?linkType=private", &macs); err != nil {
		return "", false, fmt.Errorf("find private NIC: %w", err)
	}
	if len(macs) != 1 {
		return "", false, fmt.Errorf("%s must have exactly one non-aggregated private NIC, found %d", serviceName, len(macs))
	}
	address, err := net.ParseMAC(macs[0])
	if err != nil || len(address) != 6 {
		return "", false, fmt.Errorf("invalid private NIC MAC %q", macs[0])
	}
	mac = address.String()
	var nic struct {
		VirtualNetworkInterface string `json:"virtualNetworkInterface"`
	}
	if err := c.API.GetWithContext(ctx, base+"/networkInterfaceController/"+url.PathEscape(macs[0]), &nic); err != nil {
		return "", false, err
	}
	vrackPath := "/vrack/" + url.PathEscape(vrackID)
	if nic.VirtualNetworkInterface != "" {
		var vni struct {
			Enabled bool   `json:"enabled"`
			Mode    string `json:"mode"`
			VRack   string `json:"vrack"`
		}
		if err := c.API.GetWithContext(ctx, base+"/virtualNetworkInterface/"+url.PathEscape(nic.VirtualNetworkInterface), &vni); err != nil {
			return "", false, err
		}
		if !vni.Enabled || vni.Mode != "vrack" {
			return "", false, fmt.Errorf("private interface must already be enabled in vrack mode")
		}
		if vni.VRack == vrackID {
			return mac, true, nil
		}
		if vni.VRack != "" {
			return "", false, fmt.Errorf("private interface belongs to %s, refusing to move it to %s", vni.VRack, vrackID)
		}
		return mac, false, c.API.PostWithContext(ctx, vrackPath+"/dedicatedServerInterface",
			map[string]string{"dedicatedServerInterface": nic.VirtualNetworkInterface}, nil)
	}
	// Older dedicated servers attach by service name rather than VNI UUID.
	var networks []string
	if err := c.API.GetWithContext(ctx, base+"/vrack", &networks); err != nil {
		return "", false, err
	}
	if slices.Contains(networks, vrackID) {
		return mac, true, nil
	}
	if len(networks) != 0 {
		return "", false, fmt.Errorf("server belongs to another vRack, refusing to move it to %s", vrackID)
	}
	return mac, false, c.API.PostWithContext(ctx, vrackPath+"/dedicatedServer",
		map[string]string{"dedicatedServer": serviceName}, nil)
}
