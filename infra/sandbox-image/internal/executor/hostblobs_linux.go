//go:build linux

package executor

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/mdlayher/vsock"
	"golang.org/x/sys/unix"
)

func dialHost() (net.Conn, error) { return vsock.Dial(vsock.Host, hostBlobPort, nil) }

// firstInputDrive is the guest name of input drive 0: Firecracker attaches
// the template's drives in order, the rootfs (vda) and workspace (vdb) first.
const firstInputDrive = 'c'

// capacityWait bounds how long the guest waits for a drive patch to show.
const capacityWait = 2 * time.Second

// mountTree mounts the input tree image the host attached to drive at dir:
// the image read-only, under an overlay whose upper layer in scratch takes
// whatever the action writes there, as it could into a materialized tree.
func mountTree(drive int, bytes int64, dir, scratch string) error {
	if drive < 0 || drive > 'z'-firstInputDrive || bytes <= 0 || bytes%512 != 0 {
		return fmt.Errorf("invalid input drive %d of %d bytes", drive, bytes)
	}
	name := "vd" + string(rune(firstInputDrive+drive))
	dev := "/dev/" + name
	// The host's drive patch reaches the guest as a capacity change. Until it
	// shows the device still is the placeholder; a size other than the
	// image's means a drive that is not the one the host attached.
	for deadline := time.Now().Add(capacityWait); ; time.Sleep(2 * time.Millisecond) {
		b, err := os.ReadFile("/sys/block/" + name + "/size")
		if err != nil {
			return err
		}
		sectors, err := strconv.ParseInt(strings.TrimSpace(string(b)), 10, 64)
		if err != nil {
			return err
		}
		if sectors*512 == bytes {
			break
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("%s holds %d bytes, want %d", dev, sectors*512, bytes)
		}
	}
	// The block layer may still cache the placeholder's sectors.
	f, err := os.OpenFile(dev, os.O_RDONLY, 0)
	if err != nil {
		return err
	}
	err = unix.IoctlSetInt(int(f.Fd()), unix.BLKFLSBUF, 0)
	f.Close()
	if err != nil {
		return fmt.Errorf("BLKFLSBUF %s: %w", dev, err)
	}
	lower, upper, work := filepath.Join(scratch, "lower"), filepath.Join(scratch, "upper"), filepath.Join(scratch, "work")
	for _, d := range []string{lower, upper, work} {
		if err := os.Mkdir(d, 0o755); err != nil {
			return err
		}
	}
	// The merged directory takes the upper layer's owner: the build user's,
	// like a materialized input directory.
	if err := os.Chown(upper, 1000, 1000); err != nil {
		return err
	}
	if err := unix.Mount(dev, lower, "ext4", unix.MS_RDONLY|unix.MS_NOSUID|unix.MS_NODEV, ""); err != nil {
		return fmt.Errorf("mount %s: %w", dev, err)
	}
	options := "lowerdir=" + lower + ",upperdir=" + upper + ",workdir=" + work
	if err := unix.Mount("overlay", dir, "overlay", unix.MS_NOSUID|unix.MS_NODEV, options); err != nil {
		unix.Unmount(lower, unix.MNT_DETACH)
		return fmt.Errorf("mount overlay on the input directory: %w", err)
	}
	return nil
}
