package cachevolumes

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"
	"testing"

	"github.com/klauspost/compress/zstd"
	"golang.org/x/sys/unix"
)

func TestImageArchiveRestoresIncompressibleImageAtCapacity(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "image")
	data := make([]byte, 1<<20)
	if _, err := rand.Read(data); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(src, data, 0600); err != nil {
		t.Fatal(err)
	}
	_, digest, err := compressImage(src, src+".zst")
	if err != nil {
		t.Fatal(err)
	}
	compressed, err := os.ReadFile(src + ".zst")
	if err != nil {
		t.Fatal(err)
	}
	if len(compressed) <= len(data) {
		t.Fatal("fixture must exercise compression overhead")
	}
	target := filepath.Join(dir, "restored")
	if err := RestoreImage(context.Background(), bytes.NewReader(compressed), target, digest, int64(len(data))); err != nil {
		t.Fatal(err)
	}
	restored, err := os.ReadFile(target)
	if err != nil || !bytes.Equal(restored, data) {
		t.Fatal("restoration changed bytes", err)
	}
}

func TestImageArchiveRestoresZerosAndRejectsCorruptionAndOversize(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "image")
	archive := src + ".zst"
	data := make([]byte, 2<<20)
	copy(data[1<<20:], "cache payload")
	os.WriteFile(src, data, 0600)
	_, digest, err := compressImage(src, archive)
	if err != nil {
		t.Fatal(err)
	}
	compressed, _ := os.ReadFile(archive)
	target := filepath.Join(dir, "restored")
	if err := RestoreImage(context.Background(), bytes.NewReader(compressed), target, digest, int64(len(data))); err != nil {
		t.Fatal(err)
	}
	restored, _ := os.ReadFile(target)
	if !bytes.Equal(restored, data) {
		t.Fatal("restoration changed bytes")
	}
	for name, limit := range map[string]int64{"corrupt": int64(len(data)), "oversize": 100} {
		target := filepath.Join(dir, name)
		hash := digest
		if name == "corrupt" {
			hash = "bad"
		}
		if err := RestoreImage(context.Background(), bytes.NewReader(compressed), target, hash, limit); err == nil {
			t.Fatal("accepted", name)
		}
		if _, err := os.Stat(target); !os.IsNotExist(err) {
			t.Fatal("retained unverified image")
		}
	}
}

type cancellingReader struct {
	io.Reader
	cancel context.CancelFunc
}

func (r cancellingReader) Read(p []byte) (int, error) {
	n, err := r.Reader.Read(p)
	r.cancel()
	return n, err
}
func TestRestoreCancellationStopsBufferedExpansionAndRemovesPartialImage(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "image")
	if err := os.WriteFile(src, make([]byte, 2<<20), 0600); err != nil {
		t.Fatal(err)
	}
	_, digest, err := compressImage(src, src+".zst")
	if err != nil {
		t.Fatal(err)
	}
	compressed, err := os.ReadFile(src + ".zst")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	target := filepath.Join(dir, "restored")
	err = RestoreImage(ctx, cancellingReader{bytes.NewReader(compressed), cancel}, target, digest, 2<<20)
	if !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Fatal("left cancelled restore", err)
	}
}

func TestImageArchiveStoresOnlyDataOfSparseImage(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "image")
	f, err := os.Create(src)
	if err != nil {
		t.Fatal(err)
	}
	const size = 4 << 30
	if err = f.Truncate(size); err != nil {
		t.Fatal(err)
	}
	payload := make([]byte, 3<<20)
	if _, err := rand.Read(payload); err != nil {
		t.Fatal(err)
	}
	offsets := []int64{0, 1 << 30, size - int64(len(payload))}
	for _, offset := range offsets {
		if _, err = f.WriteAt(payload, offset); err != nil {
			t.Fatal(err)
		}
	}
	// An allocated run of zeros must not be stored or allocated on restore.
	if _, err = f.WriteAt(make([]byte, 8<<20), 2<<30); err != nil {
		t.Fatal(err)
	}
	if err = f.Close(); err != nil {
		t.Fatal(err)
	}
	_, digest, err := compressImage(src, src+".zst")
	if err != nil {
		t.Fatal(err)
	}
	archive, err := os.ReadFile(src + ".zst")
	if err != nil {
		t.Fatal(err)
	}
	if limit := len(offsets)*len(payload) + 1<<20; len(archive) > limit {
		t.Fatalf("archive holds %d bytes, want at most %d", len(archive), limit)
	}
	target := filepath.Join(dir, "restored")
	if err := RestoreImage(context.Background(), bytes.NewReader(archive), target, digest, size); err != nil {
		t.Fatal(err)
	}
	restored, err := os.Open(target)
	if err != nil {
		t.Fatal(err)
	}
	defer restored.Close()
	var stat unix.Stat_t
	if err = unix.Fstat(int(restored.Fd()), &stat); err != nil {
		t.Fatal(err)
	}
	if stat.Size != size {
		t.Fatalf("restored size %d", stat.Size)
	}
	if allocated := stat.Blocks * 512; allocated > int64(len(offsets)*len(payload))+(8<<20) {
		t.Fatalf("restored image allocates %d bytes", allocated)
	}
	got := make([]byte, len(payload))
	for _, offset := range offsets {
		if _, err = restored.ReadAt(got, offset); err != nil || !bytes.Equal(got, payload) {
			t.Fatal("restoration changed bytes at", offset, err)
		}
	}
	if _, err = restored.ReadAt(got, 2<<30); err != nil || !isZero(got[:zeroChunk]) {
		t.Fatal("restoration changed a zero run", err)
	}
}

func TestImageArchiveRestoresLegacyGzipMaster(t *testing.T) {
	data := make([]byte, 2<<20)
	copy(data[1<<20:], "cache payload")
	var archive bytes.Buffer
	gz, _ := gzip.NewWriterLevel(&archive, gzip.BestSpeed)
	gz.Write(data)
	gz.Close()
	sum := sha256.Sum256(archive.Bytes())
	target := filepath.Join(t.TempDir(), "restored")
	if err := RestoreImage(context.Background(), bytes.NewReader(archive.Bytes()), target, hex.EncodeToString(sum[:]), int64(len(data))); err != nil {
		t.Fatal(err)
	}
	restored, err := os.ReadFile(target)
	if err != nil || !bytes.Equal(restored, data) {
		t.Fatal("restoration changed bytes", err)
	}
}

func TestImageArchiveRejectsExtentsOutsideImage(t *testing.T) {
	for name, extents := range map[string][][2]uint64{
		"beyond size": {{1 << 20, 1}},
		"overlapping": {{0, 8}, {4, 8}},
		"overflowing": {{8, ^uint64(0)}},
	} {
		var plain bytes.Buffer
		record := make([]byte, 16)
		copy(record, sparseArchiveMagic)
		binary.BigEndian.PutUint64(record[8:], 1<<20)
		plain.Write(record)
		for _, extent := range extents {
			binary.BigEndian.PutUint64(record, extent[0])
			binary.BigEndian.PutUint64(record[8:], extent[1])
			plain.Write(record)
			if extent[1] < 1<<20 {
				plain.Write(bytes.Repeat([]byte{1}, int(extent[1])))
			}
		}
		plain.Write(make([]byte, 16))
		var archive bytes.Buffer
		zw, _ := zstd.NewWriter(&archive)
		zw.Write(plain.Bytes())
		zw.Close()
		sum := sha256.Sum256(archive.Bytes())
		target := filepath.Join(t.TempDir(), "restored")
		if err := RestoreImage(context.Background(), bytes.NewReader(archive.Bytes()), target, hex.EncodeToString(sum[:]), 1<<20); err == nil {
			t.Fatal("accepted", name)
		}
		if _, err := os.Stat(target); !os.IsNotExist(err) {
			t.Fatal("retained unverified image", name)
		}
	}
}
