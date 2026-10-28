//go:build linux

package diskallocator

import (
	"bufio"
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

type XFS struct {
	Mount      string
	VolumeRoot string
	Reserve    uint64
	Capacity   uint64
}

func command(name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%s: %w: %s", name, err, out)
	}
	return string(out), nil
}

func (x *XFS) volumePath(v Volume) (string, error) {
	path, err := filepath.EvalSymlinks(v.Path)
	if err != nil {
		return "", err
	}
	root, err := filepath.EvalSymlinks(x.Mount)
	if err != nil {
		return "", err
	}
	allowed := strings.HasPrefix(path, root+string(filepath.Separator))
	if x.VolumeRoot != "" {
		alias, err := filepath.EvalSymlinks(x.VolumeRoot)
		if err != nil || alias != x.VolumeRoot {
			return "", fmt.Errorf("invalid provisioner volume root")
		}
		allowed = allowed || strings.HasPrefix(path, alias+string(filepath.Separator))
	}
	if path != v.Path || !allowed {
		return "", fmt.Errorf("volume %q is outside quota filesystem or contains a symlink", v.ID)
	}
	var stat, rootStat unix.Stat_t
	if err := unix.Stat(path, &stat); err != nil {
		return "", err
	}
	if err := unix.Stat(root, &rootStat); err != nil {
		return "", err
	}
	if stat.Dev != rootStat.Dev {
		return "", fmt.Errorf("volume %q is on another filesystem", v.ID)
	}
	return path, nil
}

func (x *XFS) project(v Volume) (uint32, error) {
	path, err := x.volumePath(v)
	if err != nil {
		return 0, err
	}
	out, err := command("xfs_io", "-c", "stat", path)
	if err != nil {
		return 0, err
	}
	var id uint64
	inherit := false
	for _, line := range strings.Split(out, "\n") {
		if key, value, ok := strings.Cut(line, "="); ok {
			if strings.TrimSpace(key) == "fsxattr.projid" {
				id, err = strconv.ParseUint(strings.TrimSpace(value), 10, 32)
			}
			if strings.TrimSpace(key) == "fsxattr.xflags" {
				fields := strings.Fields(value)
				if len(fields) > 0 {
					flags, _ := strconv.ParseUint(fields[0], 0, 32)
					inherit = flags&0x200 != 0
				}
			}
		}
	}
	if err != nil || id == 0 || !inherit {
		return 0, fmt.Errorf("volume %q lacks an inherited project quota", v.ID)
	}
	return uint32(id), nil
}

type quota struct{ Used, Limit uint64 }

func parseReport(out string) (map[uint32]quota, error) {
	quotas := map[uint32]quota{}
	scanner := bufio.NewScanner(strings.NewReader(out))
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) == 0 {
			continue
		}
		if len(fields) < 4 {
			return nil, fmt.Errorf("malformed XFS quota report")
		}
		id, err := strconv.ParseUint(strings.TrimPrefix(fields[0], "#"), 10, 32)
		if err != nil {
			return nil, err
		}
		used, err := strconv.ParseUint(fields[1], 10, 64)
		if err != nil || used > ^uint64(0)/1024 {
			return nil, fmt.Errorf("invalid XFS usage")
		}
		limit, err := strconv.ParseUint(fields[3], 10, 64)
		if err != nil || limit > ^uint64(0)/1024 {
			return nil, fmt.Errorf("invalid XFS quota limit")
		}
		if _, exists := quotas[uint32(id)]; exists {
			return nil, fmt.Errorf("duplicate XFS project")
		}
		quotas[uint32(id)] = quota{used * 1024, limit * 1024}
	}
	return quotas, scanner.Err()
}

func (x *XFS) Read(volumes []Volume) ([]Sample, uint64, error) {
	var fs unix.Statfs_t
	if err := unix.Statfs(x.Mount, &fs); err != nil {
		return nil, 0, err
	}
	if fs.Type != unix.XFS_SUPER_MAGIC {
		return nil, 0, fmt.Errorf("shared disk requires XFS")
	}
	state, err := command("xfs_quota", "-x", "-c", "state -p", x.Mount)
	if err != nil {
		return nil, 0, err
	}
	if !strings.Contains(state, "Accounting: ON") || !strings.Contains(state, "Enforcement: ON") {
		return nil, 0, fmt.Errorf("XFS project accounting and enforcement must be enabled")
	}
	out, err := command("xfs_quota", "-x", "-c", "report -p -b -n -N", x.Mount)
	if err != nil {
		return nil, 0, err
	}
	quotas, err := parseReport(out)
	if err != nil {
		return nil, 0, err
	}
	managed := map[uint32]bool{}
	samples := make([]Sample, 0, len(volumes))
	var used uint64
	for _, v := range volumes {
		id, err := x.project(v)
		if err != nil {
			return nil, 0, err
		}
		if managed[id] {
			return nil, 0, fmt.Errorf("replicas share project %d", id)
		}
		q, ok := quotas[id]
		if !ok || q.Limit == 0 {
			return nil, 0, fmt.Errorf("missing finite quota for %q", v.ID)
		}
		managed[id] = true
		used += q.Used
		samples = append(samples, Sample{Volume: v, Used: q.Used, Current: q.Limit})
	}
	// statfs already excludes every project's actual usage. Also reserve the
	// still-unused portion of legacy/retained projects' finite quotas.
	available := fs.Bavail * uint64(fs.Bsize)
	for id, q := range quotas {
		if managed[id] || id == 0 {
			continue
		}
		if q.Limit == 0 {
			return nil, 0, fmt.Errorf("unmanaged project %d is unbounded", id)
		}
		if q.Limit > q.Used {
			available = subtract(available, q.Limit-q.Used)
		}
	}
	capacity := subtract(used+available, x.Reserve)
	if x.Capacity > 0 {
		capacity = min(capacity, x.Capacity)
	}
	return samples, capacity, nil
}

func (x *XFS) SetLimit(v Volume, bytes uint64) error {
	id, err := x.project(v)
	if err != nil {
		return err
	}
	if bytes < v.Floor || bytes > v.Ceiling {
		return fmt.Errorf("quota outside floor/ceiling")
	}
	// MiB alignment also aligns to the filesystem block size. XFS rounds
	// sub-block limits up, which would otherwise overstate free capacity.
	bytes = bytes / quotaUnit * quotaUnit
	_, err = command("xfs_quota", "-x", "-c", fmt.Sprintf("limit -p bsoft=%dk bhard=%dk %d", bytes/1024, bytes/1024, id), x.Mount)
	return err
}

func subtract(a, b uint64) uint64 {
	if b >= a {
		return 0
	}
	return a - b
}
