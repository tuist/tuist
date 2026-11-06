package cachevolumes

import (
	"context"
	"errors"
	"os"
	"path/filepath"
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
