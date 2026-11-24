package sandbox

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

// rootfsGrowTimeout bounds the guest side of a rootfs growth, inside the
// server's 120 s budget for a create or resume.
const rootfsGrowTimeout = 30 * time.Second

// growRootfs gives a running sandbox the rootfs size of its template on this
// node when its own rootfs is smaller: a sandbox keeps the rootfs it was
// created with, so one created before a template grew would otherwise fill
// up long before newer ones. The file is extended sparsely, Firecracker
// re-reads its size on a drive patch and tells the guest, and the guest
// grows the mounted ext4 online with resize2fs, which every template's
// rootfs ships (old sandboxes run the sbx-agent of their own rootfs, so this
// uses a plain exec rather than a new agent op). The target is the largest
// rootfs of the template's tags here, which is what the server reserves for
// the sandbox (`templates[].rootfs_bytes`), so the growth needs no more of
// the node's disk budget than the sandbox already holds.
//
// It never fails the caller: the sandbox runs either way. A growth the
// guest did not finish stays recorded in the metadata and is retried on
// the next resume. Disks still arriving from an archive are left alone
// until a later resume. The caller holds sb.opMu.
func (m *Manager) growRootfs(ctx context.Context, sb *Sandbox, inst vm.Instance, agent vsock.Agent, log *slog.Logger) {
	sb.mu.Lock()
	tmpl := sb.meta.Template
	pending := sb.meta.RootfsGrowPending
	lazy := sb.lazy != nil
	sb.mu.Unlock()
	if lazy || agent == nil {
		return
	}
	target := m.templateRootfsBytes(tmpl)
	size, grew, err := extendFile(filepath.Join(sb.root, firecracker.RootfsPath), target)
	if err != nil {
		log.Warn("rootfs not grown to its template's size", "error", err, "bytes", target)
		return
	}
	if !grew && !pending {
		return
	}
	if grew {
		if err := m.setRootfsGrowPending(sb, true); err != nil {
			log.Warn("recording the rootfs growth", "error", err)
		}
	}
	started := time.Now()
	if err := m.growGuestRootfs(ctx, inst, agent, size); err != nil {
		log.Warn("guest root filesystem not grown; retrying on the next resume", "error", err, "bytes", size)
		return
	}
	if err := m.setRootfsGrowPending(sb, false); err != nil {
		log.Warn("recording the rootfs growth", "error", err)
	}
	log.Info("rootfs grown to its template's size", "bytes", size, "duration", time.Since(started))
}

// templateRootfsBytes is the largest rootfs among the node's tags of the
// template, as reported to the server, or 0 when the node has none.
func (m *Manager) templateRootfsBytes(name string) int64 {
	templates, err := m.store.List()
	if err != nil {
		return 0
	}
	var largest int64
	for _, t := range templates {
		if t.Name == name {
			largest = max(largest, vm.FileSize(t.Rootfs()))
		}
	}
	return largest
}

// extendFile makes the regular file at path at least size bytes long
// (sparse) and returns its size afterwards. The jail directory belongs to
// the jailed Firecracker's uid, so a planted symlink is refused rather than
// followed.
func extendFile(path string, size int64) (int64, bool, error) {
	file, err := os.OpenFile(path, os.O_WRONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return 0, false, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return 0, false, err
	}
	if !info.Mode().IsRegular() {
		return 0, false, fmt.Errorf("%s is not a regular file", path)
	}
	if info.Size() >= size {
		return info.Size(), false, nil
	}
	if err := file.Truncate(size); err != nil {
		return 0, false, err
	}
	return size, true, nil
}

func (m *Manager) setRootfsGrowPending(sb *Sandbox, pending bool) error {
	sb.mu.Lock()
	defer sb.mu.Unlock()
	if sb.meta.RootfsGrowPending == pending {
		return nil
	}
	sb.meta.RootfsGrowPending = pending
	return sb.meta.Save(sb.root)
}

// growGuestRootfs makes the guest see a rootfs of size bytes and grows its
// filesystem to fill it. The patch is needed after a memory restore too:
// Firecracker reopens the file at its new size, but the guest kept the
// capacity it had cached before the pause.
func (m *Manager) growGuestRootfs(ctx context.Context, inst vm.Instance, agent vsock.Agent, size int64) error {
	ctx, cancel := context.WithTimeout(ctx, rootfsGrowTimeout)
	defer cancel()
	if err := inst.API().PatchDrive(ctx, firecracker.DrivePatch{DriveID: firecracker.RootDriveID, PathOnHost: inst.GuestPath(firecracker.RootfsPath)}); err != nil {
		return fmt.Errorf("patching the rootfs drive: %w", err)
	}
	// The guest applies the new capacity asynchronously after the patch's
	// config interrupt; resize2fs would find nothing to do before it.
	script := fmt.Sprintf(`for i in $(seq 100); do
  [ $(( $(cat /sys/block/vda/size) * 512 )) -ge %d ] && exec resize2fs /dev/vda
  sleep 0.1
done
echo "/dev/vda is still $(( $(cat /sys/block/vda/size) * 512 )) bytes" >&2
exit 1`, size)
	var out strings.Builder
	code, err := vsock.RunProcess(ctx, agent, vsock.ExecRequest{Cmd: []string{"/bin/sh", "-c", script}, Cwd: "/", TimeoutMs: rootfsGrowTimeout.Milliseconds()}, func(_ string, data []byte) {
		if out.Len() < 4096 {
			out.Write(data)
		}
	})
	if err != nil {
		return err
	}
	if code != 0 {
		return fmt.Errorf("resize2fs exited with %d: %s", code, strings.TrimSpace(out.String()))
	}
	return nil
}
