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
	"path/filepath"
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

// Experiment-only control plane around the REAL driver. There is no new shipped
// CSI API, child-key authorization or Kubernetes discovery in this prototype.
func TestBorrowedRealStack(t *testing.T) {
	if os.Getenv("KURA_BORROWED_DISPOSABLE_VM") != "1" {
		t.Skip("private disposable Linux VM only")
	}
	if os.Geteuid() != 0 {
		t.Fatal("requires root")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 35*time.Minute)
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
	run("truncate", "-s", "32G", backing)
	loop := run("losetup", "--direct-io=on", "--find", "--show", backing)
	exports := filepath.Join(root, "exports")
	id := func(n int) string { return fmt.Sprintf("pvc-00000000-0000-0000-0001-%012d", n) }
	t.Cleanup(func() {
		// Ruby stops its labelled containers first. A missed container must keep the
		// backing file, not cause us to force-unmount an active filesystem.
		mounts, _ := (ProcMountTable{Path: "/proc/self/mountinfo"}).Mounts()
		safe := true
		for i := len(mounts) - 1; i >= 0; i-- {
			if strings.HasPrefix(mounts[i].MountPoint, root+"/") {
				_, e := (ExecRunner{}).Run(context.Background(), nil, "umount", mounts[i].MountPoint)
				safe = e == nil && safe
			}
		}
		for n := 1; n <= 12; n++ {
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
			_ = os.RemoveAll(root)
			t.Log("BORROWED_CLEANUP_COMPLETE=true")
		} else {
			t.Errorf("cleanup incomplete; retained %s", root)
		}
	})
	run("pvcreate", "--yes", loop)
	run("vgcreate", vg, loop)
	run("lvcreate", "--yes", "--type", "thin-pool", "--size", "24G", "--poolmetadatasize", "512M", "--chunksize", "512K", "--discards", "passdown", "--name", "pool", vg)
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
	cfg := Config{NodeID: "borrowed-test", StateDir: state, VolumeGroup: vg, Thin: ThinConfig{Pool: "pool", DataReserveBytes: 256 << 20, MetadataReserveBytes: 32 << 20, MaxVolumes: 8}, Keys: borrowedKeys{secret}, Runner: runner, Host: OSHost{}, Mounts: ProcMountTable{Path: "/proc/self/mountinfo"}}
	d, err := New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	capability := &csi.VolumeCapability{AccessType: &csi.VolumeCapability_Mount{Mount: &csi.VolumeCapability_MountVolume{FsType: "xfs"}}, AccessMode: &csi.VolumeCapability_AccessMode{Mode: csi.VolumeCapability_AccessMode_SINGLE_NODE_SINGLE_WRITER}}
	type allocation struct {
		Volume *csi.Volume
		Target string
		Owner  string
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
			Op    string `json:"op"`
			ID    int    `json:"id"`
			Owner string `json:"owner"`
			Kind  string `json:"kind"`
			Bytes int64  `json:"bytes"`
			Fail  bool   `json:"fail"`
		}
		r.Body = http.MaxBytesReader(w, r.Body, 4096)
		if e := json.NewDecoder(r.Body).Decode(&q); e != nil {
			http.Error(w, e.Error(), 400)
			return
		}
		var value any
		var e error
		switch q.Op {
		case "observe":
			value, e = d.ThinStatus(ctx)
		case "restart":
			d, e = New(cfg)
			if e == nil {
				value, e = d.ThinStatus(ctx)
			}
		case "fail-trim":
			runner.failTrim.Store(q.Fail)
			value = true
		case "create":
			if q.ID < 1 || q.ID > 12 || (q.Owner != "a" && q.Owner != "b" && q.Owner != "bench") || (q.Kind != "base" && q.Kind != "unit") || q.Bytes < 1<<30 || q.Bytes > 8<<30 {
				e = fmt.Errorf("invalid fixture request")
				break
			}
			if _, exists := allocations[q.ID]; exists {
				e = fmt.Errorf("fixture identity already allocated")
				break
			}
			var created *csi.CreateVolumeResponse
			created, e = d.CreateVolume(ctx, &csi.CreateVolumeRequest{Name: id(q.ID), CapacityRange: &csi.CapacityRange{RequiredBytes: q.Bytes}, VolumeCapabilities: []*csi.VolumeCapability{capability}, Parameters: map[string]string{"layout": ThinLayout}, AccessibilityRequirements: &csi.TopologyRequirement{Requisite: []*csi.Topology{{Segments: map[string]string{TopologyKey: "borrowed-test"}}}}})
			if e != nil {
				break
			}
			target := filepath.Join(exports, q.Owner, "base")
			if q.Kind == "unit" {
				target = filepath.Join(exports, q.Owner, "units", id(q.ID))
			}
			allocations[q.ID] = allocation{created.Volume, target, q.Owner}
			_, e = d.NodeStageVolume(ctx, &csi.NodeStageVolumeRequest{VolumeId: id(q.ID), StagingTargetPath: filepath.Join(root, "stage", id(q.ID)), VolumeCapability: capability, VolumeContext: created.Volume.VolumeContext})
			if e != nil {
				break
			}
			_, e = d.NodePublishVolume(ctx, &csi.NodePublishVolumeRequest{VolumeId: id(q.ID), StagingTargetPath: filepath.Join(root, "stage", id(q.ID)), TargetPath: target, VolumeCapability: capability, VolumeContext: map[string]string{"csi.storage.k8s.io/pod.uid": "11111111-1111-1111-1111-111111111111"}})
			if e != nil {
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
			_, e = d.NodeUnpublishVolume(ctx, &csi.NodeUnpublishVolumeRequest{VolumeId: id(q.ID), TargetPath: a.Target})
			if e != nil {
				break
			}
			_, e = d.NodeUnstageVolume(ctx, &csi.NodeUnstageVolumeRequest{VolumeId: id(q.ID), StagingTargetPath: filepath.Join(root, "stage", id(q.ID))})
			if e != nil {
				break
			}
			_, e = d.DeleteVolume(ctx, &csi.DeleteVolumeRequest{VolumeId: id(q.ID)})
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
	out, e := (ExecRunner{}).Run(ctx, nil, "ruby", script, conf)
	// Script emits measurements only; credentials and keys stay in private files.
	t.Log(string(out))
	if e != nil {
		t.Fatal(e)
	}
}
