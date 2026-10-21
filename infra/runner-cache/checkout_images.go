package cachevolumes

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type checkoutRunner func(ctx context.Context, dir string, env []string, name string, args ...string) ([]byte, error)

func (r checkoutRunner) run(ctx context.Context, dir string, name string, args ...string) ([]byte, error) {
	if r != nil {
		return r(ctx, dir, nil, name, args...)
	}
	return runCheckoutCommand(ctx, dir, nil, name, args...)
}

// APFSCheckoutImages keeps checkout masters in APFS sparse images. A guest
// attaches its clone itself, with the working tree at the volume's root.
type APFSCheckoutImages struct {
	Run func(ctx context.Context, dir string, env []string, name string, args ...string) ([]byte, error)
}

func (a *APFSCheckoutImages) MasterName() string { return "master.sparseimage" }

func (a *APFSCheckoutImages) Create(ctx context.Context, path string, bytes int64) error {
	_, err := checkoutRunner(a.Run).run(ctx, filepath.Dir(path), "hdiutil", "create", "-size", strconv.FormatInt(bytes/1_000_000, 10)+"m", "-type", "SPARSE", "-fs", "APFS", "-volname", "TuistCheckout", "-quiet", path)
	return err
}

func (a *APFSCheckoutImages) Clone(ctx context.Context, src, dst string) error {
	_, err := checkoutRunner(a.Run).run(ctx, "", "cp", "-c", src, dst)
	return err
}

func (a *APFSCheckoutImages) Attach(ctx context.Context, image, mount string, readOnly bool) error {
	args := []string{"attach", image}
	if readOnly {
		args = append(args, "-readonly")
	}
	_, err := checkoutRunner(a.Run).run(ctx, filepath.Dir(image), "hdiutil", append(args, "-nobrowse", "-noautoopen", "-quiet", "-mountpoint", mount)...)
	return err
}

func (a *APFSCheckoutImages) Detach(ctx context.Context, _, mount string) error {
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		if _, err = checkoutRunner(a.Run).run(ctx, "", "hdiutil", "detach", mount, "-quiet"); err == nil {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Second):
		}
	}
	return err
}

func (a *APFSCheckoutImages) Abandon(ctx context.Context, _, mount string) {
	if _, err := os.Stat(mount); err != nil {
		return
	}
	if _, err := checkoutRunner(a.Run).run(ctx, "", "hdiutil", "detach", mount, "-quiet"); err != nil {
		_, _ = checkoutRunner(a.Run).run(ctx, "", "hdiutil", "detach", mount, "-force", "-quiet")
	}
}

func (a *APFSCheckoutImages) Repository(mount string) string { return mount }

// Own does nothing: guests attach APFS images with owners ignored.
func (a *APFSCheckoutImages) Own(context.Context, string, int) error { return nil }

// Ext4CheckoutImages keeps checkout masters in ext4 images on the host's reflink
// filesystem. The host loop-mounts a job's clone, so the working tree sits in a
// directory beside the volume's own files, owned by the job's user.
type Ext4CheckoutImages struct {
	Run func(ctx context.Context, dir string, env []string, name string, args ...string) ([]byte, error)
}

const ext4CheckoutRepository = "checkout"

func (e *Ext4CheckoutImages) MasterName() string { return "master.img" }

// Create formats a sparse image. Inode tables and the journal are zeroed now,
// which costs nothing on a sparse file, so no clone's mount starts the kernel's
// background zeroing, which would unshare those blocks in every job.
func (e *Ext4CheckoutImages) Create(ctx context.Context, path string, bytes int64) error {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	err = file.Truncate(bytes)
	if closeErr := file.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	_, err = checkoutRunner(e.Run).run(ctx, "", "mkfs.ext4", "-F", "-q", "-m", "0", "-i", "65536", "-E", "lazy_itable_init=0,lazy_journal_init=0,nodiscard", path)
	return err
}

func (e *Ext4CheckoutImages) Clone(ctx context.Context, src, dst string) error {
	_, err := checkoutRunner(e.Run).run(ctx, "", "cp", "--reflink=always", "--", src, dst)
	return err
}

func (e *Ext4CheckoutImages) Attach(ctx context.Context, image, mount string, readOnly bool) error {
	args := []string{"--find", "--show", "--nooverlap"}
	options := "nodev,nosuid,noatime"
	if readOnly {
		args = append(args, "--read-only")
		options += ",ro"
	}
	out, err := checkoutRunner(e.Run).run(ctx, "", "losetup", append(args, image)...)
	if err != nil {
		return err
	}
	device := strings.TrimSpace(string(out))
	if !loopDevice.MatchString(device) {
		return errors.New("invalid loop device")
	}
	if _, err := checkoutRunner(e.Run).run(ctx, "", "mount", "-t", "ext4", "-o", options, device, mount); err != nil {
		_, _ = checkoutRunner(e.Run).run(context.WithoutCancel(ctx), "", "losetup", "--detach", device)
		return err
	}
	return nil
}

func (e *Ext4CheckoutImages) devices(ctx context.Context, image string) ([]string, error) {
	if _, err := os.Stat(image); os.IsNotExist(err) {
		return nil, nil
	}
	out, err := checkoutRunner(e.Run).run(ctx, "", "losetup", "--json", "--list", "--associated", image, "--output", "NAME")
	if err != nil {
		return nil, err
	}
	var list struct {
		Devices []struct {
			Name string `json:"name"`
		} `json:"loopdevices"`
	}
	if len(strings.TrimSpace(string(out))) == 0 {
		return nil, nil
	}
	if err := json.Unmarshal(out, &list); err != nil {
		return nil, err
	}
	devices := make([]string, 0, len(list.Devices))
	for _, device := range list.Devices {
		if !loopDevice.MatchString(device.Name) {
			return nil, errors.New("invalid loop device")
		}
		devices = append(devices, device.Name)
	}
	return devices, nil
}

func (e *Ext4CheckoutImages) Detach(ctx context.Context, image, mount string) error {
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		if _, err = checkoutRunner(e.Run).run(ctx, "", "umount", mount); err == nil || !mounted(mount) {
			err = nil
			break
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Second):
		}
	}
	if err != nil {
		return err
	}
	devices, err := e.devices(ctx, image)
	if err != nil {
		return err
	}
	for _, device := range devices {
		if _, err := checkoutRunner(e.Run).run(ctx, "", "losetup", "--detach", device); err != nil {
			return err
		}
	}
	// A busy loop device is only marked for removal; never install an image a
	// mount can still write to.
	if remaining, err := e.devices(ctx, image); err != nil || len(remaining) > 0 {
		return errors.Join(errors.New("loop device still attached after detach"), err)
	}
	return nil
}

func (e *Ext4CheckoutImages) Abandon(ctx context.Context, image, mount string) {
	if mounted(mount) {
		_, _ = checkoutRunner(e.Run).run(ctx, "", "umount", "--lazy", mount)
	}
	devices, _ := e.devices(ctx, image)
	for _, device := range devices {
		_, _ = checkoutRunner(e.Run).run(ctx, "", "losetup", "--detach", device)
	}
}

func (e *Ext4CheckoutImages) Repository(mount string) string {
	return filepath.Join(mount, ext4CheckoutRepository)
}

// Own gives the tree to the job's user. It runs on the host-built tree only, and
// never follows a link the checkout contains.
func (e *Ext4CheckoutImages) Own(_ context.Context, repo string, uid int) error {
	return filepath.WalkDir(repo, func(path string, _ fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		return os.Lchown(path, uid, -1)
	})
}

// mounted reports whether path is a mount point of another filesystem.
func mounted(path string) bool {
	info, err := os.Lstat(path)
	if err != nil || !info.IsDir() {
		return false
	}
	parent, err := os.Lstat(filepath.Dir(path))
	if err != nil {
		return false
	}
	return deviceOf(info) != deviceOf(parent)
}

func deviceOf(info os.FileInfo) uint64 {
	if stat, ok := info.Sys().(*syscall.Stat_t); ok {
		return uint64(stat.Dev)
	}
	return 0
}
