package lazydisk

import (
	"bytes"
	"context"
	"errors"
	"math/rand/v2"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// source serves an image from memory, a chunk at a time, optionally slowly
// or failing one chunk.
type source struct {
	data    []byte
	chunk   int64
	delay   time.Duration
	fail    int
	fetches atomic.Int64
}

func (s *source) Size() int64      { return int64(len(s.data)) }
func (s *source) ChunkSize() int64 { return s.chunk }

func (s *source) Chunk(ctx context.Context, i int) ([]byte, error) {
	s.fetches.Add(1)
	if s.delay > 0 {
		select {
		case <-time.After(s.delay):
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	if i == s.fail {
		return nil, errors.New("object storage is down")
	}
	lo := int64(i) * s.chunk
	data := s.data[lo:min(lo+s.chunk, int64(len(s.data)))]
	if bytes.Count(data, []byte{0}) == len(data) {
		return nil, nil
	}
	return bytes.Clone(data), nil
}

// image is 9.5 chunks of 64 KiB, the 4th and 6th all zeros.
func image(t *testing.T) []byte {
	data := make([]byte, 9*65536+32768)
	r := rand.New(rand.NewPCG(1, 2))
	for i := range data {
		data[i] = byte(r.IntN(255) + 1)
	}
	clear(data[3*65536 : 4*65536])
	clear(data[5*65536 : 6*65536])
	return data
}

func newImage(t *testing.T, src *source) *Image {
	t.Helper()
	f, err := os.Create(filepath.Join(t.TempDir(), "disk"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { f.Close() })
	im, err := New(f, src)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(im.Close)
	return im
}

func TestWritesDuringTheFillKeepTheRestOfTheirChunks(t *testing.T) {
	want := image(t)
	src := &source{data: bytes.Clone(want), chunk: 65536, delay: time.Millisecond, fail: -1}
	im := newImage(t, src)

	// Writes that cover parts of chunks, one across a chunk boundary and
	// one into a zero chunk, race the fill.
	writes := []struct {
		at   int64
		data []byte
	}{{65536 - 5, []byte("across the boundary")}, {3*65536 + 100, []byte("into zeros")}, {9*65536 + 32768 - 4, []byte("tail")}}
	var wg sync.WaitGroup
	wg.Go(func() {
		if err := im.Fill(3); err != nil {
			t.Errorf("fill: %v", err)
		}
	})
	for _, w := range writes {
		wg.Go(func() {
			if _, err := im.WriteAt(w.data, w.at); err != nil {
				t.Errorf("write at %d: %v", w.at, err)
			}
		})
		copy(want[w.at:], w.data)
	}
	wg.Wait()
	select {
	case <-im.Loaded():
	default:
		t.Fatal("a complete fill must report the image loaded")
	}
	got := make([]byte, len(want)+100)
	n, err := im.ReadAt(got, 0)
	if err != nil || n != len(want) || !bytes.Equal(got[:n], want) {
		t.Fatalf("the image reads back %d bytes (%v), not the archived bytes with the writes", n, err)
	}
	if fetched := src.fetches.Load(); fetched != 10 {
		t.Fatalf("each chunk must be fetched once, got %d fetches", fetched)
	}
	if _, err := im.WriteAt([]byte("x"), int64(len(want))); err == nil {
		t.Fatal("a write past the image's end must fail")
	}
}

func TestReadsFetchOnlyTheirChunks(t *testing.T) {
	want := image(t)
	src := &source{data: want, chunk: 65536, fail: -1}
	im := newImage(t, src)
	got := make([]byte, 10)
	if _, err := im.ReadAt(got, 7*65536-5); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, want[7*65536-5:7*65536+5]) || src.fetches.Load() != 2 {
		t.Fatalf("a read across two chunks fetched %d", src.fetches.Load())
	}
	// Complete chunks still read once the image is closed.
	im.Close()
	if _, err := im.ReadAt(got, 7*65536-5); err != nil {
		t.Fatalf("a fetched chunk must read after Close: %v", err)
	}
	if _, err := im.ReadAt(got, 0); err == nil {
		t.Fatal("a chunk not fetched must fail after Close")
	}
}

func TestAChunkThatCannotBeFetchedFailsTheImage(t *testing.T) {
	src := &source{data: image(t), chunk: 65536, fail: 6}
	im := newImage(t, src)
	if err := im.Fill(2); err == nil {
		t.Fatal("the fill must fail on a chunk it cannot fetch")
	}
	if _, err := im.ReadAt(make([]byte, 1), 6*65536); err == nil {
		t.Fatal("the missing chunk must not read as zeros")
	}
	select {
	case <-im.Loaded():
		t.Fatal("an image with a missing chunk is not loaded")
	default:
	}
}
