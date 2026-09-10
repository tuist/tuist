// sandboxd runs Firecracker microVM sandboxes on a bare-metal node for
// coding-agent sessions. See infra/sandboxd/AGENTS.md for the protocol and
// the node layout.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/tuist/tuist/infra/sandboxd/internal/admin"
	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/hostinfo"
	"github.com/tuist/tuist/infra/sandboxd/internal/network"
	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/sandbox"
	"github.com/tuist/tuist/infra/sandboxd/internal/server"
	"github.com/tuist/tuist/infra/sandboxd/internal/template"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

// version is set with -ldflags "-X main.version=...".
var version = "dev"

func main() {
	level, levelErr := levelEnv("LOG_LEVEL", slog.LevelInfo)
	logger := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: level}))
	if levelErr != nil {
		logger.Error("invalid log level", "env", "LOG_LEVEL", "value", os.Getenv("LOG_LEVEL"), "error", levelErr)
		os.Exit(1)
	}

	nodeName := os.Getenv("NODE_NAME")
	serverURL := os.Getenv("SERVER_URL")
	tokenPath := envOr("TOKEN_PATH", "/var/run/secrets/tuist/token")
	dataDir := envOr("DATA_DIR", "/data/sandboxes")
	templateName := envOr("TEMPLATE_NAME", "default")
	templateTag := os.Getenv("TEMPLATE_TAG")
	firecrackerBin := envOr("FIRECRACKER_BIN", "/usr/local/bin/firecracker")
	jailerBin := envOr("JAILER_BIN", "/usr/local/bin/jailer")
	jailerEnabled := boolEnv(logger, "JAILER_ENABLED", true)
	uidBase := intEnv(logger, "JAIL_UID_BASE", 10000)
	metricsAddr := envOr("METRICS_ADDR", ":9470")
	adminAddr := os.Getenv("ADMIN_ADDR")
	bootTimeout := durationEnv(logger, "BOOT_TIMEOUT", sandbox.DefaultBootTimeout)
	templateBootTimeout := durationEnv(logger, "TEMPLATE_BOOT_TIMEOUT", template.DefaultBootTimeout)
	shutdownTimeout := durationEnv(logger, "SHUTDOWN_TIMEOUT", 60*time.Second)
	templateWorkspaceGB := intEnv(logger, "TEMPLATE_WORKSPACE_GB", template.DefaultWorkspaceGB)
	prebuild, err := template.ParseShapes(os.Getenv("PREBUILD_SHAPES"))
	if err != nil {
		logger.Error("invalid PREBUILD_SHAPES", "error", err)
		os.Exit(1)
	}
	if serverURL != "" && nodeName == "" {
		logger.Error("NODE_NAME is required when SERVER_URL is set (downward API)")
		os.Exit(1)
	}
	if serverURL == "" && adminAddr == "" {
		logger.Error("neither SERVER_URL nor ADMIN_ADDR is set; nothing would drive the daemon")
		os.Exit(1)
	}
	if uidBase < 1000 {
		logger.Error("JAIL_UID_BASE must be at least 1000", "value", uidBase)
		os.Exit(1)
	}

	if err := vm.SetChildSubreaper(); err != nil {
		logger.Error("setting child subreaper", "error", err)
		os.Exit(1)
	}

	dns := hostinfo.Resolvers()
	if len(dns) == 0 {
		logger.Warn("no resolvers found in /etc/resolv.conf; guests get no DNS")
	}
	fcVersion := "unknown"
	if v, err := firecracker.BinaryVersion(context.Background(), firecrackerBin); err == nil {
		fcVersion = v
	} else {
		logger.Warn("firecracker version unavailable", "bin", firecrackerBin, "error", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	registry := prometheus.NewRegistry()
	registry.MustRegister(collectors.NewGoCollector())
	metrics := sandbox.NewMetrics(registry)

	netManager := network.NewManager(logger)
	netManager.PodInterface = os.Getenv("POD_INTERFACE")
	if err := netManager.EnsurePodNAT(ctx); err != nil {
		logger.Error("pod NAT setup", "error", err)
		os.Exit(1)
	}

	jailBase := filepath.Join(dataDir, "jail")
	store := &template.Store{Dir: filepath.Join(dataDir, "templates")}
	if err := store.CleanPartialBuilds(); err != nil {
		logger.Error("cleaning partial template builds", "error", err)
		os.Exit(1)
	}
	templates, err := store.List()
	if err != nil {
		logger.Error("listing templates", "error", err)
		os.Exit(1)
	}
	if len(templates) == 0 {
		logger.Error("no templates under data dir; the init container must seed vmlinux and rootfs.ext4", "dir", store.Dir)
		os.Exit(1)
	}
	defaultTemplate, err := store.Resolve(templateName, templateTag)
	if err != nil {
		logger.Error("resolving default template", "error", err)
		os.Exit(1)
	}
	logger.Info("default template", "name", defaultTemplate.Name, "tag", defaultTemplate.Tag, "ready_shapes", defaultTemplate.ReadyShapes())

	// events fans daemon events out to the server connection once it
	// exists.
	var serverClient *server.Client
	events := func(event protocol.Event) {
		if serverClient != nil {
			serverClient.Emit(event)
		}
	}
	slots := network.NewSlots(network.MaxSlots)
	launcher := &vm.FirecrackerLauncher{Log: logger}
	agent := func(path string) vsock.Agent { return vsock.NewUDSClient(path, firecracker.AgentPort) }
	builder := &template.Builder{
		Store: store, Launcher: launcher, Network: netManager, Slots: slots, Agent: agent,
		JailBase: jailBase, FirecrackerBin: firecrackerBin, JailerBin: jailerBin, JailerEnabled: jailerEnabled,
		UIDBase: uidBase, DNS: dns, FirecrackerVersion: fcVersion, WorkspaceGB: templateWorkspaceGB,
		BootTimeout: templateBootTimeout, Log: logger, Events: events,
		Observe: func(shape template.Shape, elapsed time.Duration, err error) {
			if err == nil {
				metrics.TemplateBuild.WithLabelValues(shape.String()).Observe(elapsed.Seconds())
			}
		},
	}
	manager := sandbox.New(sandbox.Config{
		JailBase: jailBase, FirecrackerBin: firecrackerBin, JailerBin: jailerBin, JailerEnabled: jailerEnabled,
		UIDBase: uidBase, DNS: dns, DefaultTemplate: templateName, BootTimeout: bootTimeout,
	}, sandbox.Deps{
		Store: store, Builder: builder, Launcher: launcher, Network: netManager, Slots: slots, Agent: agent,
		Metrics: metrics, Events: events, Log: logger,
	})
	if err := manager.Recover(ctx); err != nil {
		logger.Error("recovering sandboxes", "error", err)
		os.Exit(1)
	}

	go func() {
		for _, shape := range prebuild {
			if ctx.Err() != nil {
				return
			}
			if _, err := builder.Ensure(ctx, defaultTemplate, shape); err != nil {
				logger.Error("prebuilding template shape", "shape", shape.String(), "error", err)
			}
		}
	}()

	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.HandlerFor(registry, promhttp.HandlerOpts{}))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	metricsServer := &http.Server{Addr: metricsAddr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() {
		if err := metricsServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("metrics server", "error", err)
			os.Exit(1)
		}
	}()

	var adminServer *http.Server
	if adminAddr != "" {
		adminServer = &http.Server{Addr: adminAddr, Handler: admin.NewHandler(manager, logger), ReadHeaderTimeout: 5 * time.Second}
		go func() {
			logger.Info("admin API listening (unauthenticated)", "addr", adminAddr)
			if err := adminServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				logger.Error("admin server", "error", err)
				os.Exit(1)
			}
		}()
	}

	serverDone := make(chan struct{})
	if serverURL != "" {
		serverClient = server.New(server.Config{
			URL: serverURL, NodeName: nodeName, TokenPath: tokenPath, Log: logger,
			Hello: func() protocol.Hello {
				return protocol.Hello{
					DaemonVersion: version, FirecrackerVersion: fcVersion, Capacity: hostinfo.Capacity(),
					Templates: manager.Templates(), Sandboxes: manager.List(),
				}
			},
			Report: func() protocol.Report {
				return protocol.Report{Sandboxes: manager.List(), Memory: protocol.MemoryReport{UsedBytes: hostinfo.MemoryUsed()}}
			},
			Handler: func(ctx context.Context, cmd protocol.Command, stream func(protocol.Stream)) protocol.Result {
				return sandbox.Dispatch(ctx, manager, cmd, stream)
			},
		})
		go func() {
			serverClient.Run(ctx)
			close(serverDone)
		}()
	} else {
		close(serverDone)
		logger.Info("SERVER_URL not set; running admin-only")
	}

	logger.Info("sandboxd started", "version", version, "node", nodeName, "firecracker", fcVersion, "jailer", jailerEnabled, "data_dir", dataDir, "dns", dns)
	<-ctx.Done()
	stop()
	logger.Info("shutting down: pausing idle sandboxes", "timeout", shutdownTimeout)
	// Stop taking commands first: the server connection closes and its
	// in-flight lifecycle ops finish on their own detached contexts.
	<-serverDone
	if adminServer != nil {
		_ = adminServer.Close()
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	manager.Shutdown(shutdownCtx)
	_ = metricsServer.Close()
	logger.Info("sandboxd stopped")
}

func levelEnv(key string, fallback slog.Level) (slog.Level, error) {
	value := os.Getenv(key)
	if value == "" {
		return fallback, nil
	}
	var level slog.Level
	if err := level.UnmarshalText([]byte(value)); err != nil {
		return fallback, err
	}
	return level, nil
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func boolEnv(logger *slog.Logger, key string, fallback bool) bool {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		logger.Error("invalid boolean", "env", key, "value", value)
		os.Exit(1)
	}
	return parsed
}

func intEnv(logger *slog.Logger, key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		logger.Error("invalid integer", "env", key, "value", value)
		os.Exit(1)
	}
	return parsed
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
