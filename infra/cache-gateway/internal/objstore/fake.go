package objstore

import (
	"bytes"
	"context"
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"io"
	"sort"
	"sync"
	"time"
)

// Fake is an in-memory ObjectStore for tests. It enforces the real-S3
// 5 MiB minimum-part rule on CompleteMultipart so the gateway's block
// coalescing is exercised end to end.
type Fake struct {
	mu        sync.Mutex
	objects   map[string]fakeObject
	uploads   map[string]*fakeUpload
	uploadSeq int

	// now is injectable; defaults to a fixed clock so tests are
	// deterministic without using time.Now.
	now func() time.Time
}

type fakeObject struct {
	data         []byte
	etag         string
	lastModified time.Time
}

type fakeUpload struct {
	key   string
	parts map[int32][]byte
}

// NewFake builds an empty in-memory store.
func NewFake() *Fake {
	return &Fake{
		objects: map[string]fakeObject{},
		uploads: map[string]*fakeUpload{},
		now:     func() time.Time { return time.Unix(1_700_000_000, 0) },
	}
}

func etagOf(b []byte) string {
	sum := md5.Sum(b)
	return `"` + hex.EncodeToString(sum[:]) + `"`
}

func (f *Fake) PutObject(_ context.Context, key string, body io.Reader, _ int64) error {
	data, err := io.ReadAll(body)
	if err != nil {
		return err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.objects[key] = fakeObject{data: data, etag: etagOf(data), lastModified: f.now()}
	return nil
}

func (f *Fake) GetObjectRange(_ context.Context, key string, off, length int64) (io.ReadCloser, *ObjectInfo, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	obj, ok := f.objects[key]
	if !ok {
		return nil, nil, fmt.Errorf("objstore: key not found: %s", key)
	}
	if off < 0 || off > int64(len(obj.data)) {
		return nil, nil, fmt.Errorf("objstore: range start out of bounds")
	}
	end := int64(len(obj.data))
	if length >= 0 && off+length < end {
		end = off + length
	}
	chunk := append([]byte(nil), obj.data[off:end]...)
	info := &ObjectInfo{Size: int64(len(obj.data)), ETag: obj.etag, LastModified: obj.lastModified}
	return io.NopCloser(bytes.NewReader(chunk)), info, nil
}

func (f *Fake) HeadObject(_ context.Context, key string) (*ObjectInfo, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	obj, ok := f.objects[key]
	if !ok {
		return nil, fmt.Errorf("objstore: key not found: %s", key)
	}
	return &ObjectInfo{Size: int64(len(obj.data)), ETag: obj.etag, LastModified: obj.lastModified}, nil
}

func (f *Fake) CreateMultipart(_ context.Context, key string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.uploadSeq++
	id := fmt.Sprintf("upload-%d", f.uploadSeq)
	f.uploads[id] = &fakeUpload{key: key, parts: map[int32][]byte{}}
	return id, nil
}

func (f *Fake) UploadPart(_ context.Context, _ string, uploadID string, partNumber int32, body io.Reader, _ int64) (string, error) {
	data, err := io.ReadAll(body)
	if err != nil {
		return "", err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	up, ok := f.uploads[uploadID]
	if !ok {
		return "", fmt.Errorf("objstore: unknown upload %s", uploadID)
	}
	up.parts[partNumber] = data
	return etagOf(data), nil
}

func (f *Fake) CompleteMultipart(_ context.Context, key, uploadID string, parts []CompletedPart) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	up, ok := f.uploads[uploadID]
	if !ok {
		return fmt.Errorf("objstore: unknown upload %s", uploadID)
	}
	ordered := append([]CompletedPart(nil), parts...)
	sort.Slice(ordered, func(i, j int) bool { return ordered[i].PartNumber < ordered[j].PartNumber })

	var assembled bytes.Buffer
	for i, p := range ordered {
		data, ok := up.parts[p.PartNumber]
		if !ok {
			return fmt.Errorf("objstore: missing part %d", p.PartNumber)
		}
		isLast := i == len(ordered)-1
		if !isLast && len(data) < MinPartSize {
			return fmt.Errorf("objstore: EntityTooSmall: part %d is %d bytes, below the 5 MiB minimum", p.PartNumber, len(data))
		}
		assembled.Write(data)
	}
	f.objects[key] = fakeObject{data: assembled.Bytes(), etag: etagOf(assembled.Bytes()), lastModified: f.now()}
	delete(f.uploads, uploadID)
	return nil
}

func (f *Fake) AbortMultipart(_ context.Context, _ string, uploadID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.uploads, uploadID)
	return nil
}

// ObjectBytes returns a copy of a stored object's bytes (test helper).
func (f *Fake) ObjectBytes(key string) ([]byte, bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	obj, ok := f.objects[key]
	if !ok {
		return nil, false
	}
	return append([]byte(nil), obj.data...), true
}

// OpenUploads returns the count of in-flight multipart uploads (test
// helper for asserting aborts cleaned up).
func (f *Fake) OpenUploads() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.uploads)
}
