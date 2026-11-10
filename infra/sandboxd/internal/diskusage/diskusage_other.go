//go:build !linux

package diskusage

import (
	"os"

	"golang.org/x/sys/unix"
)

// Filesystem returns the size and the unprivileged free space of the
// filesystem holding path.
func Filesystem(path string) (total, available uint64, err error) {
	var stat unix.Statfs_t
	if err := unix.Statfs(path, &stat); err != nil {
		return 0, 0, err
	}
	bsize := uint64(stat.Bsize)
	return stat.Blocks * bsize, stat.Bavail * bsize, nil
}

// Only Linux exposes extent sharing; elsewhere the allocated blocks are
// the closest measure.
func exclusiveBytes(path string, info os.FileInfo) (uint64, error) {
	return allocatedBytes(path, info)
}
