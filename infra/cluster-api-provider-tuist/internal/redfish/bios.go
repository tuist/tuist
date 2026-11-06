package redfish

import (
	"context"
	"fmt"
	"sort"
	"strings"
)

const (
	biosPath        = systemPath + "/Bios"
	biosPendingPath = biosPath + "/SD"
	// mapIDs is the attribute in which the BIOS lists every attribute with
	// :1 when Redfish may set it and :0 when not.
	mapIDs = "MAPIDS"
)

// Attributes are BIOS attributes by name.
type Attributes map[string]any

// BIOS reads the BIOS attributes as of the last POST.
func (c *Client) BIOS(ctx context.Context) (Attributes, error) {
	return c.attributes(ctx, biosPath)
}

// PendingBIOS reads the attributes the BIOS applies at its next POST.
func (c *Client) PendingBIOS(ctx context.Context) (Attributes, error) {
	return c.attributes(ctx, biosPendingPath)
}

func (c *Client) attributes(ctx context.Context, path string) (Attributes, error) {
	var bios struct{ Attributes Attributes }
	if err := c.Get(ctx, path, &bios); err != nil {
		return nil, err
	}
	return bios.Attributes, nil
}

// Writable reports which attributes the BIOS lets Redfish set.
func Writable(attrs Attributes) map[string]bool {
	list, _ := attrs[mapIDs].(string)
	w := map[string]bool{}
	for _, entry := range strings.Split(list, ",") {
		name, flag, ok := strings.Cut(strings.TrimSpace(entry), ":")
		if ok && name != "" {
			w[name] = flag == "1"
		}
	}
	return w
}

// SetBIOS writes attributes to the pending settings, which the BIOS applies at
// its next POST. It refuses an attribute the BIOS does not let Redfish set,
// rather than have the BIOS drop it silently at POST.
func (c *Client) SetBIOS(ctx context.Context, set Attributes) error {
	current, err := c.BIOS(ctx)
	if err != nil {
		return err
	}
	writable := Writable(current)
	var refused []string
	for name := range set {
		if _, known := current[name]; !known || !writable[name] {
			refused = append(refused, name)
		}
	}
	if len(refused) > 0 {
		sort.Strings(refused)
		return fmt.Errorf("the BIOS does not let Redfish set %s", strings.Join(refused, ", "))
	}
	return hostOn(c.Patch(ctx, biosPendingPath, map[string]Attributes{"Attributes": set}))
}

// Setting is one setting a box is expected to have.
type Setting struct {
	// Attribute is the BIOS attribute, or SecureBoot for the Secure Boot
	// resource.
	Attribute string
	Want      any
	// What says, for a person, what the setting is.
	What string
}

// SecureBoot names the Secure Boot setting among Settings: the BIOS does not
// let Redfish write its attribute, so it goes through the SecureBoot
// resource.
const SecureBoot = "SecureBoot"

// Baseline is what the BIOS of a rack x86 server is set to, by the vendor
// before it ships and by Apply when a box is adopted.
var Baseline = []Setting{
	{Attribute: "AridApmLastState", Want: "Power On", What: "Restore AC Power Loss: Power On"},
	{Attribute: "NWSK000", Want: "Enabled", What: "Network Stack: Enabled"},
	{Attribute: "NWSK001", Want: "Enabled", What: "IPv4 PXE Support: Enabled"},
	{Attribute: "NWSK006", Want: "Enabled", What: "IPv4 HTTP Support: Enabled"},
	{Attribute: "TCG001", Want: "Enabled", What: "TPM State: Enabled"},
	{Attribute: "TER002", Want: true, What: "Console Redirection on COM2 (SOL): Enabled"},
	{Attribute: SecureBoot, Want: true, What: "Secure Boot: Enabled, factory keys"},
}

// Drift is a setting whose value differs from the baseline.
type Drift struct {
	Setting
	Have any
}

// Check compares the box's settings as of its last POST with the baseline.
func (c *Client) Check(ctx context.Context, baseline []Setting) ([]Drift, error) {
	attrs, err := c.BIOS(ctx)
	if err != nil {
		return nil, err
	}
	var sb struct{ SecureBootEnable bool }
	if err := c.Get(ctx, secureBootPath, &sb); err != nil {
		return nil, err
	}
	var drift []Drift
	for _, s := range baseline {
		var have any
		if s.Attribute == SecureBoot {
			have = sb.SecureBootEnable
		} else {
			have = attrs[s.Attribute]
		}
		if fmt.Sprint(have) != fmt.Sprint(s.Want) {
			drift = append(drift, Drift{Setting: s, Have: have})
		}
	}
	return drift, nil
}

// Apply writes what drifted from the baseline. The BIOS applies it at its
// next POST, which the caller starts; the host must be off for the BIOS part.
func (c *Client) Apply(ctx context.Context, drift []Drift) error {
	set := Attributes{}
	secureBoot := false
	for _, d := range drift {
		if d.Attribute == SecureBoot {
			secureBoot = true
			continue
		}
		set[d.Attribute] = d.Want
	}
	if len(set) > 0 {
		if err := c.SetBIOS(ctx, set); err != nil {
			return err
		}
	}
	if secureBoot {
		return c.EnableSecureBoot(ctx)
	}
	return nil
}
