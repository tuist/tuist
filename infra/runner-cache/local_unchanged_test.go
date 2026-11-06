package cachevolumes

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

// attachedVolume attaches a branch whose mounted filesystem already holds the
// seeded files, as a clone of a saved version does.
func attachedVolume(t *testing.T, b *LocalImages, seed ...string) (Slot, string) {
	t.Helper()
	slot := Slot{Identity: identity(first), PodUID: "p"}
	path := t.TempDir()
	for _, name := range seed {
		writeFile(t, filepath.Join(path, name), "saved")
	}
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	afterMarker(t, path)
	return slot, path
}

// afterMarker waits until a write would be newer than the volume's marker, so
// a test's changes are distinguishable from the attach at any clock resolution.
func afterMarker(t *testing.T, path string) {
	t.Helper()
	var marker unix.Stat_t
	if err := unix.Stat(filepath.Join(path, ".tuist-volume"), &marker); err != nil {
		t.Fatal(err)
	}
	probe := filepath.Join(t.TempDir(), "probe")
	for {
		writeFile(t, probe, "probe")
		var stat unix.Stat_t
		if err := unix.Stat(probe, &stat); err != nil {
			t.Fatal(err)
		}
		if stat.Ctim.Nano() > marker.Ctim.Nano() {
			return
		}
		time.Sleep(time.Millisecond)
	}
}

func writeFile(t *testing.T, path, contents string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(contents), 0644); err != nil {
		t.Fatal(err)
	}
}

func TestLocalWithholdsAVolumeTheJobDidNotChange(t *testing.T) {
	b, remote := newLocal(t)
	slot, path := attachedVolume(t, b, "data/dependency.jar")

	err := b.Seal(slot, path)

	if !errors.Is(err, ErrUnchanged) {
		t.Fatal("saved a volume the job did not change:", err)
	}
	if remote.uploads != 0 {
		t.Fatal("uploaded an unchanged volume")
	}
}

func TestLocalPublishesAVolumeTheJobChanged(t *testing.T) {
	for name, change := range map[string]func(t *testing.T, path string){
		"added file":     func(t *testing.T, path string) { writeFile(t, filepath.Join(path, "data", "new.jar"), "new") },
		"rewritten file": func(t *testing.T, path string) { writeFile(t, filepath.Join(path, "data", "dependency.jar"), "SAVED") },
		"removed file":   func(t *testing.T, path string) { _ = os.Remove(filepath.Join(path, "data", "dependency.jar")) },
		"removed directory": func(t *testing.T, path string) {
			_ = os.RemoveAll(filepath.Join(path, "data"))
		},
		"restored with old times": func(t *testing.T, path string) {
			restored := filepath.Join(path, "data", "restored.jar")
			writeFile(t, restored, "restored")
			earlier := time.Now().Add(-24 * time.Hour)
			_ = os.Chtimes(restored, earlier, earlier)
		},
	} {
		t.Run(name, func(t *testing.T) {
			b, remote := newLocal(t)
			slot, path := attachedVolume(t, b, "data/dependency.jar")
			change(t, path)

			if err := b.Seal(slot, path); err != nil {
				t.Fatal(err)
			}
			if remote.uploads != 1 {
				t.Fatal("did not save the changed volume")
			}
		})
	}
}

func TestLocalPublishesAVolumeAttachedBeforeChangesWereTracked(t *testing.T) {
	b, remote := newLocal(t)
	slot, path := attachedVolume(t, b, "data/dependency.jar")
	if err := os.Remove(b.image(slot) + ".entries"); err != nil {
		t.Fatal(err)
	}

	if err := b.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	if remote.uploads != 1 {
		t.Fatal("withheld a volume without a recorded baseline")
	}
}

func TestLocalWithholdsAVolumeThatRanOutOfSpace(t *testing.T) {
	b, remote := newLocal(t)
	b.MeasureFS = func(string) (int64, int64, error) { return 99, 100, nil }
	slot, path := attachedVolume(t, b)
	writeFile(t, filepath.Join(path, "data", "new.jar"), "new")

	if err := b.Seal(slot, path); !errors.Is(err, ErrFull) {
		t.Fatal("saved a volume that ran out of space:", err)
	}
	if remote.uploads != 0 {
		t.Fatal("uploaded a volume that ran out of space")
	}
}

func TestLocalDeleteRemovesTheBaseline(t *testing.T) {
	b, _ := newLocal(t)
	slot, path := attachedVolume(t, b)
	b.Unmount = func(string, string) error { return os.Remove(filepath.Join(path, ".tuist-volume")) }

	if err := b.Delete(slot, path); err != nil {
		t.Fatal(err)
	}
	if exists(b.image(slot) + ".entries") {
		t.Fatal("left the baseline behind")
	}
}

func TestLocalCountsWritesBeforeAnotherAttachOfTheSameBranch(t *testing.T) {
	b, remote := newLocal(t)
	slot, path := attachedVolume(t, b, "data/dependency.jar")
	writeFile(t, filepath.Join(path, "data", "new.jar"), "written by the first step")
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}

	if err := b.Seal(slot, path); err != nil {
		t.Fatal("a second attach hid the first step's writes:", err)
	}
	if remote.uploads != 1 {
		t.Fatal("did not save the changed volume")
	}
}

// jobWrote changes the attached volume the way a job's tools do.
func jobWrote(t *testing.T, path string) {
	t.Helper()
	afterMarker(t, path)
	writeFile(t, filepath.Join(path, "data", "output"), "written by the job")
}

// warmVolume attaches a clone of a saved version whose master holds the seeded
// files, and answers debugfs reads of that master from them.
func warmVolume(t *testing.T, seed map[string]string) (*LocalImages, *testTransfer, Slot, string) {
	t.Helper()
	b, remote := newLocal(t)
	saved := installMaster(t, b, second, strings.Repeat("a", 64), 1, time.Now())
	slot := Slot{Identity: saved.Identity, PodUID: "p"}
	slot.ID = first
	path := t.TempDir()
	for name, contents := range seed {
		writeFile(t, filepath.Join(path, name), contents)
	}
	run := b.Run
	b.Run = func(ctx context.Context, name string, args ...string) ([]byte, error) {
		if name != "debugfs" {
			return run(ctx, name, args...)
		}
		if len(args) != 4 || args[0] != "-c" || args[1] != "-f" || args[3] != b.master(slot) {
			t.Fatalf("unexpected debugfs %v", args)
		}
		script, err := os.ReadFile(args[2])
		if err != nil {
			return nil, err
		}
		for _, line := range strings.Split(strings.TrimSpace(string(script)), "\n") {
			quoted, ok := strings.CutPrefix(line, `dump -p "/`)
			if !ok {
				t.Fatalf("unexpected debugfs command %q", line)
			}
			source, target, _ := strings.Cut(strings.TrimSuffix(quoted, `"`), `" "`)
			if contents, ok := seed[source]; ok {
				writeFile(t, target, contents)
				if err := os.Chmod(target, 0644); err != nil {
					t.Fatal(err)
				}
			}
		}
		return nil, nil
	}
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	afterMarker(t, path)
	return b, remote, slot, path
}

func TestLocalWithholdsAVolumeWhoseFilesTheJobOnlyTouched(t *testing.T) {
	b, remote, slot, path := warmVolume(t, map[string]string{"cache.lock": "lock state", "entries/a1": "output", "gc.properties": ""})
	now := time.Now()
	for _, name := range []string{"cache.lock", "entries/a1", "gc.properties"} {
		if err := os.Chtimes(filepath.Join(path, name), now, now); err != nil {
			t.Fatal(err)
		}
	}
	writeFile(t, filepath.Join(path, "cache.lock"), "lock state")

	if err := b.Seal(slot, path); !errors.Is(err, ErrUnchanged) {
		t.Fatal("saved a volume whose files only had their times updated:", err)
	}
	if remote.uploads != 0 {
		t.Fatal("uploaded a volume the job only read")
	}
}

func TestLocalPublishesAVolumeWhoseTouchedFilesChanged(t *testing.T) {
	for name, change := range map[string]func(t *testing.T, path string){
		"same-size rewrite": func(t *testing.T, path string) { writeFile(t, filepath.Join(path, "entries", "a1"), "OUTPUT") },
		"added file":        func(t *testing.T, path string) { writeFile(t, filepath.Join(path, "entries", "b2"), "output") },
		"deleted file":      func(t *testing.T, path string) { _ = os.Remove(filepath.Join(path, "entries", "a1")) },
		"changed mode":      func(t *testing.T, path string) { _ = os.Chmod(filepath.Join(path, "entries", "a1"), 0600) },
		"grown file": func(t *testing.T, path string) {
			writeFile(t, filepath.Join(path, "entries", "a1"), "output, then more")
		},
	} {
		t.Run(name, func(t *testing.T) {
			b, remote, slot, path := warmVolume(t, map[string]string{"cache.lock": "lock state", "entries/a1": "output"})
			writeFile(t, filepath.Join(path, "cache.lock"), "lock state")
			change(t, path)

			if err := b.Seal(slot, path); err != nil {
				t.Fatal(err)
			}
			if remote.uploads != 1 {
				t.Fatal("did not save the changed volume")
			}
		})
	}
}

func TestLocalPublishesATouchedVolumeWhoseMasterIsGone(t *testing.T) {
	b, remote, slot, path := warmVolume(t, map[string]string{"cache.lock": "lock state"})
	writeFile(t, filepath.Join(path, "cache.lock"), "lock state")
	evictMaster(t, b, slot)

	if err := b.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	if remote.uploads != 1 {
		t.Fatal("withheld a touched volume it could not compare with its master")
	}
}

func TestLocalPublishesAVolumeWithMoreTouchedBytesThanItCompares(t *testing.T) {
	large := strings.Repeat("x", maxComparedBytes+1)
	b, remote, slot, path := warmVolume(t, map[string]string{"entries/large": large})
	writeFile(t, filepath.Join(path, "entries", "large"), large)

	if err := b.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	if remote.uploads != 1 {
		t.Fatal("withheld a volume whose changes were over the comparison budget")
	}
}
