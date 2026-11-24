// Package sparse finds the bytes of a disk image worth storing: the regions
// the filesystem reports as data, and the runs within them that are not all
// zeros. Runner cache masters (TCVSPRS1) and sandbox archives (SBXARC1) frame
// these runs differently but store the same ones, so a sparse image costs only
// the blocks a job or guest wrote in either. sandboxd imports this package; a
// change here changes its image too.
package sparse

import (
	"bytes"
	"errors"
	"os"

	"golang.org/x/sys/unix"
)

// ZeroChunk is the granularity of zero detection. Readers of both formats
// accept runs of any length up to the writer's buffer, so changing it changes
// only how much is stored.
const ZeroChunk = 128 << 10

// NextData is the first offset at or after off that holds data, or size when
// only a hole remains.
func NextData(f *os.File, off, size int64) (int64, error) {
	pos, err := unix.Seek(int(f.Fd()), off, unix.SEEK_DATA)
	if errors.Is(err, unix.ENXIO) {
		return size, nil
	}
	if err != nil {
		return off, err
	}
	return min(pos, size), nil
}

// Extents visits the regions the filesystem reports as holding data, in
// order. A filesystem without hole reporting is visited as one extent.
func Extents(f *os.File, size int64, visit func(offset, length int64) error) error {
	for offset := int64(0); offset < size; {
		start, err := NextData(f, offset, size)
		if err != nil {
			if offset == 0 && (errors.Is(err, unix.EINVAL) || errors.Is(err, unix.ENOTSUP) || errors.Is(err, unix.EOPNOTSUPP)) {
				return visit(0, size)
			}
			return err
		}
		if start >= size {
			return nil
		}
		end, err := unix.Seek(int(f.Fd()), start, unix.SEEK_HOLE)
		if err != nil {
			return err
		}
		end = min(end, size)
		if end <= start {
			return errors.New("image extent map changed while reading it")
		}
		if err = visit(start, end-start); err != nil {
			return err
		}
		offset = end
	}
	return nil
}

// NonZeroRuns visits each run of buf, split at ZeroChunk boundaries from its
// start, that holds a non-zero byte. Adjacent non-zero chunks form one run, so
// a fully written buffer is a single run.
func NonZeroRuns(buf []byte, visit func(start, end int) error) error {
	n := len(buf)
	for start := 0; start < n; {
		if IsZero(buf[start:min(start+ZeroChunk, n)]) {
			start += ZeroChunk
			continue
		}
		end := start + ZeroChunk
		for end < n && !IsZero(buf[end:min(end+ZeroChunk, n)]) {
			end += ZeroChunk
		}
		end = min(end, n)
		if err := visit(start, end); err != nil {
			return err
		}
		start = end
	}
	return nil
}

var zeros = make([]byte, ZeroChunk)

// IsZero reports whether b holds only zero bytes.
func IsZero(b []byte) bool {
	for len(b) > 0 {
		n := min(len(b), ZeroChunk)
		if !bytes.Equal(b[:n], zeros[:n]) {
			return false
		}
		b = b[n:]
	}
	return true
}
