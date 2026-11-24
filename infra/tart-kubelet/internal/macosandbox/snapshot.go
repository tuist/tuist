package macosandbox

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/pkg/archive"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// Disk snapshots are stopped Tart VMs named `sbs-<snapshot id>` in the
// sandbox store, so a create clones one with `tart clone` like the template.
// A save copies an evicted sandbox's disk files into one with APFS clones:
// its stacked image's `manifest.json` and private `overlay.asif`, whose base
// layers stay shared in the content store and which holds the workspace
// volume too, `config.json` and `nvram.bin`. Only a stacked VM is saved: a
// standalone `disk.img` is the whole image, which could never be archived or
// copied, so its host alone could boot from it. The
// checkpoint (`state.vzvmsave`) and the runtime's control files stay behind,
// so the copy keeps no memory and cold boots.
const (
	snapshotVMPrefix = "sbs-"
	snapshotMetadata = "disk-snapshot.json"
	// Saves are assembled here and renamed into `vms/`, so Tart and the
	// host's reports never see a partial snapshot. Startup empties it.
	snapshotStaging = "snapshots.tmp"
)

var errSnapshotNotFound = errors.New("disk snapshot not found")

func snapshotVMName(id string) string { return snapshotVMPrefix + id }

func (t *TartRuntime) snapshotDirectory(id string) string {
	return filepath.Join(t.Client.HomeDir, "vms", snapshotVMName(id))
}

// SaveDisks copies the disks of a fenced VM, one whose process has exited
// after its checkpoint, into the snapshot id. Saving an id that exists
// answers it unchanged, so a retried save whose answer was lost succeeds.
func (t *TartRuntime) SaveDisks(ctx context.Context, r *Record, id string) (protocol.DiskSnapshotInfo, error) {
	if info, err := t.DiskSnapshot(id); err == nil {
		return info, nil
	} else if !errors.Is(err, errSnapshotNotFound) {
		return protocol.DiskSnapshotInfo{}, err
	}
	if r.WorkspaceVolumeGB == 0 {
		return protocol.DiskSnapshotInfo{}, errors.New("sandbox has no workspace volume to save")
	}
	running, err := t.client(r).IsRunning(ctx, r.VMName())
	if err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	if running {
		return protocol.DiskSnapshotInfo{}, errors.New("sandbox VM is still running")
	}
	source := t.directory(r)
	if _, err := os.Lstat(filepath.Join(source, "disk.img")); err == nil {
		return protocol.DiskSnapshotInfo{}, fmt.Errorf("%w: its image is not stacked", ErrNotArchivable)
	}
	files := []string{"config.json", "nvram.bin", "manifest.json", "overlay.asif"}
	disk := filepath.Join(source, "overlay.asif")
	info, err := os.Lstat(disk)
	if err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || !info.Mode().IsRegular() {
		return protocol.DiskSnapshotInfo{}, errors.New("sandbox disk is not a regular file")
	}
	// Allocated, not logical, size: the clone shares these blocks with the
	// sandbox, and the snapshot never writes more.
	bytes := stat.Blocks * 512
	if err := t.admitDisk(ctx, t.client(r), 0, uint64(bytes)); err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	staging := filepath.Join(t.Client.HomeDir, snapshotStaging, id)
	if err := os.RemoveAll(staging); err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	if err := os.MkdirAll(staging, 0o700); err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	defer os.RemoveAll(staging)
	for _, name := range files {
		if err := cloneFile(filepath.Join(source, name), filepath.Join(staging, name)); err != nil {
			return protocol.DiskSnapshotInfo{}, fmt.Errorf("clone %s: %w", name, err)
		}
	}
	snapshot := protocol.DiskSnapshotInfo{ID: id, Template: r.Template, TemplateTag: r.TemplateTag, WorkspaceGB: r.WorkspaceVolumeGB, CreatedAt: time.Now().UTC(), Bytes: bytes}
	data, err := json.Marshal(snapshot)
	if err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	if err := atomicFile(filepath.Join(staging, snapshotMetadata), data); err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	t.snapMu.Lock()
	defer t.snapMu.Unlock()
	if err := os.Rename(staging, t.snapshotDirectory(id)); err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	return snapshot, syncDirectory(filepath.Dir(t.snapshotDirectory(id)))
}

// ArchiveDisks uploads a snapshot as an evicted sandbox's archive is
// uploaded (uploadDisk), so other hosts can copy it (CopyDisks). The files are
// opened first and streamed after: a delete meanwhile only unlinks them, and
// the server discards an upload whose snapshot is gone.
func (t *TartRuntime) ArchiveDisks(ctx context.Context, args protocol.ArchiveDisksArgs) (protocol.ArchiveResult, error) {
	info, err := t.DiskSnapshot(args.SnapshotID)
	if err != nil {
		return protocol.ArchiveResult{}, err
	}
	header := archive.Header{Template: info.Template, Tag: info.TemplateTag, WorkspaceGB: info.WorkspaceGB, CreatedAt: info.CreatedAt, DisksSynced: true}
	res, err := uploadDisk(ctx, t.snapshotDirectory(args.SnapshotID), header, args.PartURLs, args.PartSize)
	if err == nil {
		slog.Info("macOS disk snapshot archived", "snapshot", args.SnapshotID, "bytes", res.Bytes, "stored_bytes", res.StoredBytes, "duration_ms", res.DurationMs)
	}
	return res, err
}

// CopyDisks fills snapshot id from its archive, so this host clones it like
// one it saved. It is a restore that keeps the VM stopped (cloneArchived):
// the image the snapshot was saved from is cloned into `sbs-<id>`, pulled
// first when the template has moved on, and the archived files replace the
// clone's. The metadata is written last, so until then the host neither
// reports nor clones the snapshot; a failed copy is removed. A snapshot
// already here is kept.
func (t *TartRuntime) CopyDisks(ctx context.Context, args protocol.CopyDisksArgs) (protocol.DiskSnapshotInfo, error) {
	start := time.Now()
	if args.FromArchive == nil {
		return protocol.DiskSnapshotInfo{}, errors.New("copy_disks needs from_archive")
	}
	if !validID(args.SnapshotID) {
		return protocol.DiskSnapshotInfo{}, errors.New("invalid disk snapshot id")
	}
	if info, err := t.DiskSnapshot(args.SnapshotID); err == nil {
		return info, nil
	}
	if err := t.admitDisk(ctx, t.Client, 0, uint64(max(args.Bytes, 0))); err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	dir := t.snapshotDirectory(args.SnapshotID)
	t.snapMu.Lock()
	err := os.RemoveAll(dir)
	t.snapMu.Unlock()
	if err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	info, err := t.copyDisks(ctx, args)
	if err != nil {
		t.snapMu.Lock()
		_ = os.RemoveAll(dir)
		t.snapMu.Unlock()
		return protocol.DiskSnapshotInfo{}, fmt.Errorf("copying disk snapshot: %w", err)
	}
	slog.Info("macOS disk snapshot copied", "snapshot", args.SnapshotID, "image", info.TemplateTag, "archive_bytes", args.FromArchive.Bytes, "bytes", info.Bytes, "duration_ms", time.Since(start).Milliseconds())
	return info, nil
}

func (t *TartRuntime) copyDisks(ctx context.Context, args protocol.CopyDisksArgs) (protocol.DiskSnapshotInfo, error) {
	vm := snapshotVMName(args.SnapshotID)
	header, _, _, err := t.cloneArchived(ctx, t.Client, vm, args.Template, args.TemplateTag, args.WorkspaceGB, *args.FromArchive)
	if err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	dir := t.snapshotDirectory(args.SnapshotID)
	overlay, err := os.Lstat(filepath.Join(dir, "overlay.asif"))
	if err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	bytes := int64(0)
	if stat, ok := overlay.Sys().(*syscall.Stat_t); ok {
		bytes = stat.Blocks * 512
	}
	info := protocol.DiskSnapshotInfo{ID: args.SnapshotID, Template: args.Template, TemplateTag: header.Tag, WorkspaceGB: header.WorkspaceGB, CreatedAt: time.Now().UTC(), Bytes: bytes}
	data, err := json.Marshal(info)
	if err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	if err := atomicFile(filepath.Join(dir, snapshotMetadata), data); err != nil {
		return protocol.DiskSnapshotInfo{}, err
	}
	return info, syncDirectory(filepath.Dir(dir))
}

// DeleteDisks removes a snapshot; one that is absent is already deleted.
func (t *TartRuntime) DeleteDisks(_ context.Context, id string) error {
	t.snapMu.Lock()
	defer t.snapMu.Unlock()
	if err := os.RemoveAll(t.snapshotDirectory(id)); err != nil {
		return err
	}
	return syncDirectory(filepath.Dir(t.snapshotDirectory(id)))
}

// DiskSnapshot reads one snapshot's metadata, errSnapshotNotFound when the
// host has none under id.
func (t *TartRuntime) DiskSnapshot(id string) (protocol.DiskSnapshotInfo, error) {
	var info protocol.DiskSnapshotInfo
	data, err := os.ReadFile(filepath.Join(t.snapshotDirectory(id), snapshotMetadata))
	if os.IsNotExist(err) {
		return info, errSnapshotNotFound
	}
	if err != nil {
		return info, err
	}
	if err = json.Unmarshal(data, &info); err != nil || info.ID != id {
		return info, fmt.Errorf("invalid disk snapshot %s", id)
	}
	return info, nil
}

// DiskSnapshots lists the host's snapshots for its reports and disk budget.
func (t *TartRuntime) DiskSnapshots() ([]protocol.DiskSnapshotInfo, error) {
	entries, err := os.ReadDir(filepath.Join(t.Client.HomeDir, "vms"))
	if err != nil && !os.IsNotExist(err) {
		return nil, err
	}
	out := []protocol.DiskSnapshotInfo{}
	for _, entry := range entries {
		id, ok := strings.CutPrefix(entry.Name(), snapshotVMPrefix)
		if !ok || !validID(id) {
			continue
		}
		// A delete in flight may have removed the metadata already.
		info, err := t.DiskSnapshot(id)
		if errors.Is(err, errSnapshotNotFound) {
			continue
		}
		if err != nil {
			return nil, err
		}
		out = append(out, info)
	}
	return out, nil
}

// clearSnapshotStaging removes saves and copies a restart interrupted: the
// staging directory, and snapshot VMs whose metadata a copy never wrote.
func (t *TartRuntime) clearSnapshotStaging() error {
	if err := os.RemoveAll(filepath.Join(t.Client.HomeDir, snapshotStaging)); err != nil {
		return err
	}
	entries, err := os.ReadDir(filepath.Join(t.Client.HomeDir, "vms"))
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	for _, entry := range entries {
		id, ok := strings.CutPrefix(entry.Name(), snapshotVMPrefix)
		if !ok || !validID(id) {
			continue
		}
		if _, err := t.DiskSnapshot(id); errors.Is(err, errSnapshotNotFound) {
			if err := os.RemoveAll(t.snapshotDirectory(id)); err != nil {
				return err
			}
		}
	}
	return nil
}

// mountWorkspace puts the workspace volume a VM cloned from a snapshot
// already has back at the workspace. The volume carries its quota and the
// repository; a cold boot mounts it under /Volumes, or not at all.
func (t *TartRuntime) mountWorkspace(ctx context.Context, r *Record, workspaceGB int) error {
	if _, err := t.client(r).Exec(ctx, r.VMName(), "/bin/sh", "-c", `set -eu
work=/Users/runner/work
device=$(/usr/sbin/diskutil info -plist TuistSandboxWorkspace | /usr/bin/plutil -extract DeviceIdentifier raw -o - -)
at=$(/usr/sbin/diskutil info -plist "$device" | /usr/bin/plutil -extract MountPoint raw -o - - 2>/dev/null || true)
if [ "$at" != "$work" ]; then
	if [ -n "$at" ]; then /usr/bin/sudo -n /usr/sbin/diskutil unmount "$device"; fi
	/usr/bin/sudo -n /bin/mkdir -p "$work"
	/usr/bin/sudo -n /usr/sbin/diskutil mount -mountPoint "$work" "$device"
fi`); err != nil {
		return err
	}
	r.WorkspaceVolumeGB = workspaceGB
	return nil
}

func syncDirectory(path string) error {
	dir, err := os.Open(path)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}
