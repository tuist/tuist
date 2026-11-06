package driver

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

// Fresh pools use 512 KiB chunks (thin/AGENTS.md). Existing 64 KiB pools stay
// supported by the driver, but this step only creates or confirms the new
// geometry.
const thinPrepareChunkBytes = int64(512 << 10)

const thinCheckPath = "/usr/sbin/thin_check"

// PreparePoolOptions describes the pool to create from free VG extents and
// the node-local opt-in written next to it. All sizes are bytes.
type PreparePoolOptions struct {
	VolumeGroup          string
	StateDir             string
	Pool                 string
	DataBytes            int64
	MetadataBytes        int64
	DataReserveBytes     int64
	MetadataReserveBytes int64
	MaxVolumes           int
}

type PreparePoolResult struct {
	Layout        string     `json:"layout"`
	Mode          string     `json:"mode"`
	VolumeGroup   string     `json:"volume_group"`
	PoolUUID      string     `json:"pool_uuid"`
	DataBytes     int64      `json:"data_bytes"`
	MetadataBytes int64      `json:"metadata_bytes"`
	ChunkBytes    int64      `json:"chunk_bytes"`
	Config        ThinConfig `json:"config"`
	Created       bool       `json:"created"`
	ConfigWritten bool       `json:"config_written"`
}

func (o PreparePoolOptions) config() ThinConfig {
	return ThinConfig{Pool: o.Pool, DataReserveBytes: o.DataReserveBytes, MetadataReserveBytes: o.MetadataReserveBytes, MaxVolumes: o.MaxVolumes}
}

func (o PreparePoolOptions) validate() error {
	if err := checkStateDir(o.StateDir); err != nil {
		return err
	}
	if !volumeGroupPattern.MatchString(o.VolumeGroup) {
		return fmt.Errorf("invalid volume group %q", o.VolumeGroup)
	}
	if strings.HasPrefix(o.Pool, "pvc-") {
		return fmt.Errorf("pool name %q is reserved for volumes", o.Pool)
	}
	if err := o.config().validate(o.VolumeGroup); err != nil {
		return err
	}
	if o.DataBytes%mib != 0 || o.MetadataBytes%mib != 0 || o.DataReserveBytes%mib != 0 || o.MetadataReserveBytes%mib != 0 {
		return fmt.Errorf("sizes and reserves must be whole MiB")
	}
	if o.DataBytes < 1<<30 || o.DataBytes > 1<<50 || o.MetadataBytes < 64*mib || o.MetadataBytes > 16<<30 {
		return fmt.Errorf("data size must be 1 GiB to 1 PiB and metadata size 64 MiB to 16 GiB")
	}
	if o.DataReserveBytes >= o.DataBytes || o.MetadataReserveBytes >= o.MetadataBytes {
		return fmt.Errorf("reserves must be smaller than the pool")
	}
	// The conservative no-snapshot profile observeThin enforces: 128 bytes per
	// chunk, 1 MiB per device slot and the explicit reserve.
	minimum := ((o.DataBytes/thinPrepareChunkBytes)*128+mib-1)/mib*mib + int64(o.MaxVolumes)*mib + o.MetadataReserveBytes
	if o.MetadataBytes < minimum {
		return fmt.Errorf("metadata must be at least %d MiB for this data size, slot count and reserve", minimum/mib)
	}
	return nil
}

// PreparePool creates a NEW thin pool from free extents of the volume group
// and writes the private thin-pool.json the plugin loads on its next start.
// It never converts, shrinks or extends an LV and never consumes 100%FREE.
// Rerunning it is safe: a pool with the requested geometry and a matching
// configuration is left untouched, and any difference is refused.
func PreparePool(ctx context.Context, runner Runner, o PreparePoolOptions) (*PreparePoolResult, error) {
	if err := o.validate(); err != nil {
		return nil, err
	}
	// Host prerequisites come first, before any read that could lead to a
	// mutation. Loading the module belongs to host preparation, not to CSI.
	out, err := runner.Run(ctx, nil, "dmsetup", "targets")
	if err != nil {
		return nil, fmt.Errorf("cannot inspect kernel device-mapper targets: %w", err)
	}
	loaded := false
	for _, line := range strings.Split(string(out), "\n") {
		if f := strings.Fields(line); len(f) > 0 && f[0] == "thin-pool" {
			loaded = true
		}
	}
	if !loaded {
		return nil, errors.New("host prerequisite missing: load dm_thin_pool and configure its availability after reboot before preparing thin storage")
	}
	if _, err := runner.Run(ctx, nil, thinCheckPath, "--version"); err != nil {
		return nil, fmt.Errorf("host prerequisite missing: thin-provisioning-tools (%s) is unavailable: %w", thinCheckPath, err)
	}

	d := &Driver{runner: runner, volumeGroup: o.VolumeGroup, stateDir: o.StateDir}
	unlock, err := d.lockPool(ctx)
	if err != nil {
		return nil, err
	}
	defer unlock()

	want := o.config()
	configPath := filepath.Join(o.StateDir, "thin-pool.json")
	configExists := true
	if _, err := os.Lstat(configPath); errors.Is(err, fs.ErrNotExist) {
		configExists = false
	} else if err != nil {
		return nil, err
	}
	if configExists {
		have, err := LoadThinConfig(o.StateDir)
		if err != nil {
			return nil, fmt.Errorf("existing thin-pool.json: %w", err)
		}
		if have != want {
			return nil, fmt.Errorf("existing thin-pool.json %+v differs from the requested %+v; inspect it instead of rewriting it", have, want)
		}
	}

	out, err = d.lvm(ctx, "vgs", "--noheadings", "--units", "b", "--nosuffix", "--separator", ",", "-o", "vg_free,vg_extent_size", o.VolumeGroup)
	if code, ok := exitCode(err); ok && code == lvmNotFound {
		return nil, fmt.Errorf("volume group %s does not exist", o.VolumeGroup)
	}
	if err != nil {
		return nil, err
	}
	freeText, extentText, _ := strings.Cut(strings.TrimSpace(string(out)), ",")
	free, err := exactBytes(freeText)
	if err != nil {
		return nil, fmt.Errorf("parse free space of %s: %q", o.VolumeGroup, out)
	}
	extent, err := exactBytes(extentText)
	if err != nil || extent <= 0 {
		return nil, fmt.Errorf("parse extent size of %s: %q", o.VolumeGroup, out)
	}
	// LVM rounds sizes up to whole extents, which would make a rerun look
	// like a geometry change. Require the exact geometry instead.
	if o.DataBytes%extent != 0 || o.MetadataBytes%extent != 0 {
		return nil, fmt.Errorf("data and metadata sizes must be multiples of the %d byte extent size of %s", extent, o.VolumeGroup)
	}

	rows, err := d.thinLVs(ctx)
	if err != nil {
		return nil, err
	}
	result := &PreparePoolResult{Layout: ThinLayout, Mode: ThinMode, VolumeGroup: o.VolumeGroup, DataBytes: o.DataBytes, MetadataBytes: o.MetadataBytes, ChunkBytes: thinPrepareChunkBytes, Config: want}
	pool := findLV(rows, o.Pool)
	if pool == nil {
		if configExists {
			return nil, fmt.Errorf("thin-pool.json names %s/%s, which does not exist; inspect the node instead of recreating its pool", o.VolumeGroup, o.Pool)
		}
		// Metadata and LVM's metadata spare, plus room for extent rounding.
		if free < o.DataBytes+2*o.MetadataBytes+16*mib {
			return nil, fmt.Errorf("insufficient unallocated space in %s: %d bytes free", o.VolumeGroup, free)
		}
		if _, err := d.lvm(ctx, "lvcreate", "--yes", "--type", "thin-pool",
			"--size", strconv.FormatInt(o.DataBytes/mib, 10)+"M",
			"--poolmetadatasize", strconv.FormatInt(o.MetadataBytes/mib, 10)+"M",
			"--chunksize", "512K", "--zero", "y", "--discards", "passdown", "--errorwhenfull", "y",
			"--name", o.Pool, o.VolumeGroup); err != nil {
			return nil, err
		}
		result.Created = true
		if rows, err = d.thinLVs(ctx); err != nil {
			return nil, err
		}
		if pool = findLV(rows, o.Pool); pool == nil {
			return nil, errors.New("created pool missing from inventory")
		}
	}
	if err := d.checkPreparedPool(ctx, pool, o); err != nil {
		if result.Created {
			return nil, fmt.Errorf("created pool does not have the requested geometry, leaving it for inspection: %w", err)
		}
		return nil, fmt.Errorf("%s/%s already exists with a different geometry; never change a pool in place: %w", o.VolumeGroup, o.Pool, err)
	}
	result.PoolUUID = pool.UUID
	if configExists {
		return result, nil
	}
	if !result.Created {
		// A matching pool without configuration is an interrupted run, which
		// is only safe to complete while nothing has been allocated from it.
		for _, lv := range rows {
			if lv.Pool == o.Pool {
				return nil, fmt.Errorf("%s/%s already holds thin volumes but has no thin-pool.json; inspect it instead of adopting it", o.VolumeGroup, o.Pool)
			}
		}
	}
	if err := writeThinConfig(configPath, want); err != nil {
		return nil, err
	}
	if err := syncDir(o.StateDir); err != nil {
		return nil, err
	}
	result.ConfigWritten = true
	return result, nil
}

func findLV(rows []thinLV, name string) *thinLV {
	for i := range rows {
		if rows[i].Name == name {
			return &rows[i]
		}
	}
	return nil
}

func (d *Driver) checkPreparedPool(ctx context.Context, pool *thinLV, o PreparePoolOptions) error {
	if pool.Segment != "thin-pool" {
		return fmt.Errorf("segment type is %q", pool.Segment)
	}
	for _, field := range []struct {
		name, value string
		want        int64
	}{
		{"data size", pool.Size, o.DataBytes},
		{"metadata size", pool.Metadata, o.MetadataBytes},
		{"chunk size", pool.Chunk, thinPrepareChunkBytes},
	} {
		got, err := exactBytes(field.value)
		if err != nil {
			return err
		}
		if got != field.want {
			return fmt.Errorf("%s is %d bytes, want %d", field.name, got, field.want)
		}
	}
	if len(pool.Attr) < 8 || pool.Attr[7] != 'z' {
		return errors.New("chunk zeroing is disabled")
	}
	out, err := d.lvm(ctx, "lvs", "--reportformat", "json", "-o", "lv_name,discards,lv_when_full", d.volumeGroup+"/"+pool.Name)
	if err != nil {
		return err
	}
	var report struct {
		Report []struct {
			LV []struct {
				Discards string `json:"discards"`
				WhenFull string `json:"lv_when_full"`
			} `json:"lv"`
		} `json:"report"`
	}
	if err := json.Unmarshal(out, &report); err != nil || len(report.Report) != 1 || len(report.Report[0].LV) != 1 {
		return fmt.Errorf("invalid pool policy report %q", out)
	}
	policy := report.Report[0].LV[0]
	if policy.Discards != "passdown" {
		return fmt.Errorf("discards is %q, want passdown", policy.Discards)
	}
	if policy.WhenFull != "error" {
		return fmt.Errorf("when-full policy is %q, want error", policy.WhenFull)
	}
	return nil
}

// writeThinConfig publishes the configuration under its final name only once
// it is complete and durable, so an interrupted run never leaves a partial
// file the plugin would refuse to start with.
func writeThinConfig(path string, c ThinConfig) error {
	b, err := json.Marshal(c)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(path+".new", os.O_WRONLY|os.O_CREATE|os.O_TRUNC|syscall.O_NOFOLLOW, 0600)
	if err != nil {
		return err
	}
	if err = f.Chmod(0600); err == nil {
		if _, err = f.Write(b); err == nil {
			err = f.Sync()
		}
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		_ = os.Remove(path + ".new")
		return err
	}
	return os.Rename(path+".new", path)
}
