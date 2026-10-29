package driver

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

var podUIDPattern = regexp.MustCompile(`^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$`)

// ThinRequest fences operations against both storage and workload incarnations.
// This interface is for a trusted node allocator, never a tenant container.
type ThinRequest struct {
	VolumeID    string `json:"volume_id"`
	LVUUID      string `json:"lv_uuid"`
	PoolUUID    string `json:"pool_uuid"`
	PodUID      string `json:"pod_uid"`
	Generation  uint64 `json:"generation"`
	OperationID string `json:"operation_id"`
	FloorBytes  int64  `json:"floor_cache_bytes"`
	GrantBytes  int64  `json:"grant_cache_bytes"`
}

type ThinReclamation struct {
	VolumeID           string        `json:"volume_id"`
	BeforeMapped       int64         `json:"before_mapped_bytes"`
	AfterMapped        int64         `json:"after_mapped_bytes"`
	BeforePoolUsed     int64         `json:"before_pool_used_bytes"`
	AfterPoolUsed      int64         `json:"after_pool_used_bytes"`
	ObservedRelease    int64         `json:"observed_release_bytes"`
	CommitmentReleased int64         `json:"commitment_released_bytes"`
	Snapshot           *ThinSnapshot `json:"snapshot"`
}

func (d *Driver) ThinStatus(ctx context.Context) (*ThinSnapshot, error) {
	// Include lock acquisition in the deadline: a blocked observation must not
	// park the advertiser forever while the caller still has a live root context.
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	if d.thin.Pool == "" {
		return nil, status.Error(codes.FailedPrecondition, "thin layout is disabled")
	}
	unlock, err := d.lockPool(ctx)
	if err != nil {
		return nil, err
	}
	defer unlock()
	return d.observeThin(ctx)
}

func (d *Driver) thinRequest(ctx context.Context, v volume, req ThinRequest) (*ThinVolume, error) {
	r, err := d.readThin(v)
	if err != nil {
		return nil, err
	}
	if r == nil {
		return nil, status.Error(codes.NotFound, "thin volume missing")
	}
	if req.LVUUID != r.LVUUID || req.PoolUUID != r.PoolUUID || req.PodUID == "" || req.PodUID != r.PodUID || !podUIDPattern.MatchString(req.OperationID) {
		return nil, status.Error(codes.FailedPrecondition, "storage or pod incarnation mismatch")
	}
	if err = d.verifyThin(ctx, v, r); err != nil {
		return nil, err
	}
	mounted, err := d.volumeMounted(r.StagingPath, v)
	if err != nil {
		return nil, err
	}
	if !mounted {
		return nil, status.Error(codes.FailedPrecondition, "thin volume is not staged")
	}
	return r, nil
}

func (d *Driver) SetThinGrant(ctx context.Context, req ThinRequest) (*ThinVolume, error) {
	v, err := d.volume(req.VolumeID)
	if err != nil {
		return nil, err
	}
	unlock, err := d.lockVolume(ctx, v)
	if err != nil {
		return nil, err
	}
	defer unlock()
	r, err := d.thinRequest(ctx, v, req)
	if err != nil {
		return nil, err
	}
	// A retry after a lost response may repair a quota application interrupted
	// after the durable intent. Reusing the key with another payload is rejected.
	if r.UnitOperation != nil && !r.UnitOperation.Done {
		return nil, status.Error(codes.FailedPrecondition, "unit operation pending")
	}
	retry := req.OperationID == r.LastOperation && req.Generation+1 == r.Generation && req.FloorBytes == r.FloorBytes && req.GrantBytes == r.GrantBytes
	if !retry && req.Generation != r.Generation {
		return nil, status.Error(codes.Aborted, "stale grant generation")
	}
	if req.FloorBytes < mib || req.GrantBytes < req.FloorBytes || req.GrantBytes > r.CeilingBytes || req.FloorBytes%mib != 0 || req.GrantBytes%mib != 0 {
		return nil, status.Error(codes.InvalidArgument, "require MiB-aligned floor <= grant <= ceiling")
	}
	if !retry && req.OperationID == r.LastOperation {
		return nil, status.Error(codes.AlreadyExists, "operation ID already used")
	}
	if req.GrantBytes > r.GrantBytes {
		s, err := d.observeThin(ctx)
		if err != nil {
			return nil, err
		}
		if !s.Healthy {
			return nil, status.Error(codes.ResourceExhausted, s.Reason)
		}
	}
	if !retry {
		r.FloorBytes = req.FloorBytes
		r.GrantBytes = req.GrantBytes
		r.Generation++
		r.LastOperation = req.OperationID
		if err = d.saveThin(v, r); err != nil {
			return nil, err
		}
	}
	// Lowering a hard limit below usage stops further allocation; it does not
	// delete data, shrink XFS, or release any pool commitment.
	if err = d.applyThinQuota(ctx, r); err != nil {
		return nil, err
	}
	return r, nil
}

func (d *Driver) ReclaimThin(ctx context.Context, req ThinRequest) (*ThinReclamation, error) {
	v, err := d.volume(req.VolumeID)
	if err != nil {
		return nil, err
	}
	unlock, err := d.lockVolume(ctx, v)
	if err != nil {
		return nil, err
	}
	defer unlock()
	r, err := d.thinRequest(ctx, v, req)
	if err != nil {
		return nil, err
	}
	if req.Generation != r.Generation {
		return nil, status.Error(codes.Aborted, "stale grant generation")
	}
	before, err := d.observeThin(ctx)
	if err != nil {
		return nil, err
	}
	if _, err = d.run(ctx, nil, "sync", "-f", r.StagingPath); err != nil {
		return nil, err
	}
	if _, err = d.run(ctx, nil, "fstrim", r.StagingPath); err != nil {
		return nil, err
	}
	after, err := d.observeThin(ctx)
	if err != nil {
		return nil, err
	}
	mapped := func(s *ThinSnapshot) int64 {
		for _, o := range s.Volumes {
			if o.VolumeID == v.id {
				return o.MappedBytes
			}
		}
		return 0
	}
	a, b := mapped(before), mapped(after)
	// Concurrent workload writes can obscure a release. Report only the smaller
	// observed decrease, never fstrim's logical byte count. Full ceiling backing
	// remains reserved even when these physical blocks have been reclaimed.
	return &ThinReclamation{VolumeID: v.id, BeforeMapped: a, AfterMapped: b, BeforePoolUsed: before.DataUsed, AfterPoolUsed: after.DataUsed, ObservedRelease: max(0, min(a-b, before.DataUsed-after.DataUsed)), Snapshot: after}, nil
}

// ServeThinAPI exposes a root-only Unix socket. All handlers share the CSI
// pool/volume locks; no second privileged process issues LVM or quota commands.
func (d *Driver) ServeThinAPI(ctx context.Context) error {
	if d.thin.Pool == "" {
		return nil
	}
	path := filepath.Join(d.stateDir, "allocator.sock")
	if info, err := os.Lstat(path); err == nil {
		if info.Mode()&os.ModeSocket == 0 {
			return fmt.Errorf("allocator path is not a socket")
		}
		if err = os.Remove(path); err != nil {
			return err
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	listener, err := net.Listen("unix", path)
	if err != nil {
		return err
	}
	defer listener.Close()
	defer os.Remove(path)
	if err = os.Chmod(path, 0600); err != nil {
		return err
	}
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Context().Value(allocatorPeerKey{}) != true {
			http.Error(w, "root peer required", http.StatusForbidden)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 45*time.Second)
		defer cancel()
		var result any
		var err error
		if r.Method == http.MethodGet && r.URL.Path == "/v1/node" {
			result, err = d.ThinStatus(ctx)
		} else if r.Method == http.MethodPost && r.URL.Path == "/v1/units" {
			var req BorrowedRequest
			dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192))
			dec.DisallowUnknownFields()
			if e := dec.Decode(&req); e != nil {
				http.Error(w, "invalid request", 400)
				return
			}
			if e := dec.Decode(new(any)); e != io.EOF {
				http.Error(w, "trailing request data", 400)
				return
			}
			result, err = d.ChangeBorrowedUnit(ctx, req)
		} else if r.Method == http.MethodPost && (r.URL.Path == "/v1/grant" || r.URL.Path == "/v1/reclaim") {
			var req ThinRequest
			dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192))
			dec.DisallowUnknownFields()
			if e := dec.Decode(&req); e != nil {
				http.Error(w, "invalid request", 400)
				return
			}
			if e := dec.Decode(new(any)); e != io.EOF {
				http.Error(w, "trailing request data", 400)
				return
			}
			if r.URL.Path == "/v1/grant" {
				result, err = d.SetThinGrant(ctx, req)
			} else {
				result, err = d.ReclaimThin(ctx, req)
			}
		} else {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		if err != nil {
			code := http.StatusServiceUnavailable
			switch status.Code(err) {
			case codes.InvalidArgument:
				code = 400
			case codes.NotFound:
				code = 404
			case codes.Aborted, codes.AlreadyExists, codes.FailedPrecondition:
				code = 409
			case codes.ResourceExhausted:
				code = 507
			}
			w.WriteHeader(code)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
			return
		}
		_ = json.NewEncoder(w).Encode(result)
	})
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 50 * time.Second, IdleTimeout: 30 * time.Second}
	server.ConnContext = func(ctx context.Context, conn net.Conn) context.Context {
		return context.WithValue(ctx, allocatorPeerKey{}, allocatorRootPeer(conn))
	}
	go func() { <-ctx.Done(); _ = server.Close() }()
	err = server.Serve(listener)
	if err == http.ErrServerClosed {
		return nil
	}
	return err
}

type allocatorPeerKey struct{}
