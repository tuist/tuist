package omada

import (
	"context"
	"fmt"
	"net/http"
	"time"
)

// HealthDimension is one dimension of a device's health detail. A model without
// the sensor reports Support false and no average.
type HealthDimension struct {
	Support bool `json:"support"`
	Average *int `json:"averageNum"`
}

// SwitchHealth is the part of a switch's health detail the telemetry reads.
type SwitchHealth struct {
	Temperature HealthDimension `json:"temperature"`
}

// SwitchHealth is the switch's health averaged over [start, end].
func (c *Client) SwitchHealth(ctx context.Context, siteID, mac string, start, end time.Time) (SwitchHealth, error) {
	var health SwitchHealth
	rest := fmt.Sprintf("/health/detail?start=%d&end=%d", start.UnixMilli(), end.UnixMilli())
	err := c.call(ctx, http.MethodGet, switchPath(siteID, mac, rest), nil, &health)
	return health, err
}

// Optic is the digital diagnostics of the transceiver in one port. The
// controller documents the temperature in Celsius.
type Optic struct {
	Port        int      `json:"port"`
	Temperature *float64 `json:"temperature"`
}

// SwitchOptics lists the digital diagnostics of the switch's transceivers.
func (c *Client) SwitchOptics(ctx context.Context, siteID, mac string) ([]Optic, error) {
	var optics []Optic
	err := c.call(ctx, http.MethodGet, switchPath(siteID, mac, "/ddm/info"), nil, &optics)
	return optics, err
}
