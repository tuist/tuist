// Package objstore is the S3 seam the gateway translates Azure Block
// Blob operations onto. The real implementation talks to SeaweedFS's S3
// gateway; the fake is an in-memory store used by tests, and it enforces
// the same 5 MiB multipart minimum-part rule as real S3 so the
// coalescing logic is genuinely exercised.
package objstore

import (
	"context"
	"io"
	"time"
)

// ObjectInfo is the metadata returned by HEAD/range reads.
type ObjectInfo struct {
	Size         int64
	ETag         string
	LastModified time.Time
}

// CompletedPart identifies one finished multipart part.
type CompletedPart struct {
	PartNumber int32
	ETag       string
}

// MinPartSize is S3's minimum size for any multipart part except the
// last one.
const MinPartSize = 5 << 20

// ObjectStore is the minimal S3 surface the gateway needs.
type ObjectStore interface {
	PutObject(ctx context.Context, key string, body io.Reader, size int64) error
	// GetObjectRange reads length bytes from off. length < 0 means "to
	// end". The returned reader must be closed by the caller.
	GetObjectRange(ctx context.Context, key string, off, length int64) (io.ReadCloser, *ObjectInfo, error)
	HeadObject(ctx context.Context, key string) (*ObjectInfo, error)

	CreateMultipart(ctx context.Context, key string) (uploadID string, err error)
	UploadPart(ctx context.Context, key, uploadID string, partNumber int32, body io.Reader, size int64) (etag string, err error)
	CompleteMultipart(ctx context.Context, key, uploadID string, parts []CompletedPart) error
	AbortMultipart(ctx context.Context, key, uploadID string) error
}
