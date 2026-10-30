package podagent

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/hostdisk"
)

// pressured has a running custom branch and a running checkout branch.
func pressured(t *testing.T) (*CustomVolumes, *fakeBackend, cachevolumes.Slot, cachevolumes.Slot) {
	t.Helper()
	m, be := m2L(t)
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Space: m, reservations: map[string]cachevolumes.Slot{}}
	c.images = &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{Root: c.Root}}
	custom := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111"}, State: "active"}
	checkout := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "22222222-2222-4222-8222-222222222222", Kind: cachevolumes.KindCheckout}, State: "active"}
	for _, slot := range []cachevolumes.Slot{custom, checkout} {
		c.reservations[slot.ID] = slot
		image := filepath.Join(c.Root, "images", slot.ID+".img")
		if err := os.MkdirAll(filepath.Dir(image), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(image, nil, 0600); err != nil {
			t.Fatal(err)
		}
	}
	return c, be, custom, checkout
}

func withheld(c *CustomVolumes, slot cachevolumes.Slot) bool {
	_, err := os.Stat(filepath.Join(c.Root, "images", slot.ID+".img.pressure"))
	return err == nil
}

func TestPressureNearTheQuotaWithholdsRunningBranches(t *testing.T) {
	c, be, custom, checkout := pressured(t)
	be.totalBytes = customPressureBytes - 1

	c.notePressure(context.Background())

	if !withheld(c, custom) {
		t.Fatal("a branch written near the quota can still publish")
	}
	if withheld(c, checkout) {
		t.Fatal("marked a checkout branch, which never publishes")
	}
}

func TestPressureOnTheHostDiskWithholdsRunningBranches(t *testing.T) {
	c, _, custom, _ := pressured(t)
	c.Space.HostDiskSpace = func() (hostdisk.Stats, error) {
		return hostdisk.Stats{TotalBytes: 2000 * gib, FreeBytes: customPressureBytes - 1}, nil
	}

	c.notePressure(context.Background())

	if !withheld(c, custom) {
		t.Fatal("a branch written while the host disk was nearly full can still publish")
	}
}

// Past the budget but far from the quota, writes still succeed: only the budget
// is overcommitted, and that gap is what absorbs a job that writes more than expected.
func TestOvercommitWithinTheQuotaPublishesNormally(t *testing.T) {
	c, be, custom, _ := pressured(t)
	c.Space.BudgetGiB = 1
	be.totalBytes = 80 * gib

	c.notePressure(context.Background())

	if withheld(c, custom) {
		t.Fatal("withheld a branch written with the quota far away")
	}
}

func TestRelieveEvictsIdleCustomMastersOnceJobsOutgrowAdmission(t *testing.T) {
	for _, tc := range []struct {
		name    string
		free    uint64
		evicted bool
	}{
		{"reservations exceed free space", 4_000_000_000, true},
		{"reservations fit", 80 * gib, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m, be := m2L(t)
			be.totalBytes = tc.free
			c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Space: m, reservations: map[string]cachevolumes.Slot{}}
			c.reservations["11111111-1111-4111-8111-111111111111"] = cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111"}, State: "allocated"}
			b := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{Root: c.Root, SizeGB: 20, FreeBytesContext: c.freeBytesContext}}
			if err := b.Init(); err != nil {
				t.Fatal(err)
			}
			store, err := cachevolumes.Open(c.Root, b)
			if err != nil {
				t.Fatal(err)
			}
			defer store.Close()
			c.Store, c.images = store, b
			master := filepath.Join(c.Root, "masters", strings.Repeat("a", 64), "1.img")
			if err := os.MkdirAll(filepath.Dir(master), 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(master, []byte("master"), 0600); err != nil {
				t.Fatal(err)
			}

			c.relieve(context.Background())

			if _, err := os.Stat(master); os.IsNotExist(err) != tc.evicted {
				t.Fatalf("master evicted=%v, want %v", os.IsNotExist(err), tc.evicted)
			}
		})
	}
}
