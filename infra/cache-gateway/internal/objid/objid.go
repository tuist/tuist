// Package objid produces the single canonical storage key for a cache
// entry. The key is built only from the verified account id and a
// server-generated opaque id, never from any workflow-controlled input
// (the cache `key`/`restore_keys` live exclusively in the metadata
// index as parameterized values). Because both segments are drawn from
// a closed alphabet, it is structurally impossible for a request to
// inject `/`, `.` or `%` into a storage path: there is no
// concatenation of request bytes to escape from.
package objid

import (
	"crypto/rand"
	"encoding/base32"
	"fmt"
	"strconv"
)

// idAlphabet is RFC 4648 base32 lowercased with no padding: [a-z2-7].
// It contains no path separators, dots, or percent signs.
var idAlphabet = base32.NewEncoding("abcdefghijklmnopqrstuvwxyz234567").WithPadding(base32.NoPadding)

// idBytes is the entropy width of a fresh object id (128 bits).
const idBytes = 16

// New returns a fresh opaque object id: 128 bits of cryptographic
// randomness, base32-encoded to a fixed-length, lowercase, slash-free,
// dot-free, percent-free string. Two calls never collide in practice.
func New() (string, error) {
	var b [idBytes]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", fmt.Errorf("objid: read entropy: %w", err)
	}
	return idAlphabet.EncodeToString(b[:]), nil
}

// Key is the one canonical storage key, used identically by the URL
// signer, the blob router, and the S3 client. It is a pure function of
// the verified account id and a server-generated opaque id, so it can
// never contain a request-supplied byte.
//
//	Key(1111, "5f3k...") -> "acct/1111/blob/5f3k..."
func Key(accountID uint64, id string) string {
	return "acct/" + strconv.FormatUint(accountID, 10) + "/blob/" + id
}
