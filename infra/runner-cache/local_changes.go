package cachevolumes

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

// A seal reads at most this much of a branch and its master to tell files
// rewritten with the same bytes from changed ones. A branch over either limit
// counts as changed.
const (
	maxComparedFiles = 1000
	maxComparedBytes = 64 << 20
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
// The walk stops at the first newer entry that is not a regular file. Newer
// regular files are unchanged when they still match the master the branch was
// cloned from, as when a tool touches a cache entry or rewrites a lock file
// with the same bytes.
func (b *LocalImages) changedSinceAttach(slot Slot, path string) bool {
	data, err := os.ReadFile(b.image(slot) + ".entries")
	var baseline volumeBaseline
	if err != nil || json.Unmarshal(data, &baseline) != nil || baseline.Attached <= 0 {
		return true
	}
	if entries, err := topLevelEntries(path); err != nil || !slices.Equal(entries, baseline.Entries) {
		return true
	}
	var touched []string
	var touchedBytes int64
	err = filepath.WalkDir(path, func(entry string, d fs.DirEntry, err error) error {
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
		if stat.Ctim.Nano() <= baseline.Attached {
			return nil
		}
		if stat.Mode&unix.S_IFMT != unix.S_IFREG {
			return errChangedSinceAttach
		}
		rel, err := filepath.Rel(path, entry)
		if err != nil {
			return err
		}
		touched = append(touched, rel)
		touchedBytes += stat.Size
		if len(touched) > maxComparedFiles || touchedBytes > maxComparedBytes {
			return errChangedSinceAttach
		}
		return nil
	})
	if err != nil {
		return true
	}
	return len(touched) > 0 && !b.matchesMaster(slot, path, touched)
}

// matchesMaster reports whether each file still has the size, mode, owner and
// bytes it has in the master the branch was cloned from. debugfs reads the
// master without mounting it. Anything it cannot compare is a difference.
func (b *LocalImages) matchesMaster(slot Slot, path string, files []string) bool {
	if slot.BaseGeneration <= 0 || b.Cold(slot) || b.MountedGeneration(slot) != 0 {
		return false
	}
	master := b.master(slot)
	if _, err := os.Stat(master); err != nil {
		return false
	}
	dir := b.image(slot) + ".compare"
	_ = os.RemoveAll(dir)
	defer os.RemoveAll(dir)
	if os.Mkdir(dir, 0700) != nil || !debugfsQuotable(dir) {
		return false
	}
	var commands strings.Builder
	for i, file := range files {
		if !debugfsQuotable(file) {
			return false
		}
		fmt.Fprintf(&commands, "dump -p \"/%s\" \"%s\"\n", file, filepath.Join(dir, strconv.Itoa(i)))
	}
	script := filepath.Join(dir, "commands")
	if os.WriteFile(script, []byte(commands.String()), 0600) != nil {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	if _, err := b.commandContext(ctx, "debugfs", "-c", "-f", script, master); err != nil {
		return false
	}
	volume, err := os.OpenRoot(path)
	if err != nil {
		return false
	}
	defer volume.Close()
	for i, file := range files {
		if !matchesDump(volume, file, filepath.Join(dir, strconv.Itoa(i))) {
			return false
		}
	}
	return true
}

// debugfsQuotable reports whether a path survives debugfs's double quoting.
func debugfsQuotable(path string) bool {
	return !strings.ContainsFunc(path, func(r rune) bool { return r == '"' || r == '\\' || r < 0x20 || r == 0x7f })
}

// matchesDump compares a branch file with the copy debugfs dumped from the master.
func matchesDump(volume *os.Root, file, dumped string) bool {
	branch, err := volume.OpenFile(file, os.O_RDONLY|unix.O_NOFOLLOW, 0)
	if err != nil {
		return false
	}
	defer branch.Close()
	saved, err := os.OpenFile(dumped, os.O_RDONLY|unix.O_NOFOLLOW, 0)
	if err != nil {
		return false
	}
	defer saved.Close()
	var a, s unix.Stat_t
	if unix.Fstat(int(branch.Fd()), &a) != nil || unix.Fstat(int(saved.Fd()), &s) != nil {
		return false
	}
	if a.Mode&unix.S_IFMT != unix.S_IFREG || a.Mode != s.Mode || a.Uid != s.Uid || a.Gid != s.Gid || a.Size != s.Size || hasXattrs(branch) {
		return false
	}
	x, y := make([]byte, 64<<10), make([]byte, 64<<10)
	for remaining := a.Size; remaining > 0; {
		n := min(remaining, int64(len(x)))
		if _, err := io.ReadFull(branch, x[:n]); err != nil {
			return false
		}
		if _, err := io.ReadFull(saved, y[:n]); err != nil {
			return false
		}
		if !bytes.Equal(x[:n], y[:n]) {
			return false
		}
		remaining -= n
	}
	return true
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
