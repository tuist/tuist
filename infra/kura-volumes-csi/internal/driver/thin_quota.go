package driver

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type quotaState struct{ used, hard int64 }

func (d *Driver) thinQuota(ctx context.Context, path string) (quotaState, error) {
	out, err := d.run(ctx, nil, "xfs_quota", "-x", "-c", "state -p", path)
	if err != nil {
		return quotaState{}, err
	}
	state := strings.Join(strings.Fields(string(out)), " ")
	if !strings.Contains(state, "Accounting: ON") || !strings.Contains(state, "Enforcement: ON") {
		return quotaState{}, fmt.Errorf("project quota enforcement is not active")
	}
	out, err = d.run(ctx, nil, "xfs_quota", "-x", "-c", "report -p -b -n", path)
	if err != nil {
		return quotaState{}, err
	}
	for _, line := range strings.Split(string(out), "\n") {
		f := strings.Fields(line)
		if len(f) >= 4 && f[0] == "#1" {
			used, e := exactBytes(f[1])
			if e != nil {
				return quotaState{}, e
			}
			hard, e := exactBytes(f[3])
			if e != nil || hard == 0 || hard > 1<<50 || used > 1<<50 {
				return quotaState{}, fmt.Errorf("invalid project quota")
			}
			return quotaState{used: used * 1024, hard: hard * 1024}, nil
		}
	}
	return quotaState{}, fmt.Errorf("project quota missing")
}
func (d *Driver) applyThinQuota(ctx context.Context, r *ThinVolume) error {
	hard := r.GrantBytes + thinWorkspace
	if hard%mib != 0 {
		return fmt.Errorf("quota must be MiB aligned")
	}
	value := strconv.FormatInt(hard/mib, 10) + "m"
	// Project ID zero and hard limit zero would remove enforcement.
	if _, err := d.run(ctx, nil, "xfs_quota", "-x", "-c", "limit -p bsoft="+value+" bhard="+value+" 1", r.StagingPath); err != nil {
		return err
	}
	q, err := d.thinQuota(ctx, r.StagingPath)
	if err != nil {
		return err
	}
	if q.hard != hard {
		return fmt.Errorf("quota read-back differs from durable grant")
	}
	return nil
}
func (d *Driver) verifyThin(ctx context.Context, v volume, r *ThinVolume) error {
	if d.thin.Pool == "" {
		return status.Error(codes.FailedPrecondition, "thin configuration is required to manage existing thin volumes")
	}
	rows, err := d.thinLVs(ctx)
	if err != nil {
		return err
	}
	found, poolFound := false, false
	for _, lv := range rows {
		if lv.Name == d.thin.Pool && lv.UUID == r.PoolUUID && lv.Segment == "thin-pool" {
			poolFound = true
		}
		if lv.Name == v.id {
			size, e := exactBytes(lv.Size)
			if e != nil {
				return e
			}
			if lv.UUID != r.LVUUID || r.LVUUID == "" || lv.Pool != d.thin.Pool || lv.Segment != "thin" || lv.Origin != "" || size != r.VirtualBytes {
				return status.Error(codes.FailedPrecondition, "thin LV identity or geometry changed")
			}
			found = true
		}
	}
	if !found || !poolFound {
		return status.Error(codes.FailedPrecondition, "thin LV or pool identity missing")
	}
	return nil
}
func (d *Driver) finishThinStage(ctx context.Context, v volume, r *ThinVolume, path string) error {
	// The path is CSI-owned, but xfs_quota has its own command parser. Refuse
	// whitespace/quotes rather than interpolating an ambiguous project path.
	if strings.ContainsAny(path, " \t\r\n\"'\\") {
		return status.Error(codes.InvalidArgument, "unsupported staging path")
	}
	if r.StagingPath != "" && r.StagingPath != path {
		mounted, err := d.volumeMounted(r.StagingPath, v)
		if err != nil {
			return err
		}
		if mounted {
			return status.Error(codes.FailedPrecondition, "volume staged elsewhere")
		}
	}
	r.StagingPath = path
	if _, err := d.run(ctx, nil, "xfs_quota", "-x", "-c", "project -s -p "+path+" 1", path); err != nil {
		return err
	}
	if err := d.applyThinQuota(ctx, r); err != nil {
		return err
	}
	return d.saveThin(v, r)
}
