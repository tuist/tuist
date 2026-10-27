//go:build linux

package driver

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type thinTestKeys struct{ key []byte }

func (k thinTestKeys) Fetch(context.Context, string, int) ([]byte, int, error) {
	return append([]byte(nil), k.key...), 1, nil
}

type thinFaultRunner struct{ failTrim, failCreate, failQuota atomic.Bool }

func (r *thinFaultRunner) Run(ctx context.Context, input []byte, name string, args ...string) ([]byte, error) {
	if name == "fstrim" && r.failTrim.Load() {
		return nil, fmt.Errorf("injected discard failure")
	}
	if name == "lvcreate" && r.failCreate.Swap(false) {
		return nil, fmt.Errorf("injected create failure")
	}
	if name == "xfs_quota" && strings.Contains(strings.Join(args, " "), "limit -p") && r.failQuota.Swap(false) {
		return nil, fmt.Errorf("injected quota failure")
	}
	return (ExecRunner{}).Run(ctx, input, name, args...)
}

// This test creates ONLY its own private loop-backed VG. Run the compiled test
// binary as root in a disposable Linux VM with KURA_THIN_DISPOSABLE_VM=1.
func TestThinRealStack(t *testing.T) {
	if os.Getenv("KURA_THIN_DISPOSABLE_VM") != "1" {
		t.Skip("requires explicit disposable Linux VM opt-in")
	}
	if os.Geteuid() != 0 {
		t.Fatal("requires root in disposable VM")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	root, err := os.MkdirTemp("/var/tmp", "kura-thin-csi-")
	if err != nil {
		t.Fatal(err)
	}
	vg := fmt.Sprintf("kura_test_%d", os.Getpid())
	loop := ""
	run := func(name string, args ...string) string {
		t.Helper()
		b, e := (ExecRunner{}).Run(ctx, nil, name, args...)
		if e != nil {
			t.Fatalf("%s: %v", name, e)
		}
		return strings.TrimSpace(string(b))
	}
	file := filepath.Join(root, "disk.img")
	run("truncate", "-s", "20G", file)
	loop = run("losetup", "--find", "--show", file)
	t.Cleanup(func() {
		// A failed assertion must still close only this fixture's resources. Keep
		// the image if cleanup cannot detach it, rather than unlinking live backing.
		mounts, _ := (ProcMountTable{Path: "/proc/self/mountinfo"}).Mounts()
		for i := len(mounts) - 1; i >= 0; i-- {
			if strings.HasPrefix(mounts[i].MountPoint, root+"/") {
				_, _ = (ExecRunner{}).Run(context.Background(), nil, "umount", mounts[i].MountPoint)
			}
		}
		for i := 1; i <= 8; i++ {
			_, _ = (ExecRunner{}).Run(context.Background(), nil, "cryptsetup", "close", fmt.Sprintf("kura-pvc-00000000-0000-0000-0000-%012d", i))
		}
		_, e := (ExecRunner{}).Run(context.Background(), nil, "vgremove", "--yes", vg)
		if e != nil {
			t.Errorf("cleanup VG: %v; preserved %s", e, root)
			return
		}
		_, _ = (ExecRunner{}).Run(context.Background(), nil, "pvremove", "--yes", loop)
		_, e = (ExecRunner{}).Run(context.Background(), nil, "losetup", "-d", loop)
		if e != nil {
			t.Errorf("cleanup loop: %v; preserved %s", e, root)
			return
		}
		for i := 0; i < 30; i++ {
			b, _ := (ExecRunner{}).Run(context.Background(), nil, "losetup", "-j", file)
			if len(strings.TrimSpace(string(b))) == 0 {
				_ = os.RemoveAll(root)
				return
			}
			time.Sleep(100 * time.Millisecond)
		}
		t.Errorf("loop detach pending; preserved %s", root)
	})
	run("pvcreate", "--yes", loop)
	run("vgcreate", vg, loop)
	run("lvcreate", "--yes", "--type", "thin-pool", "--size", "16G", "--poolmetadatasize", "512M", "--chunksize", "64K", "--discards", "passdown", "--name", "tenant_pool", vg)
	run("lvchange", "--errorwhenfull", "y", vg+"/tenant_pool")
	state := filepath.Join(root, "state")
	if err = os.Mkdir(state, 0700); err != nil {
		t.Fatal(err)
	}
	key := make([]byte, 32)
	if _, err = rand.Read(key); err != nil {
		t.Fatal(err)
	}
	defer clear(key)
	runner := &thinFaultRunner{}
	cfg := Config{NodeID: "test-node", StateDir: state, VolumeGroup: vg, Thin: ThinConfig{Pool: "tenant_pool", DataReserveBytes: 256 << 20, MetadataReserveBytes: 32 << 20, MaxVolumes: 4}, Keys: thinTestKeys{key}, Runner: runner, Host: OSHost{}, Mounts: ProcMountTable{Path: "/proc/self/mountinfo"}}
	d, err := New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	capability := &csi.VolumeCapability{AccessType: &csi.VolumeCapability_Mount{Mount: &csi.VolumeCapability_MountVolume{FsType: "xfs"}}, AccessMode: &csi.VolumeCapability_AccessMode{Mode: csi.VolumeCapability_AccessMode_SINGLE_NODE_SINGLE_WRITER}}
	id := func(i int) string { return fmt.Sprintf("pvc-00000000-0000-0000-0000-%012d", i) }
	request := func(i int) *csi.CreateVolumeRequest {
		return &csi.CreateVolumeRequest{Name: id(i), CapacityRange: &csi.CapacityRange{RequiredBytes: 1 << 30}, VolumeCapabilities: []*csi.VolumeCapability{capability}, Parameters: map[string]string{"layout": ThinLayout}, AccessibilityRequirements: &csi.TopologyRequirement{Requisite: []*csi.Topology{{Segments: map[string]string{TopologyKey: "test-node"}}}}}
	}
	create := func(i int) *csi.Volume {
		t.Helper()
		r, e := d.CreateVolume(ctx, request(i))
		if e != nil {
			t.Fatal(e)
		}
		return r.Volume
	}
	a, b := create(1), create(2)
	stage := func(v *csi.Volume) {
		t.Helper()
		_, e := d.NodeStageVolume(ctx, &csi.NodeStageVolumeRequest{VolumeId: v.VolumeId, StagingTargetPath: filepath.Join(root, v.VolumeId), VolumeCapability: capability, VolumeContext: v.VolumeContext})
		if e != nil {
			t.Fatal(e)
		}
	}
	stage(a)
	stage(b)
	pod := "11111111-1111-1111-1111-111111111111"
	publish := func(v *csi.Volume, uid string) error {
		_, e := d.NodePublishVolume(ctx, &csi.NodePublishVolumeRequest{VolumeId: v.VolumeId, StagingTargetPath: filepath.Join(root, v.VolumeId), TargetPath: filepath.Join(root, "target-"+v.VolumeId), VolumeCapability: capability, VolumeContext: map[string]string{"csi.storage.k8s.io/pod.uid": uid}})
		return e
	}
	if e := publish(a, pod); e != nil {
		t.Fatal(e)
	}
	if e := publish(b, pod); e != nil {
		t.Fatal(e)
	}
	snap := func() *ThinSnapshot {
		t.Helper()
		s, e := d.ThinStatus(ctx)
		if e != nil {
			t.Fatal(e)
		}
		if !s.Healthy {
			t.Fatalf("unhealthy: %+v", s)
		}
		return s
	}
	observation := func(s *ThinSnapshot, vid string) ThinObservation {
		for _, o := range s.Volumes {
			if o.VolumeID == vid {
				return o
			}
		}
		t.Fatalf("volume missing %s", vid)
		return ThinObservation{}
	}
	req := func(i int) ThinRequest {
		o := observation(snap(), id(i))
		return ThinRequest{VolumeID: id(i), LVUUID: o.LVUUID, PoolUUID: o.PoolUUID, PodUID: pod, Generation: o.Generation, OperationID: "22222222-2222-2222-2222-222222222222"}
	}
	apiCtx, apiCancel := context.WithCancel(ctx)
	defer apiCancel()
	apiDone := make(chan error, 1)
	go func() { apiDone <- d.ServeThinAPI(apiCtx) }()
	socket := filepath.Join(state, "allocator.sock")
	for i := 0; i < 100; i++ {
		if info, e := os.Stat(socket); e == nil {
			if info.Mode().Perm() != 0600 {
				t.Fatal("allocator socket not private")
			}
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	client := &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "unix", socket)
	}}}
	response, e := client.Get("http://node/v1/node")
	if e != nil {
		t.Fatal(e)
	}
	var viaAPI ThinSnapshot
	e = json.NewDecoder(response.Body).Decode(&viaAPI)
	_ = response.Body.Close()
	if e != nil || response.StatusCode != 200 || !viaAPI.Healthy {
		t.Fatalf("node API: %d %v", response.StatusCode, e)
	}
	apiCancel()
	if e = <-apiDone; e != nil {
		t.Fatal(e)
	}
	initial := snap()
	t.Logf("initial pool data=%d metadata=%d committed=%d", initial.DataUsed, initial.MetadataUsed, initial.CommittedBytes)
	apath := filepath.Join(root, a.VolumeId, "payload")
	run("dd", "if=/dev/urandom", "of="+apath, "bs=1M", "count=768", "conv=fsync", "status=none")
	written := snap()
	aWritten := observation(written, a.VolumeId).MappedBytes
	// Open-unlinked data must remain physically charged even after a successful trim.
	held, e := os.Open(apath)
	if e != nil {
		t.Fatal(e)
	}
	defer held.Close()
	if e = os.Remove(apath); e != nil {
		t.Fatal(e)
	}
	reclaim, e := d.ReclaimThin(ctx, req(1))
	if e != nil {
		t.Fatal(e)
	}
	if reclaim.AfterMapped < aWritten-(8<<20) {
		t.Fatalf("open deleted bytes incorrectly released: %+v", reclaim)
	}
	_ = held.Close()
	runner.failTrim.Store(true)
	if _, e = d.ReclaimThin(ctx, req(1)); e == nil {
		t.Fatal("failed trim reported success")
	}
	runner.failTrim.Store(false)
	reclaim, e = d.ReclaimThin(ctx, req(1))
	if e != nil {
		t.Fatal(e)
	}
	if reclaim.ObservedRelease < 700<<20 || reclaim.CommitmentReleased != 0 {
		t.Fatalf("wrong reclaimed accounting: %+v", reclaim)
	}
	beforeB := reclaim.AfterPoolUsed
	run("dd", "if=/dev/urandom", "of="+filepath.Join(root, b.VolumeId, "payload"), "bs=1M", "count=768", "conv=fsync", "status=none")
	reused := snap()
	if reused.DataUsed < beforeB+700<<20 {
		t.Fatal("B did not allocate reclaimed pool space")
	}
	t.Logf("A reclaimed=%d; B pool growth=%d", reclaim.ObservedRelease, reused.DataUsed-beforeB)
	grant := req(1)
	grant.FloorBytes = 64 << 20
	grant.GrantBytes = 64 << 20
	changed, e := d.SetThinGrant(ctx, grant)
	if e != nil {
		t.Fatal(e)
	}
	if changed.Generation != grant.Generation+1 {
		t.Fatal("generation not advanced")
	}
	if _, e = d.SetThinGrant(ctx, grant); e != nil {
		t.Fatalf("idempotent retry: %v", e)
	}
	stale := grant
	stale.OperationID = "33333333-3333-3333-3333-333333333333"
	if _, e = d.SetThinGrant(ctx, stale); status.Code(e) != codes.Aborted {
		t.Fatalf("stale grant accepted: %v", e)
	}
	// A kernel hard limit, not virtual-device size, must reject the final write.
	_, e = (ExecRunner{}).Run(ctx, nil, "fallocate", "-l", "2300M", apath)
	if e == nil {
		t.Fatal("allocation crossed kernel quota")
	}
	if !strings.Contains(e.Error(), "Disk quota exceeded") && !strings.Contains(e.Error(), "No space left") {
		t.Fatalf("unexpected quota failure: %v", e)
	}
	if e = os.Remove(apath); e != nil {
		t.Fatal(e)
	}
	_, e = (ExecRunner{}).Run(ctx, nil, "dd", "if=/dev/zero", "of="+apath, "bs=1M", "count=2300", "conv=fsync", "status=none")
	if e == nil || (!strings.Contains(e.Error(), "Disk quota exceeded") && !strings.Contains(e.Error(), "No space left")) {
		t.Fatalf("write quota: %v", e)
	}
	if e = os.Remove(apath); e != nil {
		t.Fatal(e)
	}
	run("dd", "if=/dev/zero", "of="+apath, "bs=1M", "count=16", "conv=fsync", "status=none")
	// A failed create retains its full reservation until explicit cleanup.
	runner.failCreate.Store(true)
	if _, e = d.CreateVolume(ctx, request(7)); e == nil {
		t.Fatal("injected creation failure ignored")
	}
	pending := snap()
	if pending.CommittedBytes != initial.CommittedBytes+a.CapacityBytes {
		t.Fatal("pending intent was not charged")
	}
	if _, e = d.DeleteVolume(ctx, &csi.DeleteVolumeRequest{VolumeId: id(7)}); e != nil {
		t.Fatal(e)
	}
	// Durable quota intent wins after a crash between record and kernel update.
	failedGrant := req(2)
	failedGrant.FloorBytes = 128 << 20
	failedGrant.GrantBytes = 128 << 20
	runner.failQuota.Store(true)
	if _, e = d.SetThinGrant(ctx, failedGrant); e == nil {
		t.Fatal("injected quota failure ignored")
	}
	stage(b)
	if observation(snap(), b.VolumeId).GrantBytes != 128<<20 {
		t.Fatal("quota intent recovery lost grant")
	}
	checksum := run("sha256sum", filepath.Join(root, b.VolumeId, "payload"))
	// Reconstruct driver state as on a process restart, then reject a stale pod lease.
	d, e = New(cfg)
	if e != nil {
		t.Fatal(e)
	}
	stage(a)
	if e = publish(a, "44444444-4444-4444-4444-444444444444"); status.Code(e) != codes.FailedPrecondition {
		t.Fatalf("second pod accepted: %v", e)
	}
	if snap().CommittedBytes != initial.CommittedBytes {
		t.Fatal("grant/reclaim changed backing reservation")
	}
	// Concurrent creates are serialized and may not exceed four device slots.
	var wg sync.WaitGroup
	var success atomic.Int32
	for i := 3; i <= 6; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, e := d.CreateVolume(ctx, request(i))
			if e == nil {
				success.Add(1)
			} else if status.Code(e) != codes.ResourceExhausted {
				t.Errorf("concurrent create: %v", e)
			}
		}(i)
	}
	wg.Wait()
	if success.Load() != 2 {
		t.Fatalf("slot admission: %d", success.Load())
	}
	full := snap()
	if full.CommittedBytes > full.UsableBytes {
		t.Fatal("unbacked commitment")
	}
	// Raising reserve requirements makes observations unhealthy and blocks creation.
	pressure := cfg
	pressure.Thin.MetadataReserveBytes = 510 << 20
	pd, e := New(pressure)
	if e != nil {
		t.Fatal(e)
	}
	ps, e := pd.ThinStatus(ctx)
	if e != nil {
		t.Fatal(e)
	}
	if ps.Healthy {
		t.Fatal("metadata pressure accepted")
	}
	if _, e = pd.CreateVolume(ctx, request(7)); status.Code(e) != codes.ResourceExhausted {
		t.Fatalf("metadata pressure creation: %v", e)
	}
	pressure = cfg
	pressure.Thin.DataReserveBytes = 15 << 30
	pd, _ = New(pressure)
	if _, e = pd.CreateVolume(ctx, request(8)); status.Code(e) != codes.ResourceExhausted {
		t.Fatalf("data pressure creation: %v", e)
	}
	// Published volumes cannot be deleted. Cleanup and re-stage preserve identity.
	if _, e = d.DeleteVolume(ctx, &csi.DeleteVolumeRequest{VolumeId: a.VolumeId}); status.Code(e) != codes.FailedPrecondition {
		t.Fatalf("active deletion: %v", e)
	}
	for _, v := range []*csi.Volume{a, b} {
		if _, e = d.NodeUnpublishVolume(ctx, &csi.NodeUnpublishVolumeRequest{VolumeId: v.VolumeId, TargetPath: filepath.Join(root, "target-"+v.VolumeId)}); e != nil {
			t.Fatal(e)
		}
		if _, e = d.NodeUnstageVolume(ctx, &csi.NodeUnstageVolumeRequest{VolumeId: v.VolumeId, StagingTargetPath: filepath.Join(root, v.VolumeId)}); e != nil {
			t.Fatal(e)
		}
	}
	retained := snap()
	if retained.CommittedBytes != full.CommittedBytes {
		t.Fatal("unstaging released retained commitment")
	}
	stage(b)
	if e = publish(b, "44444444-4444-4444-4444-444444444444"); e != nil {
		t.Fatal(e)
	}
	if run("sha256sum", filepath.Join(root, b.VolumeId, "payload")) != checksum {
		t.Fatal("restart lost data")
	}
	if _, e = d.DeleteVolume(ctx, &csi.DeleteVolumeRequest{VolumeId: a.VolumeId}); e != nil {
		t.Fatal(e)
	}
	deleted := snap()
	if full.CommittedBytes-deleted.CommittedBytes != a.CapacityBytes {
		t.Fatal("deletion did not release full reservation")
	}
	if os.Getenv("KURA_THIN_BENCHMARK") == "1" {
		thickCfg := cfg
		thickCfg.Thin = ThinConfig{}
		thick, e := New(thickCfg)
		if e != nil {
			t.Fatal(e)
		}
		tr := request(8)
		tr.Parameters = nil
		tr.CapacityRange.RequiredBytes = 2 << 30
		tv, e := thick.CreateVolume(ctx, tr)
		if e != nil {
			t.Fatal(e)
		}
		thickPath := filepath.Join(root, tv.Volume.VolumeId)
		if _, e = thick.NodeStageVolume(ctx, &csi.NodeStageVolumeRequest{VolumeId: tv.Volume.VolumeId, StagingTargetPath: thickPath, VolumeCapability: capability, VolumeContext: tv.Volume.VolumeContext}); e != nil {
			t.Fatal(e)
		}
		for _, layout := range []string{"thick", "thin", "thin", "thick"} {
			path := thickPath
			if layout == "thin" {
				path = filepath.Join(root, b.VolumeId)
			}
			for _, rw := range []string{"write", "read", "randwrite", "randread"} {
				bs := "1M"
				if strings.HasPrefix(rw, "rand") {
					bs = "4k"
				}
				output := run("fio", "--name=cache", "--filename="+filepath.Join(path, "bench"), "--rw="+rw, "--bs="+bs, "--size=256M", "--direct=1", "--ioengine=libaio", "--iodepth=32", "--time_based=1", "--runtime=5", "--end_fsync=1", "--output-format=json")
				var f struct {
					Jobs []struct {
						Read, Write struct {
							IOPS      float64 `json:"iops"`
							Bandwidth int64   `json:"bw_bytes"`
							Clat      struct {
								Percentile map[string]float64 `json:"percentile"`
							} `json:"clat_ns"`
						}
					} `json:"jobs"`
				}
				if e = json.Unmarshal([]byte(output), &f); e != nil || len(f.Jobs) != 1 {
					t.Fatal("invalid fio result")
				}
				metric := f.Jobs[0].Write
				if strings.Contains(rw, "read") {
					metric = f.Jobs[0].Read
				}
				t.Logf("BENCH layout=%s rw=%s iops=%.0f bytes_per_sec=%d p99_ns=%.0f", layout, rw, metric.IOPS, metric.Bandwidth, metric.Clat.Percentile["99.000000"])
			}
			if e = os.Remove(filepath.Join(path, "bench")); e != nil {
				t.Fatal(e)
			}
			start := time.Now()
			for i := 0; i < 8; i++ {
				run("dd", "if=/dev/zero", "of="+filepath.Join(path, "churn"), "bs=1M", "count=16", "conv=fsync", "status=none")
				if e = os.Remove(filepath.Join(path, "churn")); e != nil {
					t.Fatal(e)
				}
				if layout == "thin" {
					r := req(2)
					r.PodUID = "44444444-4444-4444-4444-444444444444"
					if _, e = d.ReclaimThin(ctx, r); e != nil {
						t.Fatal(e)
					}
				}
			}
			t.Logf("BENCH layout=%s eviction_8x16MiB_ms=%d", layout, time.Since(start).Milliseconds())
		}
	}
	out, _ := json.Marshal(map[string]any{"initial": initial, "reclamation": reclaim, "retained": retained, "after_delete": deleted})
	t.Log(string(out))
}
