package omada

import (
	"context"
	"fmt"
	"net/http"
	"strings"
)

// Device status.
const (
	StatusDisconnected    = 0
	StatusConnected       = 1
	StatusPending         = 2
	StatusHeartbeatMissed = 3
	StatusIsolated        = 4
)

// Device detailStatus values the adoption flow reads.
const (
	DetailAdoptionFailed  = 24
	DetailManagedByOthers = 26
)

// Device is a device in a site as the controller lists it, pending ones
// included.
type Device struct {
	// Upper case and dash separated, A8-29-48-FE-B4-BE.
	MAC          string `json:"mac"`
	IP           string `json:"ip"`
	Model        string `json:"model"`
	Name         string `json:"name"`
	Status       int    `json:"status"`
	DetailStatus *int   `json:"detailStatus"`
}

// Detail is the device's detailStatus, or -1 when the controller gives none.
func (d Device) Detail() int {
	if d.DetailStatus == nil {
		return -1
	}
	return *d.DetailStatus
}

// State names the device's state: its detailStatus, or its status when the
// controller gives no detail.
func (d Device) State() string {
	if d.DetailStatus != nil {
		switch *d.DetailStatus {
		case 0:
			return "disconnected"
		case 1:
			return "disconnected (migrating)"
		case 10:
			return "provisioning"
		case 11:
			return "configuring"
		case 12:
			return "upgrading"
		case 13:
			return "rebooting"
		case 14:
			return "connected"
		case 16:
			return "connected (migrating)"
		case 20:
			return "pending"
		case 22:
			return "adopting"
		case 24:
			return "adoption failed"
		case 26:
			return "managed by another controller"
		case 30:
			return "heartbeat missed"
		case 40:
			return "isolated"
		default:
			return fmt.Sprintf("status %d", *d.DetailStatus)
		}
	}
	switch d.Status {
	case StatusDisconnected:
		return "disconnected"
	case StatusConnected:
		return "connected"
	case StatusPending:
		return "pending"
	case StatusHeartbeatMissed:
		return "heartbeat missed"
	case StatusIsolated:
		return "isolated"
	default:
		return fmt.Sprintf("status %d", d.Status)
	}
}

// ControllerMAC is a MAC as the controller writes it: upper case with
// dashes.
func ControllerMAC(mac string) string {
	return strings.ToUpper(strings.ReplaceAll(mac, ":", "-"))
}

// Devices lists the site's devices, pending ones included.
func (c *Client) Devices(ctx context.Context, siteID string) ([]Device, error) {
	return list[Device](ctx, c, sitePath(siteID, "/devices"))
}

// PendingDevices lists the devices waiting to be adopted into the site.
func (c *Client) PendingDevices(ctx context.Context, siteID string) ([]Device, error) {
	return list[Device](ctx, c, sitePath(siteID, "/grid/devices/pending"))
}

// StartAdopt asks the controller to adopt a pending device with the login it
// has now. Adoption takes up to a minute; watch Devices for the outcome.
func (c *Client) StartAdopt(ctx context.Context, siteID, mac string, login Login) error {
	return c.call(ctx, http.MethodPost, sitePath(siteID, "/devices/"+ControllerMAC(mac)+"/start-adopt"), login, nil)
}
