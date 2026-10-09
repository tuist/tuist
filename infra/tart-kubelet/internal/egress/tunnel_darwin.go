//go:build darwin

package egress

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"strconv"

	"golang.zx2c4.com/wireguard/conn"
	wgdevice "golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
)

// RunTunnel keeps one gateway's tunnel up until ctx is cancelled. It must run
// as root to create the utun.
func RunTunnel(ctx context.Context, c TunnelConfig, logger *slog.Logger) error {
	if err := c.Validate(); err != nil {
		return err
	}
	if os.Geteuid() != 0 {
		return fmt.Errorf("egress-tunnel must run as root")
	}
	if err := os.MkdirAll(c.StatusDir, 0o755); err != nil {
		return err
	}
	private, err := EnsureHostKey(c.StateDir)
	if err != nil {
		return fmt.Errorf("host key: %w", err)
	}
	config, err := deviceConfig(private, c)
	if err != nil {
		return err
	}

	name := InterfaceName(c.Index)
	tunDevice, err := tun.CreateTUN(name, MTU)
	if err != nil {
		return fmt.Errorf("create %s: %w", name, err)
	}
	if actual, err := tunDevice.Name(); err != nil || actual != name {
		_ = tunDevice.Close()
		return fmt.Errorf("created %q, want %q: %v", actual, name, err)
	}

	dev := wgdevice.NewDevice(tunDevice, conn.NewDefaultBind(), wgdevice.NewLogger(wgdevice.LogLevelError, "("+c.Gateway+") "))
	defer dev.Close()
	if err := dev.IpcSet(config); err != nil {
		return fmt.Errorf("configure %s: %w", name, err)
	}
	if err := dev.Up(); err != nil {
		return fmt.Errorf("bring up %s: %w", name, err)
	}

	local, gateway := TunnelAddresses(c.Index)
	ifconfig := exec.CommandContext(ctx, "/sbin/ifconfig", name, "inet", local, gateway,
		"netmask", "255.255.255.255", "mtu", strconv.Itoa(MTU), "up")
	if out, err := ifconfig.CombinedOutput(); err != nil {
		return fmt.Errorf("address %s: %w: %s", name, err, out)
	}
	logger.Info("tunnel up", "gateway", c.Gateway, "interface", name, "endpoint", c.Endpoint)

	statusLoop(ctx, c, dev, httpProbe(c.Index), logger)
	return nil
}
