package driver

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const ThinLayout = "thin-luks-xfs-v1"
const ThinMode = "ceiling-backed-v1"
const thinWorkspace = int64(2 << 30)
const thinFixedOverhead = int64(288 << 20)
const thinAlignment = int64(64 << 20)

// ThinConfig opts into an explicitly prepared pool. CSI never converts an
// existing LV or consumes free VG extents to create/extend the pool itself.
type ThinConfig struct {
	Pool                 string `json:"pool"`
	DataReserveBytes     int64  `json:"data_reserve_bytes"`
	MetadataReserveBytes int64  `json:"metadata_reserve_bytes"`
	MaxVolumes           int    `json:"max_volumes"`
}

func (c ThinConfig) validate(vg string) error {
	if c.Pool == "" {
		return nil
	}
	if vg == "" || !volumeGroupPattern.MatchString(c.Pool) || c.Pool == "data" || volumeIDPattern.MatchString(c.Pool) {
		return fmt.Errorf("invalid thin pool")
	}
	if c.DataReserveBytes < 64*mib || c.MetadataReserveBytes < 16*mib || c.MaxVolumes < 1 || c.MaxVolumes > 1024 || c.DataReserveBytes > 1<<50 || c.MetadataReserveBytes > 16<<30 {
		return fmt.Errorf("thin pool requires explicit data/metadata reserves and 1..1024 volume slots")
	}
	return nil
}

// ThinVirtualBytes translates useful cache bytes into a fully backed block
// device. The project allowance includes staging/rotation workspace; XFS and
// LUKS metadata are outside it. No physical-overcommit mode is implemented.
func ThinVirtualBytes(cache int64) (int64, error) {
	if cache < mib || cache > 1<<50 {
		return 0, fmt.Errorf("cache ceiling must be between 1 MiB and 1 PiB")
	}
	size := cache + thinWorkspace + thinFixedOverhead + (cache+19)/20
	return (size + thinAlignment - 1) / thinAlignment * thinAlignment, nil
}

type ThinVolume struct {
	UnitOperation *BorrowedOperation `json:"unit_operation,omitempty"`
	BorrowedUnits bool               `json:"borrowed_units,omitempty"`
	UnitPhase     string             `json:"unit_phase,omitempty"`

	Version       int               `json:"version"`
	VolumeID      string            `json:"volume_id"`
	LVUUID        string            `json:"lv_uuid"`
	PoolUUID      string            `json:"pool_uuid"`
	VirtualBytes  int64             `json:"virtual_bytes"`
	FloorBytes    int64             `json:"floor_cache_bytes"`
	GrantBytes    int64             `json:"grant_cache_bytes"`
	CeilingBytes  int64             `json:"ceiling_cache_bytes"`
	Generation    uint64            `json:"generation"`
	LastOperation string            `json:"last_operation,omitempty"`
	StagingPath   string            `json:"staging_path,omitempty"`
	PodUID        string            `json:"pod_uid,omitempty"`
	Targets       map[string]string `json:"targets,omitempty"`
}

func (d *Driver) thinRecordPath(v volume) string { return filepath.Join(d.stateDir, v.id+".thin.json") }
func (d *Driver) readThin(v volume) (*ThinVolume, error) {
	f, err := os.OpenFile(d.thinRecordPath(v), os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Size() > 16384 {
		return nil, fmt.Errorf("invalid thin record")
	}
	var r ThinVolume
	dec := json.NewDecoder(f)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&r); err != nil {
		return nil, err
	}
	if err := dec.Decode(new(any)); err != io.EOF {
		return nil, fmt.Errorf("trailing thin record data")
	}
	virtual, err := ThinVirtualBytes(r.CeilingBytes)
	if err != nil || r.Version != 1 || r.VolumeID != v.id || r.VirtualBytes != virtual || r.FloorBytes < mib || r.GrantBytes < r.FloorBytes || r.GrantBytes > r.CeilingBytes || r.Generation == 0 || r.PoolUUID == "" || r.GrantBytes%mib != 0 || r.CeilingBytes%mib != 0 {
		return nil, fmt.Errorf("invalid thin record for %s", v.id)
	}
	if err := validateBorrowedRecord(&r); err != nil {
		return nil, err
	}
	return &r, nil
}
func (d *Driver) saveThin(v volume, r *ThinVolume) error {
	b, err := json.Marshal(r)
	if err != nil {
		return err
	}
	if len(b) > 16384 {
		return fmt.Errorf("thin record too large")
	}
	path := d.thinRecordPath(v)
	f, err := os.OpenFile(path+".new", os.O_WRONLY|os.O_CREATE|os.O_TRUNC|syscall.O_NOFOLLOW, 0600)
	if err != nil {
		return err
	}
	if _, err = f.Write(b); err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	if err = os.Rename(path+".new", path); err != nil {
		return err
	}
	return syncDir(d.stateDir)
}

type thinLV struct {
	Name     string `json:"lv_name"`
	UUID     string `json:"lv_uuid"`
	Pool     string `json:"pool_lv"`
	Size     string `json:"lv_size"`
	Segment  string `json:"segtype"`
	Origin   string `json:"origin"`
	Attr     string `json:"lv_attr"`
	Active   string `json:"lv_active"`
	Chunk    string `json:"chunk_size"`
	Metadata string `json:"lv_metadata_size"`
}

func exactBytes(s string) (int64, error) {
	s = strings.TrimSpace(s)
	if a, b, ok := strings.Cut(s, "."); ok {
		if strings.Trim(b, "0") != "" {
			return 0, fmt.Errorf("fractional bytes")
		}
		s = a
	}
	n, e := strconv.ParseInt(s, 10, 64)
	if e != nil || n < 0 {
		return 0, fmt.Errorf("invalid byte count %q", s)
	}
	return n, nil
}
func (d *Driver) thinLVs(ctx context.Context) ([]thinLV, error) {
	out, err := d.lvm(ctx, "lvs", "--reportformat", "json", "--units", "b", "--nosuffix", "-o", "lv_name,lv_uuid,pool_lv,lv_size,segtype,origin,lv_attr,lv_active,chunk_size,lv_metadata_size", d.volumeGroup)
	if err != nil {
		return nil, err
	}
	var report struct {
		Report []struct {
			LV []thinLV `json:"lv"`
		} `json:"report"`
	}
	if err = json.Unmarshal(out, &report); err != nil {
		return nil, err
	}
	if len(report.Report) != 1 {
		return nil, fmt.Errorf("invalid LVM inventory")
	}
	return report.Report[0].LV, nil
}
func dmName(vg, name string) string {
	return strings.ReplaceAll(vg, "-", "--") + "-" + strings.ReplaceAll(name, "-", "--")
}

type ThinObservation struct {
	ThinVolume
	MappedBytes    int64  `json:"mapped_bytes"`
	QuotaUsedBytes *int64 `json:"quota_used_bytes,omitempty"`
	QuotaHardBytes *int64 `json:"quota_hard_bytes,omitempty"`
	Unknown        bool   `json:"unknown"`
}
type ThinSnapshot struct {
	Version             int               `json:"version"`
	Mode                string            `json:"mode"`
	NodeID              string            `json:"node_id"`
	PoolUUID            string            `json:"pool_uuid"`
	ObservedAt          time.Time         `json:"observed_at"`
	DurationMS          int64             `json:"duration_ms"`
	ChunkBytes          int64             `json:"chunk_bytes"`
	DataTotal           int64             `json:"data_total_bytes"`
	DataUsed            int64             `json:"data_used_bytes"`
	MetadataTotal       int64             `json:"metadata_total_bytes"`
	MetadataUsed        int64             `json:"metadata_used_bytes"`
	DataReserve         int64             `json:"data_reserve_bytes"`
	MetadataReserve     int64             `json:"metadata_reserve_bytes"`
	CommittedBytes      int64             `json:"committed_bytes"`
	UnattributedBytes   int64             `json:"unattributed_mapped_bytes"`
	UsableBytes         int64             `json:"usable_bytes"`
	AvailableCommitment int64             `json:"available_commitment_bytes"`
	Healthy             bool              `json:"healthy"`
	Reason              string            `json:"reason,omitempty"`
	Volumes             []ThinObservation `json:"volumes"`
}

func parsePair(s string, unit int64) (int64, int64, error) {
	a, b, ok := strings.Cut(s, "/")
	if !ok {
		return 0, 0, fmt.Errorf("invalid pool counters")
	}
	x, e := exactBytes(a)
	if e != nil {
		return 0, 0, e
	}
	y, e := exactBytes(b)
	if e != nil || x > y || y > math.MaxInt64/unit {
		return 0, 0, fmt.Errorf("invalid pool counters")
	}
	return x * unit, y * unit, nil
}

// observeThin is called with the pool lock. Complete virtual devices remain
// reserved until both the LV and its durable record have been removed.
func (d *Driver) observeThin(ctx context.Context) (*ThinSnapshot, error) {
	start := time.Now()
	rows, err := d.thinLVs(ctx)
	if err != nil {
		return nil, err
	}
	var pool *thinLV
	for i := range rows {
		if rows[i].Name == d.thin.Pool {
			pool = &rows[i]
		}
	}
	if pool == nil || pool.Segment != "thin-pool" {
		return nil, status.Error(codes.FailedPrecondition, "configured thin pool is absent")
	}
	chunk, err := exactBytes(pool.Chunk)
	if err != nil || chunk < 65536 || chunk > 1<<20 {
		return nil, fmt.Errorf("unsupported thin chunk size")
	}
	// Every observation would otherwise take a VG-wide LVM operation even
	// though the pool is almost always active already.
	if strings.TrimSpace(pool.Active) != "active" {
		if _, err = d.lvm(ctx, "lvchange", "--activate", "y", d.volumeGroup+"/"+d.thin.Pool); err != nil {
			return nil, err
		}
	}
	out, err := d.run(ctx, nil, "dmsetup", "status", dmName(d.volumeGroup, d.thin.Pool)+"-tpool")
	if err != nil {
		// LVM exposes an empty active pool directly; after the first thin device
		// the same target moves behind the -tpool layer. Validate either payload.
		out, err = d.run(ctx, nil, "dmsetup", "status", dmName(d.volumeGroup, d.thin.Pool))
	}
	if err != nil {
		return nil, err
	}
	fields := strings.Fields(string(out))
	if len(fields) < 11 || fields[2] != "thin-pool" {
		return nil, fmt.Errorf("invalid thin pool status")
	}
	mu, mt, err := parsePair(fields[4], 4096)
	if err != nil {
		return nil, err
	}
	du, dt, err := parsePair(fields[5], chunk)
	if err != nil {
		return nil, err
	}
	s := &ThinSnapshot{Version: 1, Mode: ThinMode, NodeID: d.nodeID, PoolUUID: pool.UUID, ChunkBytes: chunk, DataTotal: dt, DataUsed: du, MetadataTotal: mt, MetadataUsed: mu, DataReserve: d.thin.DataReserveBytes, MetadataReserve: d.thin.MetadataReserveBytes, Healthy: true, Volumes: []ThinObservation{}}
	reject := func(reason string) { s.Healthy = false; s.Reason = reason }
	if len(pool.Attr) < 8 || pool.Attr[7] != 'z' {
		reject("thin chunk zeroing is required")
	}
	if fields[7] != "rw" || fields[8] == "ignore_discard" || fields[9] != "error_if_no_space" || fields[10] != "-" {
		reject("unqualified pool state")
	}
	// Bound metadata for the entire pool, not only current mappings. This
	// deliberately conservative no-snapshot profile reserves 128 bytes per
	// chunk, 1 MiB per device and an additional explicit safety reserve.
	if dt/chunk > math.MaxInt64/128 || mt < (dt/chunk)*128+int64(d.thin.MaxVolumes)*mib+s.MetadataReserve {
		reject("metadata sizing below conservative profile")
	}
	if dt <= s.DataReserve || du > dt-s.DataReserve || mu > mt-s.MetadataReserve {
		reject("pool reserve reached")
	}
	seen := map[string]bool{}
	var mappedTotal int64
	for _, lv := range rows {
		if lv.Pool != d.thin.Pool {
			continue
		}
		size, err := exactBytes(lv.Size)
		if err != nil {
			return nil, err
		}
		if size > math.MaxInt64-s.CommittedBytes {
			return nil, fmt.Errorf("commitment overflow")
		}
		s.CommittedBytes += size
		if lv.Segment != "thin" || lv.Origin != "" {
			reject("snapshots and external origins are unsupported")
		}
		v, ve := d.volume(lv.Name)
		if ve != nil {
			reject("unknown pool member")
			continue
		}
		r, err := d.readThin(v)
		if err != nil {
			return nil, err
		}
		unknown := r == nil || r.PoolUUID != pool.UUID || (r.LVUUID != "" && r.LVUUID != lv.UUID) || (r != nil && r.VirtualBytes != size)
		if r == nil {
			r = &ThinVolume{VolumeID: lv.Name, LVUUID: lv.UUID, PoolUUID: pool.UUID, VirtualBytes: size}
		}
		if unknown {
			reject("unknown or mismatched volume")
		}
		seen[v.id] = true
		// Activation of the thin block device needs no encryption key and does
		// not mount it; this keeps retained/unstaged allocation observable.
		// An active device's kernel counters need no /dev node repair. Avoid
		// two redundant VG-wide LVM operations per device on every observation.
		// Inactive or unrecognized state still takes the full activation path;
		// a device disappearing after inventory fails the status read below.
		if strings.TrimSpace(lv.Active) != "active" {
			if _, err = d.activateLV(ctx, v); err != nil {
				return nil, err
			}
		}
		out, err := d.run(ctx, nil, "dmsetup", "status", dmName(d.volumeGroup, lv.Name))
		if err != nil {
			return nil, err
		}
		f := strings.Fields(string(out))
		if len(f) < 4 || f[2] != "thin" {
			return nil, fmt.Errorf("invalid thin volume status")
		}
		sectors, err := exactBytes(f[3])
		if err != nil || sectors > size/512 {
			return nil, fmt.Errorf("invalid mapped sectors")
		}
		o := ThinObservation{ThinVolume: *r, MappedBytes: sectors * 512, Unknown: unknown}
		mappedTotal += o.MappedBytes
		if r.StagingPath != "" {
			mounted, err := d.volumeMounted(r.StagingPath, v)
			if err != nil {
				return nil, err
			}
			if mounted {
				q, err := d.thinQuota(ctx, r.StagingPath)
				if err != nil {
					return nil, err
				}
				o.QuotaUsedBytes = &q.used
				o.QuotaHardBytes = &q.hard
				if q.hard != r.GrantBytes+thinWorkspace {
					reject("quota and durable grant disagree")
				}
			}
		}
		s.Volumes = append(s.Volumes, o)
	}
	records, err := filepath.Glob(filepath.Join(d.stateDir, "pvc-*.thin.json"))
	if err != nil {
		return nil, err
	}
	for _, path := range records {
		id := strings.TrimSuffix(filepath.Base(path), ".thin.json")
		if seen[id] {
			continue
		}
		v, err := d.volume(id)
		if err != nil {
			return nil, err
		}
		r, err := d.readThin(v)
		if err != nil || r == nil {
			return nil, fmt.Errorf("unreadable thin intent")
		}
		if r.PoolUUID != pool.UUID {
			return nil, fmt.Errorf("pool identity changed")
		}
		if r.VirtualBytes > math.MaxInt64-s.CommittedBytes {
			return nil, fmt.Errorf("commitment overflow")
		}
		s.CommittedBytes += r.VirtualBytes
		s.Volumes = append(s.Volumes, ThinObservation{ThinVolume: *r})
	}
	// Read the pool again AFTER the devices. Tenant writes may have allocated
	// more chunks meanwhile, so the difference is deliberately conservative.
	// In particular, deleted/unattributed mappings cannot become free admission
	// credit just because their LV disappeared from the LVM inventory. Mounts
	// use explicit trim (not continuous discard); all trims share this lock.
	poolOut, e := d.run(ctx, nil, "dmsetup", "status", dmName(d.volumeGroup, d.thin.Pool)+"-tpool")
	if e != nil {
		poolOut, e = d.run(ctx, nil, "dmsetup", "status", dmName(d.volumeGroup, d.thin.Pool))
	}
	if e != nil {
		return nil, e
	}
	latest := strings.Fields(string(poolOut))
	if len(latest) < 11 || latest[2] != "thin-pool" {
		return nil, fmt.Errorf("invalid final pool status")
	}
	latestUsed, latestTotal, e := parsePair(latest[5], chunk)
	if e != nil || latestTotal != dt {
		return nil, fmt.Errorf("pool geometry changed during observation")
	}
	latestMetadata, latestMetadataTotal, e := parsePair(latest[4], 4096)
	if e != nil || latestMetadataTotal != mt {
		return nil, fmt.Errorf("pool metadata geometry changed during observation")
	}
	s.DataUsed = latestUsed
	s.MetadataUsed = latestMetadata
	if latest[7] != "rw" || latest[8] == "ignore_discard" || latest[9] != "error_if_no_space" || latest[10] != "-" {
		reject("unqualified final pool state")
	}
	s.UnattributedBytes = max(0, s.DataUsed-mappedTotal)
	if s.UnattributedBytes > math.MaxInt64-s.CommittedBytes {
		return nil, fmt.Errorf("unattributed allocation overflow")
	}
	s.CommittedBytes += s.UnattributedBytes
	if s.DataUsed > dt-s.DataReserve || s.MetadataUsed > mt-s.MetadataReserve {
		reject("pool reserve reached")
	}
	if len(s.Volumes) > d.thin.MaxVolumes {
		reject("volume slot budget exceeded")
	}
	s.UsableBytes = max(0, dt-s.DataReserve)
	s.AvailableCommitment = max(0, s.UsableBytes-s.CommittedBytes)
	if s.CommittedBytes > s.UsableBytes {
		reject("virtual ceilings exceed physical backing")
	}
	s.ObservedAt = time.Now().UTC()
	s.DurationMS = time.Since(start).Milliseconds()
	return s, nil
}

func (d *Driver) createThin(ctx context.Context, v volume, cache int64, req *csi.CreateVolumeRequest) (*csi.CreateVolumeResponse, error) {
	if d.thin.Pool == "" {
		return nil, status.Error(codes.FailedPrecondition, "thin provisioning is not configured")
	}
	mode, err := encryptionMode(req.Parameters)
	if err != nil {
		return nil, err
	}
	if mode != encryptionLUKS2 {
		return nil, status.Error(codes.InvalidArgument, "thin layout requires LUKS2")
	}
	virtual, err := ThinVirtualBytes(cache)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	if limit := req.GetCapacityRange().GetLimitBytes(); limit > 0 && virtual > limit {
		return nil, status.Error(codes.OutOfRange, "ceiling plus overhead exceeds capacity limit")
	}
	r, err := d.readThin(v)
	if err != nil {
		return nil, err
	}
	if r != nil && (r.CeilingBytes != cache || r.BorrowedUnits != (req.GetParameters()["borrowed_units"] == "v1")) {
		return nil, status.Error(codes.AlreadyExists, "thin volume ceiling differs")
	}
	info, err := imageInfo(v)
	if err != nil {
		return nil, err
	}
	if info != nil {
		return nil, status.Error(codes.AlreadyExists, "volume is file backed")
	}
	s, err := d.observeThin(ctx)
	if err != nil {
		return nil, err
	}
	if !s.Healthy {
		return nil, status.Error(codes.ResourceExhausted, s.Reason)
	}
	rows, err := d.thinLVs(ctx)
	if err != nil {
		return nil, err
	}
	exists := false
	for _, lv := range rows {
		if lv.Name == v.id {
			if r == nil || lv.Pool != d.thin.Pool || lv.Segment != "thin" || lv.Origin != "" {
				return nil, status.Error(codes.AlreadyExists, "volume has another layout")
			}
			if r.LVUUID != "" && r.LVUUID != lv.UUID {
				return nil, status.Error(codes.FailedPrecondition, "LV identity changed")
			}
			r.LVUUID = lv.UUID
			exists = true
		}
	}
	if r == nil {
		if virtual > s.AvailableCommitment || len(s.Volumes) >= d.thin.MaxVolumes {
			return nil, status.Error(codes.ResourceExhausted, "complete virtual ceiling cannot be physically backed")
		}
		r = &ThinVolume{BorrowedUnits: req.GetParameters()["borrowed_units"] == "v1", Version: 1, VolumeID: v.id, PoolUUID: s.PoolUUID, VirtualBytes: virtual, FloorBytes: cache, GrantBytes: cache, CeilingBytes: cache, Generation: 1}
		if err = d.saveThin(v, r); err != nil {
			return nil, err
		}
	}
	if !exists {
		if err = writeMarker(v.marker); err != nil {
			return nil, err
		}
		if err = syncDir(d.stateDir); err != nil {
			return nil, err
		}
		if _, err = d.lvm(ctx, "lvcreate", "--yes", "--wipesignatures", "y", "--virtualsize", strconv.FormatInt(virtual, 10)+"b", "--thinpool", d.volumeGroup+"/"+d.thin.Pool, "--name", v.id); err != nil {
			return nil, err
		}
		rows, err = d.thinLVs(ctx)
		if err != nil {
			return nil, err
		}
		for _, lv := range rows {
			if lv.Name == v.id {
				r.LVUUID = lv.UUID
			}
		}
		if r.LVUUID == "" {
			return nil, fmt.Errorf("created LV missing from inventory")
		}
	}
	if err = d.saveThin(v, r); err != nil {
		return nil, err
	}
	return &csi.CreateVolumeResponse{Volume: &csi.Volume{VolumeId: v.id, CapacityBytes: virtual, AccessibleTopology: []*csi.Topology{d.topology()}, VolumeContext: map[string]string{encryptionParameter: encryptionLUKS2, "backing": "thin", "layout": ThinLayout, "lv_uuid": r.LVUUID, "pool_uuid": r.PoolUUID, "capacity_mode": ThinMode, "cache_ceiling_bytes": strconv.FormatInt(cache, 10), "borrowed_units": req.GetParameters()["borrowed_units"]}}}, nil
}

// LoadThinConfig supports node-by-node opt-in without changing the fleet-wide
// DaemonSet arguments. Preparing a node writes this root-owned file; restarting
// only that node's plugin adopts it. It is never reloaded mid-operation.
func LoadThinConfig(stateDir string) (ThinConfig, error) {
	var c ThinConfig
	f, err := os.OpenFile(filepath.Join(stateDir, "thin-pool.json"), os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if errors.Is(err, fs.ErrNotExist) {
		return c, nil
	}
	if err != nil {
		return c, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return c, err
	}
	if !info.Mode().IsRegular() || info.Size() > 4096 || info.Mode().Perm()&0077 != 0 {
		return c, fmt.Errorf("thin pool configuration must be a private regular file")
	}
	dec := json.NewDecoder(f)
	dec.DisallowUnknownFields()
	if err = dec.Decode(&c); err != nil {
		return c, err
	}
	if err = dec.Decode(new(any)); err != io.EOF {
		return c, fmt.Errorf("invalid thin pool configuration")
	}
	if c.Pool == "" {
		return c, fmt.Errorf("empty thin pool configuration")
	}
	return c, nil
}
