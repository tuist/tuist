package cachevolumes

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type testTransfer struct {
	downloads, uploads int
	source             string
	conflict, fail     bool
	generation         int64
}

func (t *testTransfer) Download(_ Slot, path string) error {
	t.downloads++
	data, err := os.ReadFile(t.source)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}
func (t *testTransfer) Publish(_ Slot, path, digest, content string) (int64, error) {
	t.uploads++
	if t.fail {
		return 0, errors.New("upload failed")
	}
	if t.conflict {
		return 0, ErrConflict
	}
	if _, err := os.Stat(path); err != nil {
		return 0, err
	}
	return t.generation, nil
}
func newLocal(t *testing.T) (*LocalImages, *testTransfer) {
	t.Helper()
	root := t.TempDir()
	remote := &testTransfer{generation: 1}
	b := &LocalImages{Root: root, SizeGB: 1, MinFreeBytes: 10, Transfer: remote, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }, Mount: func(string, string) error { return nil }, Unmount: func(string, string) error { return nil }, MeasureFS: func(string) (int64, int64, error) { return 1, 100, nil }}
	b.Run = func(_ context.Context, name string, args ...string) ([]byte, error) {
		switch name {
		case "cp":
			if args[0] != "--reflink=always" {
				t.Fatal("byte-copy fallback enabled")
			}
			data, err := os.ReadFile(args[len(args)-2])
			if err != nil {
				return nil, err
			}
			return nil, os.WriteFile(args[len(args)-1], data, 0600)
		case "mkfs.ext4":
			return nil, os.WriteFile(args[len(args)-1], []byte("empty filesystem"), 0600)
		case "losetup":
			if args[0] == "--json" {
				return json.Marshal(map[string]any{"loopdevices": []any{}})
			}
			return []byte("/dev/loop17\n"), nil
		}
		t.Fatalf("unexpected command %s %v", name, args)
		return nil, nil
	}
	if err := b.Probe(); err != nil {
		t.Fatal(err)
	}
	return b, remote
}
func TestLocalMastersWarmReuseAndPrivateBranches(t *testing.T) {
	b, remote := newLocal(t)
	slot := Slot{Identity: identity(first), PodUID: "p"}
	path := t.TempDir()
	if err := b.Attach(slot, path); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(b.image(slot), []byte("saved cache"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := b.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	masters, _ := filepath.Glob(filepath.Join(b.Root, "masters", slot.Scope, "*.img"))
	if len(masters) != 1 {
		t.Fatal(masters)
	}
	name := filepath.Base(masters[0])
	content := strings.TrimSuffix(strings.SplitN(name, "-", 2)[1], ".img")
	for _, id := range []string{second, third} {
		next := slot
		next.ID = id
		next.BaseGeneration = 1
		next.ContentDigest = content
		if err := b.Attach(next, t.TempDir()); err != nil {
			t.Fatal(err)
		}
	}
	if remote.downloads != 0 {
		t.Fatal("warm master downloaded again")
	}
	two := slot
	two.ID = second
	os.WriteFile(b.image(two), []byte("private change"), 0600)
	three := slot
	three.ID = third
	data, _ := os.ReadFile(b.image(three))
	if string(data) != "saved cache" {
		t.Fatal("private branches shared writes")
	}
}
func TestFailedAndRejectedUploadsDoNotInstallMaster(t *testing.T) {
	for _, conflict := range []bool{false, true} {
		t.Run(map[bool]string{true: "conflict", false: "failure"}[conflict], func(t *testing.T) {
			b, r := newLocal(t)
			r.conflict = conflict
			r.fail = !conflict
			slot := Slot{Identity: identity(first), PodUID: "p"}
			path := t.TempDir()
			if err := b.Attach(slot, path); err != nil {
				t.Fatal(err)
			}
			err := b.Seal(slot, path)
			if !conflict && err == nil {
				t.Fatal("ignored failed upload")
			}
			files, _ := filepath.Glob(filepath.Join(b.Root, "masters", "*", "*.img"))
			if len(files) != 0 {
				t.Fatal("installed unaccepted image")
			}
		})
	}
}
func TestColdHostDownloadsOnceAndRestartDoesNotReformat(t *testing.T) {
	b, r := newLocal(t)
	r.source = filepath.Join(t.TempDir(), "master")
	os.WriteFile(r.source, []byte("remote bytes"), 0600)
	slot := Slot{Identity: identity(first), PodUID: "p"}
	slot.BaseGeneration = 4
	slot.ContentDigest = strings.Repeat("a", 64)
	path := t.TempDir()
	if err := b.Attach(slot, path); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(b.image(slot), []byte("job writes"), 0600)
	if err := b.Attach(slot, path); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(b.image(slot))
	if string(data) != "job writes" || r.downloads != 1 {
		t.Fatal("retry lost writes", r.downloads)
	}
}
func TestRejectsFilesystemWithoutReflinksAndLowSpace(t *testing.T) {
	b, _ := newLocal(t)
	b.Run = func(context.Context, string, ...string) ([]byte, error) { return nil, errors.New("unsupported") }
	if err := b.Probe(); err == nil {
		t.Fatal("accepted non-reflink storage")
	}
	b, _ = newLocal(t)
	b.FreeBytes = func(string) (uint64, error) { return 0, nil }
	if err := b.Attach(Slot{Identity: identity(first)}, t.TempDir()); err == nil {
		t.Fatal("ignored reserve")
	}
}

func TestRefusesLegacyJournalInsteadOfTreatingRBDLeaseAsLocal(t *testing.T) {
	b, _ := newLocal(t)
	os.Remove(filepath.Join(b.Root, ".backend"))
	os.Mkdir(filepath.Join(b.Root, "state"), 0700)
	os.WriteFile(filepath.Join(b.Root, "state", first+".json"), []byte("{}"), 0600)
	if err := b.Probe(); err == nil {
		t.Fatal("accepted another backend's journal")
	}
}

type invalidatedTransfer struct{ *testTransfer }

func (invalidatedTransfer) IsCurrent(Slot) (bool, error) { return false, nil }
func TestInvalidatedLocalMasterIsEvictedWithoutTouchingActiveClone(t *testing.T) {
	b, r := newLocal(t)
	slot := Slot{Identity: identity(first), PodUID: "p"}
	if err := b.Attach(slot, t.TempDir()); err != nil {
		t.Fatal(err)
	}
	if err := b.Seal(slot, t.TempDir()); err != nil {
		t.Fatal(err)
	}
	b.Transfer = invalidatedTransfer{r}
	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	files, _ := filepath.Glob(filepath.Join(b.Root, "masters", "*", "*.img"))
	if len(files) != 0 {
		t.Fatal("invalidated master retained")
	}
	if _, err := os.Stat(b.image(slot)); err != nil {
		t.Fatal("deleted private branch before acknowledgement", err)
	}
}
