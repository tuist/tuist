// egress-tree-agent keeps a per-node shared HTB tree that enforces the kura
// per-tenant egress floors (egress_guaranteed_mbps), ceilings
// (egress_burst_mbps), and the node's box cap (tuist.dev/egress-mbps).
// See infra/egress-tree-agent/AGENTS.md for the architecture and the lab
// evidence behind it.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"

	"github.com/tuist/tuist/infra/egress-tree-agent/internal/agent"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil))

	nodeName := os.Getenv("NODE_NAME")
	if nodeName == "" {
		logger.Error("NODE_NAME is required (downward API)")
		os.Exit(1)
	}
	interval := durationEnv(logger, "RECONCILE_INTERVAL", 15*time.Second)
	metricsAddr := envOr("METRICS_ADDR", ":9469")
	trampolineDev := envOr("TRAMPOLINE_DEV", "kura-egress0")
	returnDev := envOr("RETURN_DEV", "kura-egress1")
	ciliumSock := envOr("CILIUM_SOCK", "/var/run/cilium/cilium.sock")
	pinRoot := envOr("BPF_PIN_ROOT", "/sys/fs/bpf/kura-egress-tree")
	defaultNodeMbps := int64Env(logger, "DEFAULT_NODE_EGRESS_MBPS", 0)

	client, err := kubernetesClient()
	if err != nil {
		logger.Error("building kubernetes client", "error", err)
		os.Exit(1)
	}

	registry := prometheus.NewRegistry()
	registry.MustRegister(collectors.NewGoCollector())

	a := &agent.Agent{
		NodeName:        nodeName,
		DefaultNodeMbps: defaultNodeMbps,
		BetaPodPrefix:   os.Getenv("BETA_POD_PREFIX"),
		Client:          client,
		Endpoints:       agent.NewEndpointResolver(ciliumSock),
		Tree:            agent.Tree{TrampolineDev: trampolineDev, ReturnDev: returnDev},
		Attacher:        agent.Attacher{PinRoot: pinRoot},
		Metrics:         agent.NewMetrics(registry),
		Log:             logger,
	}

	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.HandlerFor(registry, promhttp.HandlerOpts{}))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	server := &http.Server{Addr: metricsAddr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("metrics server", "error", err)
			os.Exit(1)
		}
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		cycle, cancel := context.WithTimeout(ctx, interval*4)
		if err := a.Reconcile(cycle); err != nil {
			logger.Error("reconcile", "error", err)
		}
		cancel()
		select {
		case <-ctx.Done():
			// Deliberately no teardown: the pinned links keep enforcing
			// across agent restarts and upgrades. Removing shaping is an
			// explicit operator action (see AGENTS.md).
			_ = server.Close()
			return
		case <-ticker.C:
		}
	}
}

func kubernetesClient() (kubernetes.Interface, error) {
	config, err := rest.InClusterConfig()
	if err != nil {
		kubeconfig := os.Getenv("KUBECONFIG")
		config, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
		if err != nil {
			return nil, err
		}
	}
	return kubernetes.NewForConfig(config)
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func durationEnv(logger *slog.Logger, key string, fallback time.Duration) time.Duration {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		logger.Error("invalid duration", "env", key, "value", value)
		os.Exit(1)
	}
	return parsed
}

func int64Env(logger *slog.Logger, key string, fallback int64) int64 {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		logger.Error("invalid integer", "env", key, "value", value)
		os.Exit(1)
	}
	return parsed
}
