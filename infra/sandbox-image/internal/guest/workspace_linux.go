//go:build linux

package guest

import (
	"bufio"
	"context"
	"fmt"
	"os"
	osexec "os/exec"
	"strings"

	"golang.org/x/sys/unix"
)

// EnsureWorkspace mounts dev at target. With format it first unmounts anything
// already there, drops the block layer's cached pages, makes a fresh ext4 and
// mounts that. Without it the mount only happens when nothing is mounted yet.
//
// The flush matters because the template snapshot was taken with an empty
// disk attached: the guest may have cached its zero sectors, and the sandbox's
// own disk file has been substituted under the same device since.
func EnsureWorkspace(ctx context.Context, dev, target string, format bool) error {
	mounted, err := IsMountPoint(target)
	if err != nil {
		return err
	}
	if format {
		if mounted {
			if err := unix.Unmount(target, 0); err != nil {
				return fmt.Errorf("unmount %s before formatting: %w", target, err)
			}
		}
		if err := flushBuffers(dev); err != nil {
			return err
		}
		if err := mkfs(ctx, dev); err != nil {
			return err
		}
		return mount(dev, target)
	}
	if mounted {
		return nil
	}
	if err := flushBuffers(dev); err != nil {
		return err
	}
	return mount(dev, target)
}

// IsMountPoint reports whether target is the mount point of a current mount.
func IsMountPoint(target string) (bool, error) {
	f, err := os.Open("/proc/self/mountinfo")
	if err != nil {
		return false, err
	}
	defer f.Close()
	target = strings.TrimRight(target, "/")
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) > 4 && unescapeMountPath(fields[4]) == target {
			return true, nil
		}
	}
	return false, sc.Err()
}

func flushBuffers(dev string) error {
	f, err := os.OpenFile(dev, os.O_RDONLY, 0)
	if err != nil {
		return fmt.Errorf("open %s: %w", dev, err)
	}
	defer f.Close()
	if err := unix.IoctlSetInt(int(f.Fd()), unix.BLKFLSBUF, 0); err != nil {
		return fmt.Errorf("BLKFLSBUF %s: %w", dev, err)
	}
	return nil
}

func mkfs(ctx context.Context, dev string) error {
	cmd := osexec.CommandContext(ctx, "mkfs.ext4", "-q", "-F", "-L", "workspace", dev)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("mkfs.ext4 %s: %w: %s", dev, err, strings.TrimSpace(string(out)))
	}
	return nil
}

func mount(dev, target string) error {
	if err := os.MkdirAll(target, 0o755); err != nil {
		return err
	}
	if err := unix.Mount(dev, target, "ext4", 0, ""); err != nil {
		return fmt.Errorf("mount %s on %s: %w", dev, target, err)
	}
	return nil
}

// unescapeMountPath decodes the octal escapes mountinfo uses for spaces and
// the like.
func unescapeMountPath(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+3 < len(s) {
			var c byte
			if _, err := fmt.Sscanf(s[i+1:i+4], "%03o", &c); err == nil {
				b.WriteByte(c)
				i += 3
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}
