package podagent

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

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
			m, _ := newTestManager(t, 512)
			m.HostDiskSpace = func() (hostdisk.Stats, error) {
				return hostdisk.Stats{TotalBytes: 2000 * gib, FreeBytes: tc.free}, nil
			}
			free, err := m.availableBytes()
			if err != nil || free != tc.want {
				t.Fatalf("available = %d, %v; want %d", free, err, tc.want)
			}
			_, raw, err := m.Stats()
			if err != nil || raw != 512*gib {
				t.Fatal("raw quota telemetry changed", raw, err)
			}
		})
	}
}

func TestHostFloorAppliesToBuiltinCustomAndConvergence(t *testing.T) {
	m, _ := newTestManager(t, 512)
	m.CapGiB = 30
	m.HostDiskSpace = func() (hostdisk.Stats, error) {
		return hostdisk.Stats{TotalBytes: 2000 * gib, FreeBytes: 310 * gib}, nil
	}
	att := mustAllocate(t, m, "running")
	if err := m.MaterializeEmpty(att); !errors.Is(err, errAdmissionDeclined) {
		t.Fatalf("built-in consumed host reserve: %v", err)
	}
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Builtins: m}
	if _, err := c.reserve(context.Background(), cachevolumes.Slot{}); !errors.Is(err, cachevolumes.ErrCapacity) {
		t.Fatalf("custom consumed host reserve: %v", err)
	}
	if _, err := m.PrepareConvergeSpace(masterKey{}, 20*gib, 20*gib, false, func(error) {}); !errors.Is(err, errNoRoomToConverge) {
		t.Fatalf("convergence consumed host reserve: %v", err)
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

func TestCustomAttachReclaimsBuiltinMastersAndPreservesWriters(t *testing.T) {
	m, be := m2L(t)
	be.perMaster = 20 * gib
	seedMaster(t, m, "1")
	seedMaster(t, m, "2")
	older := m.masterImage("1", ReservedTuistCacheVolume)
	oldTime := m.now().Add(-time.Second)
	if err := os.Chtimes(older, oldTime, oldTime); err != nil {
		t.Fatal(err)
	}
	branch := filepath.Join(m.Root, "branches", "running", branchImageName)
	if err := os.MkdirAll(filepath.Dir(branch), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(branch, []byte("active writer"), 0600); err != nil {
		t.Fatal(err)
	}
	m.reserved = map[string]bool{filepath.Dir(branch): true}
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Builtins: m}
	b := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{
		Root: c.Root, SizeGB: 20, MinFreeBytes: 40_000_000_000,
		FreeBytesContext: c.freeBytesContext, Reclaim: c.reclaim,
	}, Reserve: c.reserve, Create: func(_ context.Context, path string, _ int64) error {
		return os.WriteFile(path, nil, 0600)
	}}
	if err := b.Init(); err != nil {
		t.Fatal(err)
	}
	store, err := cachevolumes.Open(c.Root, b)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	id := cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111", Scope: strings.Repeat("a", 64), Account: 1}
	if _, err := store.Acquire(context.Background(), id, "job", "uid"); err != nil {
		t.Fatal("cold attach should reclaim the oldest built-in master", err)
	}
	if _, err := os.Stat(older); !os.IsNotExist(err) {
		t.Fatal("oldest master was not evicted", err)
	}
	if _, err := os.Stat(m.masterImage("2", ReservedTuistCacheVolume)); err != nil {
		t.Fatal("evicted more masters than necessary", err)
	}
	if data, err := os.ReadFile(branch); err != nil || string(data) != "active writer" || len(m.reserved) != 1 {
		t.Fatal("altered active built-in branch or reservation", err)
	}
}

func TestCustomReclaimCannotSpendPinnedHostBlocks(t *testing.T) {
	m, _ := m2L(t)
	seedMaster(t, m, "1")
	m.HostDiskSpace = func() (hostdisk.Stats, error) {
		// Simulate blocks still pinned by a live CoW clone after master eviction.
		return hostdisk.Stats{TotalBytes: 2000 * gib, FreeBytes: 310 * gib}, nil
	}
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Builtins: m}
	if err := c.reclaim(context.Background(), customCapacity); !errors.Is(err, cachevolumes.ErrCapacity) {
		t.Fatalf("credited deletion without physical space recovery: %v", err)
	}
}
