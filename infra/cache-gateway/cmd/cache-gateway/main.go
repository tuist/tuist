// Command cache-gateway terminates the GitHub Actions cache v2 protocol
// (Twirp coordination + Azure Block Blob transfer) inside a runner fleet
// and translates it to S3 against a co-located SeaweedFS cluster. It is
// one instance per fleet, fronted by the host-side runner-cache-proxy.
package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/tuist/tuist/infra/cache-gateway/internal/breaker"
	"github.com/tuist/tuist/infra/cache-gateway/internal/claims"
	"github.com/tuist/tuist/infra/cache-gateway/internal/index"
	"github.com/tuist/tuist/infra/cache-gateway/internal/multipart"
	"github.com/tuist/tuist/infra/cache-gateway/internal/objstore"
	"github.com/tuist/tuist/infra/cache-gateway/internal/server"
	"github.com/tuist/tuist/infra/cache-gateway/internal/sign"
)

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	var (
		dataBind    = flag.String("data-bind-address", envOr("CACHE_GATEWAY_DATA_BIND", ":8080"), "data surface (coordination + blob) listen address")
		metricsBind = flag.String("metrics-bind-address", envOr("CACHE_GATEWAY_METRICS_BIND", ":9090"), "metrics + health listen address")
		blobBaseURL = flag.String("blob-base-url", os.Getenv("CACHE_GATEWAY_BLOB_BASE_URL"), "externally reachable base URL of the blob surface (real certificate)")
		indexPath   = flag.String("index-path", envOr("CACHE_GATEWAY_INDEX_PATH", "/data/index.db"), "bbolt metadata index file path")
		pubKeyFile  = flag.String("token-public-key-file", os.Getenv("CACHE_GATEWAY_TOKEN_PUBLIC_KEY_FILE"), "PEM Ed25519 public key used to verify tenant tokens")
		signSecretF = flag.String("url-signing-secret-file", os.Getenv("CACHE_GATEWAY_URL_SIGNING_SECRET_FILE"), "file holding the HMAC blob-URL signing secret")
		urlTTL      = flag.Duration("url-ttl", 1*time.Hour, "validity window for signed blob URLs")

		s3Endpoint = flag.String("s3-endpoint", os.Getenv("CACHE_GATEWAY_S3_ENDPOINT"), "SeaweedFS S3 endpoint")
		s3Region   = flag.String("s3-region", envOr("CACHE_GATEWAY_S3_REGION", "us-east-1"), "S3 region")
		s3Bucket   = flag.String("s3-bucket", envOr("CACHE_GATEWAY_S3_BUCKET", "gha-cache"), "S3 bucket")
	)
	flag.Parse()

	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(log)

	if *blobBaseURL == "" || *pubKeyFile == "" || *signSecretF == "" || *s3Endpoint == "" {
		log.Error("missing required configuration", "need", "blob-base-url, token-public-key-file, url-signing-secret-file, s3-endpoint")
		os.Exit(1)
	}

	pubKey, err := os.ReadFile(*pubKeyFile)
	if err != nil {
		log.Error("read token public key", "err", err)
		os.Exit(1)
	}
	verifier, err := claims.NewEd25519Verifier(pubKey)
	if err != nil {
		log.Error("build token verifier", "err", err)
		os.Exit(1)
	}

	signSecret, err := os.ReadFile(*signSecretF)
	if err != nil {
		log.Error("read url signing secret", "err", err)
		os.Exit(1)
	}

	idx, err := index.OpenBolt(*indexPath)
	if err != nil {
		log.Error("open index", "err", err)
		os.Exit(1)
	}
	defer idx.Close()

	store, err := objstore.NewS3(objstore.S3Config{
		Endpoint:        *s3Endpoint,
		Region:          *s3Region,
		Bucket:          *s3Bucket,
		AccessKeyID:     os.Getenv("CACHE_GATEWAY_S3_ACCESS_KEY_ID"),
		SecretAccessKey: os.Getenv("CACHE_GATEWAY_S3_SECRET_ACCESS_KEY"),
	})
	if err != nil {
		log.Error("build s3 store", "err", err)
		os.Exit(1)
	}

	srv := server.New(server.Config{
		Verifier:    verifier,
		Index:       idx,
		Store:       store,
		Multipart:   multipart.New(store),
		Signer:      sign.New(trimNewline(signSecret)),
		Breaker:     breaker.New(5, 10*time.Second),
		BlobBaseURL: *blobBaseURL,
		URLTTL:      *urlTTL,
		Logger:      log,
	})

	dataSrv := &http.Server{Addr: *dataBind, Handler: srv.Handler(), ReadHeaderTimeout: 10 * time.Second}

	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	metricsSrv := &http.Server{Addr: *metricsBind, Handler: mux, ReadHeaderTimeout: 10 * time.Second}

	go func() {
		log.Info("cache-gateway metrics listening", "addr", *metricsBind)
		if err := metricsSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("metrics server exited", "err", err)
		}
	}()
	go func() {
		log.Info("cache-gateway data listening", "addr", *dataBind)
		if err := dataSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("data server exited", "err", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Info("cache-gateway shutting down")

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	_ = dataSrv.Shutdown(ctx)
	_ = metricsSrv.Shutdown(ctx)
}

func trimNewline(b []byte) []byte {
	for len(b) > 0 && (b[len(b)-1] == '\n' || b[len(b)-1] == '\r') {
		b = b[:len(b)-1]
	}
	return b
}
