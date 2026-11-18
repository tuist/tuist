package archive

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"math/rand/v2"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// warmArchive writes an object the way a paused sandbox with its memory is
// archived and answers it with the offset and digest of its disk stream.
func warmArchive(t *testing.T, mem []byte) ([]byte, int64, string, MemoryIndex) {
	t.Helper()
	dir := t.TempDir()
	memFile := writeSparse(t, filepath.Join(dir, "mem"), int64(len(mem)), map[int64][]byte{0: mem})
	var object bytes.Buffer
	object.WriteString("prefix the uploader already sent")
	index, stored, err := WriteMemory(&object, int64(object.Len()), memFile)
	if err != nil {
		t.Fatal(err)
	}
	if want := int64(len(mem) - 2*MemoryChunkSize); stored != want {
		t.Fatalf("stored %d bytes of memory, expected %d", stored, want)
	}
	if err := os.WriteFile(filepath.Join(dir, MemoryIndexName), index.Marshal(), 0o644); err != nil {
		t.Fatal(err)
	}
	tail := int64(object.Len())
	var sources []Source
	for name, data := range map[string][]byte{"snapshot": []byte("vm state"), "rootfs.ext4": []byte("rootfs")} {
		sources = append(sources, Source{Name: name, File: writeSparse(t, filepath.Join(dir, name), int64(len(data)), map[int64][]byte{0: data})})
	}
	indexFile, _ := os.Open(filepath.Join(dir, MemoryIndexName))
	defer indexFile.Close()
	sources = append(sources, Source{Name: MemoryIndexName, File: indexFile})
	hash := sha256.New()
	if _, err := Write(io.MultiWriter(&object, hash), Header{Template: "default", Memory: &MemoryHeader{Size: int64(len(mem)), Compat: "c1"}}, sources); err != nil {
		t.Fatal(err)
	}
	return object.Bytes(), tail, hex.EncodeToString(hash.Sum(nil)), index
}

// testMemory has incompressible chunks, a compressible one, two zero
// chunks (1 and 3) and a short last chunk.
func testMemory() []byte {
	mem := make([]byte, 5*MemoryChunkSize+12288)
	rng := rand.New(rand.NewPCG(3, 4))
	for i := range mem {
		mem[i] = byte(rng.IntN(256))
	}
	clear(mem[1*MemoryChunkSize : 2*MemoryChunkSize])
	clear(mem[3*MemoryChunkSize : 4*MemoryChunkSize])
	copy(mem[2*MemoryChunkSize:3*MemoryChunkSize], bytes.Repeat([]byte("page"), MemoryChunkSize/4))
	return mem
}

func serve(t *testing.T, object []byte) *httptest.Server {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(object))
	}))
	t.Cleanup(server.Close)
	return server
}

func TestMemoryArchiveRestoresFromItsTailAndByChunk(t *testing.T) {
	mem := testMemory()
	object, tail, tailSum, _ := warmArchive(t, mem)
	server := serve(t, object)
	limits := map[string]int64{"snapshot": 1 << 20, "rootfs.ext4": 1 << 20, MemoryIndexName: MaxMemoryIndexBytes(int64(len(mem)))}

	dir := t.TempDir()
	var header Header
	err := DownloadRange(context.Background(), server.Client(), server.URL, tail, int64(len(object))-tail, tailSum, func(r io.Reader) error {
		var err error
		header, err = Extract(r, dir, limits)
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	if header.Memory == nil || header.Memory.Size != int64(len(mem)) || header.Memory.Compat != "c1" {
		t.Fatalf("header %+v", header)
	}
	data, _ := os.ReadFile(filepath.Join(dir, MemoryIndexName))
	index, err := ParseMemoryIndex(data, tail)
	if err != nil {
		t.Fatal(err)
	}
	remote, err := NewRemoteMemory(server.Client(), server.URL, index)
	if err != nil {
		t.Fatal(err)
	}
	defer remote.Close()
	if remote.StoredChunks() != 4 {
		t.Fatalf("%d stored chunks, expected 4", remote.StoredChunks())
	}
	for i := range index.Chunks {
		chunk, err := remote.Chunk(context.Background(), i)
		if err != nil {
			t.Fatalf("chunk %d: %v", i, err)
		}
		start := i * MemoryChunkSize
		want := mem[start:min(start+MemoryChunkSize, len(mem))]
		if (i == 1 || i == 3) != (chunk == nil) || (chunk != nil && !bytes.Equal(chunk, want)) {
			t.Fatalf("chunk %d does not read back", i)
		}
	}

	// The whole object still extracts as a disk archive: the memory frames
	// are skippable.
	if _, err := Extract(bytes.NewReader(object[len("prefix the uploader already sent"):]), t.TempDir(), limits); err != nil {
		t.Fatalf("whole object: %v", err)
	}
}

func TestMemoryChunksAreCheckedAgainstTheIndex(t *testing.T) {
	mem := testMemory()
	object, tail, _, index := warmArchive(t, mem)
	tampered := bytes.Clone(object)
	tampered[index.Chunks[2].Offset+index.Chunks[2].Length/2] ^= 1
	remote, _ := NewRemoteMemory(http.DefaultClient, serve(t, tampered).URL, index)
	defer remote.Close()
	if _, err := remote.Chunk(context.Background(), 2); !errors.Is(err, ErrInvalid) {
		t.Fatalf("a tampered chunk answered %v", err)
	}

	// An index pointing into the disk stream is refused.
	if _, err := ParseMemoryIndex(index.Marshal(), index.Chunks[4].Offset); !errors.Is(err, ErrInvalid) {
		t.Fatalf("an index past the memory section answered %v", err)
	}
	if _, err := ParseMemoryIndex(index.Marshal(), tail); err != nil {
		t.Fatal(err)
	}
}
