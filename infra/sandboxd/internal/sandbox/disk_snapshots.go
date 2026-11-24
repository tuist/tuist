package sandbox

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/template"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

// A disk snapshot is a copy-on-write copy of a paused sandbox's rootfs and
// workspace disks, plus a hard link to the kernel it booted, under
// <SnapshotDir>/<id>/. New sandboxes clone those disks and cold boot on
// them; no memory is kept, so processes do not survive.
const (
	diskSnapshotFile      = "disk-snapshot.json"
	diskSnapshotTmpPrefix = ".tmp-"
	guestSyncTimeout      = 60 * time.Second
)

var (
	ErrDiskSnapshotNotFound    = errors.New("disk snapshot not found")
	ErrDisksNotSynced          = errors.New("disks were not synced by the last pause")
	ErrArchiveNeedsWarmRestore = errors.New("archive of an unsynced pause restores only on a node that loads its memory")
	ErrDiskSnapshotMismatch    = errors.New("disk snapshot does not match the requested sandbox")
	ErrCacheImage              = errors.New("invalid cache image")
)

type diskSnapshotMeta struct {
	ID            string    `json:"id"`
	Template      string    `json:"template"`
	Tag           string    `json:"tag"`
	WorkspaceGB   int       `json:"workspace_gb"`
	SourceSandbox string    `json:"source_sandbox"`
	CreatedAt     time.Time `json:"created_at"`
}

func (s diskSnapshotMeta) info() protocol.DiskSnapshotInfo {
	return protocol.DiskSnapshotInfo{ID: s.ID, Template: s.Template, TemplateTag: s.Tag, WorkspaceGB: s.WorkspaceGB, CreatedAt: s.CreatedAt}
}

func (m *Manager) diskSnapshotDir(id string) (string, error) {
	if m.cfg.SnapshotDir == "" {
		return "", errors.New("disk snapshots are not configured")
	}
	if err := vm.ValidateID(id); err != nil {
		return "", err
	}
	return filepath.Join(m.cfg.SnapshotDir, id), nil
}

func (m *Manager) loadDiskSnapshot(id string) (diskSnapshotMeta, string, error) {
	dir, err := m.diskSnapshotDir(id)
	if err != nil {
		return diskSnapshotMeta{}, "", err
	}
	data, err := readNoFollow(filepath.Join(dir, diskSnapshotFile))
	if errors.Is(err, os.ErrNotExist) {
		return diskSnapshotMeta{}, "", fmt.Errorf("%w: %s", ErrDiskSnapshotNotFound, id)
	}
	if err != nil {
		return diskSnapshotMeta{}, "", err
	}
	var meta diskSnapshotMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		return diskSnapshotMeta{}, "", fmt.Errorf("decoding disk snapshot %s: %w", id, err)
	}
	if meta.ID != id {
		return diskSnapshotMeta{}, "", fmt.Errorf("disk snapshot %s records id %q", id, meta.ID)
	}
	return meta, dir, nil
}

// SaveDisks copies a paused sandbox's disks into the disk snapshot id,
// replacing a previous snapshot of that id. The sandbox's last pause must
// have synced its disks.
func (m *Manager) SaveDisks(ctx context.Context, args protocol.SaveDisksArgs) (res protocol.SaveDisksResult, err error) {
	start := time.Now()
	defer func() { m.metrics.observe(protocol.OpSaveDisks, err) }()
	dir, err := m.diskSnapshotDir(args.SnapshotID)
	if err != nil {
		return res, err
	}
	sb, err := m.get(args.SandboxID)
	if err != nil {
		return res, err
	}
	sb.opMu.Lock()
	defer sb.opMu.Unlock()
	if !m.current(args.SandboxID, sb) {
		return res, fmt.Errorf("%w: %s", ErrNotFound, args.SandboxID)
	}
	sb.mu.Lock()
	meta := sb.meta
	sb.mu.Unlock()
	if meta.State != protocol.StatePaused {
		return res, fmt.Errorf("%w: %s is %s", ErrNotPaused, args.SandboxID, meta.State)
	}
	if !meta.DisksSynced {
		return res, fmt.Errorf("%w: %s", ErrDisksNotSynced, args.SandboxID)
	}

	m.snapMu.Lock()
	defer m.snapMu.Unlock()
	tmp := filepath.Join(m.cfg.SnapshotDir, diskSnapshotTmpPrefix+args.SnapshotID)
	if err := os.RemoveAll(tmp); err != nil {
		return res, err
	}
	if err := os.MkdirAll(tmp, 0o700); err != nil {
		return res, err
	}
	defer os.RemoveAll(tmp)
	if err := vm.HardLink(filepath.Join(sb.root, firecracker.KernelPath), filepath.Join(tmp, firecracker.KernelPath)); err != nil {
		return res, err
	}
	for _, name := range []string{firecracker.RootfsPath, firecracker.WorkspacePath} {
		dst := filepath.Join(tmp, name)
		if err := m.cloneFile(filepath.Join(sb.root, name), dst); err != nil {
			return res, err
		}
		if err := syncFile(dst); err != nil {
			return res, err
		}
	}
	snap := diskSnapshotMeta{
		ID: args.SnapshotID, Template: meta.Template, Tag: meta.Tag, WorkspaceGB: meta.WorkspaceGB,
		SourceSandbox: meta.ID, CreatedAt: time.Now().UTC(),
	}
	if err := writeJSON(filepath.Join(tmp, diskSnapshotFile), snap); err != nil {
		return res, err
	}
	if err := os.RemoveAll(dir); err != nil {
		return res, err
	}
	if err := os.Rename(tmp, dir); err != nil {
		return res, err
	}
	if err := syncFile(m.cfg.SnapshotDir); err != nil {
		return res, err
	}
	m.log.Info("disk snapshot saved", "snapshot", args.SnapshotID, "sandbox", args.SandboxID, "duration", time.Since(start))
	return protocol.SaveDisksResult{DurationMs: time.Since(start).Milliseconds()}, nil
}

// CopyDisks fills the disk snapshot id from its archive, so this node can
// create sandboxes from it without downloading it on the spawn's path. The
// download runs outside snapMu, so clones of other snapshots go on; a
// snapshot already on the node is kept as it is.
func (m *Manager) CopyDisks(ctx context.Context, args protocol.CopyDisksArgs) (res protocol.SaveDisksResult, err error) {
	start := time.Now()
	defer func() { m.metrics.observe(protocol.OpCopyDisks, err) }()
	dir, err := m.diskSnapshotDir(args.SnapshotID)
	if err != nil {
		return res, err
	}
	src := args.FromArchive
	if src == nil || src.URL == "" || src.Bytes <= 0 || src.SHA256 == "" {
		return res, errors.New("from_archive needs a URL, a size and a checksum")
	}
	if _, _, err := m.loadDiskSnapshot(args.SnapshotID); err == nil {
		return protocol.SaveDisksResult{DurationMs: time.Since(start).Milliseconds()}, nil
	}
	if err := os.MkdirAll(m.cfg.SnapshotDir, 0o700); err != nil {
		return res, err
	}
	// Startup removes a copy a crash interrupted with the other .tmp-* saves.
	tmp, err := os.MkdirTemp(m.cfg.SnapshotDir, diskSnapshotTmpPrefix+"copy-"+args.SnapshotID+"-")
	if err != nil {
		return res, err
	}
	defer os.RemoveAll(tmp)
	log := m.log.With("snapshot", args.SnapshotID)
	header, err := m.downloadArchive(ctx, src, tmp, args.Template, args.WorkspaceGB, 0, log)
	if err != nil {
		return res, err
	}
	for _, name := range archivedFiles {
		if err := syncFile(filepath.Join(tmp, name)); err != nil {
			return res, err
		}
	}
	snap := diskSnapshotMeta{
		ID: args.SnapshotID, Template: header.Template, Tag: header.Tag, WorkspaceGB: header.WorkspaceGB,
		SourceSandbox: header.SourceSandbox, CreatedAt: time.Now().UTC(),
	}
	if err := writeJSON(filepath.Join(tmp, diskSnapshotFile), snap); err != nil {
		return res, err
	}
	m.snapMu.Lock()
	defer m.snapMu.Unlock()
	if _, _, err := m.loadDiskSnapshot(args.SnapshotID); err == nil {
		return protocol.SaveDisksResult{DurationMs: time.Since(start).Milliseconds()}, nil
	}
	if err := os.RemoveAll(dir); err != nil {
		return res, err
	}
	if err := os.Rename(tmp, dir); err != nil {
		return res, err
	}
	if err := syncFile(m.cfg.SnapshotDir); err != nil {
		return res, err
	}
	m.log.Info("disk snapshot copied", "snapshot", args.SnapshotID, "bytes", src.Bytes, "duration", time.Since(start))
	return protocol.SaveDisksResult{DurationMs: time.Since(start).Milliseconds()}, nil
}

// DeleteDisks removes a disk snapshot. Deleting one the node does not hold
// succeeds.
func (m *Manager) DeleteDisks(ctx context.Context, id string) (err error) {
	defer func() { m.metrics.observe(protocol.OpDeleteDisks, err) }()
	dir, err := m.diskSnapshotDir(id)
	if err != nil {
		return err
	}
	m.snapMu.Lock()
	defer m.snapMu.Unlock()
	if err := os.RemoveAll(dir); err != nil {
		return err
	}
	m.log.Info("disk snapshot deleted", "snapshot", id)
	return nil
}

// DiskSnapshots lists the saved disk snapshots. Partial saves left by a
// crash are removed.
func (m *Manager) DiskSnapshots() []protocol.DiskSnapshotInfo {
	infos := []protocol.DiskSnapshotInfo{}
	if m.cfg.SnapshotDir == "" {
		return infos
	}
	entries, err := os.ReadDir(m.cfg.SnapshotDir)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			m.log.Warn("listing disk snapshots", "error", err)
		}
		return infos
	}
	for _, entry := range entries {
		if !entry.IsDir() || strings.HasPrefix(entry.Name(), diskSnapshotTmpPrefix) {
			continue
		}
		meta, _, err := m.loadDiskSnapshot(entry.Name())
		if err != nil {
			m.log.Warn("skipping unreadable disk snapshot", "snapshot", entry.Name(), "error", err)
			continue
		}
		infos = append(infos, meta.info())
	}
	sort.Slice(infos, func(i, j int) bool { return infos[i].ID < infos[j].ID })
	return infos
}

// removePartialDiskSnapshots deletes the temporary directories of saves
// that a crash interrupted.
func (m *Manager) removePartialDiskSnapshots() {
	if m.cfg.SnapshotDir == "" {
		return
	}
	entries, err := os.ReadDir(m.cfg.SnapshotDir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), diskSnapshotTmpPrefix) {
			_ = os.RemoveAll(filepath.Join(m.cfg.SnapshotDir, entry.Name()))
		}
	}
}

// cloneDiskSnapshot fills a new sandbox's jail root from a disk snapshot.
// Holding snapMu keeps a concurrent save or delete from swapping the files
// mid-clone.
func (m *Manager) cloneDiskSnapshot(snapshotID, template string, workspaceGB int, root string, uid int) (diskSnapshotMeta, error) {
	m.snapMu.Lock()
	defer m.snapMu.Unlock()
	snap, dir, err := m.loadDiskSnapshot(snapshotID)
	if err != nil {
		return snap, err
	}
	if snap.Template != template || snap.WorkspaceGB != workspaceGB {
		return snap, fmt.Errorf("%w: %s holds template %s with a %d GB workspace", ErrDiskSnapshotMismatch, snapshotID, snap.Template, snap.WorkspaceGB)
	}
	if err := vm.HardLink(filepath.Join(dir, firecracker.KernelPath), filepath.Join(root, firecracker.KernelPath)); err != nil {
		return snap, err
	}
	for _, name := range []string{firecracker.RootfsPath, firecracker.WorkspacePath} {
		dst := filepath.Join(root, name)
		if err := m.cloneFile(filepath.Join(dir, name), dst); err != nil {
			return snap, err
		}
		if err := vm.Chown(dst, uid, uid); err != nil {
			return snap, err
		}
	}
	return snap, nil
}

// createFromDiskSnapshot is Create's path for a sandbox cloned from a disk
// snapshot: the jail gets the snapshot's kernel and clones of its disks,
// and the VM cold boots on them. The caller holds sb.opMu and discards the
// sandbox when this fails.
func (m *Manager) createFromDiskSnapshot(ctx context.Context, sb *Sandbox, args protocol.CreateArgs, log *slog.Logger) (res protocol.CreateResult, err error) {
	slot, err := m.slots.Allocate()
	if err != nil {
		return res, err
	}
	sb.mu.Lock()
	sb.meta.Slot = slot
	template := sb.meta.Template
	sb.mu.Unlock()
	uid := m.cfg.UIDBase + slot
	if err := os.RemoveAll(vm.JailDir(m.cfg.JailBase, args.SandboxID)); err != nil {
		return res, err
	}
	if err := vm.Prepare(sb.root, uid, uid); err != nil {
		return res, err
	}
	snap, err := m.cloneDiskSnapshot(args.FromDiskSnapshot, template, args.WorkspaceGB, sb.root, uid)
	if err != nil {
		return res, err
	}
	sb.mu.Lock()
	sb.meta.Tag = snap.Tag
	sb.mu.Unlock()
	if args.CacheImage != "" {
		if err := m.attachCacheImage(args.CacheImage, sb.root, uid); err != nil {
			return res, err
		}
		sb.mu.Lock()
		sb.meta.CacheImage = args.CacheImage
		sb.mu.Unlock()
	}

	return m.coldCreate(ctx, sb, log.With("snapshot", args.FromDiskSnapshot, "slot", slot))
}

// attachCacheImage gives the jail a private writable clone of a cache image.
// The source must be a regular file, not a symlink out of the directory.
func (m *Manager) attachCacheImage(name, root string, uid int) error {
	src := filepath.Join(m.cfg.CacheImageDir, name)
	info, err := os.Lstat(src)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrCacheImage, err)
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("%w: %s is not a regular file", ErrCacheImage, name)
	}
	dst := filepath.Join(root, firecracker.CachePath)
	if err := m.cloneFile(src, dst); err != nil {
		return err
	}
	return vm.Chown(dst, uid, uid)
}

// cachePlaceholder gives the jail the empty cache drive a template snapshot
// built with a cache drive expects.
func (m *Manager) cachePlaceholder(root string, uid int) error {
	cache := filepath.Join(root, firecracker.CachePath)
	if err := vm.Sparse(cache, template.CachePlaceholderBytes); err != nil {
		return err
	}
	return vm.Chown(cache, uid, uid)
}

// coldCreate boots a new sandbox whose jail already holds its kernel and
// disks, and records it as running. The caller holds sb.opMu and discards
// the sandbox when this fails.
func (m *Manager) coldCreate(ctx context.Context, sb *Sandbox, log *slog.Logger) (protocol.CreateResult, error) {
	bootStart := time.Now()
	inst, agent, err := m.boot(ctx, sb, log)
	if err != nil {
		return protocol.CreateResult{}, err
	}
	m.growRootfs(ctx, sb, inst, agent, log)
	sb.mu.Lock()
	sb.meta.State = protocol.StateRunning
	sb.meta.Generation = 0
	sb.meta.Error = ""
	meta := sb.meta
	err = sb.meta.Save(sb.root)
	sb.mu.Unlock()
	if err != nil {
		return protocol.CreateResult{}, err
	}
	m.refreshGauges()
	log.Info("sandbox created on its own disks", "template", meta.Template, "tag", meta.Tag, "boot", time.Since(bootStart), "pid", inst.PID())
	return protocol.CreateResult{BootMs: time.Since(bootStart).Milliseconds()}, nil
}

// syncGuest flushes the guest's page cache to its disks.
func (m *Manager) syncGuest(ctx context.Context, sb *Sandbox) error {
	sb.mu.Lock()
	agent := sb.agent
	sb.mu.Unlock()
	if agent == nil {
		return ErrNotRunning
	}
	ctx, cancel := context.WithTimeout(ctx, guestSyncTimeout)
	defer cancel()
	code, err := vsock.RunProcess(ctx, agent, vsock.ExecRequest{Cmd: []string{"/bin/sync"}, Cwd: "/"}, func(string, []byte) {})
	if err != nil {
		return err
	}
	if code != 0 {
		return fmt.Errorf("sync exited with %d", code)
	}
	return nil
}

// dropCacheScript writes back and drops the page cache of a guest with a
// virtio balloon and prints how much cache it held, in kB. A guest without
// one prints nothing: dropping would gain the host nothing, since only the
// balloon's free page reporting returns freed pages. The guest reports only
// free 2 MiB blocks (page_reporting_order 9), and dropped cache leaves most
// of its pages scattered among used ones, so it compacts memory too: on
// staging a 4 GiB guest returned 1 GiB of dropped cache that way, against
// half of it without compaction, and compaction took 180 ms.
const dropCacheScript = `ls /sys/bus/virtio/drivers/virtio_balloon 2>/dev/null | grep -q '^virtio' || exit 0
sync
sed -n 's/^Cached: *\([0-9]*\) kB$/\1/p' /proc/meminfo
echo 1 > /proc/sys/vm/drop_caches
echo 1 > /proc/sys/vm/compact_memory`

// dropGuestCache drops a ballooned guest's page cache before a pause so the
// snapshot holds zeros, not cache, for those pages, and answers the bytes of
// cache the guest held (0 without a balloon).
func (m *Manager) dropGuestCache(ctx context.Context, sb *Sandbox) (int64, error) {
	sb.mu.Lock()
	agent := sb.agent
	sb.mu.Unlock()
	if agent == nil {
		return 0, ErrNotRunning
	}
	ctx, cancel := context.WithTimeout(ctx, guestSyncTimeout)
	defer cancel()
	var out []byte
	code, err := vsock.RunProcess(ctx, agent, vsock.ExecRequest{Cmd: []string{"/bin/sh", "-c", dropCacheScript}, Cwd: "/"}, func(stream string, data []byte) {
		if stream == "stdout" && len(out) < 64 {
			out = append(out, data...)
		}
	})
	if err != nil {
		return 0, err
	}
	if code != 0 {
		return 0, fmt.Errorf("dropping the page cache exited with %d", code)
	}
	kb, _ := strconv.ParseInt(strings.TrimSpace(string(out)), 10, 64)
	return kb << 10, nil
}

// awaitReturnedMemory waits, up to max, for the guest's freed pages to leave
// the VM process: free page reporting hands them over in batches about 2 s
// apart, so it stops once the process's resident memory has not fallen by
// 16 MiB for 3 s.
func awaitReturnedMemory(ctx context.Context, inst vm.Instance, max time.Duration) {
	const settle, step = 3 * time.Second, 500 * time.Millisecond
	resident := func() (uint64, bool) {
		mem, ok := inst.ResidentMemory()
		return mem.AnonBytes + mem.FileBytes, ok
	}
	low, ok := resident()
	if !ok {
		return
	}
	deadline, lastDrop := time.Now().Add(max), time.Now()
	for time.Now().Before(deadline) && time.Since(lastDrop) < settle {
		select {
		case <-ctx.Done():
			return
		case <-time.After(step):
		}
		now, ok := resident()
		if !ok {
			return
		}
		if now+16<<20 < low {
			low, lastDrop = now, time.Now()
		}
	}
}

func writeJSON(path string, v any) error {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY|syscall.O_NOFOLLOW, 0o644)
	if err != nil {
		return err
	}
	if _, err := file.Write(append(data, '\n')); err != nil {
		file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	return file.Close()
}

func syncFile(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	return file.Sync()
}
