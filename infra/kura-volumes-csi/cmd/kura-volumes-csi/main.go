// kura-volumes-csi is the node plugin behind the kura-volumes.tuist.dev
// StorageClass. See infra/kura-volumes-csi/AGENTS.md for the contract.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"log/slog"
	"net"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc"
	"google.golang.org/grpc/status"

	"github.com/tuist/tuist/infra/kura-volumes-csi/internal/driver"
	"github.com/tuist/tuist/infra/kura-volumes-csi/internal/volumekeys"
)

var version = "dev"

const shutdownGrace = 30 * time.Second

func main() {
	endpoint := flag.String("endpoint", "unix:///csi/csi.sock", "CSI gRPC endpoint (unix socket)")
	nodeID := flag.String("node-id", "", "Kubernetes node name, also the topology value")
	stateDir := flag.String("state-dir", "/data/kura-volumes", "canonical directory holding the volume backing files")
	reserveBytes := flag.Int64("reserve-bytes", 20<<30, "bytes CreateVolume leaves free on the state dir filesystem")
	keyServiceURL := flag.String("key-service-url", "", "base URL of the Tuist server that serves volume keys")
	tokenPath := flag.String("token-path", "/var/run/secrets/kura-volume-keys/token", "projected service account token presented to the key service")
	logLevel := flag.String("log-level", "info", "debug, info, warn or error")
	flag.Parse()

	var level slog.Level
	if err := level.UnmarshalText([]byte(*logLevel)); err != nil {
		fmt.Fprintf(os.Stderr, "invalid --log-level %q: %v\n", *logLevel, err)
		os.Exit(2)
	}
	logger := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: level}))
	if err := run(logger, *endpoint, *nodeID, *stateDir, *reserveBytes, *keyServiceURL, *tokenPath); err != nil {
		logger.Error("kura-volumes-csi failed", "error", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger, endpoint, nodeID, stateDir string, reserveBytes int64, keyServiceURL, tokenPath string) error {
	socket, err := socketPath(endpoint)
	if err != nil {
		return err
	}
	if err := checkKeyServiceURL(keyServiceURL); err != nil {
		return err
	}
	d, err := driver.New(driver.Config{
		NodeID:       nodeID,
		StateDir:     stateDir,
		ReserveBytes: reserveBytes,
		Version:      version,
		Keys:         volumekeys.New(keyServiceURL, tokenPath, volumekeys.WithLogger(logger)),
		Runner:       driver.ExecRunner{},
		Mounts:       driver.ProcMountTable{Path: "/proc/self/mountinfo"},
		Host:         driver.OSHost{},
		Logger:       logger,
	})
	if err != nil {
		return err
	}

	if err := os.Remove(socket); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("remove stale socket: %w", err)
	}
	listener, err := net.Listen("unix", socket)
	if err != nil {
		return fmt.Errorf("listen on %s: %w", socket, err)
	}
	defer os.Remove(socket)

	server := grpc.NewServer(grpc.UnaryInterceptor(logCalls(logger)))
	csi.RegisterIdentityServer(server, d)
	csi.RegisterControllerServer(server, d)
	csi.RegisterNodeServer(server, d)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	go func() {
		<-ctx.Done()
		logger.Info("shutting down")
		stopped := make(chan struct{})
		go func() {
			server.GracefulStop()
			close(stopped)
		}()
		select {
		case <-stopped:
		case <-time.After(shutdownGrace):
			server.Stop()
		}
	}()

	logger.Info("serving", "driver", driver.Name, "version", version, "node_id", nodeID, "socket", socket, "state_dir", stateDir)
	return server.Serve(listener)
}

func socketPath(endpoint string) (string, error) {
	path, ok := strings.CutPrefix(endpoint, "unix://")
	if !ok || !strings.HasPrefix(path, "/") {
		return "", fmt.Errorf("--endpoint %q must be unix:///absolute/path", endpoint)
	}
	return path, nil
}

func checkKeyServiceURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return fmt.Errorf("--key-service-url %q must be an https URL", raw)
	}
	return nil
}

func logCalls(logger *slog.Logger) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
		start := time.Now()
		resp, err := handler(ctx, req)
		attrs := []any{"method", info.FullMethod, "duration_ms", time.Since(start).Milliseconds()}
		if err != nil {
			logger.Warn("csi call failed", append(attrs, "code", status.Code(err).String(), "error", err)...)
		} else if !strings.HasPrefix(info.FullMethod, "/csi.v1.Identity/") {
			logger.Debug("csi call", attrs...)
		}
		return resp, err
	}
}
