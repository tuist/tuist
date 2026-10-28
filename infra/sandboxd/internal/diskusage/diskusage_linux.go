//go:build linux

package diskusage

import (
	"errors"
	"math"
	"os"
	"unsafe"

	"golang.org/x/sys/unix"
)

const (
	fsIocFiemap        = 0xC020660B
	fiemapExtentLast   = 0x0001
	fiemapExtentShared = 0x2000
	fiemapBatch        = 512
)

// Layouts of struct fiemap and struct fiemap_extent from
// include/uapi/linux/fiemap.h, which golang.org/x/sys does not expose.
type fiemapHeader struct {
	Start         uint64
	Length        uint64
	Flags         uint32
	MappedExtents uint32
	ExtentCount   uint32
	Reserved      uint32
}

type fiemapExtent struct {
	Logical    uint64
	Physical   uint64
	Length     uint64
	Reserved64 [2]uint64
	Flags      uint32
	Reserved   [3]uint32
}

type fiemapRequest struct {
	Header  fiemapHeader
	Extents [fiemapBatch]fiemapExtent
}

// Filesystem returns the size and the unprivileged free space of the
// filesystem holding path.
func Filesystem(path string) (total, available uint64, err error) {
	var stat unix.Statfs_t
	if err := unix.Statfs(path, &stat); err != nil {
		return 0, 0, err
	}
	bsize := uint64(stat.Bsize) //nolint:gosec // Bsize is never negative.
	return stat.Blocks * bsize, stat.Bavail * bsize, nil
}

// exclusiveBytes sums the extents of the file that no other inode shares
// (FIEMAP_EXTENT_SHARED is how XFS reports reflinked blocks). Filesystems
// without FIEMAP fall back to the inode's allocated blocks.
func exclusiveBytes(path string, info os.FileInfo) (uint64, error) {
	file, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer file.Close()

	var (
		total uint64
		start uint64
		req   fiemapRequest
	)
	for {
		req.Header = fiemapHeader{Start: start, Length: math.MaxUint64 - start, ExtentCount: fiemapBatch}
		_, _, errno := unix.Syscall(unix.SYS_IOCTL, file.Fd(), fsIocFiemap, uintptr(unsafe.Pointer(&req)))
		if errno != 0 {
			if errors.Is(errno, unix.EOPNOTSUPP) || errors.Is(errno, unix.ENOTTY) || errors.Is(errno, unix.EINVAL) {
				return allocatedBytes(path, info)
			}
			return 0, errno
		}
		mapped := int(req.Header.MappedExtents)
		if mapped == 0 {
			return total, nil
		}
		for i := range mapped {
			extent := req.Extents[i]
			if extent.Flags&fiemapExtentShared == 0 {
				total += extent.Length
			}
			if extent.Flags&fiemapExtentLast != 0 {
				return total, nil
			}
		}
		last := req.Extents[mapped-1]
		next := last.Logical + last.Length
		if next <= start || mapped < fiemapBatch {
			return total, nil
		}
		start = next
	}
}
