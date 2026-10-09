package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/egress"
)

const (
	egressTunnelCommand    = "egress-tunnel"
	egressAnnotationPrefix = egress.AnnotationPrefix
)

// egressNodeAnnotations publishes the host key and ready gateways. A host
// without egress publishes nothing, which also retires annotations left by an
// earlier configuration.
func egressNodeAnnotations(m *egress.Manager) func(context.Context) (map[string]string, error) {
	return func(ctx context.Context) (map[string]string, error) {
		if m == nil {
			return map[string]string{}, nil
		}
		return m.NodeAnnotations(ctx)
	}
}

// runEgressTunnelCommand is `tart-kubelet egress-tunnel`: the root launchd
// daemon that keeps one gateway's WireGuard tunnel up. It runs apart from the
// kubelet so the tunnel survives kubelet restarts and the kubelet stays out of
// the data path.
func runEgressTunnelCommand(args []string) int {
	flags := flag.NewFlagSet(egressTunnelCommand, flag.ContinueOnError)
	var c egress.TunnelConfig
	flags.StringVar(&c.Gateway, "gateway", "", "Gateway name.")
	flags.IntVar(&c.Index, "index", -1, "Gateway index; selects the utun unit and tunnel addresses.")
	flags.StringVar(&c.Endpoint, "endpoint", "", "Gateway WireGuard endpoint, IPv4:port.")
	flags.StringVar(&c.GatewayPublicKey, "gateway-public-key", "", "Gateway WireGuard public key (base64).")
	flags.StringVar(&c.StateDir, "state-dir", "/var/db/tuist-egress", "Directory holding the host's WireGuard key.")
	flags.StringVar(&c.StatusDir, "status-dir", "/var/run/tuist-egress", "Directory the tunnel status is written to.")
	flags.DurationVar(&c.ProbeInterval, "probe-interval", 5*time.Second, "Interval between gateway health checks.")
	if err := flags.Parse(args); err != nil {
		return 2
	}

	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil)).With("gateway", c.Gateway)
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	if err := egress.RunTunnel(ctx, c, logger); err != nil {
		logger.Error("egress tunnel failed", "err", err)
		return 1
	}
	return 0
}

// newEgressManager returns nil when no status directory is configured, i.e.
// the host has no gateways.
func newEgressManager(statusDir, stateDir, excludeRaw, nodeIP string) (*egress.Manager, error) {
	if statusDir == "" {
		return nil, nil
	}
	if !egress.IsTailnetIPv4(nodeIP) {
		return nil, fmt.Errorf("runner egress needs the node IP to be the host's tailnet address, got %q", nodeIP)
	}
	extra := []string{}
	if excludeRaw != "" {
		extra = strings.Split(excludeRaw, ",")
	}
	exclude, err := egress.ParseCIDRs(append(append([]string{}, egress.DefaultExcludeCIDRs...), extra...))
	if err != nil {
		return nil, fmt.Errorf("--runner-egress-exclude-cidrs: %w", err)
	}
	return &egress.Manager{
		StatusDir: statusDir,
		StateDir:  stateDir,
		TailnetIP: nodeIP,
		Exclude:   exclude,
		PF:        egress.SudoPFCtl{},
	}, nil
}
