package server

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"github.com/tuist/tuist/infra/cache-gateway/internal/claims"
	"github.com/tuist/tuist/infra/cache-gateway/internal/index"
	"github.com/tuist/tuist/infra/cache-gateway/internal/metrics"
	"github.com/tuist/tuist/infra/cache-gateway/internal/objid"
	"github.com/tuist/tuist/infra/cache-gateway/internal/sign"
)

// Field names follow proto3 JSON (lowerCamelCase), the wire format the
// actions/toolkit cache client uses. The exact shape is re-validated
// against a real actions/cache run at rollout (RFC rollout step 2).

type createCacheEntryRequest struct {
	Key     string `json:"key"`
	Version string `json:"version"`
}

type createCacheEntryResponse struct {
	OK              bool   `json:"ok"`
	SignedUploadURL string `json:"signedUploadUrl,omitempty"`
}

type finalizeCacheEntryRequest struct {
	Key       string `json:"key"`
	Version   string `json:"version"`
	SizeBytes int64  `json:"sizeBytes"`
}

type finalizeCacheEntryResponse struct {
	OK      bool   `json:"ok"`
	EntryID string `json:"entryId,omitempty"`
}

type getCacheEntryDownloadURLRequest struct {
	Key         string   `json:"key"`
	RestoreKeys []string `json:"restoreKeys"`
	Version     string   `json:"version"`
}

type getCacheEntryDownloadURLResponse struct {
	OK                bool   `json:"ok"`
	SignedDownloadURL string `json:"signedDownloadUrl,omitempty"`
	MatchedKey        string `json:"matchedKey,omitempty"`
}

func (s *Server) handleCoordination(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeTwirpError(w, http.StatusMethodNotAllowed, "bad_method", "expected POST")
		return
	}
	method := strings.TrimPrefix(r.URL.Path, twirpServicePrefix)

	ctx, cancel := context.WithTimeout(r.Context(), s.cfg.CoordinationTimeout)
	defer cancel()

	switch method {
	case "CreateCacheEntry":
		s.handleCreate(ctx, w, r)
	case "FinalizeCacheEntry":
		s.handleFinalize(ctx, w, r)
	case "GetCacheEntryDownloadURL":
		s.handleGetDownloadURL(ctx, w, r)
	default:
		// Unknown method: an unrecognized protocol shape. Record it and
		// return a Twirp bad_route so the proxy/runner degrades to
		// GitHub's hosted cache rather than seeing a malformed success.
		metrics.PassthroughFallback.WithLabelValues("unknown_shape").Inc()
		metrics.ProtocolShape.WithLabelValues("CacheService", method, "v2", "false").Inc()
		writeTwirpError(w, http.StatusNotFound, "bad_route", "unknown method")
	}
}

// verify extracts and validates the bearer token. A failure degrades to
// a cache miss: the caller returns {ok:false}, which actions/cache
// treats as a miss/skip (a warning, never a job failure), and grants no
// cache access at all.
func (s *Server) verify(ctx context.Context, r *http.Request) (*claims.Claims, bool) {
	raw := bearer(r)
	if raw == "" {
		return nil, false
	}
	c, err := s.cfg.Verifier.Verify(ctx, raw)
	if err != nil {
		s.log.Warn("cache token verification failed", "err", err)
		return nil, false
	}
	return c, true
}

func bearer(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if len(h) > 7 && strings.EqualFold(h[:7], "Bearer ") {
		return h[7:]
	}
	return ""
}

func (s *Server) handleCreate(ctx context.Context, w http.ResponseWriter, r *http.Request) {
	metrics.ProtocolShape.WithLabelValues("CacheService", "CreateCacheEntry", "v2", "true").Inc()

	var req createCacheEntryRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	c, ok := s.verify(ctx, r)
	if !ok {
		writeJSON(w, http.StatusOK, createCacheEntryResponse{OK: false})
		return
	}
	if !s.breakerAllows() {
		metrics.PassthroughFallback.WithLabelValues("breaker").Inc()
		metrics.Coordination.WithLabelValues("CreateCacheEntry", "error").Inc()
		writeJSON(w, http.StatusOK, createCacheEntryResponse{OK: false})
		return
	}

	id, err := objid.New()
	if err != nil {
		s.log.Error("objid generation failed", "err", err)
		metrics.Coordination.WithLabelValues("CreateCacheEntry", "error").Inc()
		writeJSON(w, http.StatusOK, createCacheEntryResponse{OK: false})
		return
	}
	scope := claims.WriteScope(c)
	// Reserve the entry; size and final CreatedAt are set on finalize.
	err = s.cfg.Index.Put(ctx, c.AccountID, req.Version, scope, []byte(req.Key), index.Entry{
		ObjectID:  id,
		CreatedAt: s.now(),
		Scope:     scope,
	})
	s.recordBackend(err)
	if err != nil {
		s.log.Error("index put failed", "err", err)
		metrics.PassthroughFallback.WithLabelValues("timeout").Inc()
		metrics.Coordination.WithLabelValues("CreateCacheEntry", "error").Inc()
		writeJSON(w, http.StatusOK, createCacheEntryResponse{OK: false})
		return
	}

	objKey := objid.Key(c.AccountID, id)
	url := s.cfg.Signer.SignedURL(s.cfg.BlobBaseURL, objKey, sign.OpPut, s.now().Add(s.cfg.URLTTL))
	metrics.Coordination.WithLabelValues("CreateCacheEntry", "ok").Inc()
	writeJSON(w, http.StatusOK, createCacheEntryResponse{OK: true, SignedUploadURL: url})
}

func (s *Server) handleFinalize(ctx context.Context, w http.ResponseWriter, r *http.Request) {
	metrics.ProtocolShape.WithLabelValues("CacheService", "FinalizeCacheEntry", "v2", "true").Inc()

	var req finalizeCacheEntryRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	c, ok := s.verify(ctx, r)
	if !ok {
		writeJSON(w, http.StatusOK, finalizeCacheEntryResponse{OK: false})
		return
	}

	scope := claims.WriteScope(c)
	entry, found, err := s.cfg.Index.GetExact(ctx, c.AccountID, req.Version, scope, []byte(req.Key))
	s.recordBackend(err)
	if err != nil || !found {
		metrics.Coordination.WithLabelValues("FinalizeCacheEntry", "error").Inc()
		writeJSON(w, http.StatusOK, finalizeCacheEntryResponse{OK: false})
		return
	}

	objKey := objid.Key(c.AccountID, entry.ObjectID)
	info, err := s.cfg.Store.HeadObject(ctx, objKey)
	s.recordBackend(err)
	if err != nil {
		// The blob did not land; do not commit the entry.
		metrics.Coordination.WithLabelValues("FinalizeCacheEntry", "error").Inc()
		writeJSON(w, http.StatusOK, finalizeCacheEntryResponse{OK: false})
		return
	}

	// Commit: stamp size + a fresh CreatedAt so newest-wins resolves to
	// the most recently finalized entry for this key.
	entry.SizeBytes = info.Size
	entry.CreatedAt = s.now()
	if err := s.cfg.Index.Put(ctx, c.AccountID, req.Version, scope, []byte(req.Key), entry); err != nil {
		metrics.Coordination.WithLabelValues("FinalizeCacheEntry", "error").Inc()
		writeJSON(w, http.StatusOK, finalizeCacheEntryResponse{OK: false})
		return
	}
	metrics.Coordination.WithLabelValues("FinalizeCacheEntry", "ok").Inc()
	writeJSON(w, http.StatusOK, finalizeCacheEntryResponse{OK: true, EntryID: entry.ObjectID})
}

func (s *Server) handleGetDownloadURL(ctx context.Context, w http.ResponseWriter, r *http.Request) {
	metrics.ProtocolShape.WithLabelValues("CacheService", "GetCacheEntryDownloadURL", "v2", "true").Inc()

	var req getCacheEntryDownloadURLRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	c, ok := s.verify(ctx, r)
	if !ok {
		writeJSON(w, http.StatusOK, getCacheEntryDownloadURLResponse{OK: false})
		return
	}
	if !s.breakerAllows() {
		metrics.PassthroughFallback.WithLabelValues("breaker").Inc()
		writeJSON(w, http.StatusOK, getCacheEntryDownloadURLResponse{OK: false})
		return
	}

	entry, matchedKey, match := s.resolve(ctx, c, req)
	if match == "miss" {
		metrics.CacheHit.WithLabelValues("miss").Inc()
		metrics.Coordination.WithLabelValues("GetCacheEntryDownloadURL", "ok").Inc()
		writeJSON(w, http.StatusOK, getCacheEntryDownloadURLResponse{OK: false})
		return
	}

	objKey := objid.Key(c.AccountID, entry.ObjectID)
	url := s.cfg.Signer.SignedURL(s.cfg.BlobBaseURL, objKey, sign.OpRead, s.now().Add(s.cfg.URLTTL))
	metrics.CacheHit.WithLabelValues(match).Inc()
	metrics.Coordination.WithLabelValues("GetCacheEntryDownloadURL", "ok").Inc()
	writeJSON(w, http.StatusOK, getCacheEntryDownloadURLResponse{
		OK:                true,
		SignedDownloadURL: url,
		MatchedKey:        matchedKey,
	})
}

// resolve applies GitHub's scope precedence: for each scope candidate in
// order, an exact key match wins, then restore-key prefixes (newest
// wins). The first scope to yield a match returns. match is "exact",
// "restore", or "miss".
func (s *Server) resolve(ctx context.Context, c *claims.Claims, req getCacheEntryDownloadURLRequest) (index.Entry, string, string) {
	for _, scope := range claims.ReadScopeOrder(c) {
		if entry, found, err := s.cfg.Index.GetExact(ctx, c.AccountID, req.Version, scope, []byte(req.Key)); err == nil && found {
			return entry, req.Key, "exact"
		}
		for _, prefix := range req.RestoreKeys {
			if entry, found, err := s.cfg.Index.FindByPrefix(ctx, c.AccountID, req.Version, scope, []byte(prefix)); err == nil && found {
				return entry, prefix, "restore"
			}
		}
	}
	return index.Entry{}, "", "miss"
}

func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(dst); err != nil {
		writeTwirpError(w, http.StatusBadRequest, "malformed", "invalid request body")
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeTwirpError(w http.ResponseWriter, status int, code, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"code": code, "msg": msg})
}
