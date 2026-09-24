//go:build linux

package cachevolumes

import (
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"golang.org/x/sys/unix"
)

func CheckFilesystem(device, path string) error {
	target, err := targetFD(path)
	if err != nil {
		return err
	}
	defer target.Close()
	same, err := sameDevice(target, device)
	if err != nil {
		return err
	}
	if !same {
		return errors.New("volume not mounted during write-back verification")
	}
	// syncfs reports delayed loop backing-file ENOSPC/EIO; fsck alone cannot
	// detect clean metadata whose file contents were lost during write-back.
	if err := unix.Syncfs(int(target.Fd())); err != nil {
		return err
	}
	data, err := os.ReadFile(filepath.Join("/sys/fs/ext4", filepath.Base(device), "errors_count"))
	if err != nil {
		return err
	}
	count, err := strconv.ParseUint(strings.TrimSpace(string(data)), 10, 64)
	if err != nil {
		return err
	}
	if count != 0 {
		return errors.New("ext4 reported errors during the job")
	}
	return nil
}

// Open beneath the pod root and operate through held descriptors. Never follow
// a job-controlled symlink when mounting, chmodding or unmounting host storage.
func targetFD(path string) (*os.File, error) {
	root, err := os.OpenRoot(filepath.Dir(path))
	if err != nil {
		return nil, err
	}
	defer root.Close()
	parent, err := root.Open(".")
	if err != nil {
		return nil, err
	}
	defer parent.Close()
	fd, err := unix.Openat(int(parent.Fd()), filepath.Base(path), unix.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW, 0)
	if err != nil {
		return nil, err
	}
	return os.NewFile(uintptr(fd), path), nil
}
func sameDevice(f *os.File, device string) (bool, error) {
	var stat, dev unix.Stat_t
	if err := unix.Fstat(int(f.Fd()), &stat); err != nil {
		return false, err
	}
	if err := unix.Stat(device, &dev); err != nil {
		return false, err
	}
	return uint64(stat.Dev) == uint64(dev.Rdev), nil
}
func Mount(device, path string) error {
	target, err := targetFD(path)
	if err != nil {
		return err
	}
	defer target.Close()
	same, err := sameDevice(target, device)
	if err != nil {
		return err
	}
	if !same {
		if err = unix.Mount(device, "/proc/self/fd/"+strconv.Itoa(int(target.Fd())), "ext4", unix.MS_NODEV|unix.MS_NOSUID, ""); err != nil {
			return err
		}
	}
	mounted, err := targetFD(path)
	if err != nil {
		return err
	}
	defer mounted.Close()
	same, err = sameDevice(mounted, device)
	if err != nil {
		return err
	}
	if !same {
		return errors.New("mount target changed")
	}
	return mounted.Chmod(0777)
}
func Unmount(device, path string) error {
	target, err := targetFD(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	defer target.Close()
	same, err := sameDevice(target, device)
	if err != nil {
		return err
	}
	if !same {
		return nil
	}
	// No job remains at this point. Close the mount reference before unmounting
	// (an open descriptor can make the mount busy), and reject final symlinks.
	if err := target.Close(); err != nil {
		return err
	}
	err = unix.Unmount(path, unix.UMOUNT_NOFOLLOW)
	if errors.Is(err, syscall.EINVAL) || errors.Is(err, syscall.ENOENT) {
		return nil
	}
	return err
}
func MeasureFS(path string) (int64, int64, error) {
	target, err := targetFD(path)
	if err != nil {
		return 0, 0, err
	}
	defer target.Close()
	var targetStat, parentStat unix.Stat_t
	if err := unix.Fstat(int(target.Fd()), &targetStat); err != nil {
		return 0, 0, err
	}
	if err := unix.Stat(filepath.Dir(path), &parentStat); err != nil {
		return 0, 0, err
	}
	if targetStat.Dev == parentStat.Dev {
		return 0, 0, errors.New("volume not mounted")
	}
	var st unix.Statfs_t
	err = unix.Fstatfs(int(target.Fd()), &st)
	if err != nil {
		return 0, 0, err
	}
	if st.Type != unix.EXT4_SUPER_MAGIC {
		return 0, 0, errors.New("volume not mounted")
	}
	return int64(st.Blocks-st.Bfree) * int64(st.Bsize), int64(st.Blocks) * int64(st.Bsize), nil
}

func FreeBytes(path string) (uint64, error) {
	var st unix.Statfs_t
	if err := unix.Statfs(path, &st); err != nil {
		return 0, err
	}
	return st.Bavail * uint64(st.Bsize), nil
}
