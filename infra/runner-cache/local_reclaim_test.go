package cachevolumes

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAdmissionReclaimsLocalMastersBeforeSharedDisk(t *testing.T) {
	root := t.TempDir()
	master := filepath.Join(root, "masters", strings.Repeat("a", 64), "cache.img")
	if err := os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(master, nil, 0600); err != nil {
		t.Fatal(err)
	}
	free := uint64(0)
	b := &LocalImages{Root: root, FreeBytes: func(string) (uint64, error) { return free, nil }}
	calls := 0
	b.Reclaim = func(_ context.Context, minimum uint64) error {
		calls++
		if _, err := os.Stat(master); !os.IsNotExist(err) {
			t.Fatal("shared reclamation ran before local eviction", err)
		}
		free = minimum
		return nil
	}
	if err := b.reserveBytes(context.Background(), 20); err != nil {
		t.Fatal(err)
	}
	if err := b.reserveBytes(context.Background(), 20); err != nil || calls != 1 {
		t.Fatal("unnecessarily reclaimed shared disk", calls, err)
	}
}

func TestSharedReclamationMustActuallyFreeSpace(t *testing.T) {
	b := &LocalImages{Root: t.TempDir(), FreeBytes: func(string) (uint64, error) { return 0, nil }}
	b.Reclaim = func(context.Context, uint64) error { return nil }
	if err := b.reserveBytes(context.Background(), 20); !errors.Is(err, ErrCapacity) {
		t.Fatal("accepted reclamation without recovering space", err)
	}
	b.Reclaim = func(context.Context, uint64) error { return context.Canceled }
	if err := b.reserveBytes(context.Background(), 20); !errors.Is(err, context.Canceled) {
		t.Fatal("lost reclamation failure", err)
	}
}
