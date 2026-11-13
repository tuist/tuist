package cachevolumes

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"hash"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"sync"
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

// CommitBlocks assembles entry id from its staged blocks, in order.
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
	readers := make([]io.Reader, 0, len(blocks))
	var files []*os.File
	defer func() {
		for _, file := range files {
			file.Close()
		}
	}()
	for _, block := range blocks {
		file, err := os.Open(s.blockPath(id, block))
		if err != nil {
			return err
		}
		files = append(files, file)
		readers = append(readers, file)
	}
	if _, err := s.write(ctx, s.blob(id), io.MultiReader(readers...), true); err != nil {
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
	info, err := os.Stat(s.blob(id))
	if err != nil || info.Size() != size {
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
func (s *ActionsStore) Open(id string) (*os.File, error) {
	if !actionsEntryID.MatchString(id) || s.uploading(id) {
		return nil, os.ErrNotExist
	}
	return os.Open(s.blob(id))
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

// write streams body to path through a temporary file, asking for room every
// actionsRoomPerPass bytes, flushing every archiveWritebackBytes and syncing
// the result. With digest it also writes the SHA-256 beside it.
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
	var dst io.Writer = newWritebackWriter(file)
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
	if err := file.Sync(); err != nil {
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
