//go:build darwin

package podagent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func createCustomImage(ctx context.Context, path string, bytes int64) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	_, err := exec.CommandContext(ctx, "hdiutil", "create", "-sectors", strconv.FormatInt(bytes/512, 10), "-fs", "APFS", "-volname", "TuistCustomCache", "-type", "SPARSE", "-quiet", path).CombinedOutput()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	return err
}

var customDisk = regexp.MustCompile(`^/dev/disk[0-9]+$`)
var customPartition = regexp.MustCompile(`^/dev/disk[0-9]+s[0-9]+$`)

func verifyCustomImage(path string) (err error) {
	return inspectCustomImage(path, runCmd)
}

func inspectCustomImage(path string, run func(time.Duration, string, ...string) (string, error)) (err error) {
	// No APFS filesystem is mounted in the host kernel. fsck reads the raw
	// partition in userspace; -noautofsck prevents an implicit repair attempt.
	out, err := run(2*time.Minute, "hdiutil", "attach", path, "-readonly", "-nomount", "-noautofsck", "-nobrowse")
	if err != nil {
		return err
	}
	var disk, partition string
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		if disk == "" && customDisk.MatchString(fields[0]) {
			disk = fields[0]
		}
		if len(fields) > 1 && customPartition.MatchString(fields[0]) && fields[1] == "Apple_APFS" {
			partition = fields[0]
		}
	}
	if disk == "" {
		return errors.New("inspection returned no disk")
	}
	defer func() {
		if _, detachErr := run(time.Minute, "hdiutil", "detach", disk, "-quiet"); detachErr != nil {
			err = errors.Join(err, fmt.Errorf("detach inspected custom image: %w", detachErr))
		}
	}()
	if partition == "" {
		return errors.New("inspection returned no APFS partition")
	}
	_, err = run(2*time.Minute, "/sbin/fsck_apfs", "-n", strings.Replace(partition, "/dev/disk", "/dev/rdisk", 1))
	return err
}

// Discover the device by backing path, including a crash between attach and
// its output being read. Also reclaim inspection mounts from older agents.
func detachCustomInspection(path string) error {
	out, err := runCmd(time.Minute, "hdiutil", "info")
	if err != nil {
		return err
	}
	inspecting := false
	for _, line := range strings.Split(out, "\n") {
		if strings.HasPrefix(line, "image-path") {
			_, value, ok := strings.Cut(line, ":")
			inspecting = ok && strings.TrimSpace(value) == path
		}
		fields := strings.Fields(line)
		if inspecting && len(fields) > 0 && customDisk.MatchString(fields[0]) {
			if _, err := runCmd(time.Minute, "hdiutil", "detach", fields[0], "-quiet"); err != nil {
				return err
			}
			inspecting = false
		}
	}
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
