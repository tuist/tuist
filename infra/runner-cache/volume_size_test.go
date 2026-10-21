package cachevolumes

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// sizedAPFS records the size a cold image is formatted at.
func sizedAPFS(t *testing.T) (*APFSImages, *int64) {
	t.Helper()
	b, _ := newAPFS(t)
	created := new(int64)
	b.Create = func(_ context.Context, path string, size int64) error {
		*created = size
		return os.WriteFile(path, []byte("cold APFS"), 0600)
	}
	return b, created
}

func TestAPFSCreatesAnEmptyImageAtTheAllocatedSize(t *testing.T) {
	b, created := sizedAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	slot.VolumeBytes = 30_000_000_000

	if err := b.Attach(context.Background(), slot, apfsPath(t, b, slot)); err != nil {
		t.Fatal(err)
	}

	if *created != 30_000_000_000 {
		t.Fatalf("formatted %d bytes, want the allocated 30 GB", *created)
	}
}

func TestAPFSUsesTheHostDefaultForAVolumeWithoutASize(t *testing.T) {
	b, created := sizedAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}

	if err := b.Attach(context.Background(), slot, apfsPath(t, b, slot)); err != nil {
		t.Fatal(err)
	}

	if *created != 20_000_000_000 {
		t.Fatalf("formatted %d bytes, want the host default", *created)
	}
}

func TestAPFSAdmitsALargerVolumeOnlyWithRoomForIt(t *testing.T) {
	b, _ := sizedAPFS(t)
	b.FreeBytes = func(string) (uint64, error) { return 25_000_000_000, nil }
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	slot.VolumeBytes = 30_000_000_000

	if err := b.Attach(context.Background(), slot, apfsPath(t, b, slot)); !errors.Is(err, ErrCapacity) {
		t.Fatal("admitted a 30 GB volume into 25 GB of free space:", err)
	}
}

func TestAPFSSealsAGuestReportUpToTheAllocatedSize(t *testing.T) {
	b, remote := newAPFS(t)
	b.Create = func(_ context.Context, path string, _ int64) error {
		return os.WriteFile(path, []byte("cold APFS"), 0600)
	}
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	slot.VolumeBytes = 30_000_000_000
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	usage, _ := json.Marshal(map[string]any{"id": slot.ID, "used_bytes": 25_000_000_000, "capacity_bytes": 29_900_000_000})
	if err := os.WriteFile(filepath.Join(path, ".usage"), usage, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(path, ".detached"), []byte(slot.ID), 0644); err != nil {
		t.Fatal(err)
	}

	if err := b.Seal(slot, path); err != nil {
		t.Fatal("rejected a guest report within the allocated size:", err)
	}
	if remote.uploads != 1 {
		t.Fatal("did not publish")
	}
}

func TestStoreRejectsAVolumeLargerThanAHostAllows(t *testing.T) {
	store, _ := newStore(t)
	for _, size := range []int64{MaxVolumeBytes + 1, -1} {
		id := identity(first)
		id.VolumeBytes = size

		if _, err := store.Acquire(context.Background(), id, "job", "pod"); err == nil {
			t.Fatalf("acquired a volume of %d bytes", size)
		}
	}
}

func TestIdentityReadsTheAllocatedSize(t *testing.T) {
	var id Identity
	if err := json.Unmarshal([]byte(`{"volume_bytes": 30000000000}`), &id); err != nil {
		t.Fatal(err)
	}

	if id.VolumeSize(20_000_000_000) != 30_000_000_000 {
		t.Fatal(id.VolumeSize(20_000_000_000))
	}
	if (Identity{}).VolumeSize(20_000_000_000) != 20_000_000_000 {
		t.Fatal("a volume without a size did not use the default")
	}
}
