//go:build linux

package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unsafe"

	"golang.org/x/sys/unix"
)

// Leave room below the host's 30 decimal GB allocated-byte publication cap for
// ext4 metadata and shutdown writes. Unlike per-builder GC, this bounds the
// aggregate of registry images, embedded build cache and ALL retained builders.
const dockerRetainedBytes int64 = 26_000_000_000

func dockerBuilderLedger(root string) string { return filepath.Join(root, "tuist", "builders.json") }

func dockerUsedBytes(root string) (int64, error) {
	var stat unix.Statfs_t
	if err := unix.Statfs(root, &stat); err != nil {
		return 0, err
	}
	return int64(stat.Blocks-stat.Bfree) * stat.Bsize, nil
}

// Record actual job use, not the fact that a later merge copied an idle builder.
func (d *daemon) recordBuilderUse(ctx context.Context) error {
	states, err := d.buildkitSnapshot(ctx, "", d.dataRoot)
	if err != nil {
		return err
	}
	ledger := readDockerLedger(dockerBuilderLedger(d.dataRoot))
	kept := dockerLedger{}
	for name, state := range states {
		entry := ledger[name]
		if state != d.base.BuildVolumes[name] {
			entry.LastUsedAt = time.Now().UTC()
		}
		kept[name] = entry
	}
	return writeDockerLedger(dockerBuilderLedger(d.dataRoot), kept)
}

type dockerEviction struct {
	name     string
	volume   bool
	lastUsed time.Time
}

// Retain whole builder volumes: deleting individual BuildKit database files or
// snapshots would corrupt the cache. Containers have stopped before this runs.
// Docker removes images/volumes through its API; only the guest sees ext4.
func (d *daemon) retainDocker(ctx context.Context, host, root string, ledger dockerLedger, limit int64) error {
	used := d.usedBytes
	if used == nil {
		used = dockerUsedBytes
	}
	bytes, err := used(root)
	if err != nil {
		return err
	}
	if bytes <= limit {
		return nil
	}
	images, err := d.images(ctx, host)
	if err != nil {
		return err
	}
	volumes, err := d.buildkitVolumes(ctx, host, root)
	if err != nil {
		return err
	}
	builders := readDockerLedger(dockerBuilderLedger(root))
	var candidates []dockerEviction
	for _, image := range images {
		candidates = append(candidates, dockerEviction{name: image.ID, lastUsed: ledger[image.ID].LastUsedAt})
	}
	for _, volume := range volumes {
		candidates = append(candidates, dockerEviction{name: volume.Name, volume: true, lastUsed: builders[volume.Name].LastUsedAt})
	}
	sort.Slice(candidates, func(i, j int) bool {
		if candidates[i].lastUsed.Equal(candidates[j].lastUsed) {
			return candidates[i].name < candidates[j].name
		}
		return candidates[i].lastUsed.Before(candidates[j].lastUsed)
	})
	for _, candidate := range candidates {
		kind := "image"
		if candidate.volume {
			kind = "volume"
		}
		if out, err := d.run(ctx, "docker", dockerArgs(host, kind, "rm", "-f", candidate.name)...); err != nil {
			return fmt.Errorf("evict cached %s: %s: %w", kind, strings.TrimSpace(string(out)), err)
		}
		if candidate.volume {
			delete(builders, candidate.name)
		} else {
			delete(ledger, candidate.name)
		}
		fmt.Fprintf(os.Stderr, "Tuist Docker cache: evicted %s %s to fit publication budget\n", kind, candidate.name)
		bytes, err = used(root)
		if err != nil {
			return err
		}
		if bytes <= limit {
			break
		}
	}
	if err := writeDockerLedger(dockerLedgerFile(root), ledger); err != nil {
		return err
	}
	if err := writeDockerLedger(dockerBuilderLedger(root), builders); err != nil {
		return err
	}
	if bytes > limit {
		return fmt.Errorf("Docker cache retains %d bytes after eviction (budget %d)", bytes, limit)
	}
	return nil
}

// Free ext4 blocks still occupy the backing sparse file until FITRIM punches
// their holes. Run after dockerd stops, while mounted, on BOTH merge choices.
// Failure withholds publication rather than repeatedly uploading deleted data.
func (d *daemon) trimDocker(ctx context.Context, root string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if d.trim != nil {
		return d.trim(root)
	}
	// ext4 defers freeing deleted extents until their journal transaction
	// commits. Without this flush, FITRIM can succeed while reclaiming almost
	// none of the files cleanup just removed.
	file, err := os.Open(root)
	if err != nil {
		return err
	}
	defer file.Close()
	err = unix.Syncfs(int(file.Fd()))
	if err != nil {
		return fmt.Errorf("sync Docker cache before trim: %w", err)
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	// Linux linux/fs.h: _IOWR('X', 121, struct fstrim_range). All three
	// fields are __u64 on both supported architectures (amd64 and arm64).
	// Calling the kernel directly avoids installing util-linux: its mount
	// replaced the BusyBox mount used by the working Kata startup path.
	rangeToTrim := struct{ Start, Length, MinLength uint64 }{Length: ^uint64(0)}
	_, _, errno := unix.Syscall(unix.SYS_IOCTL, file.Fd(), 0xc0185879, uintptr(unsafe.Pointer(&rangeToTrim)))
	if errno != 0 {
		return fmt.Errorf("trim Docker cache: %w", errno)
	}
	return nil
}
