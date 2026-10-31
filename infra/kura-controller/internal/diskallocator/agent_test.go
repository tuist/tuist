package diskallocator

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestTargets(t *testing.T) {
	for _, tc := range []struct {
		name         string
		capacity     uint64
		a, b         Sample
		wantA, wantB uint64
		fails        bool
	}{
		{"idle floor is reserved", 100, Sample{Volume: Volume{ID: "a", Floor: 20, Ceiling: 80}, Demand: 80}, Sample{Volume: Volume{ID: "b", Floor: 20, Ceiling: 80}, Demand: 0}, 80, 20, false},
		{"equal demand shares space", 100, Sample{Volume: Volume{ID: "a", Floor: 20, Ceiling: 80}, Demand: 80}, Sample{Volume: Volume{ID: "b", Floor: 20, Ceiling: 80}, Demand: 80}, 50, 50, false},
		{"ceiling redistributes surplus", 100, Sample{Volume: Volume{ID: "a", Floor: 20, Ceiling: 30}, Demand: 80}, Sample{Volume: Volume{ID: "b", Floor: 20, Ceiling: 80}, Demand: 80}, 30, 70, false},
		{"floors cannot overcommit", 39, Sample{Volume: Volume{ID: "a", Floor: 20, Ceiling: 80}}, Sample{Volume: Volume{ID: "b", Floor: 20, Ceiling: 80}}, 0, 0, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Targets(tc.capacity, []Sample{tc.a, tc.b})
			if tc.fails {
				if err == nil {
					t.Fatal("expected refusal")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got["a"] != tc.wantA || got["b"] != tc.wantB {
				t.Fatalf("targets: %v", got)
			}
		})
	}
}

type fakeDisk struct {
	samples  []Sample
	capacity uint64
	fail     bool
	calls    int
}

func (f *fakeDisk) Read(_ []Volume) ([]Sample, uint64, error) {
	return append([]Sample(nil), f.samples...), f.capacity, nil
}
func (f *fakeDisk) SetLimit(v Volume, b uint64) error {
	f.calls++
	if f.fail {
		return fmt.Errorf("quota update failed")
	}
	for i := range f.samples {
		if f.samples[i].ID == v.ID {
			f.samples[i].Current = b
		}
	}
	return nil
}
func fixture(t *testing.T) (*Agent, *fakeDisk, []Volume) {
	t.Helper()
	volumes := []Volume{{"a", "/data/a", 4 * GiB, 8 * GiB}, {"b", "/data/b", 4 * GiB, 8 * GiB}}
	disk := &fakeDisk{samples: []Sample{{Volume: volumes[0], Used: 7 * GiB, Current: 8 * GiB}, {Volume: volumes[1], Used: 4 * GiB, Current: 4 * GiB}}, capacity: 12 * GiB}
	return &Agent{Backend: disk, ControlDir: t.TempDir()}, disk, volumes
}
func TestReassignOnlyAfterPhysicalReclamation(t *testing.T) {
	a, disk, volumes := fixture(t)
	if _, err := a.Reconcile(volumes, time.Now()); err != nil {
		t.Fatal(err)
	}
	if disk.calls != 0 {
		t.Fatal("must not spend A's requested shrink")
	}
	data, err := os.ReadFile(filepath.Join(a.ControlDir, "a.json"))
	if err != nil {
		t.Fatal(err)
	}
	var budget Budget
	if err := json.Unmarshal(data, &budget); err != nil {
		t.Fatal(err)
	}
	if budget.Target != 6*GiB || budget.Current != 8*GiB {
		t.Fatalf("budget: %+v", budget)
	}
	// A restarted agent has no remembered promises. Kernel limits still
	// prevent spending the occupied or previously authorized allocation.
	a = &Agent{Backend: disk, ControlDir: a.ControlDir}
	if _, err := a.Reconcile(volumes, time.Now()); err != nil {
		t.Fatal(err)
	}
	if disk.calls != 0 {
		t.Fatal("restart prematurely released space")
	}
	disk.samples[0].Used = 5 * GiB
	if _, err := a.Reconcile(volumes, time.Now()); err != nil {
		t.Fatal(err)
	}
	if disk.samples[0].Current != 6*GiB || disk.samples[1].Current != 6*GiB {
		t.Fatalf("limits: %+v", disk.samples)
	}
}
func TestQuotaFailureDoesNotPublishAnIncrease(t *testing.T) {
	a, disk, volumes := fixture(t)
	disk.samples[0].Used = 5 * GiB
	disk.fail = true
	if _, err := a.Reconcile(volumes, time.Now()); err == nil {
		t.Fatal("expected quota failure")
	}
	if disk.samples[1].Current != 4*GiB {
		t.Fatal("failed shrink funded another replica")
	}
}
func TestExternalPressureStopsWritesButRetainsReclamation(t *testing.T) {
	a, disk, volumes := fixture(t)
	disk.capacity = 7 * GiB
	budgets, err := a.Reconcile(volumes, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	for _, b := range budgets {
		if b.AllowWrites || b.Target != 4*GiB {
			t.Fatalf("unsafe pressure budget: %+v", b)
		}
	}
}
func TestRejectsSharedDirectoryAndUnsafeIdentity(t *testing.T) {
	for _, volumes := range [][]Volume{
		{{"../other", "/data/a", 4 * GiB, 8 * GiB}},
		{{"a", "/data/a", 4 * GiB, 8 * GiB}, {"b", "/data/a", 4 * GiB, 8 * GiB}},
	} {
		if ValidateVolumes(volumes) == nil {
			t.Fatal("accepted invalid inventory")
		}
	}
}

func TestUnfundedFloorsCannotAuthorizeWritesEvenBelowCurrentQuotaCapacity(t *testing.T) {
	a, disk, volumes := fixture(t)
	for i := range disk.samples {
		disk.samples[i].Current = 3 * GiB
		disk.samples[i].Used = GiB
	}
	disk.capacity = 7 * GiB
	budgets, err := a.Reconcile(volumes, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	for _, b := range budgets {
		if b.AllowWrites {
			t.Fatal("unfunded floor authorized writes")
		}
	}
}

func TestTargetsRoundDownBeforeKernelAllocation(t *testing.T) {
	a, disk, volumes := fixture(t)
	disk.samples[0].Used = 5 * GiB
	disk.capacity = 12*GiB + 1024
	if _, err := a.Reconcile(volumes, time.Now()); err != nil {
		t.Fatal(err)
	}
	for _, s := range disk.samples {
		if s.Current%quotaUnit != 0 {
			t.Fatalf("unaligned quota: %d", s.Current)
		}
	}
	total, _ := charged(disk.samples)
	if total > disk.capacity {
		t.Fatal("rounded quota overspent capacity")
	}
}

func TestQuietUsefulOccupancyRetainsRuntimeOverhead(t *testing.T) {
	volume := Volume{"a", "/data/a", 8 * GiB, 64 * GiB}
	disk := &fakeDisk{samples: []Sample{{Volume: volume, Used: 17 * GiB, Current: 25 * GiB}}, capacity: 64 * GiB}
	a := &Agent{Backend: disk, ControlDir: t.TempDir()}
	if _, err := a.Reconcile([]Volume{volume}, time.Now()); err != nil {
		t.Fatal(err)
	}
	// Subtract the runtime's staging, rotation and metadata allowances.
	// The resulting ring must still cover the observed useful occupancy.
	ring := (disk.samples[0].Current - 2*GiB - GiB/2) / 100 * 97
	if ring < disk.samples[0].Used {
		t.Fatal("quiet occupancy would recursively shrink")
	}
}
