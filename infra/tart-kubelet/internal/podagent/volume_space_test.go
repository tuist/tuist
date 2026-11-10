package podagent

import (
	"context"
	"errors"
	"path/filepath"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/hostdisk"
)

func TestCacheAdmissionPreservesPhysicalHostFloor(t *testing.T) {
	for _, tc := range []struct {
		name string
		free uint64
		want uint64
	}{
		{"quota limits a spacious host", 1000 * gib, 512 * gib},
		{"host limits a spacious quota", 350 * gib, 50 * gib},
		{"at host floor", 300 * gib, 0},
		{"below host floor", 250 * gib, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m, _ := newTestSpace(t, 512)
			m.HostDiskSpace = func() (hostdisk.Stats, error) {
				return hostdisk.Stats{TotalBytes: 2000 * gib, FreeBytes: tc.free}, nil
			}
			free, err := m.availableBytes()
			if err != nil || free != tc.want {
				t.Fatalf("available = %d, %v; want %d", free, err, tc.want)
			}
			raw, err := m.volumeFreeBytes()
			if err != nil || raw != 512*gib {
				t.Fatal("raw quota telemetry changed", raw, err)
			}
		})
	}
}

func TestHostFloorAppliesToCustomVolumes(t *testing.T) {
	m, _ := newTestSpace(t, 512)
	m.HostDiskSpace = func() (hostdisk.Stats, error) {
		return hostdisk.Stats{TotalBytes: 2000 * gib, FreeBytes: 310 * gib}, nil
	}
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Space: m}
	if _, err := c.reserve(context.Background(), cachevolumes.Slot{Identity: cachevolumes.Identity{HeadSizeBytes: customCapacity}}); !errors.Is(err, cachevolumes.ErrCapacity) {
		t.Fatalf("custom consumed host reserve: %v", err)
	}
	m.HostDiskSpace = func() (hostdisk.Stats, error) { return hostdisk.Stats{}, errors.New("probe failed") }
	if _, err := m.availableBytes(); err == nil {
		t.Fatal("ignored host probe failure")
	}
	m.HostDiskSpace = func() (hostdisk.Stats, error) { return hostdisk.Stats{}, nil }
	if _, err := m.availableBytes(); err == nil {
		t.Fatal("accepted unknown host capacity")
	}
}

func TestCustomReclaimCannotSpendPinnedHostBlocks(t *testing.T) {
	m, _ := m2L(t)
	m.HostDiskSpace = func() (hostdisk.Stats, error) {
		// Blocks still pinned by a live CoW clone after master eviction.
		return hostdisk.Stats{TotalBytes: 2000 * gib, FreeBytes: 310 * gib}, nil
	}
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Space: m}
	if err := c.reclaim(context.Background(), customCapacity); !errors.Is(err, cachevolumes.ErrCapacity) {
		t.Fatalf("credited deletion without physical space recovery: %v", err)
	}
}

func TestCustomReclaimKeepsEveryReservation(t *testing.T) {
	m, be := m2L(t)
	be.inUse = 40 * gib
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Space: m}
	if err := c.reclaim(context.Background(), customCapacity); err != nil {
		t.Fatalf("reclaim with room to spare: %v", err)
	}
	c.reservations = map[string]cachevolumes.Slot{"other": {Identity: cachevolumes.Identity{ID: "other", VolumeBytes: 30_000_000_000, HeadSizeBytes: 20_000_000_000}}}
	if err := c.reclaim(context.Background(), customCapacity); !errors.Is(err, cachevolumes.ErrCapacity) {
		t.Fatalf("reclaim spent another job's reservation: %v", err)
	}
}

// A budget below the volume's quota bounds the caches the way a quota of that
// size would, so a host can change it with a restart instead of a new volume.
func TestCacheBudgetBoundsCachesBelowTheQuota(t *testing.T) {
	m, be := newTestSpace(t, 1024)
	m.BudgetGiB = 220
	be.inUse = 200 * gib

	if free, err := m.availableBytes(); err != nil || free != 20*gib {
		t.Fatalf("available = %d, %v; want the 20 GiB left in the budget", free, err)
	}
	if free, err := m.volumeFreeBytes(); err != nil || free != 20*gib {
		t.Fatalf("volume free = %d, %v; want the 20 GiB left in the budget", free, err)
	}
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Space: m}
	if _, err := c.reserve(context.Background(), cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "job", VolumeBytes: 30_000_000_000, HeadSizeBytes: 20_000_000_000}}); !errors.Is(err, cachevolumes.ErrCapacity) {
		t.Fatalf("admitted 30 GB with 20 GiB left in the budget: %v", err)
	}
}

// The quota stays the hard bound when the budget is set above it, as on a
// host whose volume was created before the budget was raised.
func TestCacheBudgetAboveTheQuotaLeavesTheQuota(t *testing.T) {
	m, be := newTestSpace(t, 240)
	m.BudgetGiB = 512
	be.inUse = 100 * gib

	if free, err := m.availableBytes(); err != nil || free != 140*gib {
		t.Fatalf("available = %d, %v; want the quota's 140 GiB", free, err)
	}
	if capacity, err := m.volumeCapacityBytes(); err != nil || capacity != 240*gib {
		t.Fatalf("capacity = %d, %v; want the 240 GiB quota", capacity, err)
	}
}

func TestCapacityNodeLabelsAdvertiseTheBudgetedCacheDisk(t *testing.T) {
	m, be := newTestSpace(t, 512)
	m.BudgetGiB = 240
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Space: m}

	labels, err := c.CapacityNodeLabels()
	if err != nil || len(labels) != 1 || labels[CacheCapacityNodeLabel] != "240" {
		t.Fatalf("labels = %v, %v; want %s=240", labels, err, CacheCapacityNodeLabel)
	}

	m.BudgetGiB = 0
	if labels, _ = c.CapacityNodeLabels(); labels[CacheCapacityNodeLabel] != "512" {
		t.Fatalf("labels = %v, want the quota without a budget", labels)
	}

	be.notMounted = true
	if labels, err = c.CapacityNodeLabels(); err != nil || len(labels) != 0 {
		t.Fatalf("labels = %v, %v; want none while unmounted", labels, err)
	}
}
