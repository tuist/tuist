package cachevolumes

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"io"
	"os"

	"github.com/klauspost/compress/zstd"
	"golang.org/x/sys/unix"
)

// An archive is a zstd stream holding the image's logical size followed by its
// non-zero extents, each as offset, length and bytes, and a zero-length
// terminator. Images have a fixed 20 GB logical length but hold little data, so
// both directions skip holes and zero chunks instead of streaming the full
// length. Masters published before this format are single gzip streams of the
// full image; restoration still accepts them.
const sparseArchiveMagic = "TCVSPRS1"

const (
	zeroChunk        = 128 * 1024
	archiveBuffer    = 4 << 20
	archiveMaxWindow = 64 << 20
)

var (
	zstdFrameMagic = []byte{0x28, 0xb5, 0x2f, 0xfd}
	errArchive     = errors.New("invalid cache image archive")
)

// CompressImage writes an image's publishable archive and returns its inventory
// and archive digests. The shared object protocol verifies the archive bytes, not
// the image bytes.
func CompressImage(src, dst string) (string, string, error) {
	in, err := os.Open(src)
	if err != nil {
		return "", "", err
	}
	defer in.Close()
	info, err := in.Stat()
	if err != nil {
		return "", "", err
	}
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if err != nil {
		return "", "", err
	}
	defer out.Close()
	inventory, content := sha1.New(), sha256.New()
	zw, err := zstd.NewWriter(io.MultiWriter(out, inventory, content), zstd.WithEncoderLevel(zstd.SpeedDefault))
	if err != nil {
		return "", "", err
	}
	defer zw.Close()
	header := make([]byte, 16)
	copy(header, sparseArchiveMagic)
	binary.BigEndian.PutUint64(header[8:], uint64(info.Size()))
	if _, err = zw.Write(header); err != nil {
		return "", "", err
	}
	buf := make([]byte, archiveBuffer)
	err = dataExtents(in, info.Size(), func(offset, length int64) error {
		return writeExtents(zw, in, offset, length, buf)
	})
	if err != nil {
		return "", "", err
	}
	if _, err = zw.Write(make([]byte, 16)); err != nil {
		return "", "", err
	}
	if err = zw.Close(); err != nil {
		return "", "", err
	}
	if err = out.Sync(); err != nil {
		return "", "", err
	}
	return hex.EncodeToString(inventory.Sum(nil)), hex.EncodeToString(content.Sum(nil)), nil
}

// dataExtents visits the regions the filesystem reports as holding data. A
// filesystem without hole reporting is visited as one extent.
func dataExtents(f *os.File, size int64, visit func(int64, int64) error) error {
	fd := int(f.Fd())
	for offset := int64(0); offset < size; {
		start, err := unix.Seek(fd, offset, unix.SEEK_DATA)
		if errors.Is(err, unix.ENXIO) {
			return nil
		}
		if err != nil {
			if offset == 0 && (errors.Is(err, unix.EINVAL) || errors.Is(err, unix.ENOTSUP) || errors.Is(err, unix.EOPNOTSUPP)) {
				return visit(0, size)
			}
			return err
		}
		if start >= size {
			return nil
		}
		end, err := unix.Seek(fd, start, unix.SEEK_HOLE)
		if err != nil {
			return err
		}
		end = min(end, size)
		if end <= start {
			return errors.New("cache image extent map changed during compression")
		}
		if err = visit(start, end-start); err != nil {
			return err
		}
		offset = end
	}
	return nil
}

// writeExtents records the non-zero runs of one data extent. Allocated zero
// blocks are left out so the restored image stays sparse.
func writeExtents(w io.Writer, in *os.File, offset, length int64, buf []byte) error {
	record := make([]byte, 16)
	for length > 0 {
		n := int(min(int64(len(buf)), length))
		if _, err := in.ReadAt(buf[:n], offset); err != nil {
			return err
		}
		for start := 0; start < n; {
			if isZero(buf[start:min(start+zeroChunk, n)]) {
				start += zeroChunk
				continue
			}
			end := start + zeroChunk
			for end < n && !isZero(buf[end:min(end+zeroChunk, n)]) {
				end += zeroChunk
			}
			end = min(end, n)
			binary.BigEndian.PutUint64(record, uint64(offset)+uint64(start))
			binary.BigEndian.PutUint64(record[8:], uint64(end-start))
			if _, err := w.Write(record); err != nil {
				return err
			}
			if _, err := w.Write(buf[start:end]); err != nil {
				return err
			}
			start = end
		}
		offset += int64(n)
		length -= int64(n)
	}
	return nil
}

var zeros = make([]byte, zeroChunk)

func isZero(b []byte) bool { return bytes.Equal(b, zeros[:len(b)]) }

// RestoreImage validates the transferred bytes before the caller installs the
// image as a master. Both compressed and expanded input are bounded.
func RestoreImage(ctx context.Context, src io.Reader, dst, digest string, maxBytes int64) error {
	h := sha256.New()
	// Incompressible payloads can grow slightly when compressed. Bound that
	// overhead separately while retaining the exact limit on image bytes.
	bounded := &io.LimitedReader{R: src, N: maxBytes + maxBytes/100 + (1 << 20) + 1}
	in := bufio.NewReaderSize(io.TeeReader(bounded, h), 64*1024)
	magic, err := in.Peek(len(zstdFrameMagic))
	if err != nil {
		if errors.Is(err, io.EOF) {
			return errors.New("empty cache image")
		}
		return err
	}
	sparse := bytes.Equal(magic, zstdFrameMagic)
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer out.Close()
	valid := false
	defer func() {
		if !valid {
			os.Remove(dst)
		}
	}()
	var total int64
	if sparse {
		total, err = restoreSparse(ctx, in, out, maxBytes)
	} else {
		total, err = restoreGzip(ctx, in, out, maxBytes)
	}
	if err != nil {
		return err
	}
	if _, err = io.Copy(io.Discard, in); err != nil {
		return err
	}
	if bounded.N <= 0 || hex.EncodeToString(h.Sum(nil)) != digest {
		return errors.New("cache image checksum mismatch")
	}
	if total == 0 {
		return errors.New("empty cache image")
	}
	if err = out.Truncate(total); err != nil {
		return err
	}
	if err = out.Sync(); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	valid = true
	return nil
}

func restoreSparse(ctx context.Context, src io.Reader, out *os.File, maxBytes int64) (int64, error) {
	zr, err := zstd.NewReader(src, zstd.WithDecoderMaxWindow(archiveMaxWindow))
	if err != nil {
		return 0, err
	}
	defer zr.Close()
	header := make([]byte, 16)
	if _, err = io.ReadFull(zr, header); err != nil {
		return 0, err
	}
	if string(header[:8]) != sparseArchiveMagic {
		return 0, errArchive
	}
	size := binary.BigEndian.Uint64(header[8:])
	if size > uint64(maxBytes) {
		return 0, errors.New("cache image exceeds capacity")
	}
	buf := make([]byte, archiveBuffer)
	var next uint64
	for {
		if err := ctx.Err(); err != nil {
			return 0, err
		}
		if _, err = io.ReadFull(zr, header); err != nil {
			return 0, err
		}
		offset, length := binary.BigEndian.Uint64(header), binary.BigEndian.Uint64(header[8:])
		if length == 0 {
			break
		}
		if offset < next || offset > size || length > size-offset {
			return 0, errArchive
		}
		next = offset + length
		for length > 0 {
			if err := ctx.Err(); err != nil {
				return 0, err
			}
			n := min(uint64(len(buf)), length)
			if _, err = io.ReadFull(zr, buf[:n]); err != nil {
				return 0, err
			}
			if _, err = out.WriteAt(buf[:n], int64(offset)); err != nil {
				return 0, err
			}
			offset += n
			length -= n
		}
	}
	if n, err := zr.Read(buf[:1]); n > 0 || (err != nil && !errors.Is(err, io.EOF)) {
		return 0, errors.Join(errArchive, err)
	}
	return int64(size), nil
}

func restoreGzip(ctx context.Context, src io.Reader, out *os.File, maxBytes int64) (int64, error) {
	gz, err := gzip.NewReader(src)
	if err != nil {
		return 0, err
	}
	defer gz.Close()
	buf := make([]byte, zeroChunk)
	var total int64
	for {
		if err := ctx.Err(); err != nil {
			return 0, err
		}
		n, e := io.ReadFull(gz, buf)
		total += int64(n)
		if total > maxBytes {
			return 0, errors.New("cache image exceeds capacity")
		}
		if n > 0 {
			if isZero(buf[:n]) {
				_, err = out.Seek(int64(n), io.SeekCurrent)
			} else {
				_, err = out.Write(buf[:n])
			}
			if err != nil {
				return 0, err
			}
		}
		if e == io.EOF || e == io.ErrUnexpectedEOF {
			return total, nil
		}
		if e != nil {
			return 0, e
		}
	}
}
