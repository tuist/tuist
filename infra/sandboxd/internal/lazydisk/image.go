// Package lazydisk serves a restored sandbox's disk images before they have
// arrived, the way package uffd serves its memory: Firecracker opens each
// disk through a FUSE mount over the disk's path in the jail (Mount), every
// first read or write of a chunk fetches it from the archive into a local
// sparse file, and a fill fetches the rest in the background. Once every
// chunk is on the node the local file is complete, and the caller moves it
// to the disk's path and has Firecracker reopen it, so the mount serves
// only for as long as the fill takes.
package lazydisk

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sync"
	"sync/atomic"
	"time"
)

// Source is an archived disk image, read a chunk at a time.
type Source interface {
	Size() int64
	ChunkSize() int64
	// Chunk answers chunk i, or nil when it is all zeros. Only the last
	// chunk may be shorter than ChunkSize.
	Chunk(ctx context.Context, i int) ([]byte, error)
}

const (
	fetchAttempts = 3
	fetchBackoff  = 500 * time.Millisecond
)

const (
	chunkMissing = iota
	chunkFetching
	chunkPresent
)

// Image is a disk image filled from its Source into a local file, which
// starts as a hole of the image's size. A chunk is fetched before the first
// read or write that touches it, so a write never lands under a fetch.
type Image struct {
	file *os.File
	src  Source
	ctx  context.Context
	stop context.CancelFunc

	mu      sync.Mutex
	changed *sync.Cond
	state   []uint8
	present int
	err     error
	loaded  chan struct{}

	faulted, filled atomic.Int64
}

// New fills file, which it truncates to the image's size, from src until
// Close. The file must hold no data yet.
func New(file *os.File, src Source) (*Image, error) {
	if src.Size() <= 0 || src.ChunkSize() <= 0 {
		return nil, errors.New("lazydisk: empty image")
	}
	if err := file.Truncate(src.Size()); err != nil {
		return nil, err
	}
	chunks := int((src.Size() + src.ChunkSize() - 1) / src.ChunkSize())
	ctx, stop := context.WithCancel(context.Background())
	im := &Image{file: file, src: src, ctx: ctx, stop: stop, state: make([]uint8, chunks), loaded: make(chan struct{})}
	im.changed = sync.NewCond(&im.mu)
	return im, nil
}

func (im *Image) Size() int64 { return im.src.Size() }

// Loaded is closed once every chunk is in the local file.
func (im *Image) Loaded() <-chan struct{} { return im.loaded }

// Err is the error that stopped the image: a chunk that could not be
// fetched, or Close.
func (im *Image) Err() error {
	im.mu.Lock()
	defer im.mu.Unlock()
	return im.err
}

// Stats counts the chunks fetched for a read or write and by the fill.
func (im *Image) Stats() (chunks int, faulted, filled int64) {
	return len(im.state), im.faulted.Load(), im.filled.Load()
}

// Close stops fetching; reads and writes of chunks not fetched yet fail.
func (im *Image) Close() {
	im.mu.Lock()
	if im.err == nil {
		im.err = errors.New("lazydisk: image closed")
	}
	im.mu.Unlock()
	im.stop()
	im.changed.Broadcast()
}

// ReadAt reads the image, fetching the chunks p covers first.
func (im *Image) ReadAt(p []byte, off int64) (int, error) {
	if off >= im.Size() {
		return 0, nil
	}
	p = p[:min(int64(len(p)), im.Size()-off)]
	if err := im.ensureRange(off, int64(len(p))); err != nil {
		return 0, err
	}
	return im.file.ReadAt(p, off)
}

// WriteAt writes the image, fetching the chunks p covers first so the
// parts of them it leaves alone keep their archived bytes.
func (im *Image) WriteAt(p []byte, off int64) (int, error) {
	if off < 0 || off+int64(len(p)) > im.Size() {
		return 0, fmt.Errorf("lazydisk: write of %d bytes at %d past the image's end", len(p), off)
	}
	if err := im.ensureRange(off, int64(len(p))); err != nil {
		return 0, err
	}
	return im.file.WriteAt(p, off)
}

// EnsureRange fetches the chunks of [off, off+length).
func (im *Image) EnsureRange(off, length int64) error { return im.ensureRange(off, length) }

// Sync flushes the local file.
func (im *Image) Sync() error { return im.file.Sync() }

func (im *Image) ensureRange(off, length int64) error {
	if length <= 0 {
		return nil
	}
	size := im.src.ChunkSize()
	for i := off / size; i <= (off+length-1)/size && i < int64(len(im.state)); i++ {
		if err := im.ensure(int(i), &im.faulted); err != nil {
			return err
		}
	}
	return nil
}

// Fill fetches every chunk not fetched yet with workers in parallel, and
// answers once all are in the local file or one cannot be fetched.
func (im *Image) Fill(workers int) error {
	var next atomic.Int64
	var wg sync.WaitGroup
	errs := make(chan error, max(workers, 1))
	for range max(workers, 1) {
		wg.Go(func() {
			for {
				i := int(next.Add(1) - 1)
				if i >= len(im.state) {
					return
				}
				if err := im.ensure(i, &im.filled); err != nil {
					errs <- err
					return
				}
			}
		})
	}
	wg.Wait()
	close(errs)
	return <-errs
}

func (im *Image) ensure(i int, counter *atomic.Int64) error {
	im.mu.Lock()
	for im.err == nil && im.state[i] == chunkFetching {
		im.changed.Wait()
	}
	// A chunk already in the local file reads and writes even after
	// Close, so a mount keeps serving a complete image to its last user.
	if im.state[i] == chunkPresent {
		im.mu.Unlock()
		return nil
	}
	if im.err != nil {
		err := im.err
		im.mu.Unlock()
		return err
	}
	im.state[i] = chunkFetching
	im.mu.Unlock()

	err := im.fetch(i)

	im.mu.Lock()
	defer im.mu.Unlock()
	defer im.changed.Broadcast()
	if err != nil {
		im.state[i] = chunkMissing
		if im.err == nil {
			im.err = err
		}
		return im.err
	}
	im.state[i] = chunkPresent
	counter.Add(1)
	im.present++
	if im.present == len(im.state) {
		close(im.loaded)
	}
	return nil
}

func (im *Image) fetch(i int) error {
	var data []byte
	var err error
	for attempt := 1; ; attempt++ {
		data, err = im.src.Chunk(im.ctx, i)
		if err == nil || im.ctx.Err() != nil || attempt == fetchAttempts {
			break
		}
		select {
		case <-time.After(time.Duration(attempt) * fetchBackoff):
		case <-im.ctx.Done():
		}
	}
	if err != nil {
		return fmt.Errorf("fetching disk chunk %d: %w", i, err)
	}
	// A chunk of zeros stays a hole of the fresh file.
	if data == nil {
		return nil
	}
	_, err = im.file.WriteAt(data, int64(i)*im.src.ChunkSize())
	return err
}
