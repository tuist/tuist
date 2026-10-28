//go:build linux

package driver

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/container-storage-interface/spec/lib/go/csi"
)

type borrowedKeys struct{ root []byte }

func (k borrowedKeys) Fetch(_ context.Context, id string, _ int) ([]byte, int, error) {
	h := hmac.New(sha256.New, k.root)
	_, _ = h.Write([]byte(id))
	return h.Sum(nil), 1, nil
}

// Experiment-only control plane around the REAL driver. The disposable harness
// uses fixture keys, not OpenBao or Kubernetes authorization.
func TestBorrowedRealStack(t *testing.T) {
	if os.Getenv("KURA_BORROWED_DISPOSABLE_VM") != "1" {
		t.Skip("private disposable Linux VM only")
	}
	if os.Geteuid() != 0 {
		t.Fatal("requires root")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 55*time.Minute)
	defer cancel()
	root, err := os.MkdirTemp("/var/tmp", "kura-borrowed-")
	if err != nil {
		t.Fatal(err)
	}
	vg := fmt.Sprintf("kura_borrowed_%d", os.Getpid())
	run := func(name string, args ...string) string {
		t.Helper()
		b, e := (ExecRunner{}).Run(ctx, nil, name, args...)
		if e != nil {
			t.Fatal(e)
		}
		return strings.TrimSpace(string(b))
	}
	backing := filepath.Join(root, "disk.img")
	backingSize, poolSize, slots, maxID := "48G", "24G", 8, 12
	metadataScale := os.Getenv("KURA_BORROWED_METADATA_SCALE") == "128"
	if metadataScale {
		// Sparse virtual backing; the scale script bounds actual writes to
		// 32 MiB of mapped data plus formatting overhead per device.
		backingSize, poolSize, slots, maxID = "400G", "384G", 128, 129
	}
	run("truncate", "-s", backingSize, backing)
	loop := run("losetup", "--direct-io=on", "--find", "--show", backing)
	exports := filepath.Join(root, "exports")
	id := func(n int) string { return fmt.Sprintf("pvc-00000000-0000-0000-0001-%012d", n) }
	t.Cleanup(func() {
		// Ruby stops its labelled containers first. A missed container must keep the
		// backing file, not cause us to force-unmount an active filesystem.
		safe := false
		for attempt := 0; attempt < 20; attempt++ {
			mounts, err := (ProcMountTable{Path: "/proc/self/mountinfo"}).Mounts()
			if err != nil {
				break
			}
			var owned []string
			for _, m := range mounts {
				if strings.HasPrefix(m.MountPoint, root+"/") {
					owned = append(owned, m.MountPoint)
				}
			}
			if len(owned) == 0 {
				safe = true
				break
			}
			sort.Slice(owned, func(i, j int) bool { return len(owned[i]) > len(owned[j]) })
			for _, path := range owned {
				if _, err = (ExecRunner{}).Run(context.Background(), nil, "umount", path); err != nil && attempt == 19 {
					t.Logf("cleanup unmount: %v", err)
				}
			}
			time.Sleep(250 * time.Millisecond)
		}
		records, _ := filepath.Glob(filepath.Join(root, "state", "*-unit-*.thin.json"))
		for _, record := range records {
			child := strings.TrimSuffix(filepath.Base(record), ".thin.json")
			if childVolumeIDPattern.MatchString(child) {
				_, _ = (ExecRunner{}).Run(context.Background(), nil, "cryptsetup", "close", "kura-"+child)
			}
		}
		for n := 1; n <= maxID; n++ {
			_, _ = (ExecRunner{}).Run(context.Background(), nil, "cryptsetup", "close", "kura-"+id(n))
		}
		if safe {
			_, e := (ExecRunner{}).Run(context.Background(), nil, "vgremove", "--yes", vg)
			safe = e == nil
		}
		if safe {
			_, _ = (ExecRunner{}).Run(context.Background(), nil, "pvremove", "--yes", loop)
			_, e := (ExecRunner{}).Run(context.Background(), nil, "losetup", "-d", loop)
			safe = e == nil
		}
		if safe {
			for i := 0; i < 40; i++ {
				b, e := (ExecRunner{}).Run(context.Background(), nil, "losetup", "-j", backing)
				if e == nil && len(strings.TrimSpace(string(b))) == 0 {
					break
				}
				if i == 39 {
					safe = false
				}
				time.Sleep(100 * time.Millisecond)
			}
		}
		if safe {
			// Ruby also owns a plain-XFS comparison loop. Failed setup or cleanup
			// there must not let us unlink its still-attached backing file.
			images, err := filepath.Glob(filepath.Join(root, "*.img"))
			safe = err == nil
			for _, image := range images {
				b, err := (ExecRunner{}).Run(context.Background(), nil, "losetup", "-j", image)
				if err != nil || len(strings.TrimSpace(string(b))) != 0 {
					safe = false
				}
			}
		}
		if safe {
			if err := os.RemoveAll(root); err != nil {
				t.Errorf("cleanup directory: %v", err)
				return
			}
			t.Log("BORROWED_CLEANUP_COMPLETE=true")
		} else {
			t.Errorf("cleanup incomplete; retained %s", root)
		}
	})
	run("pvcreate", "--yes", loop)
	run("vgcreate", vg, loop)
	run("lvcreate", "--yes", "--type", "thin-pool", "--size", poolSize, "--poolmetadatasize", "512M", "--chunksize", "512K", "--discards", "passdown", "--name", "pool", vg)
	run("lvchange", "--errorwhenfull", "y", vg+"/pool")
	if err = os.MkdirAll(exports, 0755); err != nil {
		t.Fatal(err)
	}
	// Restrict propagation to this fixture's parent. No host-wide mount changes.
	run("mount", "--bind", exports, exports)
	run("mount", "--make-rshared", exports)
	state := filepath.Join(root, "state")
	if err = os.Mkdir(state, 0700); err != nil {
		t.Fatal(err)
	}
	secret := make([]byte, 32)
	if _, err = rand.Read(secret); err != nil {
		t.Fatal(err)
	}
	defer clear(secret)
	runner := &thinFaultRunner{}
	cfg := Config{NodeID: "borrowed-test", StateDir: state, VolumeGroup: vg, Thin: ThinConfig{Pool: "pool", DataReserveBytes: 256 << 20, MetadataReserveBytes: 32 << 20, MaxVolumes: slots}, Keys: borrowedKeys{secret}, Runner: runner, Host: OSHost{}, Mounts: ProcMountTable{Path: "/proc/self/mountinfo"}}
	d, err := New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	capability := &csi.VolumeCapability{AccessType: &csi.VolumeCapability_Mount{Mount: &csi.VolumeCapability_MountVolume{FsType: "xfs"}}, AccessMode: &csi.VolumeCapability_AccessMode{Mode: csi.VolumeCapability_AccessMode_SINGLE_NODE_SINGLE_WRITER}}
	type allocation struct {
		Volume *csi.Volume
		Target string
		Owner  string
		Thick  bool
	}
	allocations := map[int]allocation{}
	var mu sync.Mutex
	token := hex.EncodeToString(secret)
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+token {
			http.Error(w, "denied", 403)
			return
		}
		mu.Lock()
		defer mu.Unlock()
		var q struct {
			Layout string           `json:"layout"`
			PodUID string           `json:"pod_uid"`
			Unit   *BorrowedRequest `json:"unit"`
			Op     string           `json:"op"`
			ID     int              `json:"id"`
			Owner  string           `json:"owner"`
			Kind   string           `json:"kind"`
			Bytes  int64            `json:"bytes"`
			Fail   bool             `json:"fail"`
		}
		r.Body = http.MaxBytesReader(w, r.Body, 4096)
		if e := json.NewDecoder(r.Body).Decode(&q); e != nil {
			http.Error(w, e.Error(), 400)
			return
		}
		var value any
		var e error
		switch q.Op {
		case "cold-pool":
			if !metadataScale {
				e = fmt.Errorf("cold pool restart requires private metadata-scale profile")
				break
			}
			for n, a := range allocations {
				if _, e = d.NodeUnpublishVolume(ctx, &csi.NodeUnpublishVolumeRequest{VolumeId: id(n), TargetPath: a.Target}); e != nil {
					break
				}
				if _, e = d.NodeUnstageVolume(ctx, &csi.NodeUnstageVolumeRequest{VolumeId: id(n), StagingTargetPath: filepath.Join(root, "stage", id(n))}); e != nil {
					break
				}
			}
			if e != nil {
				break
			}
			for _, state := range []string{"n", "y"} {
				if _, e = d.run(ctx, nil, "vgchange", "--activate", state, vg); e != nil {
					break
				}
			}
			if e != nil {
				break
			}
			d, e = New(cfg)
			if e != nil {
				break
			}
			for n, a := range allocations {
				stage := filepath.Join(root, "stage", id(n))
				if _, e = d.NodeStageVolume(ctx, &csi.NodeStageVolumeRequest{VolumeId: id(n), StagingTargetPath: stage, VolumeCapability: capability, VolumeContext: a.Volume.VolumeContext}); e != nil {
					break
				}
				if _, e = d.NodePublishVolume(ctx, &csi.NodePublishVolumeRequest{VolumeId: id(n), StagingTargetPath: stage, TargetPath: a.Target, VolumeCapability: capability, VolumeContext: map[string]string{"csi.storage.k8s.io/pod.uid": "11111111-1111-1111-1111-111111111111"}}); e != nil {
					break
				}
			}
			if e == nil {
				value, e = d.ThinStatus(ctx)
			}
		case "unit":
			if q.Unit == nil {
				e = fmt.Errorf("unit request required")
			} else {
				value, e = d.ChangeBorrowedUnit(ctx, *q.Unit)
			}
		case "observe":
			value, e = d.ThinStatus(ctx)
		case "restart":
			d, e = New(cfg)
			if e == nil {
				value, e = d.ThinStatus(ctx)
			}
		case "cold-parent":
			a, ok := allocations[q.ID]
			if !ok {
				e = fmt.Errorf("missing parent")
				break
			}
			if _, e = d.NodeUnpublishVolume(ctx, &csi.NodeUnpublishVolumeRequest{VolumeId: id(q.ID), TargetPath: a.Target}); e != nil {
				break
			}
			stage := filepath.Join(root, "stage", id(q.ID))
			if _, e = d.NodeUnstageVolume(ctx, &csi.NodeUnstageVolumeRequest{VolumeId: id(q.ID), StagingTargetPath: stage}); e != nil {
				break
			}
			d, e = New(cfg)
			if e != nil {
				break
			}
			if _, e = d.NodeStageVolume(ctx, &csi.NodeStageVolumeRequest{VolumeId: id(q.ID), StagingTargetPath: stage, VolumeCapability: capability, VolumeContext: a.Volume.VolumeContext}); e != nil {
				break
			}
			if _, e = d.NodePublishVolume(ctx, &csi.NodePublishVolumeRequest{VolumeId: id(q.ID), StagingTargetPath: stage, TargetPath: a.Target, VolumeCapability: capability, VolumeContext: map[string]string{"csi.storage.k8s.io/pod.uid": q.PodUID}}); e != nil {
				break
			}
			value, e = d.ThinStatus(ctx)
		case "fail-trim":
			runner.failTrim.Store(q.Fail)
			value = true
		case "fail-quota":
			runner.failQuota.Store(true)
			value = true
		case "pressure":
			var s *ThinSnapshot
			s, e = d.ThinStatus(ctx)
			if e != nil {
				break
			}
			pressured := cfg
			if q.Kind == "metadata" {
				pressured.Thin.MetadataReserveBytes = s.MetadataTotal - s.MetadataUsed + 4096
			} else if q.Kind == "data" {
				pressured.Thin.DataReserveBytes = s.DataTotal - s.DataUsed + s.ChunkBytes
			} else {
				e = fmt.Errorf("unknown reserve")
				break
			}
			d, e = New(pressured)
			if e == nil {
				value, e = d.ThinStatus(ctx)
			}
		case "race-create":
			type result struct {
				ID      int    `json:"id"`
				Created bool   `json:"created"`
				Error   string `json:"error,omitempty"`
			}
			results := make(chan result, 2)
			for _, n := range []int{4, 5} {
				go func(n int) {
					_, err := d.CreateVolume(ctx, &csi.CreateVolumeRequest{Name: id(n), CapacityRange: &csi.CapacityRange{RequiredBytes: 4 << 30}, VolumeCapabilities: []*csi.VolumeCapability{capability}, Parameters: map[string]string{"layout": ThinLayout}, AccessibilityRequirements: &csi.TopologyRequirement{Requisite: []*csi.Topology{{Segments: map[string]string{TopologyKey: "borrowed-test"}}}}})
					r := result{ID: n, Created: err == nil}
					if err != nil {
						r.Error = err.Error()
					}
					results <- r
				}(n)
			}
			value = []result{<-results, <-results}
		case "create":

			if q.ID < 1 || q.ID > maxID || (q.Owner != "a" && q.Owner != "b" && q.Owner != "bench") || (q.Kind != "base" && q.Kind != "unit" && q.Kind != "parent") || q.Bytes < 256<<20 || q.Bytes > 16<<30 {
				e = fmt.Errorf("invalid fixture request")
				break
			}
			if _, exists := allocations[q.ID]; exists {
				e = fmt.Errorf("fixture identity already allocated")
				break
			}
			allocator := d
			if q.Layout == "thick" {
				legacy := cfg
				legacy.Thin = ThinConfig{}
				allocator, e = New(legacy)
				if e != nil {
					break
				}
			} else if q.Layout != "" {
				e = fmt.Errorf("unknown layout")
				break
			}
			var created *csi.CreateVolumeResponse
			parameters := map[string]string{"layout": ThinLayout}
			if q.Layout == "thick" {
				parameters = map[string]string{}
			}
			if q.Kind == "parent" {
				parameters["borrowed_units"] = "v1"
			}
			created, e = allocator.CreateVolume(ctx, &csi.CreateVolumeRequest{Name: id(q.ID), CapacityRange: &csi.CapacityRange{RequiredBytes: q.Bytes}, VolumeCapabilities: []*csi.VolumeCapability{capability}, Parameters: parameters, AccessibilityRequirements: &csi.TopologyRequirement{Requisite: []*csi.Topology{{Segments: map[string]string{TopologyKey: "borrowed-test"}}}}})
			if e != nil {
				break
			}
			target := filepath.Join(exports, q.Owner, "base")
			if q.Kind == "parent" {
				target = filepath.Join(exports, q.Owner)
			}
			if q.Kind == "unit" {
				target = filepath.Join(exports, q.Owner, "units", id(q.ID))
			}
			allocations[q.ID] = allocation{created.Volume, target, q.Owner, q.Layout == "thick"}
			_, e = allocator.NodeStageVolume(ctx, &csi.NodeStageVolumeRequest{VolumeId: id(q.ID), StagingTargetPath: filepath.Join(root, "stage", id(q.ID)), VolumeCapability: capability, VolumeContext: created.Volume.VolumeContext})
			if e != nil {
				break
			}
			_, e = allocator.NodePublishVolume(ctx, &csi.NodePublishVolumeRequest{VolumeId: id(q.ID), StagingTargetPath: filepath.Join(root, "stage", id(q.ID)), TargetPath: target, VolumeCapability: capability, VolumeContext: map[string]string{"csi.storage.k8s.io/pod.uid": "11111111-1111-1111-1111-111111111111"}})
			if e != nil {
				break
			}
			if q.Kind == "parent" {
				value = allocations[q.ID]
				break
			}
			// A root-owned marker remains on the filesystem, not the mountpoint below.
			e = os.WriteFile(filepath.Join(target, ".unit-id"), []byte(id(q.ID)), 0444)
			if e != nil {
				break
			}
			e = os.MkdirAll(filepath.Join(target, "segments"), 0755)
			if e != nil {
				break
			}
			e = os.Chown(target, 1000, 1000)
			if e == nil {
				e = os.Chown(filepath.Join(target, "segments"), 1000, 1000)
			}
			value = allocations[q.ID]
		case "reclaim":
			var s *ThinSnapshot
			s, e = d.ThinStatus(ctx)
			if e != nil {
				break
			}
			e = fmt.Errorf("missing volume")
			for _, v := range s.Volumes {
				if v.VolumeID == id(q.ID) {
					value, e = d.ReclaimThin(ctx, ThinRequest{VolumeID: v.VolumeID, LVUUID: v.LVUUID, PoolUUID: v.PoolUUID, PodUID: v.PodUID, Generation: v.Generation, OperationID: "22222222-2222-2222-2222-222222222222"})
					break
				}
			}
		case "delete":

			a, ok := allocations[q.ID]
			if !ok {
				e = fmt.Errorf("unknown fixture allocation")
				break
			}
			allocator := d
			if a.Thick {
				legacy := cfg
				legacy.Thin = ThinConfig{}
				allocator, e = New(legacy)
				if e != nil {
					break
				}
			}
			_, e = allocator.NodeUnpublishVolume(ctx, &csi.NodeUnpublishVolumeRequest{VolumeId: id(q.ID), TargetPath: a.Target})
			if e != nil {
				break
			}
			_, e = allocator.NodeUnstageVolume(ctx, &csi.NodeUnstageVolumeRequest{VolumeId: id(q.ID), StagingTargetPath: filepath.Join(root, "stage", id(q.ID))})
			if e != nil {
				break
			}
			_, e = allocator.DeleteVolume(ctx, &csi.DeleteVolumeRequest{VolumeId: id(q.ID)})
			if e == nil {
				delete(allocations, q.ID)
				value = true
			}
		default:
			e = fmt.Errorf("unknown fixture operation")
		}
		if e != nil {
			w.WriteHeader(409)
			_ = json.NewEncoder(w).Encode(map[string]any{"error": e.Error()})
			return
		}
		_ = json.NewEncoder(w).Encode(value)
	})
	listener, e := net.Listen("tcp", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	defer server.Close()
	go func() { _ = server.Serve(listener) }()
	fixture := map[string]any{"root": root, "exports": exports, "endpoint": "http://" + listener.Addr().String(), "token": token}
	data, _ := json.Marshal(fixture)
	conf := filepath.Join(root, "fixture.json")
	if e = os.WriteFile(conf, data, 0600); e != nil {
		t.Fatal(e)
	}
	script := os.Getenv("KURA_BORROWED_SCRIPT")
	if script == "" {
		t.Fatal("fixture script required")
	}
	command := exec.CommandContext(ctx, "ruby", script, conf)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if e := command.Run(); e != nil {
		t.Fatal(e)
	}
}
