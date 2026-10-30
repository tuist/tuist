package redfish

import (
	"context"
	"fmt"
	"sort"
	"strings"
)

const (
	systemPath     = "/redfish/v1/Systems/Self"
	managerPath    = "/redfish/v1/Managers/Self"
	secureBootPath = systemPath + "/SecureBoot"
)

// Inventory is what a box is, as its BMC reports it.
type Inventory struct {
	Manufacturer string `json:"manufacturer"`
	Model        string `json:"model"`
	Serial       string `json:"serial"`
	// UUID is the SMBIOS system UUID, lowercased: the name the box's
	// RackLinuxHost takes.
	UUID        string `json:"uuid"`
	BIOSVersion string `json:"biosVersion"`
	BMCVersion  string `json:"bmcVersion"`
	PowerState  string `json:"powerState"`
	// SecureBoot is whether Secure Boot is set to be on, and SecureBootActive
	// whether the last boot ran with it.
	SecureBoot       bool `json:"secureBoot"`
	SecureBootActive bool `json:"secureBootActive"`
	// TPM is the TPM's interface type, empty without one.
	TPM string `json:"tpm,omitempty"`
	// BMCMAC is the BMC's dedicated management port.
	BMCMAC string `json:"bmcMAC"`
	// NICs are the host's network ports, in the BMC's order.
	NICs []NIC `json:"nics"`
}

// NIC is one of the host's network ports.
type NIC struct {
	Name string `json:"name"`
	MAC  string `json:"mac"`
	Link bool   `json:"link"`
}

type members struct {
	Members []struct {
		ID string `json:"@odata.id"`
	}
}

// Inventory reads what the box is.
func (c *Client) Inventory(ctx context.Context) (Inventory, error) {
	var sys struct {
		Manufacturer, Model, SerialNumber, UUID, BiosVersion, PowerState string
		TrustedModules                                                   []struct {
			InterfaceType string
			Status        struct{ State string }
		}
	}
	if err := c.Get(ctx, systemPath, &sys); err != nil {
		return Inventory{}, err
	}
	inv := Inventory{
		Manufacturer: strings.TrimSpace(sys.Manufacturer),
		Model:        strings.TrimSpace(sys.Model),
		Serial:       strings.TrimSpace(sys.SerialNumber),
		UUID:         strings.ToLower(sys.UUID),
		BIOSVersion:  sys.BiosVersion,
		PowerState:   sys.PowerState,
	}
	// The BMC lists one module several times over.
	for _, m := range sys.TrustedModules {
		if m.Status.State == "Enabled" {
			inv.TPM = m.InterfaceType
			break
		}
	}
	var sb struct {
		SecureBootEnable      bool
		SecureBootCurrentBoot string
	}
	if err := c.Get(ctx, secureBootPath, &sb); err != nil {
		return Inventory{}, err
	}
	inv.SecureBoot, inv.SecureBootActive = sb.SecureBootEnable, sb.SecureBootCurrentBoot == "Enabled"
	var mgr struct{ FirmwareVersion string }
	if err := c.Get(ctx, managerPath, &mgr); err != nil {
		return Inventory{}, err
	}
	inv.BMCVersion = mgr.FirmwareVersion

	nics, err := c.ethernet(ctx, systemPath+"/EthernetInterfaces")
	if err != nil {
		return Inventory{}, err
	}
	inv.NICs = nics
	bmc, err := c.ethernet(ctx, managerPath+"/EthernetInterfaces")
	if err != nil {
		return Inventory{}, err
	}
	for _, n := range bmc {
		if n.Name == "eth0" {
			inv.BMCMAC = n.MAC
		}
	}
	return inv, nil
}

func (c *Client) ethernet(ctx context.Context, collection string) ([]NIC, error) {
	var list members
	if err := c.Get(ctx, collection, &list); err != nil {
		return nil, err
	}
	var nics []NIC
	for _, m := range list.Members {
		var e struct {
			ID, Name, MACAddress, LinkStatus string
		}
		if err := c.Get(ctx, m.ID, &e); err != nil {
			return nil, err
		}
		if e.MACAddress == "" {
			continue
		}
		nics = append(nics, NIC{Name: e.ID, MAC: strings.ToLower(e.MACAddress), Link: e.LinkStatus == "LinkUp"})
	}
	sort.SliceStable(nics, func(i, j int) bool { return nics[i].Name < nics[j].Name })
	return nics, nil
}

// Reset types the BMC takes. It has no PowerCycle: a cycle is ForceOff, then
// On.
const (
	ResetOn               = "On"
	ResetForceOff         = "ForceOff"
	ResetForceRestart     = "ForceRestart"
	ResetGracefulShutdown = "GracefulShutdown"
)

// Reset powers the host on, off or restarts it.
func (c *Client) Reset(ctx context.Context, resetType string) error {
	switch resetType {
	case ResetOn, ResetForceOff, ResetForceRestart, ResetGracefulShutdown:
	default:
		return fmt.Errorf("reset type %q is not one the BMC takes", resetType)
	}
	return c.Post(ctx, systemPath+"/Actions/ComputerSystem.Reset", map[string]string{"ResetType": resetType})
}

// PowerState reads whether the host is On or Off.
func (c *Client) PowerState(ctx context.Context) (string, error) {
	var sys struct{ PowerState string }
	err := c.Get(ctx, systemPath, &sys)
	return sys.PowerState, err
}

// Boot targets for BootOnce.
const (
	BootCd   = "Cd"
	BootPxe  = "Pxe"
	BootHdd  = "Hdd"
	BootHTTP = "UefiHttp"
)

// BootOnce makes the host's next boot, and only that one, a UEFI boot from
// target. It takes effect at the next reset.
func (c *Client) BootOnce(ctx context.Context, target string) error {
	switch target {
	case BootCd, BootPxe, BootHdd, BootHTTP:
	default:
		return fmt.Errorf("boot target %q is not one this client sets", target)
	}
	return hostOn(c.Patch(ctx, systemPath+"/SD", map[string]any{"Boot": map[string]string{
		"BootSourceOverrideEnabled": "Once",
		"BootSourceOverrideMode":    "UEFI",
		"BootSourceOverrideTarget":  target,
	}}))
}

// EnableSecureBoot sets Secure Boot on with the keys the firmware holds. It
// takes effect at the next boot.
func (c *Client) EnableSecureBoot(ctx context.Context) error {
	return c.Patch(ctx, secureBootPath, map[string]bool{"SecureBootEnable": true})
}
