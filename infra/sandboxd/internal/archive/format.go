// Package archive writes and reads the object a paused sandbox's disks are
// archived to, and moves it to and from object storage through presigned
// URLs, so the daemon never holds storage credentials.
//
// The object is one zstd stream of:
//
//	magic "SBXARC1\n"
//	uvarint length, JSON Header
//	per file:   'F' uvarint name length, name, uvarint size
//	            per data block: 'D' uvarint offset, uvarint length, bytes
//	            'E'
//	'Z'
//
// Holes and all-zero blocks are left out, so a sparse workspace image costs
// only the blocks the guest wrote. Extraction recreates each file at its
// full size, sparse.
package archive

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"syscall"
	"time"

	"github.com/klauspost/compress/zstd"
)

const (
	magic     = "SBXARC1\n"
	blockSize = 1 << 20

	recordFile  = 'F'
	recordData  = 'D'
	recordEnd   = 'E'
	recordFinal = 'Z'

	maxHeaderBytes = 64 << 10
	maxNameBytes   = 255
)

var ErrInvalid = errors.New("invalid sandbox archive")

// Header describes the sandbox the disks belong to.
type Header struct {
	Template      string    `json:"template"`
	Tag           string    `json:"tag"`
	WorkspaceGB   int       `json:"workspace_gb"`
	SourceSandbox string    `json:"source_sandbox"`
	CreatedAt     time.Time `json:"created_at"`
	DisksSynced   bool      `json:"disks_synced"`
}

// Source is one file to archive under Name.
type Source struct {
	Name string
	File *os.File
}

// Write archives the sources to w and returns how many bytes of file data
// it stored, before compression.
func Write(w io.Writer, header Header, sources []Source) (int64, error) {
	enc, err := zstd.NewWriter(w, zstd.WithEncoderLevel(zstd.SpeedFastest))
	if err != nil {
		return 0, err
	}
	out := bufio.NewWriterSize(enc, 256<<10)
	data, err := json.Marshal(header)
	if err != nil {
		return 0, err
	}
	var scratch []byte
	scratch = append(scratch, magic...)
	scratch = binary.AppendUvarint(scratch, uint64(len(data)))
	scratch = append(scratch, data...)
	if _, err := out.Write(scratch); err != nil {
		enc.Close()
		return 0, err
	}
	var stored int64
	buf := make([]byte, blockSize)
	for _, src := range sources {
		n, err := writeFile(out, src, buf)
		stored += n
		if err != nil {
			enc.Close()
			return stored, fmt.Errorf("archiving %s: %w", src.Name, err)
		}
	}
	if err := out.WriteByte(recordFinal); err != nil {
		enc.Close()
		return stored, err
	}
	if err := out.Flush(); err != nil {
		enc.Close()
		return stored, err
	}
	return stored, enc.Close()
}

func writeFile(out *bufio.Writer, src Source, buf []byte) (int64, error) {
	if len(src.Name) == 0 || len(src.Name) > maxNameBytes {
		return 0, fmt.Errorf("file name %q", src.Name)
	}
	info, err := src.File.Stat()
	if err != nil {
		return 0, err
	}
	size := info.Size()
	record := []byte{recordFile}
	record = binary.AppendUvarint(record, uint64(len(src.Name)))
	record = append(record, src.Name...)
	record = binary.AppendUvarint(record, uint64(size))
	if _, err := out.Write(record); err != nil {
		return 0, err
	}
	var stored int64
	for offset := int64(0); offset < size; {
		start, err := nextData(src.File, offset, size)
		if err != nil {
			return stored, err
		}
		if start >= size {
			break
		}
		end, err := nextHole(src.File, start, size)
		if err != nil {
			return stored, err
		}
		for pos := start; pos < end; {
			n := min(int64(len(buf)), end-pos)
			if _, err := src.File.ReadAt(buf[:n], pos); err != nil {
				return stored, err
			}
			if !allZero(buf[:n]) {
				header := []byte{recordData}
				header = binary.AppendUvarint(header, uint64(pos))
				header = binary.AppendUvarint(header, uint64(n))
				if _, err := out.Write(header); err != nil {
					return stored, err
				}
				if _, err := out.Write(buf[:n]); err != nil {
					return stored, err
				}
				stored += n
			}
			pos += n
		}
		offset = end
	}
	return stored, out.WriteByte(recordEnd)
}

var zeroBlock = make([]byte, blockSize)

func allZero(b []byte) bool { return bytes.Equal(b, zeroBlock[:len(b)]) }

// Extract recreates the archived files in dir, which must not hold them
// yet. limits names the files the archive must contain and the largest size
// each may declare; anything else is refused.
func Extract(r io.Reader, dir string, limits map[string]int64) (Header, error) {
	var header Header
	dec, err := zstd.NewReader(r, zstd.WithDecoderConcurrency(1))
	if err != nil {
		return header, err
	}
	defer dec.Close()
	in := bufio.NewReaderSize(dec, 256<<10)
	got := make([]byte, len(magic))
	if _, err := io.ReadFull(in, got); err != nil || string(got) != magic {
		return header, fmt.Errorf("%w: bad magic", ErrInvalid)
	}
	length, err := binary.ReadUvarint(in)
	if err != nil || length > maxHeaderBytes {
		return header, fmt.Errorf("%w: header length", ErrInvalid)
	}
	data := make([]byte, length)
	if _, err := io.ReadFull(in, data); err != nil {
		return header, fmt.Errorf("%w: header: %v", ErrInvalid, err)
	}
	if err := json.Unmarshal(data, &header); err != nil {
		return header, fmt.Errorf("%w: header: %v", ErrInvalid, err)
	}
	seen := map[string]bool{}
	for {
		kind, err := in.ReadByte()
		if err != nil {
			return header, fmt.Errorf("%w: truncated: %v", ErrInvalid, err)
		}
		switch kind {
		case recordFinal:
			for name := range limits {
				if !seen[name] {
					return header, fmt.Errorf("%w: missing %s", ErrInvalid, name)
				}
			}
			// The stream must end here: trailing data means the object is not
			// what was written.
			if _, err := in.ReadByte(); !errors.Is(err, io.EOF) {
				return header, fmt.Errorf("%w: data after the end", ErrInvalid)
			}
			return header, nil
		case recordFile:
			name, err := extractFile(in, dir, limits, seen)
			if err != nil {
				return header, fmt.Errorf("extracting %s: %w", name, err)
			}
			seen[name] = true
		default:
			return header, fmt.Errorf("%w: record %q", ErrInvalid, kind)
		}
	}
}

func extractFile(in *bufio.Reader, dir string, limits map[string]int64, seen map[string]bool) (string, error) {
	nameLen, err := binary.ReadUvarint(in)
	if err != nil || nameLen == 0 || nameLen > maxNameBytes {
		return "", fmt.Errorf("%w: name length", ErrInvalid)
	}
	raw := make([]byte, nameLen)
	if _, err := io.ReadFull(in, raw); err != nil {
		return "", fmt.Errorf("%w: name: %v", ErrInvalid, err)
	}
	name := string(raw)
	limit, allowed := limits[name]
	if !allowed || seen[name] {
		return name, fmt.Errorf("%w: unexpected file", ErrInvalid)
	}
	size64, err := binary.ReadUvarint(in)
	if err != nil || size64 > uint64(limit) {
		return name, fmt.Errorf("%w: size", ErrInvalid)
	}
	size := int64(size64)
	file, err := os.OpenFile(filepath.Join(dir, name), os.O_CREATE|os.O_EXCL|os.O_WRONLY|syscall.O_NOFOLLOW, 0o644)
	if err != nil {
		return name, err
	}
	defer file.Close()
	if err := file.Truncate(size); err != nil {
		return name, err
	}
	buf := make([]byte, blockSize)
	next := int64(0)
	for {
		kind, err := in.ReadByte()
		if err != nil {
			return name, fmt.Errorf("%w: truncated: %v", ErrInvalid, err)
		}
		if kind == recordEnd {
			return name, file.Sync()
		}
		if kind != recordData {
			return name, fmt.Errorf("%w: record %q", ErrInvalid, kind)
		}
		offset, err := binary.ReadUvarint(in)
		if err != nil {
			return name, fmt.Errorf("%w: offset", ErrInvalid)
		}
		length, err := binary.ReadUvarint(in)
		if err != nil || length == 0 || length > blockSize {
			return name, fmt.Errorf("%w: block length", ErrInvalid)
		}
		if int64(offset) < next || int64(offset) > size || int64(length) > size-int64(offset) {
			return name, fmt.Errorf("%w: block outside the file", ErrInvalid)
		}
		if _, err := io.ReadFull(in, buf[:length]); err != nil {
			return name, fmt.Errorf("%w: block: %v", ErrInvalid, err)
		}
		if _, err := file.WriteAt(buf[:length], int64(offset)); err != nil {
			return name, err
		}
		next = int64(offset + length)
	}
}
