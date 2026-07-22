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

	return inventoryDigest(filepath.Join(mnt, cacheHomeSubdir))
}

// mergeInto unions the cache objects present in srcImage but absent from
// dstImage into dstImage, then returns the inventory digest of the merged
// dstImage. It attaches dstImage read-WRITE and srcImage read-only at private
// mountpoints, `ditto`s each object the destination lacks (ditto preserves the
// xattrs, symlinks and modes the signed cache relies on — a plain copy or `cp`
// would drop the xattrs-on-symlinks this whole disk-image design exists to
// carry), and recomputes the digest before detaching. Content-addressed objects
// already present in dst are skipped; nothing is ever removed.
//
// Both detaches are deferred so no path can leak an attach: a leaked attach pins
// the image file open, which would keep LRU eviction from ever reclaiming it.
func (darwinVolumeBackend) mergeInto(dstImage, srcImage string) (digest string, err error) {
	dstMnt, err := os.MkdirTemp("", "tuist-cache-merge-dst-")
	if err != nil {
		return "", fmt.Errorf("mkdir merge target mountpoint: %w", err)
	}
	defer os.RemoveAll(dstMnt)
	srcMnt, err := os.MkdirTemp("", "tuist-cache-merge-src-")
	if err != nil {
		return "", fmt.Errorf("mkdir merge source mountpoint: %w", err)
	}
	defer os.RemoveAll(srcMnt)

	if _, err := runCmd(2*time.Minute, "hdiutil", "attach", dstImage,
		"-owners", "off", "-nobrowse", "-noverify", "-quiet",
		"-mountpoint", dstMnt); err != nil {
		return "", fmt.Errorf("attach merge target read-write: %w", err)
	}
	defer func() {
		if _, derr := runCmd(1*time.Minute, "hdiutil", "detach", dstMnt, "-force", "-quiet"); derr != nil && err == nil {
			err = fmt.Errorf("detach merge target: %w", derr)
		}
	}()

	if _, err := runCmd(2*time.Minute, "hdiutil", "attach", srcImage,
		"-readonly", "-owners", "off", "-nobrowse", "-noverify", "-quiet",
		"-mountpoint", srcMnt); err != nil {
		return "", fmt.Errorf("attach merge source read-only: %w", err)
	}
	defer func() {
		if _, derr := runCmd(1*time.Minute, "hdiutil", "detach", srcMnt, "-force", "-quiet"); derr != nil && err == nil {
			err = fmt.Errorf("detach merge source: %w", derr)
		}
	}()

	dstHome := filepath.Join(dstMnt, cacheHomeSubdir)
	srcHome := filepath.Join(srcMnt, cacheHomeSubdir)
	for _, obj := range objectsToMerge(srcHome, dstHome) {
		dstObj := filepath.Join(dstHome, obj)
		if err := os.MkdirAll(filepath.Dir(dstObj), 0o755); err != nil {
			return "", fmt.Errorf("mkdir merge object parent for %s: %w", obj, err)
		}
		if _, err := runCmd(5*time.Minute, "ditto", filepath.Join(srcHome, obj), dstObj); err != nil {
			return "", fmt.Errorf("ditto merge object %s: %w", obj, err)
		}
	}
	return inventoryDigest(dstHome)
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
// the per-job hot path (admission + reconcile tick only).
func (darwinVolumeBackend) freeBytes(root string) (uint64, error) {
	out, err := runCmd(30*time.Second, "df", "-P", "-k", root)
	if err != nil {
		return 0, err
	}
	// POSIX df: header line, then one data line. Column 4 is available 1K
	// blocks. Filesystems with spaces in the device name still keep the
	// numeric columns right-aligned, so index from the end is safest.
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
	if len(fields) < 4 {
		return 0, fmt.Errorf("df line has too few columns: %q", last)
	}
	availKB, err := strconv.ParseUint(fields[3], 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse df available column %q: %w", fields[3], err)
	}
	return availKB * 1024, nil
}
