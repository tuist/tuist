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
// back as zeros, so readers see the same bytes. It returns the bytes it
// punched, which include ranges that were holes already.
func PunchZeros(path string) (int64, error) {
	f, err := os.OpenFile(path, os.O_RDWR|unix.O_NOFOLLOW, 0)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	var (
		buf      = make([]byte, 32*punchBlock)
		zero     = make([]byte, punchBlock)
		offset   int64
		runStart int64 = -1
		punched  int64
	)
	punch := func(end int64) error {
		if runStart < 0 {
			return nil
		}
		if err := unix.Fallocate(int(f.Fd()), unix.FALLOC_FL_PUNCH_HOLE|unix.FALLOC_FL_KEEP_SIZE, runStart, end-runStart); err != nil {
			return err
		}
		punched += end - runStart
		runStart = -1
		return nil
	}
	for {
		n, err := f.ReadAt(buf, offset)
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
			return punched, punch(offset)
		}
		if err != nil {
			return punched, err
		}
	}
}
