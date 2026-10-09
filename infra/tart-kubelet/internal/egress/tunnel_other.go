//go:build !darwin

package egress

import (
	"context"
	"fmt"
	"log/slog"
)

// RunTunnel is only supported on macOS hosts.
func RunTunnel(context.Context, TunnelConfig, *slog.Logger) error {
	return fmt.Errorf("egress-tunnel is only supported on macOS")
}
