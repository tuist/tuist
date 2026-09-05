// sbx-agent is the guest side of sandboxd's control channel: a vsock server
// that answers ping, set_time, configure, write_file, exec and kill.
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"

	"github.com/tuist/tuist/infra/sandbox-image/internal/agent"
	"github.com/tuist/tuist/infra/sandbox-image/internal/exec"
	"github.com/tuist/tuist/infra/sandbox-image/internal/guest"
)

// version is stamped by the build with -ldflags "-X main.version=...".
var version = "dev"

func main() {
	listen := flag.String("listen", "vsock://5000", "listen address: vsock://<port> or tcp://<host:port> (for development)")
	workspace := flag.String("workspace", guest.WorkspaceMount, "default working directory for exec")
	flag.Parse()

	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	slog.SetDefault(logger)

	l, err := listenOn(*listen)
	if err != nil {
		logger.Error("listen failed", slog.String("addr", *listen), slog.Any("error", err))
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	go func() {
		<-ctx.Done()
		l.Close()
	}()

	h := &agent.Handler{
		Version: version,
		System:  &guest.System{Logger: logger},
		Execs:   exec.NewRegistry(*workspace),
		Logger:  logger,
	}
	logger.Info("sbx-agent listening", slog.String("addr", *listen), slog.String("version", version))
	if err := h.Serve(ctx, l); err != nil {
		logger.Error("serve failed", slog.Any("error", err))
		os.Exit(1)
	}
}

func listenOn(addr string) (net.Listener, error) {
	scheme, rest, ok := strings.Cut(addr, "://")
	if !ok {
		return nil, fmt.Errorf("invalid listen address %q", addr)
	}
	switch scheme {
	case "vsock":
		port, err := strconv.ParseUint(rest, 10, 32)
		if err != nil {
			return nil, fmt.Errorf("invalid vsock port %q", rest)
		}
		return listenVsock(uint32(port))
	case "tcp":
		return net.Listen("tcp", rest)
	default:
		return nil, fmt.Errorf("unsupported listen scheme %q", scheme)
	}
}
