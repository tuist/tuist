//go:build darwin

package podagent

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"time"
)

func createCustomImage(path string, bytes int64) error {
	_, err := runCmd(2*time.Minute, "hdiutil", "create", "-sectors", strconv.FormatInt(bytes/512, 10), "-fs", "APFS", "-volname", "TuistCustomCache", "-type", "SPARSE", "-quiet", path)
	return err
}
func verifyCustomImage(path string) (used, capacity int64, err error) {
	mount := path + ".mount"
	if err = os.Mkdir(mount, 0700); err != nil {
		return 0, 0, err
	}
	defer os.Remove(mount)
	if _, err = runCmd(2*time.Minute, "hdiutil", "attach", path, "-readonly", "-owners", "off", "-nobrowse", "-quiet", "-mountpoint", mount); err != nil {
		return 0, 0, err
	}
	defer func() {
		if _, e := runCmd(time.Minute, "hdiutil", "detach", mount, "-quiet"); e != nil {
			err = fmt.Errorf("detach inspected custom image: %w", e)
		}
	}()
	_, err = runCmd(2*time.Minute, "diskutil", "verifyVolume", mount)
	if err != nil {
		return 0, 0, err
	}
	var stat syscall.Statfs_t
	if err = syscall.Statfs(mount, &stat); err != nil {
		return 0, 0, err
	}
	return int64(stat.Blocks-stat.Bfree) * int64(stat.Bsize), int64(stat.Blocks) * int64(stat.Bsize), nil
}

// A process crash during verification can leave the read-only device mounted.
// Keep its path deterministic so poisoned-branch cleanup can release it later.
func detachCustomInspection(path string) error {
	mount := path + ".mount"
	info, err := os.Stat(mount)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	parent, err := os.Stat(filepath.Dir(mount))
	if err != nil {
		return err
	}
	if info.Sys().(*syscall.Stat_t).Dev != parent.Sys().(*syscall.Stat_t).Dev {
		if _, err = runCmd(time.Minute, "hdiutil", "detach", mount, "-quiet"); err != nil {
			return err
		}
	}
	return os.Remove(mount)
}
