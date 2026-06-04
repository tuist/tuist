package index

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"time"

	bolt "go.etcd.io/bbolt"
)

var entriesBucket = []byte("entries-v1")

// BoltIndex is an embedded, single-file metadata index. restore_keys
// prefix matching is a cursor seek + forward walk; cache keys are only
// ever compared as raw bytes, so a controlled key can never become a
// path or a query fragment.
type BoltIndex struct {
	db *bolt.DB
}

type storedEntry struct {
	ObjectID  string `json:"o"`
	SizeBytes int64  `json:"s"`
	CreatedAt int64  `json:"c"` // unix nanos
	Scope     string `json:"sc"`
}

// OpenBolt opens (or creates) the index at path.
func OpenBolt(path string) (*BoltIndex, error) {
	db, err := bolt.Open(path, 0o600, &bolt.Options{Timeout: 2 * time.Second})
	if err != nil {
		return nil, fmt.Errorf("index: open %s: %w", path, err)
	}
	err = db.Update(func(tx *bolt.Tx) error {
		_, e := tx.CreateBucketIfNotExists(entriesBucket)
		return e
	})
	if err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("index: init bucket: %w", err)
	}
	return &BoltIndex{db: db}, nil
}

func (b *BoltIndex) Close() error { return b.db.Close() }

func (b *BoltIndex) Put(_ context.Context, account uint64, version, scope string, key []byte, e Entry) error {
	composite, err := encodeKey(account, version, scope, key)
	if err != nil {
		return err
	}
	val, err := json.Marshal(storedEntry{
		ObjectID:  e.ObjectID,
		SizeBytes: e.SizeBytes,
		CreatedAt: e.CreatedAt.UnixNano(),
		Scope:     scope,
	})
	if err != nil {
		return fmt.Errorf("index: marshal entry: %w", err)
	}
	return b.db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(entriesBucket).Put(composite, val)
	})
}

func (b *BoltIndex) GetExact(_ context.Context, account uint64, version, scope string, key []byte) (Entry, bool, error) {
	composite, err := encodeKey(account, version, scope, key)
	if err != nil {
		return Entry{}, false, err
	}
	var out Entry
	var found bool
	err = b.db.View(func(tx *bolt.Tx) error {
		raw := tx.Bucket(entriesBucket).Get(composite)
		if raw == nil {
			return nil
		}
		se, derr := decodeStored(raw)
		if derr != nil {
			return derr
		}
		out = se
		found = true
		return nil
	})
	if err != nil {
		return Entry{}, false, err
	}
	return out, found, nil
}

func (b *BoltIndex) FindByPrefix(_ context.Context, account uint64, version, scope string, prefix []byte) (Entry, bool, error) {
	partition, err := encodePartitionPrefix(account, version, scope)
	if err != nil {
		return Entry{}, false, err
	}
	seek := append(append([]byte(nil), partition...), prefix...)

	var best Entry
	var found bool
	err = b.db.View(func(tx *bolt.Tx) error {
		c := tx.Bucket(entriesBucket).Cursor()
		for k, v := c.Seek(seek); k != nil && bytes.HasPrefix(k, seek); k, v = c.Next() {
			// HasPrefix(k, seek) already constrains the walk to the
			// (account, version, scope) partition AND the user prefix,
			// because seek = partition || userPrefix and partition is a
			// fixed/length-prefixed leading region.
			se, derr := decodeStored(v)
			if derr != nil {
				return derr
			}
			if !found || se.CreatedAt.After(best.CreatedAt) {
				best = se
				found = true
			}
		}
		return nil
	})
	if err != nil {
		return Entry{}, false, err
	}
	return best, found, nil
}

func decodeStored(raw []byte) (Entry, error) {
	var se storedEntry
	if err := json.Unmarshal(raw, &se); err != nil {
		return Entry{}, fmt.Errorf("index: unmarshal entry: %w", err)
	}
	return Entry{
		ObjectID:  se.ObjectID,
		SizeBytes: se.SizeBytes,
		CreatedAt: time.Unix(0, se.CreatedAt),
		Scope:     se.Scope,
	}, nil
}
