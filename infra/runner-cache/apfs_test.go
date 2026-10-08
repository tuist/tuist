package cachevolumes

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func newAPFS(t *testing.T) (*APFSImages, *testTransfer) {
	t.Helper()
	remote := &testTransfer{generation: 1}
	b := &APFSImages{LocalImages: LocalImages{Root: t.TempDir(), SizeGB: 20, MinFreeBytes: 40_000_000_000, Transfer: remote, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }}, Create: func(_ context.Context, path string, size int64) error {
		if size != 20_000_000_000 {
			t.Fatal(size)
		}
		return os.WriteFile(path, []byte("cold APFS"), 0600)
	}, Verify: func(string) error { return nil }}
	b.Run = func(_ context.Context, name string, args ...string) ([]byte, error) {
		if name != "cp" || args[0] != "-c" {
			t.Fatalf("unexpected %s %v", name, args)
		}
		data, err := os.ReadFile(args[1])
		if err != nil {
			return nil, err
		}
		return nil, os.WriteFile(args[2], data, 0600)
	}
	if err := b.Init(); err != nil {
		t.Fatal(err)
	}
	return b, remote
}
func apfsPath(t *testing.T, b *APFSImages, slot Slot) string {
	t.Helper()
	path := filepath.Join(b.Root, "pods", slot.PodUID, slot.Scope)
	if err := os.MkdirAll(path, 0755); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestAPFSAdmissionBudgetsColdCreationAndRestore(t *testing.T) {
	for _, tc := range []struct {
		name         string
		free         uint64
		warm         bool
		wantCapacity bool
	}{
		{name: "cold image fits", free: 20_000_000_000},
		{name: "cold image does not fit", free: 19_999_999_999, wantCapacity: true},
		{name: "restore still needs archive headroom", free: 20_000_000_000, warm: true, wantCapacity: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			b, _ := newAPFS(t)
			b.FreeBytes = func(string) (uint64, error) { return tc.free, nil }
			slot := Slot{Identity: identity(first), PodUID: "pod"}
			if tc.warm {
				slot.BaseGeneration = 1
				slot.ImageDigest = strings.Repeat("b", 40)
				slot.ContentDigest = strings.Repeat("c", 64)
			}
			err := b.Attach(context.Background(), slot, apfsPath(t, b, slot))
			if tc.wantCapacity {
				if !errors.Is(err, ErrCapacity) {
					t.Fatalf("expected capacity rejection, got %v", err)
				}
			} else if err != nil {
				t.Fatal(err)
			}
		})
	}
}
func detached(t *testing.T, path, id string) {
	t.Helper()
	usage, _ := json.Marshal(map[string]any{"id": id, "used_bytes": 3, "capacity_bytes": 20_000_000_000})
	if err := os.WriteFile(filepath.Join(path, ".usage"), usage, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(path, ".detached"), []byte(id), 0644); err != nil {
		t.Fatal(err)
	}
}

func TestAPFSColdWarmIsolationAndRetry(t *testing.T) {
	b, remote := newAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	exposed := filepath.Join(path, "cache.sparseimage")
	if err := os.WriteFile(exposed, []byte("saved data"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(exposed); string(data) != "saved data" {
		t.Fatal("retry reformatted image")
	}
	detached(t, path, slot.ID)
	remote.fail = true
	if err := b.Seal(slot, path); err == nil {
		t.Fatal("accepted failed upload")
	}
	masters, _ := filepath.Glob(filepath.Join(b.Root, "masters", "*", "*.img"))
	if len(masters) != 0 {
		t.Fatal("failed upload became master")
	}
	remote.fail = false
	if err := b.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	masters, _ = filepath.Glob(filepath.Join(b.Root, "masters", "*", "*.img"))
	if len(masters) != 1 {
		t.Fatal(masters)
	}
	content := strings.TrimSuffix(strings.SplitN(filepath.Base(masters[0]), "-", 2)[1], ".img")
	next := slot
	next.ID = second
	next.PodUID = "next"
	next.BaseGeneration = 1
	next.ImageDigest = strings.Repeat("b", 40)
	next.ContentDigest = content
	secondPath := apfsPath(t, b, next)
	if err := b.Attach(context.Background(), next, secondPath); err != nil {
		t.Fatal(err)
	}
	if remote.downloads != 0 {
		t.Fatal("local warm master downloaded")
	}
	if data, _ := os.ReadFile(filepath.Join(secondPath, "cache.sparseimage")); string(data) != "saved data" {
		t.Fatal(string(data))
	}
	_ = os.WriteFile(filepath.Join(secondPath, "cache.sparseimage"), []byte("private changes"), 0600)
	if data, _ := os.ReadFile(masters[0]); string(data) != "saved data" {
		t.Fatal("private write mutated master")
	}
	if err := b.Keep(slot, path); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(exposed); !os.IsNotExist(err) {
		t.Fatal("private image retained")
	}
}

func TestAPFSNoPublicationWithoutCleanDetach(t *testing.T) {
	for _, reason := range []string{"missing", "wrong lease", "failed verification", "interrupted verification"} {
		t.Run(reason, func(t *testing.T) {
			b, remote := newAPFS(t)
			slot := Slot{Identity: identity(first), PodUID: "p"}
			path := apfsPath(t, b, slot)
			if err := b.Attach(context.Background(), slot, path); err != nil {
				t.Fatal(err)
			}
			switch reason {
			case "wrong lease":
				detached(t, path, "other")
			case "failed verification":
				detached(t, path, slot.ID)
				b.Verify = func(string) error { return errors.New("disk failure") }
			case "interrupted verification":
				detached(t, path, slot.ID)
				_ = os.WriteFile(b.image(slot)+".checking", nil, 0600)
			}
			if err := b.Seal(slot, path); !errors.Is(err, ErrPoisoned) {
				t.Fatal(err)
			}
			if remote.uploads != 0 {
				t.Fatal("unsafe image uploaded")
			}
		})
	}
}
func TestAPFSClearConflictNeverInstallsMaster(t *testing.T) {
	b, remote := newAPFS(t)
	remote.conflict = true
	slot := Slot{Identity: identity(first), PodUID: "p"}
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	detached(t, path, slot.ID)
	if err := b.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	files, _ := filepath.Glob(filepath.Join(b.Root, "masters", "*", "*.img"))
	if len(files) != 0 {
		t.Fatal(files)
	}
}
func TestAPFSMarkerDoesNotEscapeShare(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	_ = os.WriteFile(filepath.Join(outside, ".detached"), []byte(first), 0600)
	_ = os.Symlink(outside, filepath.Join(root, "scope"))
	if APFSMarker(filepath.Join(root, "scope"), ".detached", first) {
		t.Fatal("followed scope symlink outside VM share")
	}
}

func TestAPFSRefusesReplacedGuestImage(t *testing.T) {
	b, _ := newAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	exposed := filepath.Join(path, "cache.sparseimage")
	if err := os.Remove(exposed); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(exposed, []byte("different inode"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := b.Attach(context.Background(), slot, path); err == nil {
		t.Fatal("accepted replaced guest image")
	}
}

func TestAPFSCancelledCreationNeverExposesImage(t *testing.T) {
	b, _ := newAPFS(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	b.Create = func(_ context.Context, path string, _ int64) error {
		if err := os.WriteFile(path, []byte("partial"), 0600); err != nil {
			return err
		}
		cancel()
		return nil
	}
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	path := apfsPath(t, b, slot)
	if err := b.Attach(ctx, slot, path); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	for _, file := range []string{b.image(slot), b.image(slot) + ".sparseimage", filepath.Join(path, "cache.sparseimage")} {
		if _, err := os.Stat(file); !os.IsNotExist(err) {
			t.Fatalf("cancelled creation left %s: %v", file, err)
		}
	}
}

func TestAPFSAdmissionDoesNotHoldGuardDuringCreation(t *testing.T) {
	b, _ := newAPFS(t)
	reserved := false
	b.Reserve = func(context.Context, Slot) (func(bool), error) {
		reserved = true
		return func(retain bool) { reserved = retain }, nil
	}
	original := b.Create
	b.Create = func(ctx context.Context, path string, bytes int64) error {
		if !reserved {
			t.Fatal("creation was not reserved")
		}
		return original(ctx, path, bytes)
	}
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	if err := b.Attach(context.Background(), slot, apfsPath(t, b, slot)); err != nil {
		t.Fatal(err)
	}
	if !reserved {
		t.Fatal("live guest lost its reservation")
	}
}

func TestAPFSTimedOutRestoreCanPrefetchAndWarmNextJob(t *testing.T) {
	b, _ := newAPFS(t)
	remote := &cancelTransfer{cancelled: make(chan struct{})}
	b.Transfer = remote
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	slot.BaseGeneration = 1
	slot.ImageDigest = strings.Repeat("b", 40)
	slot.ContentDigest = strings.Repeat("c", 64)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if err := b.Attach(ctx, slot, apfsPath(t, b, slot)); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal(err)
	}
	remote.ready = true
	if err := b.Prefetch(context.Background(), slot); err != nil {
		t.Fatal(err)
	}
	slot.ID = second
	slot.PodUID = "next"
	if err := b.Attach(context.Background(), slot, apfsPath(t, b, slot)); err != nil {
		t.Fatal(err)
	}
	if remote.downloads != 2 {
		t.Fatalf("next job re-downloaded master: %d", remote.downloads)
	}
}

type cancelTransfer struct {
	cancelled chan struct{}
	ready     bool
	downloads int
	lastID    string
}

func (r *cancelTransfer) Download(ctx context.Context, slot Slot, path string) error {
	r.downloads++
	r.lastID = slot.ID
	if r.ready {
		return os.WriteFile(path, []byte("master"), 0600)
	}
	<-ctx.Done()
	close(r.cancelled)
	return ctx.Err()
}
func (*cancelTransfer) Publish(Slot, string, string, string) (int64, error) {
	panic("unexpected publication")
}

func TestAPFSRejectsUnboundAndInvalidUsage(t *testing.T) {
	for _, contents := range []string{
		`{"id":"other","used_bytes":3,"capacity_bytes":20}`,
		`{"id":"lease","used_bytes":21,"capacity_bytes":20}`,
		`{"id":"lease","used_bytes":-1,"capacity_bytes":20}`,
		`{"id":"lease","used_bytes":1,"capacity_bytes":21}`,
	} {
		path := filepath.Join(t.TempDir(), "volume")
		_ = os.Mkdir(path, 0755)
		_ = os.WriteFile(filepath.Join(path, ".usage"), []byte(contents), 0600)
		if _, _, err := APFSUsage(path, "lease", 20); err == nil {
			t.Fatal("accepted invalid usage", contents)
		}
	}
}

func TestAPFSPrefetchReservesOnceWithoutChangingTransferIdentity(t *testing.T) {
	b, _ := newAPFS(t)
	remote := &cancelTransfer{ready: true}
	b.Transfer = remote
	reserved := false
	b.FreeBytes = func(string) (uint64, error) {
		if reserved {
			return 30_000_000_000, nil
		}
		return 50_000_000_000, nil
	}
	b.Reserve = func(_ context.Context, slot Slot) (func(bool), error) {
		if slot.ID != "prefetch" {
			t.Fatal("background work reused a guest reservation", slot.ID)
		}
		reserved = true
		return func(retain bool) {
			if retain {
				t.Error("background reservation retained")
			}
			reserved = false
		}, nil
	}
	slot := Slot{Identity: identity(first)}
	slot.BaseGeneration = 1
	slot.ImageDigest = strings.Repeat("b", 40)
	slot.ContentDigest = strings.Repeat("c", 64)
	if err := b.Prefetch(context.Background(), slot); err != nil {
		t.Fatal(err)
	}
	if reserved || remote.downloads != 1 || remote.lastID != slot.ID {
		t.Fatal("prefetch reservation leaked", reserved, remote.downloads)
	}
}
