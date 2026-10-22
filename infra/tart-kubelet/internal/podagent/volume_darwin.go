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

// darwinVolumeBackend probes the runner-cache APFS volume with `df` and stat.
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
// the per-job hot path (admission and the reconcile tick only).
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

// usedBytes reports the space the filesystem holding root uses via `df`. For an
// APFS volume that is the volume's own usage, not its container's.
func (darwinVolumeBackend) usedBytes(root string) (uint64, error) {
	// Column 3 is used 1K blocks.
	return dfKilobytes(root, 2, "used")
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

// allocatedBytes reports the blocks a sparse image actually occupies, not its
// nominal size.
func (darwinVolumeBackend) allocatedBytes(path string) (uint64, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return 0, err
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return 0, fmt.Errorf("stat %s: unexpected FileInfo backing type", path)
	}
	return uint64(st.Blocks) * 512, nil
}
