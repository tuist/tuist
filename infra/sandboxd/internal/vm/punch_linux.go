//go:build linux

package vm

import (
	"bytes"
	"errors"
	"io"
	"os"

	"golang.org/x/sys/unix"
)

// punchBlock is the granularity PunchZeros frees at: fine enough to catch
// the zero runs inside a guest's partly used 2 MiB regions, coarse enough
// that a memory image does not shatter into 4 KiB extents.
const punchBlock = 64 << 10

// PunchZeros frees the disk blocks of every all-zero punchBlock of the file
// (FALLOC_FL_PUNCH_HOLE, keeping its size), so a memory image uses disk for
// what the guest holds rather than for its whole memory. The holes read
// back as zeros, so readers see the same bytes. It reads only the file's
// data (SEEK_DATA), so an image that is mostly holes, such as a diff merged
// into a punched base, is scanned in the time its data takes. It returns
// the bytes it punched, which include ranges that were holes already.
func PunchZeros(path string) (int64, error) {
	f, err := os.OpenFile(path, os.O_RDWR|unix.O_NOFOLLOW, 0)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return 0, err
	}
	fd, size := int(f.Fd()), info.Size()
	var punched int64
	for offset := int64(0); offset < size; {
		data, err := unix.Seek(fd, offset, unix.SEEK_DATA)
		if errors.Is(err, unix.ENXIO) {
			return punched + size - offset, nil
		}
		if err != nil {
			// A filesystem without SEEK_DATA: scan the rest whole.
			n, scanErr := punchRange(f, offset, size)
			return punched + n, scanErr
		}
		hole, err := unix.Seek(fd, data, unix.SEEK_HOLE)
		if err != nil {
			hole = size
		}
		punched += data - offset
		n, err := punchRange(f, data, hole)
		punched += n
		if err != nil {
			return punched, err
		}
		offset = hole
	}
	return punched, nil
}

// punchRange punches the all-zero punchBlocks of [start, end) of f.
func punchRange(f *os.File, start, end int64) (int64, error) {
	var (
		buf            = make([]byte, 32*punchBlock)
		zero           = make([]byte, punchBlock)
		offset         = start
		runStart int64 = -1
		punched  int64
	)
	punch := func(to int64) error {
		if runStart < 0 {
			return nil
		}
		if err := unix.Fallocate(int(f.Fd()), unix.FALLOC_FL_PUNCH_HOLE|unix.FALLOC_FL_KEEP_SIZE, runStart, to-runStart); err != nil {
			return err
		}
		punched += to - runStart
		runStart = -1
		return nil
	}
	for offset < end {
		n, err := f.ReadAt(buf[:min(int64(len(buf)), end-offset)], offset)
		for i := 0; i < n; i += punchBlock {
			block := buf[i:min(i+punchBlock, n)]
			if len(block) == punchBlock && bytes.Equal(block, zero) {
				if runStart < 0 {
					runStart = offset + int64(i)
				}
				continue
			}
			if perr := punch(offset + int64(i)); perr != nil {
				return punched, perr
			}
		}
		offset += int64(n)
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return punched, err
		}
	}
	return punched, punch(offset)
}
