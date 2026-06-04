package server

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/cache-gateway/internal/breaker"
	"github.com/tuist/tuist/infra/cache-gateway/internal/claims"
	"github.com/tuist/tuist/infra/cache-gateway/internal/index"
	"github.com/tuist/tuist/infra/cache-gateway/internal/multipart"
	"github.com/tuist/tuist/infra/cache-gateway/internal/objstore"
	"github.com/tuist/tuist/infra/cache-gateway/internal/sign"
)

type fakeVerifier struct{ byToken map[string]*claims.Claims }

func (f *fakeVerifier) Verify(_ context.Context, raw string) (*claims.Claims, error) {
	c, ok := f.byToken[raw]
	if !ok {
		return nil, errors.New("unknown token")
	}
	return c, nil
}

type harness struct {
	t     *testing.T
	srv   *Server
	ts    *httptest.Server
	store *objstore.Fake
	idx   *index.BoltIndex
	token string
}

func newHarness(t *testing.T, c *claims.Claims) *harness {
	t.Helper()
	store := objstore.NewFake()
	idx, err := index.OpenBolt(filepath.Join(t.TempDir(), "idx.db"))
	if err != nil {
		t.Fatalf("open index: %v", err)
	}
	t.Cleanup(func() { _ = idx.Close() })

	token := "tok-" + c.Repo
	srv := New(Config{
		Verifier:  &fakeVerifier{byToken: map[string]*claims.Claims{token: c}},
		Index:     idx,
		Store:     store,
		Multipart: multipart.New(store),
		Signer:    sign.New([]byte("blob-signing-secret")),
		Breaker:   breaker.New(3, time.Minute),
		URLTTL:    time.Hour,
	})
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)
	srv.cfg.BlobBaseURL = ts.URL

	return &harness{t: t, srv: srv, ts: ts, store: store, idx: idx, token: token}
}

func (h *harness) coord(method string, body any) *http.Response {
	h.t.Helper()
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, h.ts.URL+twirpServicePrefix+method, bytes.NewReader(b))
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		h.t.Fatalf("coord %s: %v", method, err)
	}
	return resp
}

func decode[T any](t *testing.T, resp *http.Response) T {
	t.Helper()
	defer resp.Body.Close()
	var v T
	if err := json.NewDecoder(resp.Body).Decode(&v); err != nil {
		t.Fatalf("decode: %v", err)
	}
	return v
}

func defaultClaims() *claims.Claims {
	return &claims.Claims{
		AccountID:     1111,
		Repo:          "tuist/tuist",
		Fleet:         "tuist-runners",
		Ref:           "refs/heads/main",
		DefaultBranch: "refs/heads/main",
		WorkflowJobID: 7,
	}
}

func TestEndToEndPutGet(t *testing.T) {
	h := newHarness(t, defaultClaims())
	payload := []byte("the cache tarball contents")

	// CreateCacheEntry -> signed upload URL.
	cr := decode[createCacheEntryResponse](t, h.coord("CreateCacheEntry", createCacheEntryRequest{Key: "Linux-deps", Version: "v2"}))
	if !cr.OK || cr.SignedUploadURL == "" {
		t.Fatalf("CreateCacheEntry: %+v", cr)
	}

	// Put Blob (single-shot) to the signed URL.
	putReq, _ := http.NewRequest(http.MethodPut, cr.SignedUploadURL, bytes.NewReader(payload))
	putReq.ContentLength = int64(len(payload))
	putResp, err := http.DefaultClient.Do(putReq)
	if err != nil {
		t.Fatalf("put blob: %v", err)
	}
	if putResp.StatusCode != http.StatusCreated {
		t.Fatalf("put blob status %d", putResp.StatusCode)
	}
	putResp.Body.Close()

	// FinalizeCacheEntry. This Heads the object at the index-derived key,
	// which only succeeds if the signed/routed/S3 keys all agree.
	fr := decode[finalizeCacheEntryResponse](t, h.coord("FinalizeCacheEntry", finalizeCacheEntryRequest{Key: "Linux-deps", Version: "v2", SizeBytes: int64(len(payload))}))
	if !fr.OK {
		t.Fatalf("FinalizeCacheEntry not ok: %+v", fr)
	}

	// GetCacheEntryDownloadURL -> signed download URL.
	gr := decode[getCacheEntryDownloadURLResponse](t, h.coord("GetCacheEntryDownloadURL", getCacheEntryDownloadURLRequest{Key: "Linux-deps", Version: "v2"}))
	if !gr.OK || gr.SignedDownloadURL == "" || gr.MatchedKey != "Linux-deps" {
		t.Fatalf("GetCacheEntryDownloadURL: %+v", gr)
	}

	// HEAD then GET the blob.
	headResp, _ := http.Head(gr.SignedDownloadURL)
	if headResp.StatusCode != http.StatusOK || headResp.Header.Get("x-ms-blob-type") != "BlockBlob" {
		t.Fatalf("head: status=%d type=%q", headResp.StatusCode, headResp.Header.Get("x-ms-blob-type"))
	}
	headResp.Body.Close()

	getResp, _ := http.Get(gr.SignedDownloadURL)
	got, _ := io.ReadAll(getResp.Body)
	getResp.Body.Close()
	if !bytes.Equal(got, payload) {
		t.Fatalf("download mismatch: got %q want %q", got, payload)
	}
}

func TestRangedDownload(t *testing.T) {
	h := newHarness(t, defaultClaims())
	payload := []byte("0123456789abcdef")
	cr := decode[createCacheEntryResponse](t, h.coord("CreateCacheEntry", createCacheEntryRequest{Key: "k", Version: "v2"}))
	putReq, _ := http.NewRequest(http.MethodPut, cr.SignedUploadURL, bytes.NewReader(payload))
	putReq.ContentLength = int64(len(payload))
	pr, _ := http.DefaultClient.Do(putReq)
	pr.Body.Close()
	_ = decode[finalizeCacheEntryResponse](t, h.coord("FinalizeCacheEntry", finalizeCacheEntryRequest{Key: "k", Version: "v2", SizeBytes: int64(len(payload))}))

	gr := decode[getCacheEntryDownloadURLResponse](t, h.coord("GetCacheEntryDownloadURL", getCacheEntryDownloadURLRequest{Key: "k", Version: "v2"}))
	req, _ := http.NewRequest(http.MethodGet, gr.SignedDownloadURL, nil)
	req.Header.Set("Range", "bytes=4-7")
	resp, _ := http.DefaultClient.Do(req)
	if resp.StatusCode != http.StatusPartialContent {
		t.Fatalf("expected 206, got %d", resp.StatusCode)
	}
	got, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if string(got) != "4567" {
		t.Fatalf("range body %q want 4567", got)
	}
}

// TestSignedRoutedS3KeyAgree proves that for every key — including
// traversal/encoding corpus — the object key embedded in the signed URL,
// the key the blob router writes under, and the key the index resolves
// to are identical. If they ever diverged, Finalize's HeadObject would
// fail; it succeeding for the whole corpus is the proof.
func TestSignedRoutedS3KeyAgree(t *testing.T) {
	corpus := []string{
		"Linux-deps",
		"../../etc/passwd",
		`..\..\windows`,
		"a%2Fb",
		"a%252Fb",
		"%2e%2e",
		"café",
		"with spaces and / slashes",
		"",
	}
	for i, key := range corpus {
		t.Run(fmt.Sprintf("case-%d", i), func(t *testing.T) {
			h := newHarness(t, defaultClaims())
			payload := []byte("payload-" + key)

			cr := decode[createCacheEntryResponse](t, h.coord("CreateCacheEntry", createCacheEntryRequest{Key: key, Version: "v2"}))
			if !cr.OK {
				t.Fatalf("create not ok for key %q", key)
			}
			// The signed URL path is the canonical object key.
			signedKey := objectKeyFromURL(t, cr.SignedUploadURL)

			putReq, _ := http.NewRequest(http.MethodPut, cr.SignedUploadURL, bytes.NewReader(payload))
			putReq.ContentLength = int64(len(payload))
			pr, err := http.DefaultClient.Do(putReq)
			if err != nil {
				t.Fatalf("put: %v", err)
			}
			pr.Body.Close()

			// The blob must now exist in the store under exactly that key.
			if _, ok := h.store.ObjectBytes(signedKey); !ok {
				t.Fatalf("store has no object under the signed key %q", signedKey)
			}

			// Finalize succeeds only if the index-derived key equals the
			// stored (S3) key equals the signed key.
			fr := decode[finalizeCacheEntryResponse](t, h.coord("FinalizeCacheEntry", finalizeCacheEntryRequest{Key: key, Version: "v2", SizeBytes: int64(len(payload))}))
			if !fr.OK {
				t.Fatalf("finalize not ok for key %q (signed=routed=s3 disagreement)", key)
			}
			if !strings.HasSuffix(signedKey, fr.EntryID) {
				t.Fatalf("signed key %q does not end with index object id %q", signedKey, fr.EntryID)
			}
		})
	}
}

func objectKeyFromURL(t *testing.T, raw string) string {
	t.Helper()
	u, err := url.Parse(raw)
	if err != nil {
		t.Fatalf("parse url: %v", err)
	}
	return strings.TrimPrefix(u.Path, sign.BlobPathPrefix)
}

func TestDownloadMissReturnsNotOK(t *testing.T) {
	h := newHarness(t, defaultClaims())
	gr := decode[getCacheEntryDownloadURLResponse](t, h.coord("GetCacheEntryDownloadURL", getCacheEntryDownloadURLRequest{Key: "never-saved", Version: "v2"}))
	if gr.OK {
		t.Fatal("miss should return ok=false")
	}
}

func TestUnknownMethodIsBadRoute(t *testing.T) {
	h := newHarness(t, defaultClaims())
	resp := h.coord("NotARealMethod", map[string]string{})
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("unknown method status %d want 404", resp.StatusCode)
	}
}

func TestInvalidTokenDegradesToMiss(t *testing.T) {
	h := newHarness(t, defaultClaims())
	b, _ := json.Marshal(getCacheEntryDownloadURLRequest{Key: "k", Version: "v2"})
	req, _ := http.NewRequest(http.MethodPost, h.ts.URL+twirpServicePrefix+"GetCacheEntryDownloadURL", bytes.NewReader(b))
	req.Header.Set("Authorization", "Bearer wrong-token")
	resp, _ := http.DefaultClient.Do(req)
	gr := decode[getCacheEntryDownloadURLResponse](t, resp)
	if gr.OK {
		t.Fatal("invalid token must not serve a cache URL")
	}
}

func TestBreakerOpenDegradesToMiss(t *testing.T) {
	h := newHarness(t, defaultClaims())
	// Trip the breaker.
	h.srv.cfg.Breaker.RecordFailure()
	h.srv.cfg.Breaker.RecordFailure()
	h.srv.cfg.Breaker.RecordFailure()

	cr := decode[createCacheEntryResponse](t, h.coord("CreateCacheEntry", createCacheEntryRequest{Key: "k", Version: "v2"}))
	if cr.OK {
		t.Fatal("breaker-open CreateCacheEntry should degrade to ok=false")
	}
}

func TestRefScopeForkIsolation(t *testing.T) {
	// A trusted job on the default branch saves an entry.
	trusted := newHarness(t, &claims.Claims{
		AccountID: 1111, Repo: "tuist/tuist", Ref: "refs/heads/main", DefaultBranch: "refs/heads/main", WorkflowJobID: 1,
	})
	payload := []byte("secret-from-main")
	cr := decode[createCacheEntryResponse](t, trusted.coord("CreateCacheEntry", createCacheEntryRequest{Key: "shared", Version: "v2"}))
	putReq, _ := http.NewRequest(http.MethodPut, cr.SignedUploadURL, bytes.NewReader(payload))
	putReq.ContentLength = int64(len(payload))
	pr, _ := http.DefaultClient.Do(putReq)
	pr.Body.Close()
	_ = decode[finalizeCacheEntryResponse](t, trusted.coord("FinalizeCacheEntry", finalizeCacheEntryRequest{Key: "shared", Version: "v2", SizeBytes: int64(len(payload))}))

	// A fork PR job, sharing the same account+index, must not resolve the
	// main-scoped entry.
	forkClaims := &claims.Claims{
		AccountID: 1111, Repo: "tuist/tuist", Ref: "refs/pull/9/merge",
		BaseRef: "refs/heads/main", DefaultBranch: "refs/heads/main", UntrustedFork: true, WorkflowJobID: 2,
	}
	fork := &harness{t: t, srv: trusted.srv, ts: trusted.ts, store: trusted.store, idx: trusted.idx, token: "fork-tok"}
	trusted.srv.cfg.Verifier.(*fakeVerifier).byToken["fork-tok"] = forkClaims

	gr := decode[getCacheEntryDownloadURLResponse](t, fork.coord("GetCacheEntryDownloadURL", getCacheEntryDownloadURLRequest{Key: "shared", Version: "v2"}))
	if gr.OK {
		t.Fatal("untrusted fork must not read a default-branch-scoped entry")
	}
}
