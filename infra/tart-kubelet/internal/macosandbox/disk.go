package macosandbox

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"syscall"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// Disk admission reserves complete writable root disks (including APFS clone
// growth) and two memory images per VM. Half the filesystem stays outside the
// sandbox budget; the free-space check also protects current CI disk use.
func diskRoom(vms []tart.VM, total, free uint64, nextMemoryMB int) error {
	var ceiling uint64
	for _, vm := range vms {
		if !strings.HasPrefix(vm.Name, "sbx-") {
			continue
		}
		if vm.Disk <= 0 || vm.Memory <= 0 || vm.Disk > 10000 || vm.Memory > 24576 {
			return errors.New("unknown sandbox disk ceiling")
		}
		// Tart JSON reports decimal GB; round the parsed whole GB upward.
		ceiling += (uint64(vm.Disk)+1)*1_000_000_000 + uint64(vm.Memory)*2*1024*1024 + 128*1024*1024
	}
	const reserve = 20 * 1024 * 1024 * 1024
	if ceiling > total/2 || free < uint64(nextMemoryMB)*2*1024*1024+reserve {
		return fmt.Errorf("%w: sandbox disk reserve", ErrCapacity)
	}
	return nil
}
func (t *TartRuntime) checkDisk(ctx context.Context, r *Record) error {
	var fs syscall.Statfs_t
	if err := syscall.Statfs(t.Client.HomeDir, &fs); err != nil {
		return err
	}
	vms, err := t.client(r).List(ctx)
	if err != nil {
		return err
	}
	// list omits CPU/RAM; get supplies the configured memory ceiling.
	for i, vm := range vms {
		if !strings.HasPrefix(vm.Name, "sbx-") {
			continue
		}
		detail, err := t.client(r).Get(ctx, vm.Name)
		if err != nil {
			return err
		}
		if detail == nil {
			return errors.New("sandbox disappeared during disk admission")
		}
		vms[i] = *detail
	}
	return diskRoom(vms, uint64(fs.Blocks)*uint64(fs.Bsize), uint64(fs.Bavail)*uint64(fs.Bsize), r.MemoryMB)
}

// Preparation is background work, but a cold image must still leave the CI
// disk floor intact. An already-cached immutable image needs no registry pull.
func ensureImage(ctx context.Context, c *tart.Client, image string) error {
	existing, err := c.Get(ctx, image)
	if err != nil {
		return err
	}
	if existing != nil {
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
	return c.Pull(tart.InBackground(ctx), image)
}
