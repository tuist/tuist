// Package server wires the GitHub Actions cache v2 protocol surfaces:
// the Twirp coordination methods and the Azure Block Blob subset. The
// coordination surface verifies the tenant token and mints HMAC-signed
// blob URLs; the blob surface validates those signed URLs and translates
// Azure operations to S3. Unknown protocol shapes fail open: they return
// a signal the runner uses to fall back to GitHub's hosted cache.
package server

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/tuist/tuist/infra/cache-gateway/internal/breaker"
	"github.com/tuist/tuist/infra/cache-gateway/internal/claims"
	"github.com/tuist/tuist/infra/cache-gateway/internal/index"
	"github.com/tuist/tuist/infra/cache-gateway/internal/multipart"
	"github.com/tuist/tuist/infra/cache-gateway/internal/objstore"
	"github.com/tuist/tuist/infra/cache-gateway/internal/sign"
)

// twirpServicePrefix is the coordination path prefix.
const twirpServicePrefix = "/twirp/github.actions.results.api.v1.CacheService/"

// Config configures a Server.
type Config struct {
	Verifier  claims.Verifier
	Index     index.Index
	Store     objstore.ObjectStore
	Multipart *multipart.Manager
	Signer    *sign.Signer
	Breaker   *breaker.Breaker

	// BlobBaseURL is the gateway's own externally reachable base URL for
	// the blob surface (real certificate). Signed URLs point here.
	BlobBaseURL string
	// URLTTL is how long a signed blob URL is valid.
	URLTTL time.Duration
	// CoordinationTimeout bounds each coordination call.
	CoordinationTimeout time.Duration
	// BlobTimeout bounds each blob transfer call.
	BlobTimeout time.Duration

	Logger *slog.Logger
	// now is injectable for tests.
	now func() time.Time
}

// Server serves both protocol surfaces on one mux.
type Server struct {
	cfg Config
	log *slog.Logger
	now func() time.Time
}

// New builds a Server from config.
func New(cfg Config) *Server {
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	if cfg.URLTTL == 0 {
		cfg.URLTTL = time.Hour
	}
	if cfg.CoordinationTimeout == 0 {
		cfg.CoordinationTimeout = 5 * time.Second
	}
	if cfg.BlobTimeout == 0 {
		cfg.BlobTimeout = 5 * time.Minute
	}
	if cfg.Multipart == nil && cfg.Store != nil {
		cfg.Multipart = multipart.New(cfg.Store)
	}
	now := cfg.now
	if now == nil {
		now = time.Now
	}
	return &Server{cfg: cfg, log: cfg.Logger, now: now}
}

// Handler returns the HTTP handler serving both surfaces. It also serves
// /healthz on the data path so the host-side proxy (which only knows the
// data URL) can health-gate its breaker against it.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc(twirpServicePrefix, s.handleCoordination)
	mux.HandleFunc(sign.BlobPathPrefix, s.handleBlob)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	return mux
}

func (s *Server) breakerAllows() bool {
	if s.cfg.Breaker == nil {
		return true
	}
	return s.cfg.Breaker.Allow()
}

func (s *Server) recordBackend(err error) {
	if s.cfg.Breaker == nil {
		return
	}
	if err != nil {
		s.cfg.Breaker.RecordFailure()
		return
	}
	s.cfg.Breaker.RecordSuccess()
}
