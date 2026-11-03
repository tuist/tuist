package driver

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestThinStageDoesNotWalkExistingCache(t *testing.T) {
	e := newEnv(t)
	r := &ThinVolume{VolumeID: testVolumeID, GrantBytes: 1 << 30}
	// Exercise both first stage and idempotent restage with the same record.
	for i := 0; i < 2; i++ {
		e.runner.expect(
			call{cmd: "xfs_quota -x -c project -s -d 0 -p " + e.staging + " 1 " + e.staging},
			call{cmd: "xfs_quota -x -c limit -p bsoft=3072m bhard=3072m 1 " + e.staging},
			call{cmd: "xfs_quota -x -c state -p " + e.staging, out: "Accounting: ON\nEnforcement: ON"},
			call{cmd: "xfs_quota -x -c report -p -b -n " + e.staging, out: fmt.Sprintf("#1 0 0 %d", (r.GrantBytes+thinWorkspace)/1024)},
		)
		if err := e.d.finishThinStage(context.Background(), e.v, r, e.staging); err != nil {
			t.Fatal(err)
		}
	}
}

func TestFailedThinObservationWithdrawsInsteadOfAdvertisingZero(t *testing.T) {
	e := newEnv(t)
	e.d.thin.Pool = "tenants"
	unlock, err := e.d.lockPool(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer unlock()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	capacity, present, err := e.d.KuraDiskCapacity(ctx)
	if err != nil || present || capacity != 0 {
		t.Fatalf("failed observation must remove capacity: %d %v %v", capacity, present, err)
	}
}

func TestThinSizingAndConfiguration(t *testing.T) {
	for _, n := range []int64{0, -1, 1 << 51} {
		if _, e := ThinVirtualBytes(n); e == nil {
			t.Fatalf("accepted cache size %d", n)
		}
	}
	n, e := ThinVirtualBytes(1 << 30)
	if e != nil || n != 3623878656 {
		t.Fatalf("versioned sizing contract: %d %v", n, e)
	}
	dir := t.TempDir()
	c, e := LoadThinConfig(dir)
	if e != nil || c.Pool != "" {
		t.Fatal("absent config must keep legacy nodes")
	}
	path := filepath.Join(dir, "thin-pool.json")
	data := []byte(`{"pool":"tenants","data_reserve_bytes":1073741824,"metadata_reserve_bytes":67108864,"max_volumes":128}`)
	if e = os.WriteFile(path, data, 0600); e != nil {
		t.Fatal(e)
	}
	c, e = LoadThinConfig(dir)
	if e != nil || c.validate("kura-volumes") != nil {
		t.Fatalf("valid private config: %v", e)
	}
	if e = os.Chmod(path, 0644); e != nil {
		t.Fatal(e)
	}
	if _, e = LoadThinConfig(dir); e == nil {
		t.Fatal("public config accepted")
	}
	if e = os.Chmod(path, 0600); e != nil {
		t.Fatal(e)
	}
	if e = os.WriteFile(path, append(data, []byte(` {}`)...), 0600); e != nil {
		t.Fatal(e)
	}
	if _, e = LoadThinConfig(dir); e == nil {
		t.Fatal("trailing config accepted")
	}
	if e = os.Remove(path); e != nil {
		t.Fatal(e)
	}
	if e = os.Symlink(filepath.Join(dir, "missing"), path); e != nil {
		t.Fatal(e)
	}
	if _, e = LoadThinConfig(dir); e == nil {
		t.Fatal("symlink config accepted")
	}
}

func TestThinCountersRemainExact(t *testing.T) {
	used, total, e := parsePair("1025/4096", 65536)
	if e != nil || used != 67174400 || total != 268435456 {
		t.Fatalf("counters: %d %d %v", used, total, e)
	}
	for _, s := range []string{"-1/2", "3/2", "1/9000000000000000", "1.1/2", "1"} {
		if _, _, e = parsePair(s, 65536); e == nil {
			t.Fatalf("invalid counters accepted: %s", s)
		}
	}
}

// observePool scripts one observation of an empty pool and returns its snapshot.
func observePool(t *testing.T, active string, extra ...call) *ThinSnapshot {
	t.Helper()
	e := newEnv(t)
	e.d.volumeGroup = "kura-volumes"
	e.d.thin = ThinConfig{Pool: "tenants", DataReserveBytes: 64 << 20, MetadataReserveBytes: 16 << 20, MaxVolumes: 4}
	inventory := fmt.Sprintf(`{"report":[{"lv":[{"lv_name":"tenants","lv_uuid":"pool-uuid","pool_lv":"","lv_size":"68719476736","segtype":"thin-pool","origin":"","lv_attr":"twi-aotz--","lv_active":%q,"chunk_size":"65536","lv_metadata_size":"1073741824"}]}]}`, active)
	status := "0 134217728 thin-pool 1 10/262144 10/1048576 - rw discard_passdown error_if_no_space - 1024"
	e.runner.expect(call{cmd: lvmCmd("lvs", "--reportformat json --units b --nosuffix -o lv_name,lv_uuid,pool_lv,lv_size,segtype,origin,lv_attr,lv_active,chunk_size,lv_metadata_size kura-volumes"), out: inventory})
	e.runner.expect(extra...)
	e.runner.expect(
		call{cmd: "dmsetup status kura--volumes-tenants-tpool", out: status},
		call{cmd: "dmsetup status kura--volumes-tenants-tpool", out: status},
	)
	s, err := e.d.observeThin(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestThinObservationActivatesOnlyAnInactivePool(t *testing.T) {
	if s := observePool(t, "active"); !s.Healthy {
		t.Fatalf("active pool unhealthy: %s", s.Reason)
	}
	if s := observePool(t, "", call{cmd: lvmCmd("lvchange", "--activate y kura-volumes/tenants")}); !s.Healthy {
		t.Fatalf("activated pool unhealthy: %s", s.Reason)
	}
}
