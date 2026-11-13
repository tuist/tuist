package archive

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"

	"github.com/klauspost/compress/zstd"
)

// An archive with a memory image puts it ahead of the disk stream:
//
//	per memory chunk that is not all zeros: a zstd skippable frame
//	    (magic 0x184D2A50, uint32 length) holding one zstd frame of the chunk
//	the disk stream, whose files include the VM state ("snapshot") and the
//	    memory index ("mem.index")
//
// Decoders skip skippable frames, so the whole object still decodes to the
// disk stream; a restore that wants the memory reads only the disk stream
// (from the tail offset) and later fetches chunks by range, as the guest
// touches them.
//
// mem.index is:
//
//	magic "SBXMEM1\n"
//	uvarint chunk size, uvarint memory size
//	per chunk: uvarint length (0 for an all-zero chunk); when not 0,
//	    uvarint object offset of the zstd frame and its 32-byte SHA-256
const (
	MemoryChunkSize = 2 << 20
	MemoryIndexName = "mem.index"

	memoryMagic       = "SBXMEM1\n"
	skippableMagic    = 0x184D2A50
	maxMemoryBytes    = 1 << 40
	maxCompressedSlop = 64 << 10
)

// MemoryIndex locates each chunk of an archived memory image.
type MemoryIndex struct {
	ChunkSize int64
	Size      int64
	Chunks    []MemoryChunk
}

// MemoryChunk is one chunk's zstd frame in the object; Length 0 is a chunk
// of zeros that the object does not hold.
type MemoryChunk struct {
	Offset int64
	Length int64
	Sum    [32]byte
}

// WriteMemory writes mem's chunks to w as skippable frames, w having
// received offset bytes of the object already, and answers their index and
// how many bytes of memory it stored, before compression.
func WriteMemory(w io.Writer, offset int64, mem *os.File) (MemoryIndex, int64, error) {
	info, err := mem.Stat()
	if err != nil {
		return MemoryIndex{}, 0, err
	}
	index := MemoryIndex{ChunkSize: MemoryChunkSize, Size: info.Size()}
	enc, err := zstd.NewWriter(nil, zstd.WithEncoderLevel(zstd.SpeedFastest), zstd.WithEncoderConcurrency(1))
	if err != nil {
		return index, 0, err
	}
	defer enc.Close()
	buf := make([]byte, MemoryChunkSize)
	var frame []byte
	var stored int64
	for pos := int64(0); pos < index.Size; pos += MemoryChunkSize {
		n := min(MemoryChunkSize, index.Size-pos)
		if _, err := mem.ReadAt(buf[:n], pos); err != nil {
			return index, stored, err
		}
		if allZero(buf[:n]) {
			index.Chunks = append(index.Chunks, MemoryChunk{})
			continue
		}
		frame = append(frame[:0], 0, 0, 0, 0, 0, 0, 0, 0)
		frame = enc.EncodeAll(buf[:n], frame)
		binary.LittleEndian.PutUint32(frame[0:], skippableMagic)
		binary.LittleEndian.PutUint32(frame[4:], uint32(len(frame)-8))
		if _, err := w.Write(frame); err != nil {
			return index, stored, err
		}
		index.Chunks = append(index.Chunks, MemoryChunk{Offset: offset + 8, Length: int64(len(frame) - 8), Sum: sha256.Sum256(frame[8:])})
		offset += int64(len(frame))
		stored += n
	}
	return index, stored, nil
}

func (ix MemoryIndex) Marshal() []byte {
	out := []byte(memoryMagic)
	out = binary.AppendUvarint(out, uint64(ix.ChunkSize))
	out = binary.AppendUvarint(out, uint64(ix.Size))
	for _, c := range ix.Chunks {
		out = binary.AppendUvarint(out, uint64(c.Length))
		if c.Length > 0 {
			out = binary.AppendUvarint(out, uint64(c.Offset))
			out = append(out, c.Sum[:]...)
		}
	}
	return out
}

// MaxMemoryIndexBytes bounds the index of a memory image of size bytes.
func MaxMemoryIndexBytes(size int64) int64 {
	return int64(len(memoryMagic)) + 20 + (size/MemoryChunkSize+1)*(10+10+32)
}

// ParseMemoryIndex reads an index whose frames must all lie before end,
// the offset where the disk stream starts.
func ParseMemoryIndex(data []byte, end int64) (MemoryIndex, error) {
	var ix MemoryIndex
	r := bytes.NewReader(data)
	got := make([]byte, len(memoryMagic))
	if _, err := io.ReadFull(r, got); err != nil || string(got) != memoryMagic {
		return ix, fmt.Errorf("%w: memory index magic", ErrInvalid)
	}
	chunk, err1 := binary.ReadUvarint(r)
	size, err2 := binary.ReadUvarint(r)
	if err1 != nil || err2 != nil || chunk != MemoryChunkSize || size == 0 || size > maxMemoryBytes {
		return ix, fmt.Errorf("%w: memory index sizes", ErrInvalid)
	}
	ix.ChunkSize, ix.Size = int64(chunk), int64(size)
	count := (ix.Size + ix.ChunkSize - 1) / ix.ChunkSize
	ix.Chunks = make([]MemoryChunk, count)
	next := int64(0)
	for i := range ix.Chunks {
		length, err := binary.ReadUvarint(r)
		if err != nil || length > MemoryChunkSize+maxCompressedSlop {
			return ix, fmt.Errorf("%w: memory chunk %d length", ErrInvalid, i)
		}
		if length == 0 {
			continue
		}
		offset, err := binary.ReadUvarint(r)
		if err != nil || int64(offset) < next+8 || int64(offset+length) > end {
			return ix, fmt.Errorf("%w: memory chunk %d outside the memory section", ErrInvalid, i)
		}
		c := &ix.Chunks[i]
		c.Offset, c.Length, next = int64(offset), int64(length), int64(offset+length)
		if _, err := io.ReadFull(r, c.Sum[:]); err != nil {
			return ix, fmt.Errorf("%w: memory chunk %d checksum", ErrInvalid, i)
		}
	}
	if r.Len() != 0 {
		return ix, fmt.Errorf("%w: data after the memory index", ErrInvalid)
	}
	return ix, nil
}

// RemoteMemory reads an archived memory image's chunks from the object by
// range, checking each against the index.
type RemoteMemory struct {
	client *http.Client
	url    string
	index  MemoryIndex
	dec    *zstd.Decoder
}

func NewRemoteMemory(client *http.Client, url string, index MemoryIndex) (*RemoteMemory, error) {
	dec, err := zstd.NewReader(nil, zstd.WithDecoderConcurrency(0), zstd.WithDecoderMaxMemory(MemoryChunkSize))
	if err != nil {
		return nil, err
	}
	return &RemoteMemory{client: client, url: url, index: index, dec: dec}, nil
}

func (m *RemoteMemory) Size() int64      { return m.index.Size }
func (m *RemoteMemory) ChunkSize() int64 { return m.index.ChunkSize }
func (m *RemoteMemory) Close()           { m.dec.Close() }

// StoredChunks counts the chunks the object holds, the ones not all zeros.
func (m *RemoteMemory) StoredChunks() int {
	n := 0
	for _, c := range m.index.Chunks {
		if c.Length > 0 {
			n++
		}
	}
	return n
}

func (m *RemoteMemory) Chunk(ctx context.Context, i int) ([]byte, error) {
	c := m.index.Chunks[i]
	if c.Length == 0 {
		return nil, nil
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, m.url, nil)
	if err != nil {
		return nil, redact(err)
	}
	req.Header.Set("Range", "bytes="+strconv.FormatInt(c.Offset, 10)+"-"+strconv.FormatInt(c.Offset+c.Length-1, 10))
	resp, err := m.client.Do(req)
	if err != nil {
		return nil, redact(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusPartialContent {
		return nil, fmt.Errorf("object storage answered %d to a range read", resp.StatusCode)
	}
	frame := make([]byte, c.Length)
	if _, err := io.ReadFull(resp.Body, frame); err != nil {
		return nil, redact(err)
	}
	if sha256.Sum256(frame) != c.Sum {
		return nil, fmt.Errorf("%w: memory chunk %d checksum", ErrInvalid, i)
	}
	want := min(m.index.ChunkSize, m.index.Size-int64(i)*m.index.ChunkSize)
	data, err := m.dec.DecodeAll(frame, make([]byte, 0, want))
	if err != nil || int64(len(data)) != want {
		return nil, errors.Join(fmt.Errorf("%w: memory chunk %d does not decode to %d bytes", ErrInvalid, i, want), err)
	}
	return data, nil
}
