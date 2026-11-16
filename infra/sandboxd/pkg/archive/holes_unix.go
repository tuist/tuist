//go:build linux || darwin

package archive

import (
	"errors"
	"os"

	"golang.org/x/sys/unix"
)

// nextData is the first offset at or after off that holds data, or size
// when only a hole remains. A filesystem that cannot tell reports all of
// the file as data.
func nextData(f *os.File, off, size int64) (int64, error) {
	pos, err := unix.Seek(int(f.Fd()), off, unix.SEEK_DATA)
	switch {
	case errors.Is(err, unix.ENXIO):
		return size, nil
	case err != nil:
		return off, nil
	}
	return min(pos, size), nil
}

// nextHole is the first offset after off where a hole starts, or size.
func nextHole(f *os.File, off, size int64) (int64, error) {
	pos, err := unix.Seek(int(f.Fd()), off, unix.SEEK_HOLE)
	if err != nil {
		return size, nil
	}
	return min(pos, size), nil
}
