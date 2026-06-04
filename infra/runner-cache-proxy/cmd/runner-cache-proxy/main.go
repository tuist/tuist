// Command runner-cache-proxy is the host-side interception proxy for the
// self-hosted GitHub Actions cache. It runs on the runner host (Mac mini
// / Hetzner node), never in the guest. pf/nftables DNAT redirects guest
// :443 here; the proxy peeks the SNI, MITMs only the GitHub cache plane
// (routing CacheService to the local cache-gateway with a host-side token
// swap), and blind-splices everything else. It fails open to genuine
// GitHub on any uncertainty.
package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/allowlist"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/breaker"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/config"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/intercept"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/metrics"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/mitm"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/router"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/tokenregistry"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/upstream"
)

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	cfg := config.Default()
	flag.StringVar(&cfg.ListenAddr, "listen", envOr("RUNNER_CACHE_PROXY_LISTEN", cfg.ListenAddr), "DNAT target listen address")
	flag.StringVar(&cfg.MetricsAddr, "metrics-bind-address", envOr("RUNNER_CACHE_PROXY_METRICS", cfg.MetricsAddr), "metrics + health listen address")
	flag.StringVar(&cfg.CACertPath, "ca-cert", os.Getenv("RUNNER_CACHE_PROXY_CA_CERT"), "MITM CA certificate path")
	flag.StringVar(&cfg.CAKeyPath, "ca-key", os.Getenv("RUNNER_CACHE_PROXY_CA_KEY"), "MITM CA private key path (host-only)")
	flag.StringVar(&cfg.TokenDir, "token-dir", envOr("RUNNER_CACHE_PROXY_TOKEN_DIR", cfg.TokenDir), "watched source-IP -> cache-token staging directory")
	flag.StringVar(&cfg.GatewayURL, "gateway-url", os.Getenv("RUNNER_CACHE_PROXY_GATEWAY_URL"), "cache-gateway base URL (empty disables diversion)")
	allowed := flag.String("allowed-sni", os.Getenv("RUNNER_CACHE_PROXY_ALLOWED_SNI"), "comma-separated SNI allowlist override")
	flag.Parse()

	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(log)

	if *allowed != "" {
		cfg.AllowedSNIs = splitComma(*allowed)
	}
	if err := cfg.Validate(); err != nil {
		log.Error("invalid configuration", "err", err)
		os.Exit(1)
	}

	caCert, err := os.ReadFile(cfg.CACertPath)
	if err != nil {
		log.Error("read CA cert", "err", err)
		os.Exit(1)
	}
	caKey, err := os.ReadFile(cfg.CAKeyPath)
	if err != nil {
		log.Error("read CA key", "err", err)
		os.Exit(1)
	}
	ca, err := mitm.LoadCA(caCert, caKey)
	if err != nil {
		log.Error("load CA", "err", err)
		os.Exit(1)
	}
	leaves, err := mitm.NewLeafCache(ca)
	if err != nil {
		log.Error("leaf cache", "err", err)
		os.Exit(1)
	}

	hosts := allowlist.DefaultHosts
	if len(cfg.AllowedSNIs) > 0 {
		hosts = cfg.AllowedSNIs
	}
	matcher := allowlist.New(hosts)

	registry := tokenregistry.New(cfg.TokenDir)
	bkr := breaker.New(cfg.BreakerFailureThreshold, cfg.BreakerCooldown)

	proxy, err := upstream.New(upstream.Options{
		GatewayURL: cfg.GatewayURL,
		Registry:   registry,
		Breaker:    bkr,
		Decisions:  router.NewDecisionCache(cfg.DecisionTTL),
	})
	if err != nil {
		log.Error("build proxy", "err", err)
		os.Exit(1)
	}

	ln, err := net.Listen("tcp", cfg.ListenAddr)
	if err != nil {
		log.Error("listen", "err", err, "addr", cfg.ListenAddr)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Watch the token staging directory.
	go func() {
		if err := registry.Watch(ctx); err != nil {
			log.Error("token registry watch", "err", err)
		}
	}()

	// Probe gateway health to gate the breaker, and export the registry
	// size + breaker state as metrics.
	if cfg.GatewayURL != "" {
		go bkr.RunProber(ctx, gatewayProbe(cfg.GatewayURL, cfg.DialTimeout), cfg.HealthProbeInterval)
	}
	go observe(ctx, registry, bkr)

	// Metrics + health.
	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	metricsSrv := &http.Server{Addr: cfg.MetricsAddr, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	go func() {
		if err := metricsSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("metrics server", "err", err)
		}
	}()

	listener := intercept.NewListener(intercept.Options{
		Listener:    ln,
		OriginalDst: intercept.NewOriginalDst(),
		Allow:       matcher,
		Leaves:      leaves,
		Proxy:       proxy,
		Logger:      log,
	})

	log.Info("runner-cache-proxy listening", "addr", cfg.ListenAddr, "gateway", cfg.GatewayURL)
	if err := listener.Serve(ctx); err != nil {
		log.Error("serve", "err", err)
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = metricsSrv.Shutdown(shutdownCtx)
}

func gatewayProbe(gatewayURL string, timeout time.Duration) func(context.Context) bool {
	healthURL := strings.TrimRight(gatewayURL, "/") + "/healthz"
	client := &http.Client{Timeout: timeout}
	return func(ctx context.Context) bool {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, healthURL, nil)
		if err != nil {
			return false
		}
		resp, err := client.Do(req)
		if err != nil {
			return false
		}
		defer resp.Body.Close()
		return resp.StatusCode == http.StatusOK
	}
}

func observe(ctx context.Context, registry *tokenregistry.Registry, bkr *breaker.Breaker) {
	t := time.NewTicker(2 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			metrics.TokenRegistrySize.Set(float64(registry.Size()))
			metrics.BreakerState.Set(float64(bkr.State()))
		}
	}
}

func splitComma(s string) []string {
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
