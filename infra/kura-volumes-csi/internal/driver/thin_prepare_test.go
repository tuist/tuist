package driver

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

const prepareVG = "kura-volumes"

func prepareOptions(t *testing.T) PreparePoolOptions {
	t.Helper()
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return PreparePoolOptions{VolumeGroup: prepareVG, StateDir: dir, Pool: "kura-thin", DataBytes: 600 << 30, MetadataBytes: 1 << 30, DataReserveBytes: 1 << 30, MetadataReserveBytes: 64 << 20, MaxVolumes: 128}
}

func prerequisiteCalls() []call {
	return []call{
		{cmd: "dmsetup targets", out: "thin-pool        v1.23.0\nthin             v1.23.0\nstriped          v1.6.0\n"},
		{cmd: thinCheckPath + " --version", out: "1.0.9\n"},
		{cmd: lvmCmd("vgs", "--noheadings --units b --nosuffix --separator , -o vg_free,vg_extent_size "+prepareVG), out: "  858993459200,4194304\n"},
	}
}

func inventoryCall(rows ...string) call {
	return call{cmd: lvmCmd("lvs", "--reportformat json --units b --nosuffix -o lv_name,lv_uuid,pool_lv,lv_size,segtype,origin,lv_attr,lv_active,chunk_size,lv_metadata_size "+prepareVG), out: `{"report":[{"lv":[` + strings.Join(rows, ",") + `]}]}`}
}

const dataLVRow = `{"lv_name":"data","lv_uuid":"data-uuid","pool_lv":"","lv_size":"137438953472","segtype":"linear","origin":"","lv_attr":"-wi-ao----","lv_active":"active","chunk_size":"0","lv_metadata_size":""}`

func poolRow(chunk string) string {
	return `{"lv_name":"kura-thin","lv_uuid":"pool-uuid","pool_lv":"","lv_size":"644245094400","segtype":"thin-pool","origin":"","lv_attr":"twi-a-tz--","lv_active":"active","chunk_size":"` + chunk + `","lv_metadata_size":"1073741824"}`
}

func policyCall(discards, whenFull string) call {
	return call{cmd: lvmCmd("lvs", "--reportformat json -o lv_name,discards,lv_when_full "+prepareVG+"/kura-thin"), out: `{"report":[{"lv":[{"lv_name":"kura-thin","discards":"` + discards + `","lv_when_full":"` + whenFull + `"}]}]}`}
}

const createCall = "lvcreate --config " + lvmConfig + " --yes --type thin-pool --size 614400M --poolmetadatasize 1024M --chunksize 512K --zero y --discards passdown --name kura-thin " + prepareVG

var whenFullCall = call{cmd: lvmCmd("lvchange", "--errorwhenfull y "+prepareVG+"/kura-thin")}

const wantConfig = `{"pool":"kura-thin","data_reserve_bytes":1073741824,"metadata_reserve_bytes":67108864,"max_volumes":128}`

func TestPreparePoolCreatesFreshPoolAndConfig(t *testing.T) {
	o := prepareOptions(t)
	r := &fakeRunner{t: t}
	r.expect(prerequisiteCalls()...)
	r.expect(inventoryCall(dataLVRow), call{cmd: createCall}, whenFullCall, inventoryCall(dataLVRow, poolRow("524288")), policyCall("passdown", "error"))
	result, err := PreparePool(context.Background(), r, o)
	if err != nil {
		t.Fatal(err)
	}
	r.verify()
	if !result.Created || !result.ConfigWritten || result.PoolUUID != "pool-uuid" {
		t.Fatalf("result = %+v", result)
	}
	path := filepath.Join(o.StateDir, "thin-pool.json")
	data, err := os.ReadFile(path)
	if err != nil || string(data) != wantConfig {
		t.Fatalf("config = %s, %v", data, err)
	}
	if info, _ := os.Stat(path); info.Mode().Perm() != 0600 {
		t.Fatalf("config mode = %v", info.Mode())
	}
	if c, err := LoadThinConfig(o.StateDir); err != nil || c != o.config() {
		t.Fatalf("plugin cannot load the written config: %+v %v", c, err)
	}
	if _, err := os.Stat(path + ".new"); !os.IsNotExist(err) {
		t.Fatalf("temporary config left behind: %v", err)
	}
}

func TestPreparePoolIsIdempotentForAnIdenticalPool(t *testing.T) {
	o := prepareOptions(t)
	if err := os.WriteFile(filepath.Join(o.StateDir, "thin-pool.json"), []byte(wantConfig), 0600); err != nil {
		t.Fatal(err)
	}
	// A volume in the pool must not stop a confirming rerun.
	member := `{"lv_name":"` + testVolumeID + `","lv_uuid":"v","pool_lv":"kura-thin","lv_size":"3623878656","segtype":"thin","origin":"","lv_attr":"Vwi-aotz--","lv_active":"active","chunk_size":"0","lv_metadata_size":""}`
	r := &fakeRunner{t: t}
	r.expect(prerequisiteCalls()...)
	r.expect(inventoryCall(dataLVRow, poolRow("524288"), member), policyCall("passdown", "error"))
	result, err := PreparePool(context.Background(), r, o)
	if err != nil {
		t.Fatal(err)
	}
	r.verify()
	if result.Created || result.ConfigWritten {
		t.Fatalf("identical rerun changed something: %+v", result)
	}
}

func TestPreparePoolRefusesDifferentGeometry(t *testing.T) {
	for name, tc := range map[string]struct {
		row    string
		policy []call
		want   string
	}{
		"chunk":     {row: poolRow("65536"), want: "chunk size"},
		"size":      {row: strings.Replace(poolRow("524288"), "644245094400", "34359738368", 1), want: "data size"},
		"metadata":  {row: strings.Replace(poolRow("524288"), `"lv_metadata_size":"1073741824"`, `"lv_metadata_size":"268435456"`, 1), want: "metadata size"},
		"zeroing":   {row: strings.Replace(poolRow("524288"), "twi-a-tz--", "twi-a-t---", 1), want: "zeroing"},
		"discards":  {row: poolRow("524288"), policy: []call{policyCall("nopassdown", "error")}, want: "discards"},
		"when full": {row: poolRow("524288"), policy: []call{policyCall("passdown", "queue")}, want: "when-full"},
		"not thin":  {row: strings.Replace(poolRow("524288"), `"segtype":"thin-pool"`, `"segtype":"linear"`, 1), want: "segment type"},
	} {
		t.Run(name, func(t *testing.T) {
			o := prepareOptions(t)
			r := &fakeRunner{t: t}
			r.expect(prerequisiteCalls()...)
			r.expect(inventoryCall(dataLVRow, tc.row))
			r.expect(tc.policy...)
			_, err := PreparePool(context.Background(), r, o)
			if err == nil || !strings.Contains(err.Error(), "different geometry") || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("err = %v", err)
			}
			r.verify()
			if _, err := os.Lstat(filepath.Join(o.StateDir, "thin-pool.json")); !os.IsNotExist(err) {
				t.Fatalf("config written for a mismatched pool: %v", err)
			}
		})
	}
}

func TestPreparePoolFailsBeforeMutationWithoutThinTarget(t *testing.T) {
	o := prepareOptions(t)
	r := &fakeRunner{t: t}
	r.expect(call{cmd: "dmsetup targets", out: "striped          v1.6.0\nlinear           v1.4.0\n"})
	_, err := PreparePool(context.Background(), r, o)
	if err == nil || !strings.Contains(err.Error(), "dm_thin_pool") {
		t.Fatalf("err = %v", err)
	}
	r.verify()
	entries, _ := os.ReadDir(o.StateDir)
	if len(entries) != 0 {
		t.Fatalf("state dir touched: %v", entries)
	}
}

func TestPreparePoolRefusesConfigAndPoolDisagreements(t *testing.T) {
	t.Run("different config", func(t *testing.T) {
		o := prepareOptions(t)
		if err := os.WriteFile(filepath.Join(o.StateDir, "thin-pool.json"), []byte(strings.Replace(wantConfig, "128", "64", 1)), 0600); err != nil {
			t.Fatal(err)
		}
		r := &fakeRunner{t: t}
		r.expect(prerequisiteCalls()[:2]...)
		if _, err := PreparePool(context.Background(), r, o); err == nil || !strings.Contains(err.Error(), "differs") {
			t.Fatalf("err = %v", err)
		}
		r.verify()
	})
	t.Run("config without pool", func(t *testing.T) {
		o := prepareOptions(t)
		if err := os.WriteFile(filepath.Join(o.StateDir, "thin-pool.json"), []byte(wantConfig), 0600); err != nil {
			t.Fatal(err)
		}
		r := &fakeRunner{t: t}
		r.expect(prerequisiteCalls()...)
		r.expect(inventoryCall(dataLVRow))
		if _, err := PreparePool(context.Background(), r, o); err == nil || !strings.Contains(err.Error(), "does not exist") {
			t.Fatalf("err = %v", err)
		}
		r.verify()
	})
	t.Run("populated pool without config", func(t *testing.T) {
		o := prepareOptions(t)
		member := `{"lv_name":"` + testVolumeID + `","lv_uuid":"v","pool_lv":"kura-thin","lv_size":"3623878656","segtype":"thin","origin":"","lv_attr":"Vwi-aotz--","lv_active":"active","chunk_size":"0","lv_metadata_size":""}`
		r := &fakeRunner{t: t}
		r.expect(prerequisiteCalls()...)
		r.expect(inventoryCall(dataLVRow, poolRow("524288"), member), policyCall("passdown", "error"))
		if _, err := PreparePool(context.Background(), r, o); err == nil || !strings.Contains(err.Error(), "already holds thin volumes") {
			t.Fatalf("err = %v", err)
		}
		r.verify()
	})
	t.Run("insufficient free extents", func(t *testing.T) {
		o := prepareOptions(t)
		r := &fakeRunner{t: t}
		calls := prerequisiteCalls()
		calls[2].out = "  644245094400,4194304\n"
		r.expect(calls...)
		r.expect(inventoryCall(dataLVRow))
		if _, err := PreparePool(context.Background(), r, o); err == nil || !strings.Contains(err.Error(), "insufficient") {
			t.Fatalf("err = %v", err)
		}
		r.verify()
	})
}

func TestPreparePoolValidatesBeforeRunningCommands(t *testing.T) {
	for name, mutate := range map[string]func(*PreparePoolOptions){
		"small metadata":  func(o *PreparePoolOptions) { o.MetadataBytes = 128 << 20 },
		"reserved name":   func(o *PreparePoolOptions) { o.Pool = "data" },
		"volume name":     func(o *PreparePoolOptions) { o.Pool = "pvc-pool" },
		"unaligned size":  func(o *PreparePoolOptions) { o.DataBytes += 512 },
		"tiny reserve":    func(o *PreparePoolOptions) { o.DataReserveBytes = 32 << 20 },
		"relative state":  func(o *PreparePoolOptions) { o.StateDir = "data/kura-volumes" },
		"no volume group": func(o *PreparePoolOptions) { o.VolumeGroup = "" },
	} {
		t.Run(name, func(t *testing.T) {
			o := prepareOptions(t)
			mutate(&o)
			r := &fakeRunner{t: t}
			if _, err := PreparePool(context.Background(), r, o); err == nil {
				t.Fatal("accepted")
			}
			r.verify()
		})
	}
}

func gauges(t *testing.T, reg *prometheus.Registry) map[string]float64 {
	t.Helper()
	families, err := reg.Gather()
	if err != nil {
		t.Fatal(err)
	}
	values := map[string]float64{}
	for _, f := range families {
		for _, m := range f.GetMetric() {
			labels := map[string]string{}
			for _, l := range m.GetLabel() {
				labels[l.GetName()] = l.GetValue()
			}
			if len(labels) != 3 || labels["node"] != testNode || labels["vg"] != prepareVG || labels["pool"] != "tenants" {
				t.Fatalf("%s has unexpected labels %v", f.GetName(), labels)
			}
			values[f.GetName()] = m.GetGauge().GetValue()
		}
	}
	return values
}

func TestThinMetricsFollowObservations(t *testing.T) {
	e := newEnv(t)
	e.d.volumeGroup = prepareVG
	e.d.thin = ThinConfig{Pool: "tenants", DataReserveBytes: 64 << 20, MetadataReserveBytes: 16 << 20, MaxVolumes: 4}
	e.d.metrics = newThinMetrics()
	s := &ThinSnapshot{DataTotal: 100, DataUsed: 85, MetadataTotal: 10, MetadataUsed: 2, Healthy: true, ObservedAt: time.Unix(1700000000, 0)}
	e.d.recordThin(context.Background(), s, nil)
	got := gauges(t, e.d.metrics.registry)
	want := map[string]float64{
		"kura_volumes_thin_pool_data_size_bytes": 100, "kura_volumes_thin_pool_data_used_bytes": 85,
		"kura_volumes_thin_pool_metadata_size_bytes": 10, "kura_volumes_thin_pool_metadata_used_bytes": 2,
		"kura_volumes_thin_pool_healthy": 1, "kura_volumes_thin_pool_read_only": 0, "kura_volumes_thin_pool_out_of_data_space": 0,
		"kura_volumes_thin_pool_last_observation_timestamp_seconds": 1700000000,
	}
	for name, value := range want {
		if got[name] != value {
			t.Fatalf("%s = %v, want %v (all: %v)", name, got[name], value, got)
		}
	}

	// A failed observation withdraws usage but still reports a failed pool.
	e.runner.expect(call{cmd: "dmsetup status kura--volumes-tenants-tpool", out: "0 134217728 thin-pool Fail"})
	e.d.recordThin(context.Background(), nil, os.ErrDeadlineExceeded)
	got = gauges(t, e.d.metrics.registry)
	if _, ok := got["kura_volumes_thin_pool_data_used_bytes"]; ok || got["kura_volumes_thin_pool_read_only"] != 1 || len(got) != 3 {
		t.Fatalf("after failure: %v", got)
	}
}

func TestThinPoolModes(t *testing.T) {
	for line, want := range map[string][2]bool{
		"0 8 thin-pool 1 10/262144 10/1048576 - rw discard_passdown error_if_no_space - 1024":                     {false, false},
		"0 8 thin-pool 1 10/262144 1048576/1048576 - out_of_data_space discard_passdown error_if_no_space - 1024": {false, true},
		"0 8 thin-pool 1 10/262144 10/1048576 - ro discard_passdown error_if_no_space - 1024":                     {true, false},
		"0 8 thin-pool 1 10/262144 10/1048576 - rw discard_passdown error_if_no_space needs_check 1024":           {true, false},
		"0 8 thin-pool Fail": {true, false},
	} {
		ro, full, ok := poolMode(strings.Fields(line))
		if !ok || ro != want[0] || full != want[1] {
			t.Fatalf("%q = %v %v %v", line, ro, full, ok)
		}
	}
	if _, _, ok := poolMode(strings.Fields("0 8 linear")); ok {
		t.Fatal("non-pool status accepted")
	}
}
