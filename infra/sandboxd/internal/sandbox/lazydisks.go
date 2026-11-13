package sandbox

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/archive"
	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/lazydisk"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// An archive written with lazy disks (protocol.ArchiveArgs.LazyDisks)
// holds the rootfs and the workspace as chunks, like the memory image, and
// its disk stream only their indexes. A warm restore serves each disk to
// Firecracker through a FUSE mount over the disk's path in the jail
// (package lazydisk): a chunk the guest reads or writes first is fetched
// then, and a fill fetches the rest into a local file beside it,
// <disk>.fill. Once both are complete the files replace the mounts and
// Firecracker reopens its drives on them, so the sandbox depends on the
// archive and on FUSE only while the fill runs. Without FUSE, or after a
// restore through the mounts failed on this node, the restore fills the
// disks before it starts the VM, which is the old wait for the whole tail.
const (
	lazyDiskSuffix      = ".fill"
	lazyDiskFillWorkers = 4
	// lazyDiskSettle bounds how long a pause waits for the disks of a
	// restore still filling, which it must hold whole before it can save
	// the sandbox.
	lazyDiskSettle = 10 * time.Minute
)

var lazyDiskNames = []string{firecracker.RootfsPath, firecracker.WorkspacePath}

// lazyDisks are a restored sandbox's disks while they still arrive.
type lazyDisks struct {
	disks []*lazyDisk
	// loaded is closed once both disks are complete, filled once the fill
	// ended, after which err holds why it failed, if it did.
	loaded, filled chan struct{}
	err            error
}

type lazyDisk struct {
	name   string
	file   *os.File
	remote *archive.RemoteMemory
	image  *lazydisk.Image
	mount  *lazydisk.Mount
}

// openLazyDisks prepares the disks of a restore from their indexes in the
// jail root, each mounted over its path when mount is set, and starts
// filling them.
func (m *Manager) openLazyDisks(sb *Sandbox, src *protocol.ArchiveSource, workspaceGB, uid int, mount bool) (ld *lazyDisks, err error) {
	ld = &lazyDisks{loaded: make(chan struct{}), filled: make(chan struct{})}
	defer func() {
		if err != nil {
			ld.close()
		}
	}()
	for _, name := range lazyDiskNames {
		indexPath := filepath.Join(sb.root, archive.DiskIndexName(name))
		data, err := os.ReadFile(indexPath)
		if err != nil {
			return nil, err
		}
		index, err := archive.ParseMemoryIndex(data, src.TailOffset)
		if err != nil {
			return nil, err
		}
		if name == firecracker.WorkspacePath && index.Size != int64(workspaceGB)<<30 {
			return nil, fmt.Errorf("%w: workspace image is %d bytes", ErrArchiveMismatch, index.Size)
		}
		if name == firecracker.RootfsPath && index.Size > maxRootfsBytes {
			return nil, fmt.Errorf("%w: rootfs image is %d bytes", archive.ErrInvalid, index.Size)
		}
		remote, err := archive.NewRemoteMemory(m.http, src.URL, index)
		if err != nil {
			return nil, err
		}
		disk := &lazyDisk{name: name, remote: remote}
		ld.disks = append(ld.disks, disk)
		path := filepath.Join(sb.root, name)
		if disk.file, err = os.OpenFile(path+lazyDiskSuffix, os.O_CREATE|os.O_EXCL|os.O_RDWR|syscall.O_NOFOLLOW, 0o600); err != nil {
			return nil, err
		}
		if err := vm.Chown(path+lazyDiskSuffix, uid, uid); err != nil {
			return nil, err
		}
		if disk.image, err = lazydisk.New(disk.file, remote); err != nil {
			return nil, err
		}
		_ = os.Remove(indexPath)
		if !mount {
			continue
		}
		// The mount covers a placeholder at the disk's path, which the
		// filled file replaces.
		placeholder, err := os.OpenFile(path, os.O_CREATE|os.O_TRUNC|os.O_WRONLY|syscall.O_NOFOLLOW, 0o600)
		if err != nil {
			return nil, err
		}
		placeholder.Close()
		if err := vm.Chown(path, uid, uid); err != nil {
			return nil, err
		}
		if disk.mount, err = lazydisk.MountImage(path, disk.image, uint32(uid), uint32(uid)); err != nil { //nolint:gosec // Slot uids are small and positive.
			return nil, fmt.Errorf("mounting %s: %w", name, err)
		}
	}
	go ld.fill()
	return ld, nil
}

func (ld *lazyDisks) fill() {
	defer close(ld.filled)
	errs := make(chan error, len(ld.disks))
	for _, disk := range ld.disks {
		go func() { errs <- disk.image.Fill(lazyDiskFillWorkers) }()
	}
	var err error
	for range ld.disks {
		err = errors.Join(err, <-errs)
	}
	if err != nil {
		ld.err = err
		return
	}
	close(ld.loaded)
}

// wait waits until both disks are complete, the fill failed, or ctx ends.
func (ld *lazyDisks) wait(ctx context.Context) error {
	select {
	case <-ld.filled:
		return ld.err
	case <-ctx.Done():
		return ctx.Err()
	}
}

// install moves the complete disks to their paths, under any mount, which
// it detaches: a Firecracker that has a disk open keeps using it through
// the mount until it reopens the drive.
func (ld *lazyDisks) install(root string) error {
	for _, disk := range ld.disks {
		if disk.mount != nil {
			if err := disk.mount.Detach(); err != nil {
				return fmt.Errorf("unmounting %s: %w", disk.name, err)
			}
		}
		if err := disk.image.Sync(); err != nil {
			return err
		}
		path := filepath.Join(root, disk.name)
		if err := os.Rename(path+lazyDiskSuffix, path); err != nil {
			return err
		}
	}
	return nil
}

// release stops the images once the mounts' last users closed them: a
// Firecracker that still has a disk open through its mount keeps reading
// and writing the complete local file through it until it exits.
func (ld *lazyDisks) release() {
	for _, disk := range ld.disks {
		if disk.mount != nil {
			<-disk.mount.Done()
		}
	}
	ld.close()
}

// close detaches the mounts and stops fetching, without waiting for the
// mounts' users.
func (ld *lazyDisks) close() {
	for _, disk := range ld.disks {
		if disk.mount != nil {
			_ = disk.mount.Detach()
		}
		if disk.image != nil {
			disk.image.Close()
		}
		if disk.file != nil {
			disk.file.Close()
		}
		disk.remote.Close()
	}
}

func (ld *lazyDisks) stats() []any {
	var out []any
	for _, disk := range ld.disks {
		chunks, faulted, filled := disk.image.Stats()
		out = append(out, disk.name, fmt.Sprintf("%d chunks, %d faulted, %d filled", chunks, faulted, filled))
	}
	return out
}

// fillDisks fills a restore's disks before its VM starts, for a node that
// cannot or should not mount them.
func (m *Manager) fillDisks(ctx context.Context, sb *Sandbox, src *protocol.ArchiveSource, workspaceGB, uid int, log *slog.Logger) error {
	start := time.Now()
	ld, err := m.openLazyDisks(sb, src, workspaceGB, uid, false)
	if err != nil {
		return err
	}
	defer ld.close()
	if err := ld.wait(ctx); err != nil {
		return fmt.Errorf("restoring the disks from the archive: %w", err)
	}
	if err := ld.install(sb.root); err != nil {
		return err
	}
	log.Info("archived disks downloaded", "download", time.Since(start))
	return nil
}

// serveLazyDisks follows a warm restore's mounted disks: once both are
// complete it installs them and has Firecracker reopen its drives on them;
// a disk that cannot be fetched kills the VM, as missing memory does.
func (m *Manager) serveLazyDisks(sb *Sandbox, ld *lazyDisks, inst vm.Instance, log *slog.Logger) {
	start := time.Now()
	select {
	case <-ld.filled:
	case <-inst.Done():
		return
	}
	sb.opMu.Lock()
	defer sb.opMu.Unlock()
	sb.mu.Lock()
	current := sb.lazy == ld && sb.inst == inst
	sb.mu.Unlock()
	if !current {
		// A pause or delete settled them.
		return
	}
	if ld.err != nil {
		m.memoryFailed(sb, inst, ld.err)
		m.dropLazyDisks(sb)
		return
	}
	if err := ld.install(sb.root); err != nil {
		m.memoryFailed(sb, inst, err)
		m.dropLazyDisks(sb)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	var patchErr error
	for _, drive := range []firecracker.DrivePatch{
		{DriveID: firecracker.RootDriveID, PathOnHost: inst.GuestPath(firecracker.RootfsPath)},
		{DriveID: firecracker.WorkspaceDriveID, PathOnHost: inst.GuestPath(firecracker.WorkspacePath)},
	} {
		if patchErr = inst.API().PatchDrive(ctx, drive); patchErr != nil {
			break
		}
	}
	sb.mu.Lock()
	sb.lazy = nil
	sb.mu.Unlock()
	log.Info("sandbox disks loaded from its archive", append([]any{"elapsed", time.Since(start), "reopened", patchErr == nil}, ld.stats()...)...)
	if patchErr != nil {
		// The drives stay on the mounts, which serve the installed files,
		// until this Firecracker exits.
		log.Warn("firecracker did not reopen the restored disks; serving them through FUSE until it exits", "error", patchErr)
	}
	go ld.release()
	m.restorePartLoaded(sb, false)
}

// settleLazyDisks completes the disks of a restore still filling once its
// VM is gone, for a pause, which must save them whole.
func (m *Manager) settleLazyDisks(ctx context.Context, sb *Sandbox) error {
	sb.mu.Lock()
	ld := sb.lazy
	sb.mu.Unlock()
	if ld == nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(ctx, lazyDiskSettle)
	defer cancel()
	err := ld.wait(ctx)
	if err == nil {
		err = ld.install(sb.root)
	}
	go ld.release()
	sb.mu.Lock()
	sb.lazy = nil
	sb.mu.Unlock()
	return err
}

// dropLazyDisks stops the disks of a restore still filling, for a delete
// or a VM that died.
func (m *Manager) dropLazyDisks(sb *Sandbox) {
	sb.mu.Lock()
	ld := sb.lazy
	sb.lazy = nil
	sb.mu.Unlock()
	if ld != nil {
		ld.close()
	}
}
