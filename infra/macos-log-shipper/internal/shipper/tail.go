package shipper

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"syscall"
)

// maxChunkBytes bounds how much a single read pulls off a file. The file on
// disk is the shipper's buffer — there is no in-memory queue — so a host that
// could not reach Loki for a day catches up in chunks of this size rather than
// building one push body large enough for Loki to reject.
const maxChunkBytes = 1 << 20

// ReadResult is one poll's worth of progress on a file.
type ReadResult struct {
	Lines []string
	// Next is where to resume. It stops short of a trailing partial line so a
	// half-written line is re-read whole on the next poll instead of shipping
	// as two fragments.
	Next Position
	// Restarted is true when the file was replaced or truncated since the last
	// poll, so the caller knows the offset reset was intentional.
	Restarted bool
}

// statFile returns the file's inode and size.
func statFile(path string) (inode uint64, size int64, err error) {
	info, err := os.Stat(path)
	if err != nil {
		return 0, 0, err
	}
	sys, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return 0, info.Size(), fmt.Errorf("stat %s: no inode information", path)
	}
	return uint64(sys.Ino), info.Size(), nil
}

// ReadNew reads whatever has been appended to path since from, returning
// complete lines only.
//
// The file is opened and closed on every poll rather than held open across
// them. Holding the descriptor is how a tailer keeps reading a rotated file to
// its end, but it is also how a tailer keeps a deleted multi-gigabyte file
// pinned against the disk — and these Mac minis already run close enough to
// full that a golden-image GC exists to claw space back. Re-opening trades the
// last few lines of a rotated file for never pinning one.
func ReadNew(path string, from Position, exists bool) (ReadResult, error) {
	inode, size, err := statFile(path)
	if err != nil {
		return ReadResult{}, err
	}

	res := ReadResult{Next: Position{Inode: inode, Offset: from.Offset}}
	switch {
	case !exists:
		// First sight of this file. Start at the end: /var/log/tart-kubelet.log
		// is never rotated, so on a host that has been up for months byte 0 is
		// months of history nobody asked for and Grafana Cloud would reject
		// most of it as too old anyway.
		res.Next = Position{Inode: inode, Offset: size}
		return res, nil
	case inode != from.Inode, size < from.Offset:
		// Replaced or truncated — the stored offset points into a file that no
		// longer exists, or past the end of the one that does.
		res.Restarted = true
		res.Next = Position{Inode: inode, Offset: 0}
	}

	if size <= res.Next.Offset {
		return res, nil
	}

	f, err := os.Open(path)
	if err != nil {
		return res, err
	}
	defer f.Close()

	if _, err := f.Seek(res.Next.Offset, io.SeekStart); err != nil {
		return res, fmt.Errorf("seek %s: %w", path, err)
	}
	buf := make([]byte, min64(size-res.Next.Offset, maxChunkBytes))
	n, err := io.ReadFull(f, buf)
	if err != nil && !errors.Is(err, io.ErrUnexpectedEOF) && !errors.Is(err, io.EOF) {
		return res, fmt.Errorf("read %s: %w", path, err)
	}
	buf = buf[:n]

	consumed := len(buf)
	if idx := bytes.LastIndexByte(buf, '\n'); idx >= 0 {
		consumed = idx + 1
	} else if consumed < maxChunkBytes {
		// No newline and the chunk isn't full: the writer is mid-line. Leave it
		// for the next poll.
		return res, nil
	}
	// A full chunk with no newline is a line longer than maxChunkBytes. Emit it
	// as-is and move on; refusing to advance would wedge the file forever.

	for _, line := range bytes.Split(buf[:consumed], []byte{'\n'}) {
		line = bytes.TrimRight(line, "\r")
		if len(line) == 0 {
			continue
		}
		res.Lines = append(res.Lines, string(line))
	}
	res.Next.Offset += int64(consumed)
	return res, nil
}

func min64(a, b int64) int64 {
	if a < b {
		return a
	}
	return b
}
