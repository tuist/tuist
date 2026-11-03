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
	"sort"
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
	actionsEntryIdle   = 7 * 24 * time.Hour
	actionsUploadIdle  = time.Hour
	actionsMaxBlocks   = 50_000
	actionsMaxEntry    = 10_000_000_000
	actionsRoomPerPass = 64 << 20
)

// ActionsStore keeps GitHub Actions cache entries on this host's cache
// filesystem: `uploads/<id>/` while a job sends one, `entries/<id>` once its
// save finished. An entry's mtime is its last use. Entries are a cache of the
// server's index and give way to volume masters (`Shed`); they never take the
// filesystem below Reserve.
type ActionsStore struct {
	Root      string
	Reserve   uint64
	MaxBytes  uint64
	FreeBytes func(string) (uint64, error)
	Log       *slog.Logger
	// writes bounds concurrent incoming streams, each holding up to
	// archiveWritebackBytes of dirty pages.
	writes chan struct{}
	once   sync.Once
	mu     sync.Mutex
}

func (s *ActionsStore) init() {
	s.once.Do(func() { s.writes = make(chan struct{}, 4) })
}

func (s *ActionsStore) upload(id string) string { return filepath.Join(s.Root, "uploads", id) }
func (s *ActionsStore) entry(id string) string  { return filepath.Join(s.Root, "entries", id) }

// Begin prepares the upload of entry id.
func (s *ActionsStore) Begin(id string) error {
	if !actionsEntryID.MatchString(id) {
		return ErrActionsUpload
	}
	if err := os.MkdirAll(filepath.Join(s.Root, "entries"), 0o700); err != nil {
		return err
	}
	return os.MkdirAll(filepath.Join(s.upload(id), "blocks"), 0o700)
}

// PutBlob stores a single-request upload of entry id.
func (s *ActionsStore) PutBlob(ctx context.Context, id string, body io.Reader) (int64, error) {
	if !actionsEntryID.MatchString(id) || !s.uploading(id) {
		return 0, ErrActionsUpload
	}
	return s.write(ctx, filepath.Join(s.upload(id), "blob"), body, true)
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
	if _, err := s.write(ctx, filepath.Join(s.upload(id), "blob"), io.MultiReader(readers...), true); err != nil {
		return err
	}
	return os.RemoveAll(filepath.Join(s.upload(id), "blocks"))
}

// Seal makes a finished upload of size bytes servable and returns its SHA-256.
func (s *ActionsStore) Seal(id string, size int64) (string, error) {
	if !actionsEntryID.MatchString(id) {
		return "", ErrActionsUpload
	}
	blob := filepath.Join(s.upload(id), "blob")
	info, err := os.Stat(blob)
	if err != nil || info.Size() != size {
		return "", ErrActionsUpload
	}
	sum, err := os.ReadFile(blob + ".sha256")
	if err != nil {
		return "", err
	}
	if err := os.Rename(blob, s.entry(id)); err != nil {
		return "", err
	}
	syncDir(filepath.Join(s.Root, "entries"))
	os.RemoveAll(s.upload(id))
	return string(sum), nil
}

// Install writes a copy of entry id another host saved, only into free space.
func (s *ActionsStore) Install(ctx context.Context, id string, size int64, body io.Reader) error {
	if !actionsEntryID.MatchString(id) {
		return ErrActionsUpload
	}
	if s.Has(id) {
		return nil
	}
	free, err := s.free()
	if err != nil {
		return err
	}
	if size < 0 || free < s.Reserve+uint64(size) {
		return ErrCapacity
	}
	if err := os.MkdirAll(filepath.Join(s.Root, "entries"), 0o700); err != nil {
		return err
	}
	staging := filepath.Join(s.Root, "uploads", "fetch-"+id)
	if err := os.MkdirAll(filepath.Dir(staging), 0o700); err != nil {
		return err
	}
	defer os.Remove(staging)
	written, err := s.write(ctx, staging, io.LimitReader(body, size+1), false)
	if err != nil {
		return err
	}
	if written != size {
		return fmt.Errorf("%w: received %d of %d bytes", ErrActionsUpload, written, size)
	}
	if err := os.Rename(staging, s.entry(id)); err != nil {
		return err
	}
	syncDir(filepath.Join(s.Root, "entries"))
	return nil
}

// Has reports whether this host holds entry id.
func (s *ActionsStore) Has(id string) bool {
	if !actionsEntryID.MatchString(id) {
		return false
	}
	_, err := os.Stat(s.entry(id))
	return err == nil
}

// Open opens entry id for reading and records the use.
func (s *ActionsStore) Open(id string) (*os.File, error) {
	if !actionsEntryID.MatchString(id) {
		return nil, os.ErrNotExist
	}
	file, err := os.Open(s.entry(id))
	if err != nil {
		return nil, err
	}
	now := time.Now()
	_ = os.Chtimes(s.entry(id), now, now)
	return file, nil
}

// Remove deletes entry id and any upload of it.
func (s *ActionsStore) Remove(id string) {
	if !actionsEntryID.MatchString(id) {
		return
	}
	os.Remove(s.entry(id))
	os.RemoveAll(s.upload(id))
}

// Maintain deletes uploads abandoned for an hour, entries unused for seven
// days, and the least recently used entries beyond MaxBytes.
func (s *ActionsStore) Maintain() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	uploads, _ := os.ReadDir(filepath.Join(s.Root, "uploads"))
	for _, upload := range uploads {
		if info, err := upload.Info(); err == nil && time.Since(info.ModTime()) > actionsUploadIdle {
			os.RemoveAll(filepath.Join(s.Root, "uploads", upload.Name()))
		}
	}
	entries, total, err := s.entries()
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if time.Since(entry.used) <= actionsEntryIdle && (s.MaxBytes == 0 || total <= s.MaxBytes) {
			continue
		}
		reason := EvictExpired
		if time.Since(entry.used) <= actionsEntryIdle {
			reason = EvictIdle
		}
		if err := os.Remove(entry.path); err == nil {
			total -= entry.bytes
			logger(s.Log).Info("actions cache entry evicted", "reason", reason, "bytes", entry.bytes)
		}
	}
	return nil
}

// Shed evicts the least recently used entries while free space is below
// minimum, so volume masters never give way to them. Reports whether it
// evicted any.
func (s *ActionsStore) Shed(ctx context.Context, minimum uint64) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	entries, _, err := s.entries()
	if err != nil {
		return false
	}
	evicted := false
	for _, entry := range entries {
		if ctx.Err() != nil {
			break
		}
		if free, err := s.free(); err != nil || free >= minimum {
			break
		}
		if os.Remove(entry.path) == nil {
			evicted = true
			logger(s.Log).Info("actions cache entry evicted", "reason", "pressure", "bytes", entry.bytes, "needed_bytes", minimum)
		}
	}
	return evicted
}

type actionsEntry struct {
	path  string
	bytes uint64
	used  time.Time
}

// entries lists stored entries, least recently used first, with their total size.
func (s *ActionsStore) entries() ([]actionsEntry, uint64, error) {
	dir := filepath.Join(s.Root, "entries")
	names, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil, 0, nil
	}
	if err != nil {
		return nil, 0, err
	}
	var entries []actionsEntry
	var total uint64
	for _, name := range names {
		info, err := name.Info()
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		bytes := uint64(allocatedBytes(filepath.Join(dir, name.Name())))
		entries = append(entries, actionsEntry{path: filepath.Join(dir, name.Name()), bytes: bytes, used: info.ModTime()})
		total += bytes
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].used.Before(entries[j].used) })
	return entries, total, nil
}

func (s *ActionsStore) uploading(id string) bool {
	info, err := os.Stat(filepath.Join(s.upload(id), "blocks"))
	return err == nil && info.IsDir()
}

func (s *ActionsStore) blockPath(id, block string) string {
	return filepath.Join(s.upload(id), "blocks", hex.EncodeToString([]byte(block)))
}

func (s *ActionsStore) free() (uint64, error) {
	if s.FreeBytes == nil {
		return FreeBytes(s.Root)
	}
	return s.FreeBytes(s.Root)
}

// room admits n more bytes above the reserve, evicting this store's least
// recently used entries when that makes the room.
func (s *ActionsStore) room(n uint64) error {
	free, err := s.free()
	if err != nil {
		return err
	}
	if free >= s.Reserve+n {
		return nil
	}
	if s.Shed(context.Background(), s.Reserve+n) {
		if free, err = s.free(); err == nil && free >= s.Reserve+n {
			return nil
		}
	}
	return ErrCapacity
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

func syncDir(path string) {
	if dir, err := os.Open(path); err == nil {
		dir.Sync()
		dir.Close()
	}
}
