package index

import (
	"encoding/binary"
	"errors"
)

// The composite index key encodes the tenant-scoping fields as
// fixed-width / length-prefixed segments up front and the
// workflow-controlled cache key as the trailing, raw, opaque region:
//
//	account_id (8, big-endian)
//	len(version) (2, big-endian) | version bytes
//	len(scope)   (2, big-endian) | scope bytes
//	key bytes ... (raw, trailing, no length field)
//
// Two consequences make this safe and correct:
//
//   - A lexicographic prefix scan over restore_keys can never bleed
//     across accounts, versions, or scopes: any change in those leading
//     fixed-width fields changes bytes *before* the key region, so the
//     scan stays inside one (account, version, scope) partition.
//   - The cache key is stored as raw bytes with no normalization, so
//     byte-distinct keys are distinct entries (NFC != NFD, `a%2Fb` !=
//     `a/b`, `../x` is just opaque bytes). It is a KV lookup value, never
//     a path.
//
// The key has no length field precisely because it is the terminal
// region; that is what lets a partition prefix be a strict byte prefix
// of any full key in the partition.

// maxControlledFieldLen caps version/scope at the uint16 length-prefix
// width. GitHub refs and cache versions are far below this.
const maxControlledFieldLen = 1<<16 - 1

var (
	errFieldTooLong = errors.New("index: controlled field exceeds 65535 bytes")
)

// encodePartitionPrefix returns the leading, fixed/length-prefixed
// portion shared by every entry in (account, version, scope). A prefix
// scan seeks to encodePartitionPrefix(...) + userPrefix.
func encodePartitionPrefix(account uint64, version, scope string) ([]byte, error) {
	if len(version) > maxControlledFieldLen || len(scope) > maxControlledFieldLen {
		return nil, errFieldTooLong
	}
	buf := make([]byte, 0, 8+2+len(version)+2+len(scope))
	buf = binary.BigEndian.AppendUint64(buf, account)
	buf = binary.BigEndian.AppendUint16(buf, uint16(len(version)))
	buf = append(buf, version...)
	buf = binary.BigEndian.AppendUint16(buf, uint16(len(scope)))
	buf = append(buf, scope...)
	return buf, nil
}

// encodeKey returns the full composite key for an exact entry.
func encodeKey(account uint64, version, scope string, key []byte) ([]byte, error) {
	prefix, err := encodePartitionPrefix(account, version, scope)
	if err != nil {
		return nil, err
	}
	return append(prefix, key...), nil
}

// decodeKey extracts the trailing raw cache key from a composite key. It
// is used by scans to recover the user key that matched a prefix.
func decodeKey(composite []byte) (account uint64, version, scope string, key []byte, err error) {
	if len(composite) < 8+2 {
		return 0, "", "", nil, errors.New("index: composite key too short")
	}
	account = binary.BigEndian.Uint64(composite[:8])
	off := 8

	vlen := int(binary.BigEndian.Uint16(composite[off : off+2]))
	off += 2
	if off+vlen+2 > len(composite) {
		return 0, "", "", nil, errors.New("index: truncated version field")
	}
	version = string(composite[off : off+vlen])
	off += vlen

	slen := int(binary.BigEndian.Uint16(composite[off : off+2]))
	off += 2
	if off+slen > len(composite) {
		return 0, "", "", nil, errors.New("index: truncated scope field")
	}
	scope = string(composite[off : off+slen])
	off += slen

	key = append([]byte(nil), composite[off:]...)
	return account, version, scope, key, nil
}
