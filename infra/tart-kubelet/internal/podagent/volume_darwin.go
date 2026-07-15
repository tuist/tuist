//go:build darwin

package podagent

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// darwinVolumeBackend implements volumeBackend with the real macOS mechanics:
// APFS `clonefile` (via `cp -c -R`) for instant CoW directory branching, and
// `df`/statfs for admission accounting. Both masters and branches are ordinary
// directory trees on the runner-cache APFS volume, so there is no disk-image
// machinery — clone is a metadata-only operation whose cost tracks file count,
// not bytes (measured ~59 ms syscall / ~579 ms via cp for a 2.4 GB / 6.3k-file
// tree on staging).
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

// cloneTree CoW-clones the directory tree at src to dst. `cp -c` forces
// clonefile(2) and fails rather than silently falling back to a byte copy, so
// a cross-volume mistake surfaces instead of quietly costing a full copy. dst
// must not exist; its parent must.
func (darwinVolumeBackend) cloneTree(src, dst string) error {
	if _, err := os.Stat(src); err != nil {
		return fmt.Errorf("clone source missing: %w", err)
	}
	if _, err := runCmd(2*time.Minute, "cp", "-c", "-R", src, dst); err != nil {
		return err
	}
	return nil
}

// cloneFile CoW-clones a single file src to dst. `cp -c` forces clonefile(2)
// (no -R: the CAS disk image is one file), so a cross-volume mistake surfaces
// as an error instead of a silent full byte copy. dst must not exist.
//
// src must be a regular file: `cp -c` FOLLOWS a command-line symlink, and the
// only caller cloning a guest-writable path (the branch CAS image) could be
// pointed at another account's master by a hostile job swapping the image for a
// symlink. Reject non-regular sources here as a backend-level backstop to the
// caller's own Lstat guard.
func (darwinVolumeBackend) cloneFile(src, dst string) error {
	fi, err := os.Lstat(src)
	if err != nil {
		return fmt.Errorf("clone source missing: %w", err)
	}
	if !fi.Mode().IsRegular() {
		return fmt.Errorf("refusing to clone non-regular file %s (mode %s)", src, fi.Mode())
	}
	if _, err := runCmd(2*time.Minute, "cp", "-c", src, dst); err != nil {
		return err
	}
	return nil
}

// createSparseImage creates an empty sparse APFS disk image of logical size
// sizeGiB at path (hdiutil appends `.sparseimage`). Sparse so an account's CAS
// master costs only its real bytes, not the logical cap. The volume label is
// fixed so the guest mounts it at a predictable path.
func (darwinVolumeBackend) createSparseImage(path string, sizeGiB int) error {
	_, err := runCmd(2*time.Minute, "hdiutil", "create",
		"-size", fmt.Sprintf("%dg", sizeGiB),
		"-type", "SPARSE",
		"-fs", "APFS",
		"-volname", "TuistCAS",
		path,
	)
	return err
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
