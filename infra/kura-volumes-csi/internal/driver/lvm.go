package driver

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// lvmConfig keeps LVM away from the container's own /etc and udev: devices are
// scanned directly, nodes are created by LVM itself, and no metadata backup is
// written inside the container.
const lvmConfig = "devices { use_devicesfile = 0 obtain_device_list_from_udev = 0 } " +
	"activation { udev_sync = 0 udev_rules = 0 } " +
	"backup { backup = 0 archive = 0 }"

// lvmNotFound is the exit code of lvs and vgs for a volume group or logical
// volume that does not exist.
const lvmNotFound = 5

func (d *Driver) lvm(ctx context.Context, command string, args ...string) ([]byte, error) {
	return d.runner.Run(ctx, nil, command, append([]string{"--config", lvmConfig}, args...)...)
}

func (d *Driver) lvName(v volume) string { return d.volumeGroup + "/" + v.id }

func (d *Driver) lvPath(v volume) string { return d.devDir + "/" + d.volumeGroup + "/" + v.id }

// lvSize returns the size of the volume's logical volume, or false when the
// driver has no volume group or the volume group has no such volume.
func (d *Driver) lvSize(ctx context.Context, v volume) (int64, bool, error) {
	if d.volumeGroup == "" {
		return 0, false, nil
	}
	out, err := d.lvm(ctx, "lvs", "--noheadings", "--nosuffix", "--units", "b", "-o", "lv_size", d.lvName(v))
	if code, ok := exitCode(err); ok && code == lvmNotFound {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, status.Error(codes.Internal, err.Error())
	}
	size, err := strconv.ParseInt(strings.TrimSpace(string(out)), 10, 64)
	if err != nil {
		return 0, false, status.Errorf(codes.Internal, "parse size of %s: %q", d.lvName(v), out)
	}
	return size, true, nil
}

// volumeGroupFree returns the free bytes of the driver's volume group, or
// false when the node has none.
func (d *Driver) volumeGroupFree(ctx context.Context) (int64, bool, error) {
	if d.volumeGroup == "" {
		return 0, false, nil
	}
	out, err := d.lvm(ctx, "vgs", "--noheadings", "--nosuffix", "--units", "b", "-o", "vg_free", d.volumeGroup)
	if code, ok := exitCode(err); ok && code == lvmNotFound {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, status.Error(codes.Internal, err.Error())
	}
	free, err := strconv.ParseInt(strings.TrimSpace(string(out)), 10, 64)
	if err != nil {
		return 0, false, status.Errorf(codes.Internal, "parse free space of %s: %q", d.volumeGroup, out)
	}
	return free, true, nil
}

// createLV publishes the unformatted marker before the logical volume, so a
// volume that exists is always either marked or formatted by this driver.
// lvcreate wipes signatures and zeroes the start of the new volume.
func (d *Driver) createLV(ctx context.Context, v volume, capacity int64) error {
	if err := writeMarker(v.marker); err != nil {
		return status.Errorf(codes.Internal, "write unformatted marker: %v", err)
	}
	if err := syncDir(d.stateDir); err != nil {
		return status.Errorf(codes.Internal, "sync state dir: %v", err)
	}
	if _, err := d.lvm(ctx, "lvcreate", "--yes", "--wipesignatures", "y", "--zero", "y",
		"--size", strconv.FormatInt(capacity, 10)+"b", "--name", v.id, d.volumeGroup); err != nil {
		return status.Error(codes.Internal, err.Error())
	}
	return nil
}

// activateLV makes the logical volume's device node available, which after a
// reboot is not guaranteed.
func (d *Driver) activateLV(ctx context.Context, v volume) (string, error) {
	if _, err := d.lvm(ctx, "lvchange", "--activate", "y", d.lvName(v)); err != nil {
		return "", status.Error(codes.Internal, err.Error())
	}
	if _, err := d.lvm(ctx, "vgmknodes", d.lvName(v)); err != nil {
		return "", status.Error(codes.Internal, err.Error())
	}
	return d.lvPath(v), nil
}

// removeLV wipes the LUKS header off the logical volume before releasing its
// extents, so the ciphertext left in them cannot be opened even with the key.
func (d *Driver) removeLV(ctx context.Context, v volume, size int64) error {
	device, err := d.activateLV(ctx, v)
	if err != nil {
		return err
	}
	luks, err := d.isLUKS(ctx, device)
	if err != nil {
		return err
	}
	if luks {
		if _, err := d.run(ctx, nil, "cryptsetup", "erase", "--batch-mode", device); err != nil {
			return err
		}
	}
	if err := wipeDeviceHeader(device, size); err != nil {
		return status.Errorf(codes.Internal, "wipe volume header: %v", err)
	}
	if _, err := d.lvm(ctx, "lvremove", "--yes", d.lvName(v)); err != nil {
		return status.Error(codes.Internal, err.Error())
	}
	return nil
}

// wipeDeviceHeader zeroes the start of a block device. A device's own size
// is not visible to stat, so the caller passes it. The path is LVM's symlink
// to the device node, so it is followed.
func wipeDeviceHeader(path string, size int64) error {
	f, err := os.OpenFile(path, os.O_WRONLY, 0)
	if err != nil {
		return err
	}
	defer f.Close()
	if err := zeroPrefix(f, min(size, headerWipeBytes)); err != nil {
		return err
	}
	return f.Close()
}

// KuraDiskCapacity is the room the volume group holds for Kura volumes: its
// size less every logical volume that is not one, such as the node's /data.
// It is false when the driver has no volume group or the node lacks it.
func (d *Driver) KuraDiskCapacity(ctx context.Context) (int64, bool, error) {
	if d.volumeGroup == "" {
		return 0, false, nil
	}
	out, err := d.lvm(ctx, "vgs", "--noheadings", "--nosuffix", "--units", "b", "-o", "vg_size", d.volumeGroup)
	if code, ok := exitCode(err); ok && code == lvmNotFound {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, err
	}
	capacity, err := strconv.ParseInt(strings.TrimSpace(string(out)), 10, 64)
	if err != nil {
		return 0, false, fmt.Errorf("parse size of %s: %q", d.volumeGroup, out)
	}
	out, err = d.lvm(ctx, "lvs", "--noheadings", "--nosuffix", "--units", "b", "--separator", ",", "-o", "lv_name,lv_size", d.volumeGroup)
	if err != nil {
		return 0, false, err
	}
	for _, line := range strings.Split(string(out), "\n") {
		name, size, found := strings.Cut(strings.TrimSpace(line), ",")
		if !found || volumeIDPattern.MatchString(name) {
			continue
		}
		bytes, err := strconv.ParseInt(size, 10, 64)
		if err != nil {
			return 0, false, fmt.Errorf("parse size of %s/%s: %q", d.volumeGroup, name, size)
		}
		capacity -= bytes
	}
	return max(capacity, 0), true, nil
}
