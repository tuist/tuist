package driver

import (
	"fmt"

	"golang.org/x/sys/unix"
)

type OSHost struct{}

func (OSHost) FSStats(path string) (FSStats, error) {
	var st unix.Statfs_t
	if err := unix.Statfs(path, &st); err != nil {
		return FSStats{}, err
	}
	blockSize := st.Frsize
	if blockSize == 0 {
		blockSize = st.Bsize
	}
	total := int64(st.Blocks) * blockSize
	return FSStats{
		TotalBytes:      total,
		AvailableBytes:  int64(st.Bavail) * blockSize,
		UsedBytes:       total - int64(st.Bfree)*blockSize,
		TotalInodes:     int64(st.Files),
		AvailableInodes: int64(st.Ffree),
		UsedInodes:      int64(st.Files) - int64(st.Ffree),
	}, nil
}

func (OSHost) DeviceNumber(path string) (string, error) {
	var st unix.Stat_t
	if err := unix.Stat(path, &st); err != nil {
		return "", err
	}
	if st.Mode&unix.S_IFMT != unix.S_IFBLK {
		return "", fmt.Errorf("%s is not a block device", path)
	}
	return fmt.Sprintf("%d:%d", unix.Major(st.Rdev), unix.Minor(st.Rdev)), nil
}
