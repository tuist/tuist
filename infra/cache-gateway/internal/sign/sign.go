// Package sign mints and verifies HMAC-signed blob URLs. The signature
// covers a canonical subset (operation, opaque object key, expiry) and
// deliberately ignores every other query parameter, so the Azure Blob
// SDK appending `&comp=block&blockid=...` to a URL after we signed it
// does not break verification. The signed URL is the only credential on
// the blob surface (the SAS-URL pattern); no bearer token is used there.
package sign

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Op is the coarse operation class a signed URL authorizes. Uploads get
// a put URL; downloads get a read URL that covers both the SDK's HEAD
// (get blob properties) and its ranged GETs.
type Op string

const (
	OpPut  Op = "put"
	OpRead Op = "read"
)

// BlobPathPrefix is the URL path prefix under which opaque object keys
// are served, e.g. /blob/acct/1111/blob/<id>.
const BlobPathPrefix = "/blob/"

const (
	paramOp  = "sigop"
	paramExp = "sigexp"
	paramSig = "sig"
)

// Signer mints and verifies signed blob URLs.
type Signer struct {
	secret []byte
	now    func() time.Time
}

// New builds a Signer from a shared HMAC secret.
func New(secret []byte) *Signer {
	return &Signer{secret: secret, now: time.Now}
}

func canonical(op Op, objectKey string, exp int64) string {
	return string(op) + "\n" + objectKey + "\n" + strconv.FormatInt(exp, 10)
}

func (s *Signer) mac(op Op, objectKey string, exp int64) string {
	m := hmac.New(sha256.New, s.secret)
	m.Write([]byte(canonical(op, objectKey, exp)))
	return base64.RawURLEncoding.EncodeToString(m.Sum(nil))
}

// SignedQuery returns the auth query parameters for an object key, op and
// expiry. The caller composes the full URL as
// baseURL + BlobPathPrefix + objectKey + "?" + SignedQuery(...).Encode().
func (s *Signer) SignedQuery(objectKey string, op Op, expiry time.Time) url.Values {
	exp := expiry.Unix()
	q := url.Values{}
	q.Set(paramOp, string(op))
	q.Set(paramExp, strconv.FormatInt(exp, 10))
	q.Set(paramSig, s.mac(op, objectKey, exp))
	return q
}

// SignedURL returns a full signed URL for objectKey rooted at base.
func (s *Signer) SignedURL(base, objectKey string, op Op, expiry time.Time) string {
	b := strings.TrimRight(base, "/")
	return b + BlobPathPrefix + objectKey + "?" + s.SignedQuery(objectKey, op, expiry).Encode()
}

// Verify validates the signed URL on r. It extracts the object key from
// the path, recomputes the HMAC over the canonical subset, constant-time
// compares, and checks expiry. Any non-signing query parameter (the
// Azure SDK's comp/blockid/timeout/...) is ignored by construction.
func (s *Signer) Verify(r *http.Request) (objectKey string, op Op, err error) {
	if !strings.HasPrefix(r.URL.Path, BlobPathPrefix) {
		return "", "", fmt.Errorf("sign: path %q is not under %s", r.URL.Path, BlobPathPrefix)
	}
	objectKey = strings.TrimPrefix(r.URL.Path, BlobPathPrefix)
	if objectKey == "" {
		return "", "", fmt.Errorf("sign: empty object key")
	}

	q := r.URL.Query()
	op = Op(q.Get(paramOp))
	switch op {
	case OpPut, OpRead:
	default:
		return "", "", fmt.Errorf("sign: unknown op %q", op)
	}

	exp, perr := strconv.ParseInt(q.Get(paramExp), 10, 64)
	if perr != nil {
		return "", "", fmt.Errorf("sign: bad exp: %w", perr)
	}

	want := s.mac(op, objectKey, exp)
	got := q.Get(paramSig)
	if !hmac.Equal([]byte(want), []byte(got)) {
		return "", "", fmt.Errorf("sign: signature mismatch")
	}
	if s.now().Unix() > exp {
		return "", "", fmt.Errorf("sign: url expired")
	}
	return objectKey, op, nil
}
