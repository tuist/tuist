package cachevolumes

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"hash"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"sync"
	"sync/atomic"
	"time"
)

var (
	actionsEntryID = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
	// Azure block IDs are base64 of at most 64 bytes.
	actionsBlockID = regexp.MustCompile(`^[A-Za-z0-9+/=_-]{1,100}$`)
	// ErrActionsUpload is an upload this host cannot accept as sent.
	ErrActionsUpload = errors.New("invalid actions cache upload")
)

const (
	actionsUploadIdle = time.Hour
	actionsMaxBlocks  = 50_000
	// One presigned PUT to the entry's store carries at most 5 GB.
	actionsMaxEntry    = 5_000_000_000
	actionsRoomPerPass = 64 << 20
)

// ActionsStore stages GitHub Actions cache uploads on this host's cache
// filesystem, `uploads/<id>/`, until they are copied to the entry's store.
// Staging never takes the filesystem below Reserve, and nothing is kept once
// the copy finished or failed.
type ActionsStore struct {
	Root      string
	Reserve   uint64
	FreeBytes func(string) (uint64, error)
	Log       *slog.Logger
	// writes bounds concurrent incoming streams, each holding up to
	// archiveWritebackBytes of dirty pages.
	writes chan struct{}
	once   sync.Once
	// unflushed counts bytes staged since the last fsync, by every stream.
	unflushed atomic.Int64
}

func (s *ActionsStore) init() {
	s.once.Do(func() { s.writes = make(chan struct{}, 4) })
}

func (s *ActionsStore) upload(id string) string { return filepath.Join(s.Root, "uploads", id) }
func (s *ActionsStore) blob(id string) string   { return filepath.Join(s.upload(id), "blob") }

// Begin prepares the upload of entry id.
func (s *ActionsStore) Begin(id string) error {
	if !actionsEntryID.MatchString(id) {
		return ErrActionsUpload
	}
	return os.MkdirAll(filepath.Join(s.upload(id), "blocks"), 0o700)
}

// PutBlob stores a single-request upload of entry id.
func (s *ActionsStore) PutBlob(ctx context.Context, id string, body io.Reader) (int64, error) {
	if !actionsEntryID.MatchString(id) || !s.uploading(id) {
		return 0, ErrActionsUpload
	}
	return s.write(ctx, s.blob(id), body, true)
}

// PutBlock stores one staged block of entry id.
func (s *ActionsStore) PutBlock(ctx context.Context, id, block string, body io.Reader) (int64, error) {
	if !actionsEntryID.MatchString(id) || !actionsBlockID.MatchString(block) || !s.uploading(id) {
		return 0, ErrActionsUpload
	}
	return s.write(ctx, s.blockPath(id, block), body, false)
}

// CommitBlocks ends the upload of entry id as its staged blocks, in list
// order. The blocks stay where they are, already synced: they are linked into
// `parts/` in order and only read to hash them, never rewritten into one file.
// Unlisted blocks go.
func (s *ActionsStore) CommitBlocks(ctx context.Context, id string, blocks []string) error {
	if !actionsEntryID.MatchString(id) || !s.uploading(id) || len(blocks) == 0 || len(blocks) > actionsMaxBlocks {
		return ErrActionsUpload
	}
	var total int64
	for _, block := range blocks {
		info, err := os.Stat(s.blockPath(id, block))
		if !actionsBlockID.MatchString(block) || err != nil {
			return ErrActionsUpload
		}
		total += info.Size()
	}
	if total > actionsMaxEntry {
		return ErrActionsUpload
	}
	parts := s.parts(id)
	if err := os.RemoveAll(parts); err != nil {
		return err
	}
	if err := os.Mkdir(parts, 0o700); err != nil {
		return err
	}
	paths := make([]string, len(blocks))
	for i, block := range blocks {
		// A link, not a rename: a list may name a block more than once.
		paths[i] = filepath.Join(parts, fmt.Sprintf("%05d", i))
		if err := os.Link(s.blockPath(id, block), paths[i]); err != nil {
			return err
		}
	}
	sum := sha256.New()
	content := &partsReader{paths: paths}
	defer content.Close()
	if _, err := io.Copy(sum, readerWithContext{ctx, content}); err != nil {
		return err
	}
	if err := os.WriteFile(s.blob(id)+".sha256", []byte(hex.EncodeToString(sum.Sum(nil))), 0o600); err != nil {
		return err
	}
	return os.RemoveAll(filepath.Join(s.upload(id), "blocks"))
}

// Seal ends the upload of entry id, which must hold size bytes, and returns
// its SHA-256. A sealed upload takes no more writes.
func (s *ActionsStore) Seal(id string, size int64) (string, error) {
	if !actionsEntryID.MatchString(id) {
		return "", ErrActionsUpload
	}
	paths, err := s.content(id)
	if err != nil {
		return "", ErrActionsUpload
	}
	var total int64
	for _, path := range paths {
		info, err := os.Stat(path)
		if err != nil {
			return "", ErrActionsUpload
		}
		total += info.Size()
	}
	if total != size {
		return "", ErrActionsUpload
	}
	sum, err := os.ReadFile(s.blob(id) + ".sha256")
	if err != nil {
		return "", err
	}
	if err := os.RemoveAll(filepath.Join(s.upload(id), "blocks")); err != nil {
		return "", err
	}
	return string(sum), nil
}

// Open opens the sealed upload of entry id for copying to its store.
func (s *ActionsStore) Open(id string) (io.ReadCloser, error) {
	if !actionsEntryID.MatchString(id) || s.uploading(id) {
		return nil, os.ErrNotExist
	}
	paths, err := s.content(id)
	if err != nil {
		return nil, err
	}
	return &partsReader{paths: paths}, nil
}

// content lists the files holding entry id in order: its single-request blob,
// else the parts its block list committed.
func (s *ActionsStore) content(id string) ([]string, error) {
	if _, err := os.Stat(s.blob(id)); err == nil {
		return []string{s.blob(id)}, nil
	}
	entries, err := os.ReadDir(s.parts(id))
	if err != nil {
		return nil, err
	}
	if len(entries) == 0 {
		return nil, os.ErrNotExist
	}
	paths := make([]string, len(entries))
	for i, entry := range entries {
		paths[i] = filepath.Join(s.parts(id), entry.Name())
	}
	return paths, nil
}

// Remove deletes the upload of entry id.
func (s *ActionsStore) Remove(id string) {
	if !actionsEntryID.MatchString(id) {
		return
	}
	os.RemoveAll(s.upload(id))
}

// Maintain deletes uploads nobody touched for an hour: abandoned by their job,
// or left by an agent that restarted before copying them.
func (s *ActionsStore) Maintain() error {
	uploads, err := os.ReadDir(filepath.Join(s.Root, "uploads"))
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, upload := range uploads {
		if info, err := upload.Info(); err == nil && time.Since(info.ModTime()) > actionsUploadIdle {
			os.RemoveAll(filepath.Join(s.Root, "uploads", upload.Name()))
		}
	}
	return nil
}

func (s *ActionsStore) uploading(id string) bool {
	info, err := os.Stat(filepath.Join(s.upload(id), "blocks"))
	return err == nil && info.IsDir()
}

func (s *ActionsStore) blockPath(id, block string) string {
	return filepath.Join(s.upload(id), "blocks", hex.EncodeToString([]byte(block)))
}

func (s *ActionsStore) parts(id string) string { return filepath.Join(s.upload(id), "parts") }

// partsReader reads files one after another, holding one open at a time: a
// block list can name 50,000 blocks.
type partsReader struct {
	paths []string
	file  *os.File
}

func (r *partsReader) Read(p []byte) (int, error) {
	for {
		if r.file == nil {
			if len(r.paths) == 0 {
				return 0, io.EOF
			}
			file, err := os.Open(r.paths[0])
			if err != nil {
				return 0, err
			}
			r.file, r.paths = file, r.paths[1:]
		}
		n, err := r.file.Read(p)
		if err == io.EOF {
			r.file.Close()
			r.file = nil
			if n == 0 {
				continue
			}
			err = nil
		}
		return n, err
	}
}

func (r *partsReader) Close() error {
	r.paths = nil
	if r.file == nil {
		return nil
	}
	err := r.file.Close()
	r.file = nil
	return err
}

type readerWithContext struct {
	ctx context.Context
	io.Reader
}

func (r readerWithContext) Read(p []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	return r.Reader.Read(p)
}

// room admits n more bytes above the reserve.
func (s *ActionsStore) room(n uint64) error {
	freeBytes := s.FreeBytes
	if freeBytes == nil {
		freeBytes = FreeBytes
	}
	free, err := freeBytes(s.Root)
	if err != nil {
		return err
	}
	if free < s.Reserve+n {
		return ErrCapacity
	}
	return nil
}

// flush writes file's dirty pages out and, once the store's streams staged
// archiveWritebackBytes since the last fsync, fsyncs it. Writeback alone does
// not bound dirty memory on the loop-mounted cache: the pages move to the
// backing file, still charged to the agent, until an fsync flushes the loop
// device. An fsync per block would cost the clients that send 1 MiB blocks one
// at a time (buildx) 11 ms each, against 0.2 ms for writeback. Staged bytes
// need no durability: copies are queued in memory, so after a crash none is
// copied, and the store checks every copy against its SHA-256.
func (s *ActionsStore) flush(file *os.File, n int64) error {
	if err := startWriteback(file); err != nil {
		return err
	}
	if s.unflushed.Add(n) < archiveWritebackBytes {
		return nil
	}
	s.unflushed.Store(0)
	return file.Sync()
}

// write streams body to path through a temporary file, asking for room every
// actionsRoomPerPass bytes and flushing it every archiveWritebackBytes and at
// the end. With digest it also writes the SHA-256 beside it.
func (s *ActionsStore) write(ctx context.Context, path string, body io.Reader, digest bool) (int64, error) {
	s.init()
	select {
	case s.writes <- struct{}{}:
		defer func() { <-s.writes }()
	case <-ctx.Done():
		return 0, ctx.Err()
	}
	tmp := path + ".part"
	file, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return 0, err
	}
	defer os.Remove(tmp)
	defer file.Close()
	var sum hash.Hash
	writeback := &writebackWriter{dst: file}
	writeback.sync = func() error { return s.flush(file, archiveWritebackBytes) }
	var dst io.Writer = writeback
	if digest {
		sum = sha256.New()
		dst = io.MultiWriter(dst, sum)
	}
	var written int64
	buffer := make([]byte, 1<<20)
	for {
		if err := ctx.Err(); err != nil {
			return written, err
		}
		if written%actionsRoomPerPass == 0 {
			if err := s.room(actionsRoomPerPass); err != nil {
				return written, err
			}
		}
		chunk := int64(len(buffer))
		if remaining := actionsRoomPerPass - written%actionsRoomPerPass; remaining < chunk {
			chunk = remaining
		}
		n, readErr := body.Read(buffer[:chunk])
		if n > 0 {
			if _, err := dst.Write(buffer[:n]); err != nil {
				return written, err
			}
			written += int64(n)
			if written > actionsMaxEntry {
				return written, ErrActionsUpload
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return written, readErr
		}
	}
	if err := s.flush(file, int64(writeback.pending)); err != nil {
		return written, err
	}
	if err := file.Close(); err != nil {
		return written, err
	}
	if digest {
		if err := os.WriteFile(path+".sha256", []byte(hex.EncodeToString(sum.Sum(nil))), 0o600); err != nil {
			return written, err
		}
	}
	return written, os.Rename(tmp, path)
}
