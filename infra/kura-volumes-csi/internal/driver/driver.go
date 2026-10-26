// Package driver implements the kura-volumes.tuist.dev CSI driver: one LUKS2
// container per volume, backed by a logical volume in the node's volume group
// or, on a node without one, a preallocated file in the state directory, and
// keyed by a passphrase fetched from the Tuist server on every stage.
package driver

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"

	"github.com/container-storage-interface/spec/lib/go/csi"
)

const (
	Name        = "kura-volumes.tuist.dev"
	TopologyKey = "topology.kura-volumes.tuist.dev/node"
)

var volumeGroupPattern = regexp.MustCompile(`^[a-zA-Z0-9_][a-zA-Z0-9_.+-]*$`)

// KeyFetcher returns the 32-byte LUKS passphrase of a volume and the key
// version it was derived under. version 0 requests the active key; any other
// value pins it. Callers zero the passphrase once cryptsetup has it.
type KeyFetcher interface {
	Fetch(ctx context.Context, volumeID string, version int) ([]byte, int, error)
}

type Config struct {
	NodeID       string
	StateDir     string
	ReserveBytes int64
	// VolumeGroup is the LVM volume group new volumes are created in when the
	// node has it. Empty, or absent on the node, keeps backing files.
	VolumeGroup string
	Version     string
	Keys        KeyFetcher
	Runner      Runner
	Mounts      MountTable
	Host        Host
	Logger      *slog.Logger
}

type Driver struct {
	csi.UnimplementedIdentityServer
	csi.UnimplementedControllerServer
	csi.UnimplementedNodeServer

	nodeID       string
	stateDir     string
	reserveBytes int64
	volumeGroup  string
	devDir       string
	version      string
	keys         KeyFetcher
	runner       Runner
	mounts       MountTable
	host         Host
	logger       *slog.Logger
}

func New(cfg Config) (*Driver, error) {
	if cfg.NodeID == "" {
		return nil, errors.New("node id is required")
	}
	if cfg.ReserveBytes < 0 {
		return nil, errors.New("reserve bytes must not be negative")
	}
	if cfg.Keys == nil || cfg.Runner == nil || cfg.Mounts == nil || cfg.Host == nil {
		return nil, errors.New("keys, runner, mounts and host are required")
	}
	if err := checkStateDir(cfg.StateDir); err != nil {
		return nil, err
	}
	if cfg.VolumeGroup != "" && !volumeGroupPattern.MatchString(cfg.VolumeGroup) {
		return nil, fmt.Errorf("volume group %q is not a valid LVM name", cfg.VolumeGroup)
	}
	logger := cfg.Logger
	if logger == nil {
		logger = slog.New(slog.DiscardHandler)
	}
	return &Driver{
		nodeID:       cfg.NodeID,
		stateDir:     cfg.StateDir,
		reserveBytes: cfg.ReserveBytes,
		volumeGroup:  cfg.VolumeGroup,
		devDir:       "/dev",
		version:      cfg.Version,
		keys:         cfg.Keys,
		runner:       cfg.Runner,
		mounts:       cfg.Mounts,
		host:         cfg.Host,
		logger:       logger,
	}, nil
}

func checkStateDir(dir string) error {
	if !filepath.IsAbs(dir) || filepath.Clean(dir) != dir || dir == "/" {
		return fmt.Errorf("state dir %q must be an absolute, clean path other than /", dir)
	}
	info, err := os.Lstat(dir)
	if err != nil {
		return fmt.Errorf("state dir: %w", err)
	}
	if !info.IsDir() {
		return fmt.Errorf("state dir %q is not a directory", dir)
	}
	resolved, err := filepath.EvalSymlinks(dir)
	if err != nil {
		return fmt.Errorf("state dir: %w", err)
	}
	if resolved != dir {
		return fmt.Errorf("state dir %q must be canonical, without symlinks (resolves to %q)", dir, resolved)
	}
	return nil
}

func (d *Driver) GetPluginInfo(context.Context, *csi.GetPluginInfoRequest) (*csi.GetPluginInfoResponse, error) {
	return &csi.GetPluginInfoResponse{Name: Name, VendorVersion: d.version}, nil
}

func (d *Driver) GetPluginCapabilities(context.Context, *csi.GetPluginCapabilitiesRequest) (*csi.GetPluginCapabilitiesResponse, error) {
	service := func(t csi.PluginCapability_Service_Type) *csi.PluginCapability {
		return &csi.PluginCapability{Type: &csi.PluginCapability_Service_{Service: &csi.PluginCapability_Service{Type: t}}}
	}
	return &csi.GetPluginCapabilitiesResponse{Capabilities: []*csi.PluginCapability{
		service(csi.PluginCapability_Service_CONTROLLER_SERVICE),
		service(csi.PluginCapability_Service_VOLUME_ACCESSIBILITY_CONSTRAINTS),
	}}, nil
}

func (d *Driver) Probe(context.Context, *csi.ProbeRequest) (*csi.ProbeResponse, error) {
	return &csi.ProbeResponse{}, nil
}

func (d *Driver) topology() *csi.Topology {
	return &csi.Topology{Segments: map[string]string{TopologyKey: d.nodeID}}
}
