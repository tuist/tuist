package gateway

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/netip"
	"os"
	"strings"
	"sync"
	"time"

	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
	corev1 "k8s.io/api/core/v1"

	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/config"
	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/netdev"
	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/nftables"
	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/peers"
)

type WireGuard interface {
	Device(name string) (*wgtypes.Device, error)
	ConfigureDevice(name string, cfg wgtypes.Config) error
}

type NodeLister interface {
	List() ([]*corev1.Node, error)
}

type Forwarding interface {
	Ensure() (bool, error)
}

type Deps struct {
	Link       netdev.Link
	WireGuard  WireGuard
	NFT        nftables.Applier
	Forwarding Forwarding
	Nodes      NodeLister
	ReadKey    func() (wgtypes.Key, error)
	Logger     *slog.Logger
	Metrics    *Metrics
	Now        func() time.Time
}

type Status struct {
	Forwarding  bool
	Link        bool
	Rules       bool
	PeersSynced bool
}

func (s Status) Ready() bool {
	return s.Forwarding && s.Link && s.Rules && s.PeersSynced
}

// Reconciler converges wg0, the nftables table and the WireGuard peers to the
// configuration and the current Nodes.
type Reconciler struct {
	cfg     config.Config
	deps    Deps
	ruleset string

	mu          sync.RWMutex
	status      Status
	everSynced  bool
	lastPass    time.Time
	nodeByKey   map[wgtypes.Key]string
	lastSkipped map[string]string
}

func New(cfg config.Config, deps Deps) *Reconciler {
	if deps.Logger == nil {
		deps.Logger = slog.New(slog.DiscardHandler)
	}
	if deps.Now == nil {
		deps.Now = time.Now
	}
	return &Reconciler{
		cfg:  cfg,
		deps: deps,
		ruleset: nftables.Render(nftables.Options{
			TunnelInterface: config.InterfaceName,
			OutInterface:    cfg.OutInterface,
			TunnelAddress:   cfg.TunnelAddress.Addr(),
			HealthPort:      config.HealthPort,
			PeerCIDR:        cfg.PeerCIDR,
			ExcludedCIDRs:   cfg.ExcludedCIDRs,
			SNAT:            cfg.SNAT,
		}),
		nodeByKey: map[wgtypes.Key]string{},
	}
}

func (r *Reconciler) Ruleset() string { return r.ruleset }

func (r *Reconciler) Status() Status {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.status
}

func (r *Reconciler) LastPass() time.Time {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.lastPass
}

// NodeFor returns the Node a configured peer key belongs to.
func (r *Reconciler) NodeFor(key wgtypes.Key) (string, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	node, ok := r.nodeByKey[key]
	return node, ok
}

// Reconcile runs every step even when an earlier one fails, so a broken
// step does not leave the others stale, and returns the joined errors.
func (r *Reconciler) Reconcile(ctx context.Context) error {
	var errs []error
	status := Status{}

	forwarding, err := r.deps.Forwarding.Ensure()
	if err != nil {
		errs = append(errs, fmt.Errorf("ip forwarding: %w", err))
	}
	status.Forwarding = forwarding && err == nil

	linkErr := r.deps.Link.Ensure(netdev.LinkSpec{
		Name:    config.InterfaceName,
		MTU:     config.MTU,
		Address: r.cfg.TunnelAddress,
		Route:   r.cfg.PeerCIDR,
	})
	var ownKey wgtypes.Key
	if linkErr != nil {
		errs = append(errs, fmt.Errorf("link: %w", linkErr))
	} else if key, err := r.configureDevice(); err != nil {
		errs = append(errs, fmt.Errorf("wireguard device: %w", err))
	} else {
		ownKey = key
		status.Link = true
	}

	if err := r.deps.NFT.Apply(ctx, r.ruleset); err != nil {
		errs = append(errs, fmt.Errorf("nftables: %w", err))
	} else {
		status.Rules = true
	}

	if status.Link {
		if err := r.syncPeers(ownKey); err != nil {
			errs = append(errs, fmt.Errorf("peers: %w", err))
		} else {
			r.mu.Lock()
			r.everSynced = true
			r.mu.Unlock()
		}
	}

	r.mu.Lock()
	status.PeersSynced = r.everSynced
	if !status.Link {
		status.PeersSynced = false
	}
	r.status = status
	r.lastPass = r.deps.Now()
	r.mu.Unlock()

	err = errors.Join(errs...)
	if r.deps.Metrics != nil {
		r.deps.Metrics.ObserveReconcile(status, err)
	}
	return err
}

func (r *Reconciler) configureDevice() (wgtypes.Key, error) {
	key, err := r.deps.ReadKey()
	if err != nil {
		return wgtypes.Key{}, fmt.Errorf("read private key: %w", err)
	}
	device, err := r.deps.WireGuard.Device(config.InterfaceName)
	if err != nil {
		return wgtypes.Key{}, err
	}
	var update wgtypes.Config
	changed := false
	if device.PrivateKey != key {
		update.PrivateKey = &key
		changed = true
	}
	if device.ListenPort != r.cfg.ListenPort {
		port := r.cfg.ListenPort
		update.ListenPort = &port
		changed = true
	}
	if changed {
		if err := r.deps.WireGuard.ConfigureDevice(config.InterfaceName, update); err != nil {
			return wgtypes.Key{}, err
		}
		r.deps.Logger.Info("configured wireguard device", "interface", config.InterfaceName, "listen_port", r.cfg.ListenPort, "public_key", key.PublicKey().String())
	}
	return key.PublicKey(), nil
}

func (r *Reconciler) syncPeers(ownKey wgtypes.Key) error {
	nodes, err := r.deps.Nodes.List()
	if err != nil {
		return fmt.Errorf("list nodes: %w", err)
	}
	desired, skipped := peers.FromNodes(nodes, r.cfg.PeerCIDR, ownKey)
	r.logSkipped(skipped)

	device, err := r.deps.WireGuard.Device(config.InterfaceName)
	if err != nil {
		return err
	}
	changes := peers.Diff(device.Peers, desired)
	if len(changes) > 0 {
		if err := r.deps.WireGuard.ConfigureDevice(config.InterfaceName, wgtypes.Config{Peers: changes}); err != nil {
			return err
		}
	}

	byKey := make(map[wgtypes.Key]string, len(desired))
	for _, peer := range desired {
		byKey[peer.PublicKey] = peer.Node
	}
	r.mu.Lock()
	previous := r.nodeByKey
	r.nodeByKey = byKey
	r.mu.Unlock()

	for _, change := range changes {
		key := change.PublicKey
		switch {
		case change.Remove:
			r.deps.Logger.Info("removed peer", "node", previous[key], "public_key", key.String())
		default:
			r.deps.Logger.Info("configured peer", "node", byKey[key], "public_key", key.String(), "allowed_ip", change.AllowedIPs[0].String())
		}
	}
	return nil
}

func (r *Reconciler) logSkipped(skipped []peers.Skipped) {
	current := make(map[string]string, len(skipped))
	for _, s := range skipped {
		current[s.Node] = s.Reason
	}
	r.mu.Lock()
	previous := r.lastSkipped
	r.lastSkipped = current
	r.mu.Unlock()
	for node, reason := range current {
		if previous[node] != reason {
			r.deps.Logger.Warn("skipping node as peer", "node", node, "reason", reason)
		}
	}
}

// KeyFileReader reads a base64 WireGuard private key from path on every call,
// so a rotated Secret is picked up without a restart.
func KeyFileReader(path string) func() (wgtypes.Key, error) {
	return func() (wgtypes.Key, error) {
		data, err := os.ReadFile(path)
		if err != nil {
			return wgtypes.Key{}, err
		}
		key, err := wgtypes.ParseKey(strings.TrimSpace(string(data)))
		if err != nil {
			return wgtypes.Key{}, fmt.Errorf("parse %s: %w", path, err)
		}
		if key == (wgtypes.Key{}) {
			return wgtypes.Key{}, fmt.Errorf("%s holds an all-zero key", path)
		}
		return key, nil
	}
}

// TunnelHealthAddress is where /healthz listens: the tunnel address on the
// health port.
func TunnelHealthAddress(cfg config.Config) string {
	return netip.AddrPortFrom(cfg.TunnelAddress.Addr(), config.HealthPort).String()
}
