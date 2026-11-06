package cachevolumes

import (
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"

	"golang.org/x/sys/unix"
)

// volumeBaseline is what a branch held when its first attach finished: the
// marker's ctime and the volume's top-level entries. A later attach of the
// same branch keeps it, so writes before that attach still count.
type volumeBaseline struct {
	Attached int64    `json:"attached_ctime_ns"`
	Entries  []string `json:"entries"`
}

func topLevelEntries(path string) ([]string, error) {
	entries, err := os.ReadDir(path)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, entry := range entries {
		if entry.Name() != ".tuist-volume" {
			names = append(names, entry.Name())
		}
	}
	return names, nil
}

// recordBaseline runs after the marker is written. Without a baseline the
// branch counts as changed, so a failure here never withholds it.
func (b *LocalImages) recordBaseline(slot Slot, path string) {
	baseline := b.image(slot) + ".entries"
	if _, err := os.Stat(baseline); !os.IsNotExist(err) {
		return
	}
	var marker unix.Stat_t
	if unix.Stat(filepath.Join(path, ".tuist-volume"), &marker) != nil {
		return
	}
	entries, err := topLevelEntries(path)
	if err != nil {
		return
	}
	data, _ := json.Marshal(volumeBaseline{Attached: marker.Ctim.Nano(), Entries: entries})
	_ = os.WriteFile(baseline, data, 0600)
}

var errChangedSinceAttach = errors.New("changed since attach")

// changedSinceAttach reports whether anything in the mounted volume changed
// after its first attach. Writing, renaming, deleting or changing the metadata
// of an entry updates its ctime or its parent's, which no tool can set back.
// The walk stops at the first newer entry.
func (b *LocalImages) changedSinceAttach(slot Slot, path string) bool {
	data, err := os.ReadFile(b.image(slot) + ".entries")
	var baseline volumeBaseline
	if err != nil || json.Unmarshal(data, &baseline) != nil || baseline.Attached <= 0 {
		return true
	}
	if entries, err := topLevelEntries(path); err != nil || !slices.Equal(entries, baseline.Entries) {
		return true
	}
	return filepath.WalkDir(path, func(entry string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry == path || entry == filepath.Join(path, ".tuist-volume") {
			return nil
		}
		var stat unix.Stat_t
		if err := unix.Lstat(entry, &stat); err != nil {
			return err
		}
		if stat.Ctim.Nano() > baseline.Attached {
			return errChangedSinceAttach
		}
		return nil
	}) != nil
}

// withheld reports why a finished branch must not replace the saved version,
// measured while it is still mounted.
func (b *LocalImages) withheld(slot Slot, path string) error {
	if b.MeasureFS != nil {
		if used, capacity, err := b.MeasureFS(path); err == nil && outOfSpace(used, capacity) {
			return ErrFull
		}
	}
	if !b.changedSinceAttach(slot, path) {
		return ErrUnchanged
	}
	return nil
}
