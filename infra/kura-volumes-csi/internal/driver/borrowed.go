package driver

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"syscall"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Only in-process calls made while holding the pool lock carry this marker.
// Nested child lifecycle calls still acquire their own volume lock.
type borrowedPoolLock struct{}

var childVolumeIDPattern = regexp.MustCompile(`^(pvc-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})-unit-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$`)

// BorrowedRequest always names the stable parent and its current pod generation.
// UnitID is immutable and never reused after release. Useful capacity is distinct
// from the full device commitment reported by ThinStatus.
type BorrowedRequest struct {
	ThinRequest
	UnitID     string `json:"unit_id"`
	CacheBytes int64  `json:"cache_bytes"`
	Action     string `json:"action"`
}

// One durable operation is retained for bounded retry/recovery. A lost response
// must not turn a retry into a second grant or resurrect a released unit.
type BorrowedOperation struct {
	ID         string `json:"id"`
	Generation uint64 `json:"generation"`
	UnitID     string `json:"unit_id"`
	Action     string `json:"action"`
	CacheBytes int64  `json:"cache_bytes"`
	Done       bool   `json:"done"`
}

func (o *BorrowedOperation) matches(req BorrowedRequest) bool {
	return o != nil && o.ID == req.OperationID && o.Generation == req.Generation && o.UnitID == req.UnitID && o.Action == req.Action && o.CacheBytes == req.CacheBytes
}

func unitCapability() *csi.VolumeCapability {
	return &csi.VolumeCapability{AccessType: &csi.VolumeCapability_Mount{Mount: &csi.VolumeCapability_MountVolume{FsType: "xfs"}}, AccessMode: &csi.VolumeCapability_AccessMode{Mode: csi.VolumeCapability_AccessMode_SINGLE_NODE_SINGLE_WRITER}}
}
func (d *Driver) borrowedChildren(parent string) ([]*ThinVolume, error) {
	paths, err := filepath.Glob(filepath.Join(d.stateDir, parent+"-unit-*.thin.json"))
	if err != nil {
		return nil, err
	}
	children := make([]*ThinVolume, 0, len(paths))
	for _, path := range paths {
		id := strings.TrimSuffix(filepath.Base(path), ".thin.json")
		v, err := d.volume(id)
		if err != nil {
			return nil, err
		}
		r, err := d.readThin(v)
		if err != nil {
			return nil, err
		}
		if r == nil {
			return nil, fmt.Errorf("child disappeared under pool lock")
		}
		if r.BorrowedUnits || (r.UnitPhase != "" && r.UnitPhase != "active" && r.UnitPhase != "draining" && r.UnitPhase != "releasing") {
			return nil, fmt.Errorf("invalid child state")
		}
		children = append(children, r)
	}
	return children, nil
}

// All mountpoint parents are root-owned, non-symlink directories. The runtime
// can write base/ and child segments/, but cannot replace control or mountpoints.
func ownedDirectory(path string) error {
	if err := os.Mkdir(path, 0755); err != nil && !os.IsExist(err) {
		return err
	}
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !info.IsDir() || !ok || stat.Uid != 0 || info.Mode().Perm()&0022 != 0 {
		return fmt.Errorf("unsafe unit directory")
	}
	return nil
}
func (d *Driver) prepareBorrowedParent(ctx context.Context, r *ThinVolume) error {
	if !r.BorrowedUnits {
		return nil
	}
	if err := ownedDirectory(r.StagingPath); err != nil {
		return err
	}
	for _, name := range []string{"base", "units"} {
		path := filepath.Join(r.StagingPath, name)
		if name == "base" {
			if err := os.Mkdir(path, 0755); err != nil && !os.IsExist(err) {
				return err
			}
			info, err := os.Lstat(path)
			if err != nil || !info.IsDir() {
				return fmt.Errorf("invalid base directory")
			}
			if err := os.Chown(path, 1000, 1000); err != nil {
				return err
			}
		} else if err := ownedDirectory(path); err != nil {
			return err
		}
	}
	if _, err := d.run(ctx, nil, "mount", "--make-rshared", r.StagingPath); err != nil {
		return err
	}
	return d.writeBorrowedControl(r)
}
func (d *Driver) writeBorrowedControl(parent *ThinVolume) error {
	children, err := d.borrowedChildren(parent.VolumeID)
	if err != nil {
		return err
	}
	placements := []string{"base"}
	drain := []string{}
	for _, child := range children {
		if child.UnitPhase == "active" {
			placements = append(placements, child.VolumeID)
		} else if child.UnitPhase == "draining" {
			drain = append(drain, child.VolumeID)
		}
	}
	sort.Strings(placements)
	sort.Strings(drain)
	bytes, err := json.Marshal(map[string]any{"generation": parent.Generation, "placements": placements, "drain": drain})
	if err != nil {
		return err
	}
	// The writable base tree is a child, so tenants cannot exchange this path.
	path := filepath.Join(parent.StagingPath, "control.json")
	f, err := os.OpenFile(path+".new", os.O_CREATE|os.O_TRUNC|os.O_WRONLY|syscall.O_NOFOLLOW, 0644)
	if err != nil {
		return err
	}
	if _, err = f.Write(bytes); err == nil {
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
	return syncDir(parent.StagingPath)
}
func (d *Driver) stageBorrowedChild(ctx context.Context, parent, child *ThinVolume) error {
	ctx = context.WithValue(ctx, borrowedPoolLock{}, true)
	staging := filepath.Join(d.stateDir, "unit-staging", child.VolumeID)
	if err := ownedDirectory(filepath.Join(d.stateDir, "unit-staging")); err != nil {
		return err
	}
	if _, err := d.NodeStageVolume(ctx, &csi.NodeStageVolumeRequest{VolumeId: child.VolumeID, StagingTargetPath: staging, VolumeCapability: unitCapability(), VolumeContext: map[string]string{"layout": ThinLayout}}); err != nil {
		return err
	}
	// Child filesystem root is not writable by the runtime. Marker and segment
	// directory creation is serialized with lifecycle operations by the pool lock.
	marker := filepath.Join(staging, ".unit-id")
	if data, err := os.ReadFile(marker); err == nil {
		if string(data) != child.VolumeID {
			return fmt.Errorf("child marker identity mismatch")
		}
	} else if os.IsNotExist(err) {
		f, err := os.OpenFile(marker, os.O_WRONLY|os.O_CREATE|os.O_EXCL|syscall.O_NOFOLLOW, 0444)
		if err != nil {
			return err
		}
		_, err = f.WriteString(child.VolumeID)
		if err == nil {
			err = f.Sync()
		}
		closeErr := f.Close()
		if err != nil {
			return err
		}
		if closeErr != nil {
			return closeErr
		}
	} else {
		return err
	}
	segments := filepath.Join(staging, "segments")
	if err := os.Mkdir(segments, 0755); err != nil && !os.IsExist(err) {
		return err
	}
	info, err := os.Lstat(segments)
	if err != nil || !info.IsDir() {
		return fmt.Errorf("invalid child segments directory")
	}
	if err := os.Chown(segments, 1000, 1000); err != nil {
		return err
	}
	if err := syncDir(staging); err != nil {
		return err
	}
	if err := ownedDirectory(filepath.Join(parent.StagingPath, "units")); err != nil {
		return err
	}
	_, err = d.NodePublishVolume(ctx, &csi.NodePublishVolumeRequest{VolumeId: child.VolumeID, StagingTargetPath: staging, TargetPath: filepath.Join(parent.StagingPath, "units", child.VolumeID), VolumeCapability: unitCapability(), VolumeContext: map[string]string{"csi.storage.k8s.io/pod.uid": parent.PodUID}})
	return err
}
func (d *Driver) restoreBorrowedChildren(ctx context.Context, parent *ThinVolume) error {
	if parent == nil || !parent.BorrowedUnits {
		return nil
	}
	children, err := d.borrowedChildren(parent.VolumeID)
	if err != nil {
		return err
	}
	for _, child := range children {
		// A create interrupted before its active marker must be completed only by
		// retrying the fenced operation, never advertised to a runtime prematurely.
		if child.UnitPhase == "" || child.UnitPhase == "releasing" {
			continue
		}
		if err = d.stageBorrowedChild(ctx, parent, child); err != nil {
			return err
		}
	}
	return d.writeBorrowedControl(parent)
}
func (d *Driver) unpublishBorrowedChildren(ctx context.Context, parent *ThinVolume) error {
	if parent == nil || !parent.BorrowedUnits {
		return nil
	}
	ctx = context.WithValue(ctx, borrowedPoolLock{}, true)
	children, err := d.borrowedChildren(parent.VolumeID)
	if err != nil {
		return err
	}
	for _, child := range children {
		for target := range child.Targets {
			if target != filepath.Join(parent.StagingPath, "units", child.VolumeID) {
				return fmt.Errorf("unexpected child publication")
			}
			if _, err = d.NodeUnpublishVolume(ctx, &csi.NodeUnpublishVolumeRequest{VolumeId: child.VolumeID, TargetPath: target}); err != nil {
				return err
			}
		}
		if child.StagingPath != "" {
			if _, err = d.NodeUnstageVolume(ctx, &csi.NodeUnstageVolumeRequest{VolumeId: child.VolumeID, StagingTargetPath: child.StagingPath}); err != nil {
				return err
			}
		}
	}
	return nil
}

func (d *Driver) ChangeBorrowedUnit(ctx context.Context, req BorrowedRequest) (*ThinSnapshot, error) {
	v, err := d.volume(req.VolumeID)
	if err != nil {
		return nil, err
	}
	if !volumeIDPattern.MatchString(req.VolumeID) || !podUIDPattern.MatchString(req.UnitID) {
		return nil, status.Error(codes.InvalidArgument, "invalid parent or unit identity")
	}
	if req.Action != "create" && req.Action != "drain" && req.Action != "release" {
		return nil, status.Error(codes.InvalidArgument, "unknown unit action")
	}
	unlock, err := d.lockVolume(ctx, v)
	if err != nil {
		return nil, err
	}
	defer unlock()
	parent, err := d.thinRequest(ctx, v, req.ThinRequest)
	if err != nil {
		return nil, err
	}
	if !parent.BorrowedUnits {
		return nil, status.Error(codes.FailedPrecondition, "parent does not enable borrowed units")
	}
	if req.Action == "create" && (req.CacheBytes < mib || req.CacheBytes%mib != 0) || req.Action != "create" && req.CacheBytes != 0 {
		return nil, status.Error(codes.InvalidArgument, "invalid unit capacity")
	}

	childID := parent.VolumeID + "-unit-" + req.UnitID
	childVolume, _ := d.volume(childID)
	child, err := d.readThin(childVolume)
	if err != nil {
		return nil, err
	}
	if req.Action == "create" {
		if exists, e := fileExists(filepath.Join(d.stateDir, childID+".released")); e != nil {
			return nil, e
		} else if exists {
			return nil, status.Error(codes.FailedPrecondition, "released unit identity cannot be reused")
		}
		if child != nil && (child.CeilingBytes != req.CacheBytes || child.UnitPhase == "draining" || child.UnitPhase == "releasing") {
			return nil, status.Error(codes.FailedPrecondition, "unit capacity or lifecycle differs")
		}
	}
	if req.Action == "drain" && (child == nil || child.UnitPhase == "releasing") {
		return nil, status.Error(codes.FailedPrecondition, "unit cannot enter drain")
	}
	retry := parent.UnitOperation.matches(req) && parent.Generation == req.Generation+1
	if !retry && req.Generation != parent.Generation {
		return nil, status.Error(codes.Aborted, "stale parent generation")
	}
	if !retry {
		if parent.UnitOperation != nil {
			old := parent.UnitOperation
			if old.ID == req.OperationID {
				return nil, status.Error(codes.AlreadyExists, "unit operation ID reused")
			}
			// After pod replacement a new fenced caller can resume the same
			// incomplete intent, but cannot replace it with a different grant.
			if !old.Done && (old.UnitID != req.UnitID || old.Action != req.Action || old.CacheBytes != req.CacheBytes) {
				return nil, status.Error(codes.FailedPrecondition, "resume incomplete unit operation first")
			}
		}
		parent.UnitOperation = &BorrowedOperation{ID: req.OperationID, Generation: req.Generation, UnitID: req.UnitID, Action: req.Action, CacheBytes: req.CacheBytes}
		parent.Generation++
		parent.LastOperation = ""
		if err = d.saveThin(v, parent); err != nil {
			return nil, err
		}
	} else if parent.UnitOperation.Done {
		if err = d.writeBorrowedControl(parent); err != nil {
			return nil, err
		}
		return d.observeThin(ctx)
	}
	// Internal nested calls skip only the already-held pool lock, not child locks.
	ctx = context.WithValue(ctx, borrowedPoolLock{}, true)
	switch req.Action {
	case "create":
		if exists, err := fileExists(filepath.Join(d.stateDir, childID+".released")); err != nil {
			return nil, err
		} else if exists {
			return nil, status.Error(codes.FailedPrecondition, "released unit identity cannot be reused")
		}

		if req.CacheBytes < mib || req.CacheBytes%mib != 0 {
			return nil, status.Error(codes.InvalidArgument, "unit capacity must be MiB aligned")
		}
		if child != nil && child.UnitPhase == "draining" {
			return nil, status.Error(codes.FailedPrecondition, "unit is draining")
		}
		_, err = d.CreateVolume(ctx, &csi.CreateVolumeRequest{Name: childID, CapacityRange: &csi.CapacityRange{RequiredBytes: req.CacheBytes}, VolumeCapabilities: []*csi.VolumeCapability{unitCapability()}, Parameters: map[string]string{"layout": ThinLayout}, AccessibilityRequirements: &csi.TopologyRequirement{Requisite: []*csi.Topology{d.topology()}}})
		if err != nil {
			return nil, err
		}
		child, err = d.readThin(childVolume)
		if err != nil {
			return nil, err
		}
		if err = d.stageBorrowedChild(ctx, parent, child); err != nil {
			return nil, err
		}
		child, err = d.readThin(childVolume)
		if err != nil {
			return nil, err
		}
		child.UnitPhase = "active"
		if err = d.saveThin(childVolume, child); err != nil {
			return nil, err
		}
	case "drain":
		if child == nil {
			return nil, status.Error(codes.NotFound, "child missing")
		}
		child.UnitPhase = "draining"
		if err = d.saveThin(childVolume, child); err != nil {
			return nil, err
		}
	case "release":
		if child != nil {
			if child.UnitPhase != "draining" && child.UnitPhase != "releasing" {
				return nil, status.Error(codes.FailedPrecondition, "drain child before release")
			}
			if child.UnitPhase == "draining" {
				if child.StagingPath == "" {
					return nil, status.Error(codes.FailedPrecondition, "stage child to verify drain")
				}
				entries, err := os.ReadDir(filepath.Join(child.StagingPath, "segments"))
				if err != nil {
					return nil, err
				}
				if len(entries) != 0 {
					return nil, status.Error(codes.FailedPrecondition, "child still contains segments")
				}

				child.UnitPhase = "releasing"
				if err = d.saveThin(childVolume, child); err != nil {
					return nil, err
				}
			}
			for target := range child.Targets {
				if target != filepath.Join(parent.StagingPath, "units", childID) {
					return nil, fmt.Errorf("unexpected child publication")
				}
				if _, err = d.NodeUnpublishVolume(ctx, &csi.NodeUnpublishVolumeRequest{VolumeId: childID, TargetPath: target}); err != nil {
					return nil, err
				}
			}
			if _, err = d.NodeUnstageVolume(ctx, &csi.NodeUnstageVolumeRequest{VolumeId: childID, StagingTargetPath: child.StagingPath}); err != nil {
				return nil, err
			}
			if err = writeMarker(filepath.Join(d.stateDir, childID+".released")); err != nil {
				return nil, err
			}
			if err = syncDir(d.stateDir); err != nil {
				return nil, err
			}
			if _, err = d.DeleteVolume(ctx, &csi.DeleteVolumeRequest{VolumeId: childID}); err != nil {
				return nil, err
			}
		}
	}
	parent.UnitOperation.Done = true
	if err = d.saveThin(v, parent); err != nil {
		return nil, err
	}
	if err = d.writeBorrowedControl(parent); err != nil {
		return nil, err
	}
	return d.observeThin(ctx)
}
