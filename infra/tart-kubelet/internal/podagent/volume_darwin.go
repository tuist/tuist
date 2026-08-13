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

// imageTreeBytes attaches the image read-only and sums the live bytes under each
// of its top-level trees. Read-only so it is safe beside a concurrent clone and
// cannot mutate what it measures, and the detach is deferred and its failure
// propagated: a leaked attach pins the image file against LRU eviction.
func (darwinVolumeBackend) imageTreeBytes(path string) (buckets map[string]uint64, err error) {
	mnt, err := os.MkdirTemp("", "tuist-cache-measure-")
	if err != nil {
		return nil, fmt.Errorf("mkdir measure mountpoint: %w", err)
	}
	defer os.RemoveAll(mnt)

	if _, err := runCmd(2*time.Minute, "hdiutil", "attach", path,
		"-readonly", "-owners", "off", "-nobrowse", "-noverify", "-quiet",
		"-mountpoint", mnt); err != nil {
		return nil, fmt.Errorf("attach image read-only: %w", err)
	}
	defer func() {
		if _, derr := runCmd(1*time.Minute, "hdiutil", "detach", mnt, "-force", "-quiet"); derr != nil && err == nil {
			err = fmt.Errorf("detach measured image: %w", derr)
		}
	}()

	return treeLiveBytes(mnt)
}

// repackImage rebuilds src's live cache into a brand-new sparse image at dst,
// which is how a bloated master is reclaimed.
//
// `hdiutil compact` is deliberately NOT used. It was measured on 2026-07-18 to
// reclaim 4 MB of ~400 MB on a partially-churned image: APFS inside an image
// issues no TRIM to the virtual block device, so compact only ever reclaims an
// image that has been emptied outright. A churned master — which is every hot
// master — is exactly the case it cannot help with. Copying the live trees into
// a fresh image sidesteps the question entirely: the new file's size is the live
// content, whatever the old one had accumulated.
//
// The WHOLE volume is carried over, not a list of trees the host expects to find.
// The cap is a ceiling on the image; what lives inside it belongs to the guest.
// Today that is the binary cache under `tuist/` plus the folded Xcode compilation
// cache under `CompilationCache.noindex`, but an allowlist would silently drop
// the next store folded in beside them, and would repack a user-declared volume
// (spec #69) — which has neither of those trees — to empty. Since the repack
// keeps the master's generation, anything dropped is unrecoverable: convergence
// reads the generation as current and has nothing to adopt.
//
// `ditto` rather than `cp -R`: it preserves xattrs on symlinks, which is the
// whole reason this cache lives in a disk image instead of on the virtio-fs
// share (versioned framework bundles and the CLI's artifact signatures both
// depend on them).
//
// Detach failures are propagated, not swallowed. A source image left attached
// pins the blocks the repack was meant to reclaim, so the caller would swap in a
// new image and report a reclamation that did not happen; a target left attached
// would be renamed into place while still mounted.
func (b darwinVolumeBackend) repackImage(src, dst string, sizeGiB int) (err error) {
	if err := b.createImage(dst, sizeGiB); err != nil {
		return fmt.Errorf("create repack target image: %w", err)
	}

	srcMnt, err := os.MkdirTemp("", "tuist-cache-repack-src-")
	if err != nil {
		return fmt.Errorf("mkdir repack source mountpoint: %w", err)
	}
	defer os.RemoveAll(srcMnt)
	dstMnt, err := os.MkdirTemp("", "tuist-cache-repack-dst-")
	if err != nil {
		return fmt.Errorf("mkdir repack target mountpoint: %w", err)
	}
	defer os.RemoveAll(dstMnt)

	// Source read-only so a repack can never mutate the master it is copying
	// from, and so it is safe beside a concurrent read.
	if _, err := runCmd(2*time.Minute, "hdiutil", "attach", src,
		"-readonly", "-owners", "off", "-nobrowse", "-noverify", "-quiet",
		"-mountpoint", srcMnt); err != nil {
		return fmt.Errorf("attach source image read-only: %w", err)
	}
	defer func() {
		if _, derr := runCmd(1*time.Minute, "hdiutil", "detach", srcMnt, "-force", "-quiet"); derr != nil && err == nil {
			err = fmt.Errorf("detach repack source image: %w", derr)
		}
	}()

	if _, err := runCmd(2*time.Minute, "hdiutil", "attach", dst,
		"-owners", "off", "-nobrowse", "-noverify", "-quiet",
		"-mountpoint", dstMnt); err != nil {
		return fmt.Errorf("attach target image: %w", err)
	}
	defer func() {
		if _, derr := runCmd(1*time.Minute, "hdiutil", "detach", dstMnt, "-force", "-quiet"); derr != nil && err == nil {
			err = fmt.Errorf("detach repacked image: %w", derr)
		}
	}()

	entries, err := os.ReadDir(srcMnt)
	if err != nil {
		return fmt.Errorf("read source image root: %w", err)
	}
	for _, entry := range entries {
		// Dot-prefixed entries at the volume root are the filesystem's own
		// (.fseventsd, .Spotlight-V100, .Trashes); the fresh image grows its own.
		// This is the same "dotfiles are not cache content" rule inventoryDigest
		// applies, so the repacked image digests identically to its source.
		if strings.HasPrefix(entry.Name(), ".") {
			continue
		}
		if _, err := runCmd(30*time.Minute, "ditto",
			filepath.Join(srcMnt, entry.Name()), filepath.Join(dstMnt, entry.Name())); err != nil {
			return fmt.Errorf("ditto %s into repacked image: %w", entry.Name(), err)
		}
	}
	return nil
}
