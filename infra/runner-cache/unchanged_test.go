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

// finishedClone attaches a warm branch cloned from a local master and detaches
// it with the given guest usage report.
func finishedClone(t *testing.T, usage map[string]any) (*APFSImages, *testTransfer, Slot, string) {
	t.Helper()
	b, remote := newAPFS(t)
	saved := installMaster(t, &b.LocalImages, second, strings.Repeat("a", 64), 1, time.Now())
	slot := warmSlot(first, "pod")
	slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = saved.BaseGeneration, saved.ImageDigest, saved.ContentDigest
	path := apfsPath(t, b, slot)
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	if b.Cold(slot) {
		t.Fatal("the clone started empty")
	}
	usage["id"] = slot.ID
	data, _ := json.Marshal(usage)
	if err := os.WriteFile(filepath.Join(path, ".usage"), data, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(path, ".detached"), []byte(slot.ID), 0644); err != nil {
		t.Fatal(err)
	}
	return b, remote, slot, path
}

func TestAPFSWithholdsAnUnchangedVolume(t *testing.T) {
	b, remote, slot, path := finishedClone(t, map[string]any{"used_bytes": 3, "capacity_bytes": 20_000_000_000, "changed": false})

	err := b.Seal(slot, path)

	if !errors.Is(err, ErrWithheld) || Result(err) != "unchanged" {
		t.Fatal("saved a volume the job did not change:", err)
	}
	if remote.uploads != 0 {
		t.Fatal("uploaded an unchanged volume")
	}
}

func TestAPFSWithholdsAVolumeThatRanOutOfSpace(t *testing.T) {
	b, remote, slot, path := finishedClone(t, map[string]any{"used_bytes": 19_800_000_000, "capacity_bytes": 20_000_000_000, "changed": true})

	err := b.Seal(slot, path)

	if !errors.Is(err, ErrWithheld) || Result(err) != "full" {
		t.Fatal("saved a volume that ran out of space:", err)
	}
	if remote.uploads != 0 {
		t.Fatal("uploaded a volume that ran out of space")
	}
}

func TestAPFSPublishesAChangedVolume(t *testing.T) {
	for name, usage := range map[string]map[string]any{
		"changed":               {"used_bytes": 3, "capacity_bytes": 20_000_000_000, "changed": true},
		"reported by old guest": {"used_bytes": 3, "capacity_bytes": 20_000_000_000},
		"just below full":       {"used_bytes": 19_799_999_999, "capacity_bytes": 20_000_000_000, "changed": true},
	} {
		t.Run(name, func(t *testing.T) {
			b, remote, slot, path := finishedClone(t, usage)

			if err := b.Seal(slot, path); err != nil {
				t.Fatal(err)
			}
			if remote.uploads != 1 {
				t.Fatal("did not upload the changed volume")
			}
		})
	}
}

func TestAPFSMeasuresAFinishedVolumeBeforeSealing(t *testing.T) {
	b, _, slot, path := finishedClone(t, map[string]any{"used_bytes": 19_900_000_000, "capacity_bytes": 20_000_000_000, "changed": true})

	used, capacity, err := b.Measure(slot, path)

	if err != nil || used != 19_900_000_000 || capacity != 20_000_000_000 {
		t.Fatalf("measured %d/%d (%v); the server needs the size of a volume it will not save", used, capacity, err)
	}
}
