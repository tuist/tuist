package macosandbox

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// Disk admission reserves complete writable root disks (including APFS clone
// growth) and two memory images per VM, and what each disk snapshot holds.
// Half the filesystem stays outside the sandbox budget; the free-space check
// also protects current CI disk use. next is the ceiling of a VM or snapshot
// not yet cloned, so not in vms or snapshots.
func diskRoom(vms []tart.VM, snapshots, total, free uint64, nextMemoryMB int, next uint64) error {
	ceiling := next + snapshots
	for _, vm := range vms {
		if !isSandboxVM(vm.Name) {
			continue
		}
		if vm.Disk <= 0 || vm.Memory <= 0 || vm.Disk > 10000 || vm.Memory > 24576 {
			return errors.New("unknown sandbox disk ceiling")
		}
		// Tart JSON reports decimal GB; round the parsed whole GB upward.
		ceiling += sandboxCeiling((uint64(vm.Disk)+1)*1_000_000_000, vm.Memory)
	}
	const reserve = 20 * 1024 * 1024 * 1024
	if ceiling > total/2 || free < uint64(nextMemoryMB)*2*1024*1024+reserve {
		return fmt.Errorf("%w: sandbox disk reserve", ErrCapacity)
	}
	return nil
}

// sandboxCeiling is what diskRoom reserves for one sandbox VM: its writable
// root disk and two memory images.
func sandboxCeiling(rootDisk uint64, memoryMB int) uint64 {
	return rootDisk + uint64(memoryMB)*2*1024*1024 + 128*1024*1024
}

// diskReport gives the server what diskRoom decides with, so placement
// skips a host whose disk cannot take another sandbox instead of sending
// it a create the host refuses: half the filesystem as the budget, and
// the free space.
func diskReport(home string) protocol.DiskReport {
	var fs syscall.Statfs_t
	if syscall.Statfs(home, &fs) != nil {
		return protocol.DiskReport{}
	}
	total := uint64(fs.Blocks) * uint64(fs.Bsize)
	return protocol.DiskReport{TotalBytes: total, AvailableBytes: uint64(fs.Bavail) * uint64(fs.Bsize), BudgetBytes: total / 2}
}

// logStoredBytes logs what a saved sandbox VM's files hold on the host's
// disk, to size an archive of it. A clone of a stacked image gets an empty
// `overlay.asif` and reads everything else from the content store, so its
// allocated bytes are the session's own writes; the checkpoint is beside it.
func logStoredBytes(dir, id string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	fields := []any{"sandbox_id", id}
	var total int64
	for _, entry := range entries {
		info, err := entry.Info()
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		stat, ok := info.Sys().(*syscall.Stat_t)
		if !ok {
			continue
		}
		allocated := int64(stat.Blocks) * 512
		total += allocated
		if allocated >= 1<<20 {
			fields = append(fields, entry.Name(), allocated)
		}
		if entry.Name() == "overlay.asif" {
			fields = append(fields, "overlay_size", info.Size())
		}
	}
	slog.Info("macOS sandbox saved disk usage", append(fields, "total_bytes", total)...)
}

// rootDisk is the root disk ceiling diskRoom reserves per sandbox, the
// largest of the sandbox VMs in vms, or 0 when none reports its disk. Every
// sandbox VM is a clone of the template image, whose own size Tart may not
// report (a stacked image's `Disk` can be null).
func rootDisk(vms []tart.VM) int64 {
	var largest int64
	for _, vm := range vms {
		if isSandboxVM(vm.Name) && vm.Disk > 0 {
			largest = max(largest, (int64(vm.Disk)+1)*1_000_000_000)
		}
	}
	return largest
}

// learnRootDisk records the root disk ceiling for the host's report: the
// largest cached template image's size when Tart reports it, otherwise that
// of a sandbox VM already on the host. Every template is a runner image of
// the same disk size, so one ceiling covers them all. checkDisk refreshes it on every create,
// resume and save.
func (t *TartRuntime) learnRootDisk(ctx context.Context) error {
	vms, err := t.Client.List(ctx)
	if err != nil {
		return err
	}
	images := map[string]bool{}
	for _, image := range t.Templates.Images() {
		images[image] = true
	}
	var largest int64
	for _, vm := range vms {
		if vm.Source == "OCI" && images[vm.Name] && vm.Disk > 0 {
			largest = max(largest, (int64(vm.Disk)+1)*1_000_000_000)
		}
	}
	if largest > 0 {
		t.rootfs.Store(largest)
		return nil
	}
	for _, vm := range vms {
		if !strings.HasPrefix(vm.Name, sandboxVMPrefix) {
			continue
		}
		detail, err := t.Client.Get(ctx, vm.Name)
		if err != nil {
			return err
		}
		if detail != nil {
			if size := rootDisk([]tart.VM{*detail}); size > 0 {
				t.rootfs.Store(size)
				return nil
			}
		}
	}
	return nil
}
func isSandboxVM(name string) bool {
	return strings.HasPrefix(name, sandboxVMPrefix) || strings.HasPrefix(name, warmVMPrefix)
}

func (t *TartRuntime) checkDisk(ctx context.Context, r *Record) error {
	return t.admitDisk(ctx, t.client(r), r.MemoryMB, 0)
}

// roomForClone checks the disk for a VM not cloned yet, counting it at the
// template's root disk once known. Warm checks it before cloning, and the
// warm-host label follows it, so a host without room is neither offered warm
// Pods nor clones and deletes a VM for each one it refuses.
func (t *TartRuntime) roomForClone(ctx context.Context, c *tart.Client, memoryMB int) error {
	return t.admitDisk(ctx, c, memoryMB, sandboxCeiling(uint64(max(t.rootfs.Load(), 0)), memoryMB))
}

// filesystemSize answers the size and free space of the filesystem at path.
// A variable so tests can stand in a host-sized disk.
var filesystemSize = func(path string) (total, free uint64, err error) {
	var fs syscall.Statfs_t
	if err = syscall.Statfs(path, &fs); err != nil {
		return 0, 0, err
	}
	return uint64(fs.Blocks) * uint64(fs.Bsize), uint64(fs.Bavail) * uint64(fs.Bsize), nil
}

func (t *TartRuntime) admitDisk(ctx context.Context, c *tart.Client, memoryMB int, next uint64) error {
	total, free, err := filesystemSize(t.Client.HomeDir)
	if err != nil {
		return err
	}
	vms, err := c.List(ctx)
	if err != nil {
		return err
	}
	// list omits CPU/RAM; get supplies the configured memory ceiling.
	for i, vm := range vms {
		if !isSandboxVM(vm.Name) {
			continue
		}
		detail, err := c.Get(ctx, vm.Name)
		if err != nil {
			return err
		}
		if detail == nil {
			return errors.New("sandbox disappeared during disk admission")
		}
		vms[i] = *detail
	}
	if size := rootDisk(vms); size > 0 {
		t.rootfs.Store(size)
	}
	snapshots, err := t.DiskSnapshots()
	if err != nil {
		return err
	}
	return diskRoom(vms, snapshotBytes(snapshots), total, free, memoryMB, next)
}

func snapshotBytes(snapshots []protocol.DiskSnapshotInfo) uint64 {
	var total uint64
	for _, s := range snapshots {
		total += uint64(max(s.Bytes, 0))
	}
	return total
}

// hasImage reports whether the store has cached image. `tart get` opens only
// local VMs, so it is read from `tart list`, which names a cached image by the
// reference it was pulled as.
func hasImage(ctx context.Context, c *tart.Client, image string) (bool, error) {
	vms, err := c.List(ctx)
	if err != nil {
		return false, err
	}
	for _, vm := range vms {
		if vm.Source == "OCI" && vm.Name == image {
			return true, nil
		}
	}
	return false, nil
}

// Preparation is background work, but a cold image must still leave the CI
// disk floor intact. An already-cached immutable image needs no registry pull,
// and one the CI store at ciStore holds is cloned from it (seedImage).
func ensureImage(ctx context.Context, c *tart.Client, ciStore, image string) error {
	cached, err := hasImage(ctx, c, image)
	if err != nil || cached {
		return err
	}
	if err = seedImage(ciStore, c.HomeDir, image); err != nil {
		slog.Info("macOS sandbox template not cloned from the CI store", "image", image, "reason", err)
	} else if cached, err = hasImage(ctx, c, image); err != nil {
		return err
	} else if cached {
		slog.Info("cloned macOS sandbox template from the CI store", "image", image)
		return nil
	}
	var fs syscall.Statfs_t
	if err = syscall.Statfs(c.HomeDir, &fs); err != nil {
		return err
	}
	total, free := uint64(fs.Blocks)*uint64(fs.Bsize), uint64(fs.Bavail)*uint64(fs.Bsize)
	// Runner images occupy roughly 60 GiB; reserve 100 GiB before beginning a
	// cold pull, in addition to the same 30% free floor as CI image preparation.
	if free < total*3/10+100*1024*1024*1024 {
		return fmt.Errorf("%w: template disk floor", ErrCapacity)
	}
	// A cold Xcode image at background QoS can exceed the CI client's normal
	// twenty-minute deadline. The store is isolated and eviction runs separately.
	copy := *c
	copy.PullTimeout = templatePreparationTimeout
	started := time.Now()
	slog.Info("preparing macOS sandbox template", "image", image)
	err = copy.Pull(tart.InBackground(ctx), image)
	if err == nil {
		slog.Info("prepared macOS sandbox template", "image", image, "duration", time.Since(started))
	}
	return err
}
