package driver

import (
	"context"
	"math"
	"os"
	"strconv"
	"syscall"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	mib = int64(1) << 20
	// headerWipeBytes covers the LUKS2 header, its backup and the default
	// 16 MiB keyslot area.
	headerWipeBytes = 32 * mib
)

func (d *Driver) ControllerGetCapabilities(context.Context, *csi.ControllerGetCapabilitiesRequest) (*csi.ControllerGetCapabilitiesResponse, error) {
	return &csi.ControllerGetCapabilitiesResponse{Capabilities: []*csi.ControllerServiceCapability{{
		Type: &csi.ControllerServiceCapability_Rpc{Rpc: &csi.ControllerServiceCapability_RPC{
			Type: csi.ControllerServiceCapability_RPC_CREATE_DELETE_VOLUME,
		}},
	}}}, nil
}

func (d *Driver) CreateVolume(ctx context.Context, req *csi.CreateVolumeRequest) (*csi.CreateVolumeResponse, error) {
	v, err := d.volume(req.GetName())
	if err != nil {
		return nil, err
	}
	if err := validateCapabilities(req.GetVolumeCapabilities()); err != nil {
		return nil, err
	}
	if req.GetVolumeContentSource() != nil {
		return nil, status.Error(codes.InvalidArgument, "volume content sources are not supported")
	}
	capacity, err := capacityBytes(req.GetCapacityRange())
	if err != nil {
		return nil, err
	}
	if !d.accessibleFrom(req.GetAccessibilityRequirements()) {
		return nil, status.Errorf(codes.ResourceExhausted, "volume %s is not requested for node %s", v.id, d.nodeID)
	}

	unlock, err := d.lockVolume(ctx, v)
	if err != nil {
		return nil, err
	}
	defer unlock()

	response := &csi.CreateVolumeResponse{Volume: &csi.Volume{
		VolumeId:           v.id,
		CapacityBytes:      capacity,
		AccessibleTopology: []*csi.Topology{d.topology()},
	}}

	info, err := imageInfo(v)
	if err != nil {
		return nil, err
	}
	if info != nil {
		if info.Size() != capacity {
			return nil, status.Errorf(codes.AlreadyExists, "volume %s exists with %d bytes, requested %d", v.id, info.Size(), capacity)
		}
		return response, nil
	}

	if err := removeIfExists(v.temp); err != nil {
		return nil, status.Errorf(codes.Internal, "remove stale temporary file: %v", err)
	}
	stats, err := d.host.FSStats(d.stateDir)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "stat state dir filesystem: %v", err)
	}
	if capacity > math.MaxInt64-d.reserveBytes || stats.AvailableBytes < capacity+d.reserveBytes {
		return nil, status.Errorf(codes.ResourceExhausted, "node %s has %d bytes available, volume needs %d plus a %d byte reserve", d.nodeID, stats.AvailableBytes, capacity, d.reserveBytes)
	}
	if err := d.allocateImage(ctx, v, capacity); err != nil {
		_ = os.Remove(v.temp)
		return nil, err
	}
	d.logger.Info("created volume", "volume_id", v.id, "capacity_bytes", capacity)
	return response, nil
}

// allocateImage fully reserves the backing file so a volume can never fail
// on a full state dir filesystem, and publishes it under its final name only
// after the unformatted marker exists.
func (d *Driver) allocateImage(ctx context.Context, v volume, capacity int64) error {
	f, err := os.OpenFile(v.temp, os.O_WRONLY|os.O_CREATE|os.O_EXCL|syscall.O_NOFOLLOW, 0o600)
	if err != nil {
		return status.Errorf(codes.Internal, "create backing file: %v", err)
	}
	if err := f.Close(); err != nil {
		return status.Errorf(codes.Internal, "create backing file: %v", err)
	}
	if _, err := d.run(ctx, nil, "fallocate", "-l", strconv.FormatInt(capacity, 10), v.temp); err != nil {
		return err
	}
	if err := syncFile(v.temp); err != nil {
		return status.Errorf(codes.Internal, "sync backing file: %v", err)
	}
	if err := writeMarker(v.marker); err != nil {
		return status.Errorf(codes.Internal, "write unformatted marker: %v", err)
	}
	if err := os.Rename(v.temp, v.image); err != nil {
		return status.Errorf(codes.Internal, "rename backing file: %v", err)
	}
	if err := syncDir(d.stateDir); err != nil {
		return status.Errorf(codes.Internal, "sync state dir: %v", err)
	}
	return nil
}

func syncFile(path string) error {
	f, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return err
	}
	defer f.Close()
	return f.Sync()
}

func writeMarker(path string) error {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|syscall.O_NOFOLLOW, 0o600)
	if err != nil {
		return err
	}
	if err := f.Sync(); err != nil {
		_ = f.Close()
		return err
	}
	return f.Close()
}

func capacityBytes(r *csi.CapacityRange) (int64, error) {
	required := r.GetRequiredBytes()
	if required <= 0 {
		return 0, status.Error(codes.InvalidArgument, "capacity_range.required_bytes must be positive")
	}
	if required > math.MaxInt64-mib {
		return 0, status.Errorf(codes.OutOfRange, "requested capacity %d is too large", required)
	}
	capacity := (required + mib - 1) / mib * mib
	if limit := r.GetLimitBytes(); limit > 0 && capacity > limit {
		return 0, status.Errorf(codes.OutOfRange, "capacity %d rounded to MiB exceeds the %d byte limit", capacity, limit)
	}
	return capacity, nil
}

func (d *Driver) accessibleFrom(req *csi.TopologyRequirement) bool {
	for _, topologies := range [][]*csi.Topology{req.GetRequisite(), req.GetPreferred()} {
		for _, t := range topologies {
			if t.GetSegments()[TopologyKey] == d.nodeID {
				return true
			}
		}
	}
	return false
}

func (d *Driver) DeleteVolume(ctx context.Context, req *csi.DeleteVolumeRequest) (*csi.DeleteVolumeResponse, error) {
	v, err := d.volume(req.GetVolumeId())
	if err != nil {
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
	if info != nil {
		loops, err := d.loopDevices(ctx, v)
		if err != nil {
			return nil, err
		}
		if len(loops) > 0 {
			return nil, status.Errorf(codes.FailedPrecondition, "volume %s is still attached to %v", v.id, loops)
		}
		active, _, err := d.mapperBacking(ctx, v)
		if err != nil {
			return nil, err
		}
		if active {
			return nil, status.Errorf(codes.FailedPrecondition, "volume %s is still open as %s", v.id, v.mapper)
		}
		luks, err := d.isLUKS(ctx, v.image)
		if err != nil {
			return nil, err
		}
		if luks {
			if _, err := d.run(ctx, nil, "cryptsetup", "erase", "--batch-mode", v.image); err != nil {
				return nil, err
			}
		}
		if err := wipeHeader(v.image); err != nil {
			return nil, status.Errorf(codes.Internal, "wipe volume header: %v", err)
		}
	}
	for _, path := range []string{v.image, v.temp, v.marker, v.keyVersion, v.keyVersionTemp, v.lock} {
		if err := removeIfExists(path); err != nil {
			return nil, status.Errorf(codes.Internal, "remove %s: %v", path, err)
		}
	}
	if err := syncDir(d.stateDir); err != nil {
		return nil, status.Errorf(codes.Internal, "sync state dir: %v", err)
	}
	d.logger.Info("deleted volume", "volume_id", v.id, "existed", info != nil)
	return &csi.DeleteVolumeResponse{}, nil
}

// wipeHeader zeroes the start of the backing file so no LUKS header or
// keyslot survives in the file's blocks after it is unlinked.
func wipeHeader(path string) error {
	f, err := os.OpenFile(path, os.O_WRONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return err
	}
	remaining := min(info.Size(), headerWipeBytes)
	zeros := make([]byte, mib)
	for remaining > 0 {
		n := min(remaining, int64(len(zeros)))
		if _, err := f.Write(zeros[:n]); err != nil {
			return err
		}
		remaining -= n
	}
	if err := f.Sync(); err != nil {
		return err
	}
	return f.Close()
}

func (d *Driver) ValidateVolumeCapabilities(ctx context.Context, req *csi.ValidateVolumeCapabilitiesRequest) (*csi.ValidateVolumeCapabilitiesResponse, error) {
	v, err := d.volume(req.GetVolumeId())
	if err != nil {
		return nil, err
	}
	info, err := imageInfo(v)
	if err != nil {
		return nil, err
	}
	if info == nil {
		return nil, status.Errorf(codes.NotFound, "volume %s does not exist on node %s", v.id, d.nodeID)
	}
	if err := validateCapabilities(req.GetVolumeCapabilities()); err != nil {
		if status.Code(err) == codes.InvalidArgument && len(req.GetVolumeCapabilities()) > 0 {
			return &csi.ValidateVolumeCapabilitiesResponse{Message: status.Convert(err).Message()}, nil
		}
		return nil, err
	}
	return &csi.ValidateVolumeCapabilitiesResponse{Confirmed: &csi.ValidateVolumeCapabilitiesResponse_Confirmed{
		VolumeCapabilities: req.GetVolumeCapabilities(),
	}}, nil
}
