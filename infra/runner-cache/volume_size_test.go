package cachevolumes

import (
	"context"
	"encoding/binary"
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

func TestAPFSAdmitsALargeHeadOnlyWithRoomForIt(t *testing.T) {
	b, _ := sizedAPFS(t)
	b.FreeBytes = func(string) (uint64, error) { return 25_000_000_000, nil }
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	slot.VolumeBytes, slot.HeadSizeBytes = 30_000_000_000, 20_000_000_000

	if err := b.Attach(context.Background(), slot, apfsPath(t, b, slot)); !errors.Is(err, ErrCapacity) {
		t.Fatal("admitted a 20 GB head into 25 GB of free space:", err)
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
	for _, size := range []int64{DefaultMaxVolumeBytes + 1, -1} {
		id := identity(first)
		id.VolumeBytes = size

		if _, err := store.Acquire(context.Background(), id, "job", "pod"); err == nil {
			t.Fatalf("acquired a volume of %d bytes", size)
		}
	}
}

func TestStoreAcceptsVolumesUpToTheConfiguredMaximum(t *testing.T) {
	store, _ := newStore(t)
	store.MaxVolumeBytes = 100_000_000_000
	id := identity(first)
	id.VolumeBytes = 100_000_000_000

	if _, err := store.Acquire(context.Background(), id, "job", "pod"); err != nil {
		t.Fatal("rejected a volume at the host maximum:", err)
	}
	larger := identity(second)
	larger.VolumeBytes = 100_000_000_001
	if _, err := store.Acquire(context.Background(), larger, "job", "pod"); err == nil {
		t.Fatal("acquired a volume above the host maximum")
	}
	store.MaxVolumeBytes = 20_000_000_000
	if _, err := store.Snapshot(); err != nil {
		t.Fatal("a lease journaled under a larger maximum became unreadable:", err)
	}
}

func TestStoreRejectsANegativeHeadSize(t *testing.T) {
	store, _ := newStore(t)
	id := identity(first)
	id.HeadSizeBytes = -1

	if _, err := store.Acquire(context.Background(), id, "job", "pod"); err == nil {
		t.Fatal("acquired a volume with a negative head size")
	}
}

func TestRequestedVolumeBytesAcceptsWholeGigabytesFromOneToAHundred(t *testing.T) {
	for requested, want := range map[int64]int64{
		1_000_000_000:   1_000_000_000,
		37_000_000_000:  37_000_000_000,
		100_000_000_000: 100_000_000_000,
		0:               0,
		-1_000_000_000:  0,
		999_999_999:     0,
		2_500_000_000:   0,
		101_000_000_000: 0,
	} {
		if got := RequestedVolumeBytes(requested); got != want {
			t.Errorf("RequestedVolumeBytes(%d) = %d, want %d", requested, got, want)
		}
	}
}

func TestIdentityReadsTheHeadSize(t *testing.T) {
	var id Identity
	if err := json.Unmarshal([]byte(`{"volume_bytes": 30000000000, "head_size_bytes": 4000000000}`), &id); err != nil {
		t.Fatal(err)
	}

	if id.RestoreBytes(20_000_000_000) != 8_000_000_000 {
		t.Fatal("restore does not need twice the head's used bytes:", id.RestoreBytes(20_000_000_000))
	}
	id.HeadSizeBytes = 0
	if id.RestoreBytes(20_000_000_000) != 60_000_000_000 {
		t.Fatal("restore of an unknown head does not need twice the volume:", id.RestoreBytes(20_000_000_000))
	}
}

// grownAPFS records every Grow call against a warm copy of a local master.
func grownAPFS(t *testing.T, failure error) (*APFSImages, Slot, *[]int64) {
	t.Helper()
	b, _ := sizedAPFS(t)
	grown := &[]int64{}
	b.Grow = func(_ context.Context, path string, bytes int64) error {
		if filepath.Ext(path) != ".sparseimage" {
			t.Errorf("grew %s, want the private copy before exposure", path)
		}
		*grown = append(*grown, bytes)
		return failure
	}
	slot := warmSlot(first, "pod")
	master := b.master(slot)
	if err := os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(master, []byte("saved APFS"), 0600); err != nil {
		t.Fatal(err)
	}
	return b, slot, grown
}

func TestAPFSGrowsAWarmCopyToTheChosenCapacity(t *testing.T) {
	b, slot, grown := grownAPFS(t, nil)
	slot.VolumeBytes = 50_000_000_000

	if err := b.Attach(context.Background(), slot, apfsPath(t, b, slot)); err != nil {
		t.Fatal(err)
	}

	if len(*grown) != 1 || (*grown)[0] != 50_000_000_000 {
		t.Fatalf("grew %v, want one growth to 50 GB", *grown)
	}
	if data, _ := os.ReadFile(filepath.Join(apfsPath(t, b, slot), SharedImageName)); string(data) != "saved APFS" {
		t.Fatal("did not attach the warm copy")
	}
}

func TestAPFSKeepsAWarmCopyThatCannotGrow(t *testing.T) {
	b, slot, _ := grownAPFS(t, errors.New("resize failed"))
	slot.VolumeBytes = 50_000_000_000
	path := apfsPath(t, b, slot)

	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal("a failed growth failed the attach:", err)
	}
	if b.Cold(slot) {
		t.Fatal("a copy that could not grow was not warm")
	}
}

func TestAPFSNeverGrowsAnEmptyStartOrAVolumeWithoutACapacity(t *testing.T) {
	b, slot, grown := grownAPFS(t, nil)
	if err := b.Attach(context.Background(), slot, apfsPath(t, b, slot)); err != nil {
		t.Fatal(err)
	}
	cold := Slot{Identity: identity(second), PodUID: "other-pod"}
	cold.VolumeBytes = 50_000_000_000
	if err := b.Attach(context.Background(), cold, apfsPath(t, b, cold)); err != nil {
		t.Fatal(err)
	}

	if len(*grown) != 0 {
		t.Fatalf("grew %v", *grown)
	}
}

func TestAPFSPrefetchNeedsTwiceTheHeadsUsedBytes(t *testing.T) {
	for _, spare := range []bool{false, true} {
		b, _ := newAPFS(t)
		b.Transfer = &cancelTransfer{ready: true}
		b.FreeBytes = func(string) (uint64, error) { return 25_000_000_000, nil }
		prefetch := b.Prefetch
		if spare {
			prefetch = b.PrefetchSpare
		}
		unknown := warmSlot(first, "")
		unknown.VolumeBytes = 50_000_000_000
		if err := prefetch(context.Background(), unknown); !errors.Is(err, ErrCapacity) {
			t.Fatal("prefetched a head of unknown size without twice the volume free:", err)
		}
		known := unknown
		known.HeadSizeBytes = 12_000_000_000
		if err := prefetch(context.Background(), known); err != nil {
			t.Fatal("refused a head whose archive and image fit:", err)
		}
	}
}

func TestAPFSSealsAGuestReportUpToTheHostMaximum(t *testing.T) {
	for capacity, accepted := range map[int64]bool{50_000_000_000: true, 100_000_000_001: false} {
		b, _ := sizedAPFS(t)
		b.MaxVolumeBytes = 100_000_000_000
		slot := Slot{Identity: identity(first), PodUID: "pod"}
		slot.VolumeBytes = 30_000_000_000
		path := apfsPath(t, b, slot)
		if err := b.Attach(context.Background(), slot, path); err != nil {
			t.Fatal(err)
		}
		usage, _ := json.Marshal(map[string]any{"id": slot.ID, "used_bytes": 10_000_000_000, "capacity_bytes": capacity})
		if err := os.WriteFile(filepath.Join(path, ".usage"), usage, 0644); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(path, ".detached"), []byte(slot.ID), 0644); err != nil {
			t.Fatal(err)
		}

		if err := b.Seal(slot, path); (err == nil) != accepted {
			t.Fatalf("capacity %d: seal returned %v", capacity, err)
		}
	}
}

func TestIdentityExpectsTheHeadPlusGrowthWithinTheVolume(t *testing.T) {
	for _, tc := range []struct {
		name         string
		volume, head int64
		expected     int64
	}{
		{"unmeasured", 20_000_000_000, 0, 5_000_000_000},
		{"unmeasured small volume", 3_000_000_000, 0, 3_000_000_000},
		{"unmeasured without a size", 0, 0, 5_000_000_000},
		{"small head grows by the minimum", 20_000_000_000, 700_000_000, 2_700_000_000},
		{"large head grows by half", 30_000_000_000, 15_000_000_000, 22_500_000_000},
		{"head near the capacity", 20_000_000_000, 18_000_000_000, 20_000_000_000},
	} {
		t.Run(tc.name, func(t *testing.T) {
			id := Identity{VolumeBytes: tc.volume, HeadSizeBytes: tc.head}
			if got := id.ExpectedBytes(20_000_000_000); got != tc.expected {
				t.Fatalf("expected %d bytes, want %d", got, tc.expected)
			}
		})
	}
}

func TestLocalAdmissionScalesWithWhatTheJobIsExpectedToWrite(t *testing.T) {
	for _, tc := range []struct {
		name         string
		volume, head int64
		admitted     bool
	}{
		{"unmeasured 100 GB volume needs only the floor", 100_000_000_000, 0, true},
		{"head within the default", 20_000_000_000, 18_000_000_000, true},
		{"large head that fits", 100_000_000_000, 26_000_000_000, true},
		{"large head that does not fit", 100_000_000_000, 30_000_000_000, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			b, _ := newLocal(t)
			b.SizeGB, b.MinFreeBytes = 20, 40_000_000_000
			b.FreeBytes = func(string) (uint64, error) { return 60_000_000_000, nil }
			slot := Slot{Identity: identity(first), PodUID: "p"}
			slot.VolumeBytes, slot.HeadSizeBytes = tc.volume, tc.head

			err := b.Attach(context.Background(), slot, t.TempDir())
			if tc.admitted && err != nil {
				t.Fatalf("rejected with 60 GB free: %v", err)
			}
			if !tc.admitted && !errors.Is(err, ErrCapacity) {
				t.Fatalf("admitted with 60 GB free: %v", err)
			}
		})
	}
}

// ext4Master writes a sparse image whose ext4 superblock describes a
// filesystem filling it.
func ext4Master(t *testing.T, path string, bytes int64) {
	t.Helper()
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	var sb [1024]byte
	binary.LittleEndian.PutUint32(sb[0x04:], uint32(bytes/4096))
	binary.LittleEndian.PutUint32(sb[0x18:], 2)
	binary.LittleEndian.PutUint16(sb[0x38:], 0xEF53)
	if _, err = f.WriteAt(sb[:], 1024); err != nil {
		t.Fatal(err)
	}
	if err = f.Truncate(bytes); err != nil {
		t.Fatal(err)
	}
}

func TestLocalGrowsAWarmCopyAndItsFilesystemBeforeTheJob(t *testing.T) {
	b, remote := newLocal(t)
	remote.source = filepath.Join(t.TempDir(), "master.img")
	ext4Master(t, remote.source, 8<<20)
	var resized []string
	run := b.Run
	b.Run = func(ctx context.Context, name string, args ...string) ([]byte, error) {
		if name == "resize2fs" {
			resized = append(resized, args...)
			return nil, nil
		}
		return run(ctx, name, args...)
	}
	slot := warmSlot(first, "p")
	slot.VolumeBytes = 1_000_000_000
	if err := b.Prefetch(context.Background(), slot); err != nil {
		t.Fatal(err)
	}

	if err := b.Attach(context.Background(), slot, t.TempDir()); err != nil {
		t.Fatal(err)
	}

	if info, err := os.Stat(b.image(slot)); err != nil || info.Size() != 1_000_000_000 {
		t.Fatal("did not extend the copy to the chosen capacity", info, err)
	}
	if len(resized) != 1 || resized[0] != "/dev/loop17" {
		t.Fatalf("resized %v, want the mounted loop device", resized)
	}
	if info, _ := os.Stat(remote.source); info.Size() != 8<<20 {
		t.Fatal("grew the master")
	}
}

func TestLocalNeverShrinksOrResizesAFullSizeCopy(t *testing.T) {
	b, remote := newLocal(t)
	remote.source = filepath.Join(t.TempDir(), "master.img")
	ext4Master(t, remote.source, 16<<20)
	run := b.Run
	b.Run = func(ctx context.Context, name string, args ...string) ([]byte, error) {
		if name == "resize2fs" {
			t.Fatal("resized a filesystem that fills its image")
		}
		return run(ctx, name, args...)
	}
	slot := warmSlot(first, "p")
	slot.VolumeBytes = 8 << 20
	if err := b.Prefetch(context.Background(), slot); err != nil {
		t.Fatal(err)
	}

	if err := b.Attach(context.Background(), slot, t.TempDir()); err != nil {
		t.Fatal(err)
	}

	if info, err := os.Stat(b.image(slot)); err != nil || info.Size() != 16<<20 {
		t.Fatal("changed the size of a larger copy", info, err)
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

func TestRequestedSizeDecodesOnlyAValidSize(t *testing.T) {
	for raw, want := range map[string]RequestedSize{
		`50000000000`:  50_000_000_000,
		`2500000000`:   0,
		`"50gb"`:       0,
		`5e10`:         0,
		`null`:         0,
		`{"size": 50}`: 0,
	} {
		var request struct {
			Key  string        `json:"key"`
			Size RequestedSize `json:"requested_volume_bytes"`
		}
		if err := json.Unmarshal([]byte(`{"key":"deps","requested_volume_bytes":`+raw+`}`), &request); err != nil {
			t.Fatalf("%s failed the request: %v", raw, err)
		}
		if request.Size != want || request.Key != "deps" {
			t.Errorf("%s decoded as %d, want %d", raw, request.Size, want)
		}
	}
}
