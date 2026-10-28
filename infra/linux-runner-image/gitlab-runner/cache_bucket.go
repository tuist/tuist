package main

import (
	"context"
	"errors"
	"net/url"
	"os"
	"time"

	"gocloud.dev/blob"
	"gocloud.dev/blob/driver"
	"gocloud.dev/gcerrors"
)

// GitLab Runner's cache archiver writes to a Go CDK bucket when the adapter
// returns a Go CDK URL. The `tuist` scheme uploads that stream in parts through
// URLs the Tuist server presigns, so archives are not capped by a single PUT.
const (
	cacheURLScheme   = "tuist"
	cacheEndpointEnv = "TUIST_GITLAB_CACHE_ENDPOINT"
	cacheTokenEnv    = "TUIST_GITLAB_CACHE_TOKEN"
	cachePartSize    = 64 << 20
)

var (
	errCacheObjectNotFound  = errors.New("cache object not found")
	errCacheNotSupported    = errors.New("not supported by the Tuist cache bucket")
	errCacheMissingEndpoint = errors.New("Tuist cache endpoint is not configured")
)

func init() {
	blob.DefaultURLMux().RegisterBucket(cacheURLScheme, cacheBucketOpener{})
}

type cacheBucketOpener struct{}

func (cacheBucketOpener) OpenBucketURL(_ context.Context, _ *url.URL) (*blob.Bucket, error) {
	endpoint, token := os.Getenv(cacheEndpointEnv), os.Getenv(cacheTokenEnv)
	if endpoint == "" || token == "" {
		return nil, errCacheMissingEndpoint
	}
	return blob.NewBucket(&cacheBucket{client: newCacheClient(endpoint, token), partSize: cachePartSize}), nil
}

type cacheBucket struct {
	client   *cacheClient
	partSize int
}

func (b *cacheBucket) NewTypedWriter(ctx context.Context, key, _ string, _ *driver.WriterOptions) (driver.Writer, error) {
	return &cacheWriter{ctx: ctx, client: b.client, objectName: key, partSize: b.partSize}, nil
}

// The archiver only asks for attributes to decide whether to upload, so an
// unknown object is always reported as absent.
func (b *cacheBucket) Attributes(context.Context, string) (*driver.Attributes, error) {
	return nil, errCacheObjectNotFound
}

func (b *cacheBucket) ErrorCode(err error) gcerrors.ErrorCode {
	switch {
	case errors.Is(err, errCacheObjectNotFound):
		return gcerrors.NotFound
	case errors.Is(err, errCacheNotSupported):
		return gcerrors.Unimplemented
	default:
		return gcerrors.Unknown
	}
}

func (b *cacheBucket) As(any) bool             { return false }
func (b *cacheBucket) ErrorAs(error, any) bool { return false }
func (b *cacheBucket) Close() error            { return nil }

func (b *cacheBucket) ListPaged(context.Context, *driver.ListOptions) (*driver.ListPage, error) {
	return nil, errCacheNotSupported
}

func (b *cacheBucket) NewRangeReader(context.Context, string, int64, int64, *driver.ReaderOptions) (driver.Reader, error) {
	return nil, errCacheNotSupported
}

func (b *cacheBucket) Copy(context.Context, string, string, *driver.CopyOptions) error {
	return errCacheNotSupported
}

func (b *cacheBucket) Delete(context.Context, string) error { return errCacheNotSupported }

func (b *cacheBucket) SignedURL(context.Context, string, *driver.SignedURLOptions) (string, error) {
	return "", errCacheNotSupported
}

type cachePart struct {
	PartNumber int    `json:"part_number"`
	ETag       string `json:"etag"`
}

// cacheWriter buffers one part at a time, so memory stays at one part size
// however large the archive is.
type cacheWriter struct {
	ctx        context.Context
	client     *cacheClient
	objectName string
	partSize   int
	buffer     []byte
	uploadID   string
	parts      []cachePart
	err        error
}

func (w *cacheWriter) Write(p []byte) (int, error) {
	if w.err != nil {
		return 0, w.err
	}
	written := 0
	for len(p) > 0 {
		if w.buffer == nil {
			w.buffer = make([]byte, 0, w.partSize)
		}
		n := min(len(p), w.partSize-len(w.buffer))
		w.buffer = append(w.buffer, p[:n]...)
		p, written = p[n:], written+n
		if len(w.buffer) == w.partSize {
			if w.err = w.flush(); w.err != nil {
				return written, w.err
			}
		}
	}
	return written, nil
}

// Close completes the upload, or aborts it when the write failed or its
// context was cancelled, which is how the archiver abandons a copy.
func (w *cacheWriter) Close() error {
	if w.err == nil {
		w.err = w.ctx.Err()
	}
	if w.err == nil && (len(w.buffer) > 0 || len(w.parts) == 0) {
		w.err = w.flush()
	}
	if w.err == nil {
		w.err = w.client.post(w.ctx, "cache/uploads/complete", map[string]any{
			"object_name": w.objectName, "upload_id": w.uploadID, "parts": w.parts,
		}, nil)
	}
	if w.err != nil && w.uploadID != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_ = w.client.post(ctx, "cache/uploads/abort", map[string]any{"object_name": w.objectName, "upload_id": w.uploadID}, nil)
	}
	return w.err
}

func (w *cacheWriter) flush() error {
	if w.uploadID == "" {
		var started struct {
			UploadID string `json:"upload_id"`
		}
		if err := w.client.post(w.ctx, "cache/uploads", map[string]any{"object_name": w.objectName}, &started); err != nil {
			return err
		}
		if started.UploadID == "" {
			return errCacheRejected
		}
		w.uploadID = started.UploadID
	}
	number := len(w.parts) + 1
	var part struct {
		URL string `json:"url"`
	}
	if err := w.client.post(w.ctx, "cache/uploads/part", map[string]any{
		"object_name": w.objectName, "upload_id": w.uploadID, "part_number": number,
	}, &part); err != nil {
		return err
	}
	if presigned(part.URL).URL == nil {
		return errCacheRejected
	}
	etag, err := w.client.putPart(w.ctx, part.URL, w.buffer)
	if err != nil {
		return err
	}
	w.parts = append(w.parts, cachePart{PartNumber: number, ETag: etag})
	w.buffer = w.buffer[:0]
	return nil
}
