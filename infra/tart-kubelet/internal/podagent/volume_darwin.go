//go:build darwin

package podagent

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

// darwinVolumeBackend implements volumeBackend with the real macOS mechanics:
// APFS `clonefile` (via `cp -c`) for instant CoW branching of a cache image,
// `df`/statfs for admission accounting, and `hdiutil` to create and inspect
// sparse APFS images. Masters and branches are single image files on the
// runner-cache APFS volume, so a clone is one metadata-only operation
// regardless of how much cache is inside.
type darwinVolumeBackend struct{}

func newVolumeBackend() volumeBackend { return darwinVolumeBackend{} }

func runCmd(timeout time.Duration, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %s: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// clonePath CoW-clones the file at src to dst. `cp -c` forces clonefile(2) and
// fails rather than silently falling back to a byte copy, so a cross-volume
// mistake surfaces instead of quietly costing a full copy. dst must not exist;
// its parent must.
func (darwinVolumeBackend) clonePath(src, dst string) error {
	if _, err := os.Stat(src); err != nil {
		return fmt.Errorf("clone source missing: %w", err)
	}
	if _, err := runCmd(2*time.Minute, "cp", "-c", src, dst); err != nil {
		return err
	}
	return nil
}

// createImage creates an empty sparse APFS disk image capped at sizeGiB. Sparse:
// the file is a few MB until the guest writes into it, so the cap is a ceiling
// rather than an allocation.
func (darwinVolumeBackend) createImage(path string, sizeGiB int) error {
	if sizeGiB <= 0 {
		return fmt.Errorf("cache image size must be positive, got %d", sizeGiB)
	}
	_, err := runCmd(2*time.Minute, "hdiutil", "create",
		"-size", strconv.Itoa(sizeGiB)+"g",
		"-fs", "APFS",
		"-volname", "TuistCache",
		"-type", "SPARSE",
		"-quiet", path)
	return err
}

// growImage raises a detached sparse image's capacity to sizeGiB, and the APFS
// container inside follows it. It reads the current size first because
// `hdiutil resize -size` also shrinks an image larger than the size it is given,
// and a master converged from a host with a larger ceiling must reach a job
// unchanged. A created image reports a few sectors under its nominal size, so
// anything within a MiB of the target is already grown.
func (darwinVolumeBackend) growImage(path string, sizeGiB int) error {
	if sizeGiB <= 0 {
		return fmt.Errorf("cache image size must be positive, got %d", sizeGiB)
	}
	out, err := runCmd(time.Minute, "hdiutil", "resize", "-limits", path)
	if err != nil {
		return err
	}
	fields := strings.Fields(out)
	if len(fields) != 3 {
		return fmt.Errorf("hdiutil resize -limits %s: want minimum, current and maximum, got %q", path, strings.TrimSpace(out))
	}
	currentSectors, err := strconv.ParseUint(fields[1], 10, 64)
	if err != nil {
		return fmt.Errorf("hdiutil resize -limits %s: current size %q: %w", path, fields[1], err)
	}
	const mib = uint64(1 << 20)
	if currentSectors*512+mib >= uint64(sizeGiB)<<30 {
		return nil
	}
	_, err = runCmd(2*time.Minute, "hdiutil", "resize", "-size", strconv.Itoa(sizeGiB)+"g", path)
	return err
}

// imageInventoryDigest attaches the image READ-ONLY at a private mountpoint and
// digests the cache home inside it. Read-only makes it safe to run beside a
// concurrent reader and unable to mutate what it measures; `-owners off` keeps
// the host's uid out of it; `-nobrowse` keeps it out of the Finder/`/Volumes`
// namespace.
//
// The detach is deferred so no path can leak an attach: a leaked attach pins the
// image file open, which would keep LRU eviction from ever reclaiming it.
func (darwinVolumeBackend) imageInventoryDigest(path string) (digest string, err error) {
	mnt, err := os.MkdirTemp("", "tuist-cache-inspect-")
	if err != nil {
		return "", fmt.Errorf("mkdir inspect mountpoint: %w", err)
	}
	defer os.RemoveAll(mnt)

	if _, err := runCmd(2*time.Minute, "hdiutil", "attach", path,
		"-readonly", "-owners", "off", "-nobrowse", "-noverify", "-quiet",
		"-mountpoint", mnt); err != nil {
		return "", fmt.Errorf("attach image read-only: %w", err)
	}
	defer func() {
		if _, derr := runCmd(1*time.Minute, "hdiutil", "detach", mnt, "-force", "-quiet"); derr != nil && err == nil {
			err = fmt.Errorf("detach inspected image: %w", derr)
		}
	}()

	return inventoryDigest(mnt)
}

// isMounted reports whether root is its own mounted volume rather than a bare
// mountpoint directory on the boot filesystem. A mount point's device id
// differs from its parent's; an unmounted path either does not exist (the
// volume never mounted) or, if a stale directory lingers, shares the boot
// volume's device id. This is the canonical mountpoint(1) check and, unlike
// `df`, cannot be fooled into reporting the boot volume's free space for an
// unmounted cache root.
func (darwinVolumeBackend) isMounted(root string) (bool, error) {
	rootInfo, err := os.Stat(root)
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}
	parentInfo, err := os.Stat(filepath.Dir(root))
	if err != nil {
		return false, err
	}
	rootStat, ok := rootInfo.Sys().(*syscall.Stat_t)
	if !ok {
		return false, fmt.Errorf("stat %s: unexpected FileInfo backing type", root)
	}
	parentStat, ok := parentInfo.Sys().(*syscall.Stat_t)
	if !ok {
		return false, fmt.Errorf("stat %s: unexpected FileInfo backing type", filepath.Dir(root))
	}
	return rootStat.Dev != parentStat.Dev, nil
}

// freeBytes reports available bytes on the filesystem holding root via `df`.
// statfs would avoid the fork, but df is dependency-free and the call is off
// the per-job hot path (admission, convergence and the reconcile tick only).
func (darwinVolumeBackend) freeBytes(root string) (uint64, error) {
	// Column 4 is available 1K blocks.
	return dfKilobytes(root, 3, "available")
}

// capacityBytes reports the size of the filesystem holding root via `df`. For
// the runner-cache APFS volume that is its quota.
func (darwinVolumeBackend) capacityBytes(root string) (uint64, error) {
	// Column 2 is the filesystem's size in 1K blocks.
	return dfKilobytes(root, 1, "size")
}

func dfKilobytes(root string, column int, name string) (uint64, error) {
	out, err := runCmd(30*time.Second, "df", "-P", "-k", root)
	if err != nil {
		return 0, err
	}
	// POSIX df: header line, then one data line: filesystem, size, used,
	// available, capacity, mount point.
	sc := bufio.NewScanner(strings.NewReader(out))
	var last string
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "Filesystem") {
			continue
		}
		last = line
	}
	if last == "" {
		return 0, fmt.Errorf("df returned no data line: %q", out)
	}
	fields := strings.Fields(last)
	if len(fields) <= column {
		return 0, fmt.Errorf("df line has too few columns: %q", last)
	}
	kb, err := strconv.ParseUint(fields[column], 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse df %s column %q: %w", name, fields[column], err)
	}
	return kb * 1024, nil
}

// noPageCache stops reads and writes through f from filling the unified buffer
// cache. A convergence streams a whole master through the host, and on a host
// whose guest is already backed by swap those pages come out of the guest's.
func noPageCache(f *os.File) {
	_, _ = unix.FcntlInt(f.Fd(), unix.F_NOCACHE, 1)
}

// PhysicalMemoryBytes is the host's installed RAM.
func PhysicalMemoryBytes() (uint64, error) {
	return unix.SysctlUint64("hw.memsize")
}

// allocatedBytes reports the blocks a sparse image actually occupies, not its
// nominal size.
func (darwinVolumeBackend) allocatedBytes(path string) (uint64, error) {
	info, err := os.Stat(path)
	if err != nil {
		return 0, err
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return 0, fmt.Errorf("stat %s: unexpected FileInfo backing type", path)
	}
	return uint64(st.Blocks) * 512, nil
}
