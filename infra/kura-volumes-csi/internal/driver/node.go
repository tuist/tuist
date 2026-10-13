package driver

import (
	"context"
	"errors"
	"io/fs"
	"os"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func (d *Driver) NodeGetInfo(context.Context, *csi.NodeGetInfoRequest) (*csi.NodeGetInfoResponse, error) {
	return &csi.NodeGetInfoResponse{NodeId: d.nodeID, AccessibleTopology: d.topology()}, nil
}

func (d *Driver) NodeGetCapabilities(context.Context, *csi.NodeGetCapabilitiesRequest) (*csi.NodeGetCapabilitiesResponse, error) {
	rpc := func(t csi.NodeServiceCapability_RPC_Type) *csi.NodeServiceCapability {
		return &csi.NodeServiceCapability{Type: &csi.NodeServiceCapability_Rpc{Rpc: &csi.NodeServiceCapability_RPC{Type: t}}}
	}
	return &csi.NodeGetCapabilitiesResponse{Capabilities: []*csi.NodeServiceCapability{
		rpc(csi.NodeServiceCapability_RPC_STAGE_UNSTAGE_VOLUME),
		rpc(csi.NodeServiceCapability_RPC_GET_VOLUME_STATS),
	}}, nil
}

func (d *Driver) NodeStageVolume(ctx context.Context, req *csi.NodeStageVolumeRequest) (*csi.NodeStageVolumeResponse, error) {
	v, err := d.volume(req.GetVolumeId())
	if err != nil {
		return nil, err
	}
	staging := req.GetStagingTargetPath()
	if err := checkPath("staging_target_path", staging); err != nil {
		return nil, err
	}
	if err := validateCapability(req.GetVolumeCapability()); err != nil {
		return nil, err
	}
	unlock, err := d.lockVolume(ctx, v)
	if err != nil {
		return nil, err
	}
	defer unlock()

	info, err := imageInfo(v)
	if err != nil {
		return nil, err
	}
	if info == nil {
		return nil, status.Errorf(codes.NotFound, "volume %s does not exist on node %s", v.id, d.nodeID)
	}
	mounted, err := d.volumeMounted(staging, v)
	if err != nil {
		return nil, err
	}
	if mounted {
		return &csi.NodeStageVolumeResponse{}, nil
	}

	loop, err := d.attachLoop(ctx, v)
	if err != nil {
		return nil, err
	}
	unformatted, err := fileExists(v.marker)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "stat unformatted marker: %v", err)
	}
	active, backing, err := d.mapperBacking(ctx, v)
	if err != nil {
		return nil, err
	}
	if active && backing != loop {
		return nil, status.Errorf(codes.FailedPrecondition, "%s is open on %s, expected %s", v.mapper, backing, loop)
	}
	if !active {
		if err := d.openLUKS(ctx, v, loop, unformatted); err != nil {
			return nil, err
		}
	}
	if unformatted {
		// The marker is removed before the first mount, so any filesystem
		// signature present now comes from an interrupted format of this
		// same volume and forcing over it loses nothing.
		if _, err := d.run(ctx, nil, "mkfs.xfs", "-q", "-K", "-f", v.mapperPath()); err != nil {
			return nil, err
		}
		if err := os.Remove(v.marker); err != nil {
			return nil, status.Errorf(codes.Internal, "remove unformatted marker: %v", err)
		}
		if err := syncDir(d.stateDir); err != nil {
			return nil, status.Errorf(codes.Internal, "sync state dir: %v", err)
		}
		d.logger.Info("formatted volume", "volume_id", v.id)
	}
	if err := os.MkdirAll(staging, 0o750); err != nil {
		return nil, status.Errorf(codes.Internal, "create staging path: %v", err)
	}
	if _, err := d.run(ctx, nil, "mount", "-t", "xfs", "-o", "nodev,nosuid,noatime", v.mapperPath(), staging); err != nil {
		return nil, err
	}
	d.logger.Info("staged volume", "volume_id", v.id, "loop_device", loop)
	return &csi.NodeStageVolumeResponse{}, nil
}

// openLUKS opens the volume's LUKS2 container, creating it first when the
// volume has never been formatted. A device that is neither LUKS nor marked
// unformatted holds data this driver does not recognise and is never touched.
func (d *Driver) openLUKS(ctx context.Context, v volume, loop string, unformatted bool) error {
	luks, err := d.isLUKS(ctx, loop)
	if err != nil {
		return err
	}
	if !luks && !unformatted {
		return status.Errorf(codes.FailedPrecondition, "volume %s is neither LUKS2 nor marked unformatted; refusing to format it", v.id)
	}
	stored, err := readKeyVersion(v)
	if err != nil {
		return err
	}
	key, version, err := d.keys.Fetch(ctx, v.id, stored)
	if err != nil {
		return err
	}
	defer clear(key)
	if !luks && stored == 0 {
		// Recorded before luksFormat so a crash in between cannot leave a
		// header whose key version is unknown.
		if err := d.writeKeyVersion(v, version); err != nil {
			return err
		}
	}
	if !luks {
		// The passphrase is a uniformly random 32-byte HKDF output, so key
		// stretching adds nothing; a minimal PBKDF2 also avoids argon2's
		// per-open memory spike.
		if _, err := d.run(ctx, key, "cryptsetup", "luksFormat", "--type", "luks2",
			"--cipher", "aes-xts-plain64", "--key-size", "512",
			"--pbkdf", "pbkdf2", "--pbkdf-force-iterations", "1000",
			"--batch-mode", "--key-file=-", loop); err != nil {
			return err
		}
	}
	// Bypassing dm-crypt's workqueues does the crypto inline on the submitting
	// CPU, which removes most of its added latency on NVMe.
	if _, err := d.run(ctx, key, "cryptsetup", "open", "--type", "luks2",
		"--perf-no_read_workqueue", "--perf-no_write_workqueue",
		"--key-file=-", loop, v.mapper); err != nil {
		return err
	}
	if luks && stored == 0 {
		// Only recorded once the active key has proven it opens the header.
		d.logger.Warn("LUKS volume had no key version file; recording the version that opened it", "volume_id", v.id, "key_version", version)
		return d.writeKeyVersion(v, version)
	}
	return nil
}

func (d *Driver) NodeUnstageVolume(ctx context.Context, req *csi.NodeUnstageVolumeRequest) (*csi.NodeUnstageVolumeResponse, error) {
	v, err := d.volume(req.GetVolumeId())
	if err != nil {
		return nil, err
	}
	staging := req.GetStagingTargetPath()
	if err := checkPath("staging_target_path", staging); err != nil {
		return nil, err
	}
	unlock, err := d.lockVolume(ctx, v)
	if err != nil {
		return nil, err
	}
	defer unlock()

	m, err := d.mountAt(staging)
	if err != nil {
		return nil, err
	}
	if m != nil {
		if _, err := d.run(ctx, nil, "umount", staging); err != nil {
			return nil, err
		}
	}
	active, _, err := d.mapperBacking(ctx, v)
	if err != nil {
		return nil, err
	}
	if active {
		if _, err := d.run(ctx, nil, "cryptsetup", "close", v.mapper); err != nil {
			return nil, err
		}
	}
	info, err := imageInfo(v)
	if err != nil {
		return nil, err
	}
	if info != nil {
		loops, err := d.loopDevices(ctx, v)
		if err != nil {
			return nil, err
		}
		for _, loop := range loops {
			if _, err := d.run(ctx, nil, "losetup", "-d", loop); err != nil {
				return nil, err
			}
		}
	}
	d.logger.Info("unstaged volume", "volume_id", v.id)
	return &csi.NodeUnstageVolumeResponse{}, nil
}

func (d *Driver) NodePublishVolume(ctx context.Context, req *csi.NodePublishVolumeRequest) (*csi.NodePublishVolumeResponse, error) {
	v, err := d.volume(req.GetVolumeId())
	if err != nil {
		return nil, err
	}
	staging := req.GetStagingTargetPath()
	if err := checkPath("staging_target_path", staging); err != nil {
		return nil, err
	}
	target := req.GetTargetPath()
	if err := checkPath("target_path", target); err != nil {
		return nil, err
	}
	if err := validateCapability(req.GetVolumeCapability()); err != nil {
		return nil, err
	}
	unlock, err := d.lockVolume(ctx, v)
	if err != nil {
		return nil, err
	}
	defer unlock()

	staged, err := d.volumeMounted(staging, v)
	if err != nil {
		return nil, err
	}
	if !staged {
		return nil, status.Errorf(codes.FailedPrecondition, "volume %s is not staged at %s", v.id, staging)
	}
	published, err := d.volumeMounted(target, v)
	if err != nil {
		return nil, err
	}
	if published {
		return &csi.NodePublishVolumeResponse{}, nil
	}
	if err := os.MkdirAll(target, 0o750); err != nil {
		return nil, status.Errorf(codes.Internal, "create target path: %v", err)
	}
	options := "bind,nodev,nosuid"
	if req.GetReadonly() {
		options += ",ro"
	}
	if _, err := d.run(ctx, nil, "mount", "-o", options, staging, target); err != nil {
		return nil, err
	}
	return &csi.NodePublishVolumeResponse{}, nil
}

func (d *Driver) NodeUnpublishVolume(ctx context.Context, req *csi.NodeUnpublishVolumeRequest) (*csi.NodeUnpublishVolumeResponse, error) {
	v, err := d.volume(req.GetVolumeId())
	if err != nil {
		return nil, err
	}
	target := req.GetTargetPath()
	if err := checkPath("target_path", target); err != nil {
		return nil, err
	}
	unlock, err := d.lockVolume(ctx, v)
	if err != nil {
		return nil, err
	}
	defer unlock()

	m, err := d.mountAt(target)
	if err != nil {
		return nil, err
	}
	if m != nil {
		if _, err := d.run(ctx, nil, "umount", target); err != nil {
			return nil, err
		}
	}
	if err := os.Remove(target); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return nil, status.Errorf(codes.Internal, "remove target path: %v", err)
	}
	return &csi.NodeUnpublishVolumeResponse{}, nil
}

func (d *Driver) NodeGetVolumeStats(_ context.Context, req *csi.NodeGetVolumeStatsRequest) (*csi.NodeGetVolumeStatsResponse, error) {
	v, err := d.volume(req.GetVolumeId())
	if err != nil {
		return nil, err
	}
	path := req.GetVolumePath()
	if err := checkPath("volume_path", path); err != nil {
		return nil, err
	}
	mounted, err := d.volumeMounted(path, v)
	if err != nil {
		return nil, err
	}
	if !mounted {
		return nil, status.Errorf(codes.NotFound, "volume %s is not mounted at %s", v.id, path)
	}
	stats, err := d.host.FSStats(path)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "statfs %s: %v", path, err)
	}
	return &csi.NodeGetVolumeStatsResponse{Usage: []*csi.VolumeUsage{
		{Unit: csi.VolumeUsage_BYTES, Total: stats.TotalBytes, Available: stats.AvailableBytes, Used: stats.UsedBytes},
		{Unit: csi.VolumeUsage_INODES, Total: stats.TotalInodes, Available: stats.AvailableInodes, Used: stats.UsedInodes},
	}}, nil
}
