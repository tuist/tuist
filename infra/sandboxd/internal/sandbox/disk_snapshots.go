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
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
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
	ErrDiskSnapshotNotFound = errors.New("disk snapshot not found")
	ErrDisksNotSynced       = errors.New("disks were not synced by the last pause")
	ErrDiskSnapshotMismatch = errors.New("disk snapshot does not match the requested sandbox")
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

	bootStart := time.Now()
	inst, _, err := m.boot(ctx, sb, log)
	if err != nil {
		return res, err
	}
	sb.mu.Lock()
	sb.meta.State = protocol.StateRunning
	sb.meta.Generation = 0
	sb.meta.Error = ""
	err = sb.meta.Save(sb.root)
	sb.mu.Unlock()
	if err != nil {
		return res, err
	}
	m.refreshGauges()
	log.Info("sandbox created from disk snapshot", "snapshot", args.FromDiskSnapshot, "template", snap.Template, "tag", snap.Tag, "slot", slot, "boot", time.Since(bootStart), "pid", inst.PID())
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
