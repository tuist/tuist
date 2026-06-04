// Package index is the small metadata index that maps a tenant's cache
// key (workflow-controlled, opaque) to a server-generated object id. The
// cache key is only ever a parameterized lookup value here; it never
// becomes a storage path, URL, or signed string.
package index

import (
	"context"
	"time"
)

// Entry is the indexed metadata for one cache entry. ObjectID is the
// opaque, server-generated storage id; it is the only thing that becomes
// part of an S3 key.
type Entry struct {
	ObjectID  string
	SizeBytes int64
	CreatedAt time.Time
	Scope     string
}

// Index records and resolves cache entries. Implementations must treat
// the key argument as opaque bytes and never normalize it.
type Index interface {
	// Put records (account, version, scope, key) -> entry. A later Put
	// with the same composite key overwrites; on read, newest CreatedAt
	// wins among prefix matches.
	Put(ctx context.Context, account uint64, version, scope string, key []byte, e Entry) error

	// GetExact resolves an exact (account, version, scope, key) tuple.
	GetExact(ctx context.Context, account uint64, version, scope string, key []byte) (Entry, bool, error)

	// FindByPrefix returns the newest entry whose stored key has the
	// given prefix within (account, version, scope). An empty prefix
	// matches every key in the partition. It never returns an entry from
	// another account, version, or scope.
	FindByPrefix(ctx context.Context, account uint64, version, scope string, prefix []byte) (Entry, bool, error)

	Close() error
}
