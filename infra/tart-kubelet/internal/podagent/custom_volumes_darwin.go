//go:build darwin

package podagent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

func createCustomImage(ctx context.Context, path string, bytes int64) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	_, err := exec.CommandContext(ctx, "hdiutil", "create", "-sectors", strconv.FormatInt(bytes/512, 10), "-fs", "APFS", "-volname", "TuistCustomCache", "-type", "SPARSE", "-quiet", path).CombinedOutput()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	return err
}

// createCustomDisk formats an empty ASIF image holding one APFS volume named
// for its lineage, which the guest mounts once Tart hot-plugs the image.
func createCustomDisk(ctx context.Context, slot cachevolumes.Slot, path string, bytes int64) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	size := strconv.FormatInt((bytes+999_999_999)/1_000_000_000, 10) + "G"
	out, err := exec.CommandContext(ctx, "diskutil", "image", "create", "blank", "--fs", "APFS", "--format", "ASIF", "--size", size, "--volumeName", cachevolumes.DiskVolumeName(slot.Scope), path).CombinedOutput()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if err != nil {
		return fmt.Errorf("%w (%s)", err, strings.TrimSpace(string(out)))
	}
	return nil
}

var customImageSize = regexp.MustCompile(`(?m)^\s*Total Bytes:\s*([0-9]+)\s*$`)

// growCustomImage extends a private copy's image file to bytes, never shrinking
// it. -imageonly changes only the image: the host never attaches the guest's
// filesystem, and the guest grows the APFS container after attaching it.
func growCustomImage(ctx context.Context, path string, bytes int64) error {
	return growImageOnly(ctx, path, bytes, []string{"hdiutil", "imageinfo", path},
		"hdiutil", "resize", "-sectors", strconv.FormatInt(bytes/512, 10), "-imageonly", path)
}

// growCustomDisk is growCustomImage for an ASIF image, which hdiutil cannot
// open. --image-only also moves the secondary GPT; the guest grows the
// container once the disk appears.
func growCustomDisk(ctx context.Context, path string, bytes int64) error {
	return growImageOnly(ctx, path, bytes, []string{"diskutil", "image", "info", path},
		"diskutil", "image", "resize", "--size", strconv.FormatInt(bytes, 10), "--image-only", path)
}

func growImageOnly(ctx context.Context, path string, bytes int64, info []string, resize ...string) error {
	ctx, cancel := context.WithTimeout(ctx, time.Minute)
	defer cancel()
	current, err := imageBytes(ctx, info...)
	if err != nil || current >= bytes {
		return err
	}
	_, err = exec.CommandContext(ctx, resize[0], resize[1:]...).CombinedOutput()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	return err
}

// customImageBytes is the image's size from its header. `hdiutil resize
// -limits` reports the partition instead, which only the guest grows.
func customImageBytes(ctx context.Context, path string) (int64, error) {
	return imageBytes(ctx, "hdiutil", "imageinfo", path)
}

// imageBytes reads Total Bytes, which both hdiutil imageinfo and diskutil
// image info print.
func imageBytes(ctx context.Context, info ...string) (int64, error) {
	out, err := exec.CommandContext(ctx, info[0], info[1:]...).Output()
	if err != nil {
		return 0, err
	}
	match := customImageSize.FindSubmatch(out)
	if match == nil {
		return 0, errors.New("image info reports no size")
	}
	return strconv.ParseInt(string(match[1]), 10, 64)
}

var customDisk = regexp.MustCompile(`^/dev/disk[0-9]+$`)
var customPartition = regexp.MustCompile(`^/dev/disk[0-9]+s[0-9]+$`)

// apfsContainerType is the APFS container's partition type as hdiutil prints it.
const apfsContainerType = "EF57347C-0000-11AA-AA11"

var customContainerInUse = regexp.MustCompile(`(?m)^\s*Capacity In Use By Volumes:\s*([0-9]+) B\b`)

func verifyCustomImage(path string) (int64, error) {
	return inspectCustomImage(path, runCmd)
}

// verifyCustomDisk is verifyCustomImage for an ASIF image, which only diskutil
// attaches. hdiutil still detaches it and finds it in detachCustomInspection.
func verifyCustomDisk(path string) (int64, error) {
	return inspectImage(runCmd, "diskutil", "image", "attach", "--readOnly", "--noMount", "--nobrowse", path)
}

// inspectCustomImage checks the image's APFS container and returns the bytes
// it holds, which is what the guest's statfs reported before it detached.
func inspectCustomImage(path string, run func(time.Duration, string, ...string) (string, error)) (held int64, err error) {
	// No APFS filesystem is mounted in the host kernel. fsck reads the raw
	// partition in userspace; -noautofsck prevents an implicit repair attempt.
	return inspectImage(run, "hdiutil", "attach", path, "-readonly", "-nomount", "-noautofsck", "-nobrowse")
}

func inspectImage(run func(time.Duration, string, ...string) (string, error), attach ...string) (held int64, err error) {
	out, err := run(2*time.Minute, attach[0], attach[1:]...)
	if err != nil {
		return 0, err
	}
	var disk, partition, container string
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		if disk == "" && customDisk.MatchString(fields[0]) {
			disk = fields[0]
		}
		if len(fields) > 1 && customPartition.MatchString(fields[0]) && fields[1] == "Apple_APFS" {
			partition = fields[0]
		}
		// hdiutil prints the container's type GUID, diskutil its name.
		if len(fields) > 1 && customDisk.MatchString(fields[0]) && (strings.HasPrefix(fields[1], apfsContainerType) || fields[1] == "Apple_APFS_Container") {
			container = fields[0]
		}
	}
	if disk == "" {
		return 0, errors.New("inspection returned no disk")
	}
	defer func() {
		if _, detachErr := run(time.Minute, "hdiutil", "detach", disk, "-quiet"); detachErr != nil {
			err = errors.Join(err, fmt.Errorf("detach inspected custom image: %w", detachErr))
		}
	}()
	if partition == "" {
		return 0, errors.New("inspection returned no APFS partition")
	}
	if container == "" {
		return 0, errors.New("inspection returned no APFS container")
	}
	if _, err = run(2*time.Minute, "/sbin/fsck_apfs", "-n", strings.Replace(partition, "/dev/disk", "/dev/rdisk", 1)); err != nil {
		return 0, err
	}
	// The read-only attach already exposes the unmounted container; this only
	// reads the space it reports.
	out, err = run(time.Minute, "diskutil", "apfs", "list", container)
	if err != nil {
		return 0, err
	}
	match := customContainerInUse.FindStringSubmatch(out)
	if match == nil {
		return 0, errors.New("inspection reported no APFS container usage")
	}
	return strconv.ParseInt(match[1], 10, 64)
}

// Discover the device by backing path, including a crash between attach and
// its output being read. Also reclaim inspection mounts from older agents.
func detachCustomInspection(path string) error {
	out, err := runCmd(time.Minute, "hdiutil", "info")
	if err != nil {
		return err
	}
	inspecting := false
	for _, line := range strings.Split(out, "\n") {
		if strings.HasPrefix(line, "image-path") {
			_, value, ok := strings.Cut(line, ":")
			inspecting = ok && strings.TrimSpace(value) == path
		}
		fields := strings.Fields(line)
		if inspecting && len(fields) > 0 && customDisk.MatchString(fields[0]) {
			if _, err := runCmd(time.Minute, "hdiutil", "detach", fields[0], "-quiet"); err != nil {
				return err
			}
			inspecting = false
		}
	}
	mount := path + ".mount"
	info, err := os.Stat(mount)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	parent, err := os.Stat(filepath.Dir(mount))
	if err != nil {
		return err
	}
	if info.Sys().(*syscall.Stat_t).Dev != parent.Sys().(*syscall.Stat_t).Dev {
		if _, err = runCmd(time.Minute, "hdiutil", "detach", mount, "-quiet"); err != nil {
			return err
		}
	}
	return os.Remove(mount)
}
