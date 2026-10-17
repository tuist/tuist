// Package diskusage measures what the daemon's data directory occupies on
// the node's filesystem so the server can budget sandboxes against it.
//
// A jail shares most of its bytes with its template: the kernel and the
// initial memory image are hardlinks, the rootfs is a reflink clone. The
// number that matters for a budget is what a sandbox holds exclusively
// (its rootfs delta, the workspace it filled, the memory image its own
// pauses wrote), so files are counted once per inode, templates before
// jails, and on Linux only the extents no other file shares are summed.
package diskusage

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"syscall"

	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
)

// Exclusive returns the bytes a regular file holds that nothing else
// shares. Platform files provide the default; tests inject their own.
type Exclusive func(path string, info os.FileInfo) (uint64, error)

type Accounter struct {
	DataDir      string
	TemplatesDir string
	JailDir      string
	BudgetBytes  uint64
	Exclusive    Exclusive
}

type inode struct {
	dev uint64
	ino uint64
}

// Report measures the filesystem behind DataDir and the exclusive bytes
// under the templates and jail directories.
func (a Accounter) Report() (protocol.DiskReport, error) {
	report := protocol.DiskReport{BudgetBytes: a.BudgetBytes}
	total, available, err := Filesystem(a.DataDir)
	if err != nil {
		return report, err
	}
	report.TotalBytes = total
	report.AvailableBytes = available

	exclusive := a.Exclusive
	if exclusive == nil {
		exclusive = exclusiveBytes
	}
	seen := map[inode]struct{}{}
	templates, err := sum(a.TemplatesDir, seen, exclusive)
	if err != nil {
		return report, err
	}
	sandboxes, err := sum(a.JailDir, seen, exclusive)
	if err != nil {
		return report, err
	}
	report.TemplatesBytes = templates
	report.SandboxesBytes = sandboxes
	return report, nil
}

func sum(root string, seen map[inode]struct{}, exclusive Exclusive) (uint64, error) {
	var total uint64
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			// Jails come and go under the walker; a vanished entry is
			// not an accounting error.
			if errors.Is(err, fs.ErrNotExist) {
				return nil
			}
			return err
		}
		if !entry.Type().IsRegular() {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			if errors.Is(err, fs.ErrNotExist) {
				return nil
			}
			return err
		}
		if stat, ok := info.Sys().(*syscall.Stat_t); ok {
			key := inode{dev: uint64(stat.Dev), ino: uint64(stat.Ino)} //nolint:unconvert // Dev is int32 on darwin.
			if _, dup := seen[key]; dup {
				return nil
			}
			seen[key] = struct{}{}
		}
		bytes, err := exclusive(path, info)
		if err != nil {
			if errors.Is(err, fs.ErrNotExist) {
				return nil
			}
			return err
		}
		total += bytes
		return nil
	})
	if errors.Is(err, fs.ErrNotExist) {
		return total, nil
	}
	return total, err
}

// allocatedBytes is the fallback when extents cannot be inspected: the
// blocks the inode has allocated, which is exact for sparse files and
// overcounts only reflink clones.
func allocatedBytes(_ string, info os.FileInfo) (uint64, error) {
	if stat, ok := info.Sys().(*syscall.Stat_t); ok {
		return uint64(stat.Blocks) * 512, nil //nolint:gosec // Blocks is never negative.
	}
	return uint64(info.Size()), nil //nolint:gosec // Size is never negative.
}
