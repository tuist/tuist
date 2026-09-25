package cachevolumes

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newAPFS(t *testing.T) (*APFSImages, *testTransfer) {
	t.Helper()
	remote := &testTransfer{generation: 1}
	b := &APFSImages{LocalImages: LocalImages{Root: t.TempDir(), SizeGB: 20, MinFreeBytes: 40_000_000_000, Transfer: remote, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }}, Create: func(path string, size int64) error {
		if size != 20_000_000_000 {
			t.Fatal(size)
		}
		return os.WriteFile(path, []byte("cold APFS"), 0600)
	}, Verify: func(string) (int64, int64, error) { return 3, 20_000_000_000, nil }}
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
func detached(t *testing.T, path, id string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(path, ".detached"), []byte(id), 0644); err != nil {
		t.Fatal(err)
	}
}

func TestAPFSColdWarmIsolationAndRetry(t *testing.T) {
	b, remote := newAPFS(t)
	slot := Slot{Identity: identity(first), PodUID: "pod"}
	path := apfsPath(t, b, slot)
	if err := b.Attach(slot, path); err != nil {
		t.Fatal(err)
	}
	exposed := filepath.Join(path, "cache.sparseimage")
	if err := os.WriteFile(exposed, []byte("saved data"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := b.Attach(slot, path); err != nil {
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
	next.ContentDigest = content
	secondPath := apfsPath(t, b, next)
	if err := b.Attach(next, secondPath); err != nil {
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
			if err := b.Attach(slot, path); err != nil {
				t.Fatal(err)
			}
			switch reason {
			case "wrong lease":
				detached(t, path, "other")
			case "failed verification":
				detached(t, path, slot.ID)
				b.Verify = func(string) (int64, int64, error) { return 0, 0, errors.New("disk failure") }
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
	if err := b.Attach(slot, path); err != nil {
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
	if err := b.Attach(slot, path); err != nil {
		t.Fatal(err)
	}
	exposed := filepath.Join(path, "cache.sparseimage")
	if err := os.Remove(exposed); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(exposed, []byte("different inode"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := b.Attach(slot, path); err == nil {
		t.Fatal("accepted replaced guest image")
	}
}
