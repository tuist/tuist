package egress

import (
	"bufio"
	"context"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// TunnelConfig configures the daemon that keeps one gateway's tunnel up.
type TunnelConfig struct {
	Gateway          string
	Index            int
	Endpoint         string
	GatewayPublicKey string
	StateDir         string
	StatusDir        string
	ProbeInterval    time.Duration
}

// Validate rejects anything that would render an ambiguous interface, address
// or peer.
func (c TunnelConfig) Validate() error {
	if err := ValidateGatewayName(c.Gateway); err != nil {
		return err
	}
	if err := ValidateIndex(c.Index); err != nil {
		return err
	}
	host, port, err := net.SplitHostPort(c.Endpoint)
	if err != nil {
		return fmt.Errorf("endpoint %q: %w", c.Endpoint, err)
	}
	if ip := net.ParseIP(host); ip == nil || ip.To4() == nil {
		return fmt.Errorf("endpoint %q must be an IPv4 address and port", c.Endpoint)
	}
	if n, err := strconv.Atoi(port); err != nil || n < 1 || n > 65535 {
		return fmt.Errorf("endpoint %q has an invalid port", c.Endpoint)
	}
	if _, err := ParseKey(c.GatewayPublicKey); err != nil {
		return fmt.Errorf("gateway public key: %w", err)
	}
	if c.StateDir == "" || c.StatusDir == "" {
		return fmt.Errorf("state and status directories are required")
	}
	return nil
}

// deviceConfig is the WireGuard UAPI configuration of the tunnel: one peer,
// the gateway. AllowedIPs only filters what the gateway may send back; the
// tunnel installs no routes, so nothing enters it unless pf routes it there.
func deviceConfig(private Key, c TunnelConfig) (string, error) {
	public, err := ParseKey(c.GatewayPublicKey)
	if err != nil {
		return "", err
	}
	return strings.Join([]string{
		"private_key=" + private.Hex(),
		"replace_peers=true",
		"public_key=" + public.Hex(),
		"endpoint=" + c.Endpoint,
		"persistent_keepalive_interval=25",
		"replace_allowed_ips=true",
		"allowed_ip=0.0.0.0/0",
		"",
	}, "\n"), nil
}

type peerStats struct {
	lastHandshakeUnix int64
	rxBytes           uint64
	txBytes           uint64
}

func parsePeerStats(uapi string) peerStats {
	var stats peerStats
	scanner := bufio.NewScanner(strings.NewReader(uapi))
	for scanner.Scan() {
		key, value, ok := strings.Cut(scanner.Text(), "=")
		if !ok {
			continue
		}
		switch key {
		case "last_handshake_time_sec":
			stats.lastHandshakeUnix, _ = strconv.ParseInt(value, 10, 64)
		case "rx_bytes":
			stats.rxBytes, _ = strconv.ParseUint(value, 10, 64)
		case "tx_bytes":
			stats.txBytes, _ = strconv.ParseUint(value, 10, 64)
		}
	}
	return stats
}

// device is the running WireGuard device the status loop reads.
type device interface {
	IpcGet() (string, error)
}

type prober func(ctx context.Context) error

func httpProbe(index int) prober {
	_, gateway := TunnelAddresses(index)
	url := fmt.Sprintf("http://%s/healthz", net.JoinHostPort(gateway, strconv.Itoa(HealthPort)))
	client := &http.Client{Timeout: 2 * time.Second}
	return func(ctx context.Context) error {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			return err
		}
		resp, err := client.Do(req)
		if err != nil {
			return err
		}
		_ = resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("gateway health returned %d", resp.StatusCode)
		}
		return nil
	}
}

func reportStatus(ctx context.Context, c TunnelConfig, dev device, probe prober, now time.Time) Status {
	status := Status{
		Gateway:     c.Gateway,
		Index:       c.Index,
		Interface:   InterfaceName(c.Index),
		Endpoint:    c.Endpoint,
		UpdatedUnix: now.Unix(),
	}
	if uapi, err := dev.IpcGet(); err == nil {
		stats := parsePeerStats(uapi)
		status.LastHandshakeUnix = stats.lastHandshakeUnix
		status.RxBytes = stats.rxBytes
		status.TxBytes = stats.txBytes
	}
	if err := probe(ctx); err != nil {
		status.ProbeError = err.Error()
	} else {
		status.ProbeOK = true
	}
	return status
}

func statusLoop(ctx context.Context, c TunnelConfig, dev device, probe prober, logger *slog.Logger) {
	interval := c.ProbeInterval
	if interval <= 0 {
		interval = 5 * time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	wasOK := false
	for {
		status := reportStatus(ctx, c, dev, probe, time.Now())
		if err := WriteStatus(c.StatusDir, status); err != nil {
			logger.Error("write tunnel status", "err", err)
		}
		if status.ProbeOK != wasOK {
			logger.Info("tunnel health changed", "ok", status.ProbeOK, "probeError", status.ProbeError)
			wasOK = status.ProbeOK
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
