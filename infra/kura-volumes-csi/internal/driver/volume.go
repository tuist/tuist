package driver

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

var volumeIDPattern = regexp.MustCompile(`^pvc-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

const lockRetryInterval = 100 * time.Millisecond

type volume struct {
	id     string
	image  string
	temp   string
	marker string
	lock   string
	mapper string

	keyVersion     string
	keyVersionTemp string
}

func (v volume) mapperPath() string { return "/dev/mapper/" + v.mapper }

func (d *Driver) volume(id string) (volume, error) {
	if !volumeIDPattern.MatchString(id) {
		return volume{}, status.Errorf(codes.InvalidArgument, "invalid volume id %q", id)
	}
	base := filepath.Join(d.stateDir, id)
	return volume{
		id:     id,
		image:  base + ".img",
		temp:   base + ".img.new",
		marker: base + ".unformatted",
		lock:   base + ".lock",
		mapper: "kura-" + id,

		keyVersion:     base + ".key-version",
		keyVersionTemp: base + ".key-version.new",
	}, nil
}

// lockVolume serializes every operation on one volume across the driver's
// goroutines and any other process on the node. It polls so a cancelled
// request releases its wait instead of blocking a gRPC worker.
func (d *Driver) lockVolume(ctx context.Context, v volume) (func(), error) {
	for {
		f, err := os.OpenFile(v.lock, os.O_RDWR|os.O_CREATE|syscall.O_NOFOLLOW, 0o600)
		if err != nil {
			return nil, status.Errorf(codes.Internal, "open lock: %v", err)
		}
		err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			// A DeleteVolume that held the lock unlinks the file before
			// releasing it; a lock on that orphaned inode protects nothing.
			if sameFile(f, v.lock) {
				return func() {
					_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
					_ = f.Close()
				}, nil
			}
			_ = f.Close()
			continue
		}
		_ = f.Close()
		if !errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, status.Errorf(codes.Internal, "lock volume: %v", err)
		}
		select {
		case <-ctx.Done():
			return nil, status.Errorf(codes.Aborted, "an operation on volume %s is already in progress", v.id)
		case <-time.After(lockRetryInterval):
		}
	}
}

func sameFile(f *os.File, path string) bool {
	held, err := f.Stat()
	if err != nil {
		return false
	}
	current, err := os.Lstat(path)
	if err != nil {
		return false
	}
	return os.SameFile(held, current)
}

// imageInfo returns nil when the backing file does not exist.
func imageInfo(v volume) (fs.FileInfo, error) {
	info, err := os.Lstat(v.image)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, status.Errorf(codes.Internal, "stat backing file: %v", err)
	}
	if !info.Mode().IsRegular() {
		return nil, status.Errorf(codes.FailedPrecondition, "backing file %s is not a regular file", v.image)
	}
	return info, nil
}

func fileExists(path string) (bool, error) {
	_, err := os.Lstat(path)
	if errors.Is(err, fs.ErrNotExist) {
		return false, nil
	}
	return err == nil, err
}

func removeIfExists(path string) error {
	if err := os.Remove(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return nil
}

func syncDir(dir string) error {
	f, err := os.Open(dir)
	if err != nil {
		return err
	}
	defer f.Close()
	return f.Sync()
}

func validateCapability(c *csi.VolumeCapability) error {
	if c == nil {
		return status.Error(codes.InvalidArgument, "volume capability is required")
	}
	mount := c.GetMount()
	if mount == nil {
		return status.Error(codes.InvalidArgument, "only the mount access type is supported")
	}
	if fsType := mount.GetFsType(); fsType != "" && fsType != "xfs" {
		return status.Errorf(codes.InvalidArgument, "unsupported fs type %q, volumes are xfs", fsType)
	}
	switch c.GetAccessMode().GetMode() {
	case csi.VolumeCapability_AccessMode_SINGLE_NODE_WRITER,
		csi.VolumeCapability_AccessMode_SINGLE_NODE_READER_ONLY,
		csi.VolumeCapability_AccessMode_SINGLE_NODE_SINGLE_WRITER,
		csi.VolumeCapability_AccessMode_SINGLE_NODE_MULTI_WRITER:
		return nil
	default:
		return status.Errorf(codes.InvalidArgument, "unsupported access mode %s", c.GetAccessMode().GetMode())
	}
}

func validateCapabilities(caps []*csi.VolumeCapability) error {
	if len(caps) == 0 {
		return status.Error(codes.InvalidArgument, "volume capabilities are required")
	}
	for _, c := range caps {
		if err := validateCapability(c); err != nil {
			return err
		}
	}
	return nil
}

func (d *Driver) run(ctx context.Context, stdin []byte, name string, args ...string) ([]byte, error) {
	out, err := d.runner.Run(ctx, stdin, name, args...)
	if err != nil {
		return out, status.Error(codes.Internal, err.Error())
	}
	return out, nil
}

// loopDevices lists the loop devices backed by the volume's image.
func (d *Driver) loopDevices(ctx context.Context, v volume) ([]string, error) {
	out, err := d.run(ctx, nil, "losetup", "--noheadings", "--output", "NAME", "-j", v.image)
	if err != nil {
		return nil, err
	}
	var devices []string
	for _, line := range strings.Split(string(out), "\n") {
		if line = strings.TrimSpace(line); line != "" {
			devices = append(devices, line)
		}
	}
	return devices, nil
}

func (d *Driver) attachLoop(ctx context.Context, v volume) (string, error) {
	devices, err := d.loopDevices(ctx, v)
	if err != nil {
		return "", err
	}
	switch len(devices) {
	case 0:
		out, err := d.run(ctx, nil, "losetup", "--find", "--show", "--direct-io=on", v.image)
		if err != nil {
			return "", err
		}
		device := strings.TrimSpace(string(out))
		if !strings.HasPrefix(device, "/dev/loop") {
			return "", status.Errorf(codes.Internal, "losetup returned unexpected device %q", device)
		}
		return device, nil
	case 1:
		return devices[0], nil
	default:
		return "", status.Errorf(codes.FailedPrecondition, "backing file %s is attached to several loop devices: %s", v.image, strings.Join(devices, ", "))
	}
}

// mapperBacking reports whether the volume's dm-crypt mapping is active and
// which device backs it.
func (d *Driver) mapperBacking(ctx context.Context, v volume) (bool, string, error) {
	out, err := d.runner.Run(ctx, nil, "cryptsetup", "status", v.mapper)
	if code, ok := exitCode(err); ok && code == 4 {
		return false, "", nil
	}
	if err != nil {
		return false, "", status.Error(codes.Internal, err.Error())
	}
	scanner := bufio.NewScanner(bytes.NewReader(out))
	for scanner.Scan() {
		key, value, found := strings.Cut(strings.TrimSpace(scanner.Text()), ":")
		if found && key == "device" {
			return true, strings.TrimSpace(value), nil
		}
	}
	return true, "", status.Errorf(codes.Internal, "cryptsetup status %s reported no backing device", v.mapper)
}

func (d *Driver) isLUKS(ctx context.Context, device string) (bool, error) {
	_, err := d.runner.Run(ctx, nil, "cryptsetup", "isLuks", "--type", "luks2", device)
	if err == nil {
		return true, nil
	}
	if code, ok := exitCode(err); ok && code == 1 {
		return false, nil
	}
	return false, status.Error(codes.Internal, err.Error())
}

// mountAt returns the topmost mount at path, or nil.
func (d *Driver) mountAt(path string) (*Mount, error) {
	mounts, err := d.mounts.Mounts()
	if err != nil {
		return nil, status.Errorf(codes.Internal, "read mount table: %v", err)
	}
	var found *Mount
	for i := range mounts {
		if mounts[i].MountPoint == path {
			found = &mounts[i]
		}
	}
	return found, nil
}

func (d *Driver) isVolumeMount(m *Mount, v volume) bool {
	if m.Source == v.mapperPath() {
		return true
	}
	number, err := d.host.DeviceNumber(v.mapperPath())
	return err == nil && number == m.MajorMinor
}

// volumeMounted reports whether the volume's filesystem is mounted at path,
// and fails when something else is.
func (d *Driver) volumeMounted(path string, v volume) (bool, error) {
	m, err := d.mountAt(path)
	if err != nil || m == nil {
		return false, err
	}
	if !d.isVolumeMount(m, v) {
		return false, status.Errorf(codes.FailedPrecondition, "%s is already mounted from %s, not volume %s", path, m.Source, v.id)
	}
	return true, nil
}

func checkPath(name, path string) error {
	if path == "" {
		return status.Errorf(codes.InvalidArgument, "%s is required", name)
	}
	if !filepath.IsAbs(path) || filepath.Clean(path) != path {
		return status.Errorf(codes.InvalidArgument, "%s %q must be an absolute, clean path", name, path)
	}
	return nil
}
