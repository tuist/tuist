//go:build linux

package main

import (
	"log/slog"
	"os"

	"golang.org/x/sys/unix"

	"github.com/tuist/tuist/infra/sandbox-image/internal/guest"
)

type mount struct {
	source, target, fstype string
	flags                  uintptr
	data                   string
}

// mounts lists the pseudo filesystems in dependency order. The kernel already
// mounts devtmpfs before init (CONFIG_DEVTMPFS_MOUNT); mounting is skipped for
// anything that is already a mount point.
var mounts = []mount{
	{"proc", "/proc", "proc", unix.MS_NOSUID | unix.MS_NOEXEC | unix.MS_NODEV, ""},
	{"sysfs", "/sys", "sysfs", unix.MS_NOSUID | unix.MS_NOEXEC | unix.MS_NODEV, ""},
	{"devtmpfs", "/dev", "devtmpfs", unix.MS_NOSUID, "mode=0755"},
	{"devpts", "/dev/pts", "devpts", unix.MS_NOSUID | unix.MS_NOEXEC, "gid=5,mode=620,ptmxmode=666"},
	{"tmpfs", "/dev/shm", "tmpfs", unix.MS_NOSUID | unix.MS_NODEV, "mode=1777"},
	{"tmpfs", "/run", "tmpfs", unix.MS_NOSUID | unix.MS_NODEV, "mode=0755"},
	{"tmpfs", "/tmp", "tmpfs", unix.MS_NOSUID | unix.MS_NODEV, "mode=1777"},
	{"cgroup2", "/sys/fs/cgroup", "cgroup2", unix.MS_NOSUID | unix.MS_NOEXEC | unix.MS_NODEV, ""},
}

func mountFilesystems(log *slog.Logger) {
	for _, m := range mounts {
		if err := os.MkdirAll(m.target, 0o755); err != nil {
			log.Error("mkdir", slog.String("target", m.target), slog.Any("error", err))
			continue
		}
		// Before /proc is up IsMountPoint fails; mounting proc twice only stacks
		// a second instance, so treat the failure as "not mounted".
		if mounted, err := guest.IsMountPoint(m.target); err == nil && mounted {
			continue
		}
		if err := unix.Mount(m.source, m.target, m.fstype, m.flags, m.data); err != nil {
			log.Error("mount", slog.String("target", m.target), slog.String("fstype", m.fstype), slog.Any("error", err))
		}
	}
}
