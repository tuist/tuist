// Package multipart maps the Azure Block Blob staged-block protocol onto
// S3 multipart uploads. Azure lets a client stage blocks (Put Block) in
// any order and commit them in a chosen order (Put Block List); S3
// instead assembles parts in ascending part-number order and rejects any
// non-final part smaller than 5 MiB. This package bridges the two by
// buffering staged blocks and, at commit time, coalescing them in
// list-order into parts that respect the 5 MiB floor — or single-shotting
// the whole object when it is small. That makes a customer-tuned
// uploadChunkSize below 5 MiB degrade gracefully instead of failing.
package multipart

import (
	"bytes"
	"context"
	"fmt"
	"sync"

	"github.com/tuist/tuist/infra/cache-gateway/internal/objstore"
)

// Manager holds in-flight upload state keyed by the opaque blob path.
// State is process-local; a restart simply fails an in-flight upload,
// which the client retries (cache uploads are idempotent by key+version).
type Manager struct {
	store objstore.ObjectStore

	mu       sync.Mutex
	sessions map[string]*session
}

type session struct {
	mu     sync.Mutex
	blocks map[string][]byte
}

// New builds a Manager over an object store.
func New(store objstore.ObjectStore) *Manager {
	return &Manager{store: store, sessions: map[string]*session{}}
}

func (m *Manager) sessionFor(objectKey string) *session {
	m.mu.Lock()
	defer m.mu.Unlock()
	s, ok := m.sessions[objectKey]
	if !ok {
		s = &session{blocks: map[string][]byte{}}
		m.sessions[objectKey] = s
	}
	return s
}

// Discard drops any buffered state for an object key.
func (m *Manager) Discard(objectKey string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.sessions, objectKey)
}

// PutBlock buffers one staged block. Blocks may arrive in any order;
// ordering is resolved by PutBlockList.
func (m *Manager) PutBlock(_ context.Context, objectKey, blockID string, data []byte) error {
	s := m.sessionFor(objectKey)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.blocks[blockID] = append([]byte(nil), data...)
	return nil
}

// PutBlockList commits the object by walking the block IDs in the given
// order, coalescing into >=5 MiB parts (final part may be smaller), or
// single-shotting the whole object when it is below the multipart floor.
func (m *Manager) PutBlockList(ctx context.Context, objectKey string, orderedBlockIDs []string) error {
	s := m.sessionFor(objectKey)
	s.mu.Lock()
	defer s.mu.Unlock()
	defer m.Discard(objectKey)

	// Validate all referenced blocks exist before mutating the store.
	for _, id := range orderedBlockIDs {
		if _, ok := s.blocks[id]; !ok {
			return fmt.Errorf("multipart: block list references unknown block %q", id)
		}
	}

	var (
		uploadID string
		parts    []objstore.CompletedPart
		partNum  int32
		buf      bytes.Buffer
	)

	flushPart := func() error {
		if uploadID == "" {
			id, err := m.store.CreateMultipart(ctx, objectKey)
			if err != nil {
				return err
			}
			uploadID = id
		}
		partNum++
		etag, err := m.store.UploadPart(ctx, objectKey, uploadID, partNum, bytes.NewReader(buf.Bytes()), int64(buf.Len()))
		if err != nil {
			return err
		}
		parts = append(parts, objstore.CompletedPart{PartNumber: partNum, ETag: etag})
		buf.Reset()
		return nil
	}

	for _, id := range orderedBlockIDs {
		buf.Write(s.blocks[id])
		delete(s.blocks, id) // free as we consume
		if buf.Len() >= objstore.MinPartSize {
			if err := flushPart(); err != nil {
				m.abort(ctx, objectKey, uploadID)
				return err
			}
		}
	}

	if uploadID == "" {
		// Never crossed the multipart floor: one PutObject.
		if err := m.store.PutObject(ctx, objectKey, bytes.NewReader(buf.Bytes()), int64(buf.Len())); err != nil {
			return err
		}
		return nil
	}

	// Flush the trailing remainder as the final part (may be < 5 MiB).
	if buf.Len() > 0 {
		if err := flushPart(); err != nil {
			m.abort(ctx, objectKey, uploadID)
			return err
		}
	}

	if err := m.store.CompleteMultipart(ctx, objectKey, uploadID, parts); err != nil {
		m.abort(ctx, objectKey, uploadID)
		return err
	}
	return nil
}

func (m *Manager) abort(ctx context.Context, objectKey, uploadID string) {
	if uploadID == "" {
		return
	}
	_ = m.store.AbortMultipart(ctx, objectKey, uploadID)
}
