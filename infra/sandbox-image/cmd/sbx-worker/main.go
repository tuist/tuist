// sbx-worker services one already-claimed Managed Agents work item inside the
// guest with the Anthropic SDK's EnvironmentWorker. sandboxd starts it with
// the ANTHROPIC_* variables of the item and reads its exit code.
package main

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	anthropic "github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/lib/environments"
	"github.com/anthropics/anthropic-sdk-go/option"

	"github.com/tuist/tuist/infra/sandbox-image/internal/guest"
)

const defaultMaxIdle = 30 * time.Second

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	slog.SetDefault(logger)
	os.Exit(run(logger))
}

func run(logger *slog.Logger) int {
	workdir := os.Getenv("SBX_WORKDIR")
	if workdir == "" {
		workdir = guest.WorkspaceMount
	}
	maxIdle := defaultMaxIdle
	if raw := os.Getenv("SBX_MAX_IDLE"); raw != "" {
		parsed, err := time.ParseDuration(raw)
		if err != nil {
			logger.Error("invalid SBX_MAX_IDLE", slog.String("value", raw), slog.Any("error", err))
			return 1
		}
		maxIdle = parsed
	}
	environmentKey := os.Getenv("ANTHROPIC_ENVIRONMENT_KEY")
	if environmentKey == "" {
		logger.Error("ANTHROPIC_ENVIRONMENT_KEY is not set")
		return 1
	}
	hostname, err := os.Hostname()
	if err != nil {
		hostname = "sandbox"
	}
	logger = logger.With(
		slog.String("session_id", os.Getenv("ANTHROPIC_SESSION_ID")),
		slog.String("work_id", os.Getenv("ANTHROPIC_WORK_ID")),
		slog.String("environment_id", os.Getenv("ANTHROPIC_ENVIRONMENT_ID")))

	// NewClient reads ANTHROPIC_BASE_URL itself; the environment key is the
	// bearer credential for every call the worker makes.
	client := anthropic.NewClient(option.WithAuthToken(environmentKey))
	worker := environments.NewEnvironmentWorker(client, environments.EnvironmentWorkerOptions{
		EnvironmentKey: environmentKey,
		WorkerID:       hostname,
		Workdir:        workdir,
		MaxIdle:        &maxIdle,
		Logger:         logger,
	})

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	logger.Info("worker starting",
		slog.String("workdir", workdir),
		slog.Duration("max_idle", maxIdle),
		slog.String("worker_id", hostname),
		slog.Bool("base_url_override", os.Getenv("ANTHROPIC_BASE_URL") != ""))
	start := time.Now()
	// The session, work item and secret come from the ANTHROPIC_* variables
	// HandleItem falls back to when the options are empty.
	err = worker.HandleItem(ctx, environments.HandleItemOptions{})
	duration := time.Since(start)
	switch {
	case err == nil:
		logger.Info("worker finished", slog.Duration("duration", duration))
		return 0
	case ctx.Err() != nil && errors.Is(err, context.Canceled):
		// A stop_worker from sandboxd, not a failure.
		logger.Info("worker stopped by signal", slog.Duration("duration", duration))
		return 0
	default:
		logger.Error("worker failed", slog.Duration("duration", duration), slog.Any("error", err))
		return 1
	}
}
