package main

import (
	"context"
	"encoding/json"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/kura-controller/internal/connectivity"
)

func main() {
	// There is deliberately no command-line or environment configuration.
	if len(os.Args) != 1 {
		os.Exit(2)
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	encoder := json.NewEncoder(os.Stdout)
	for {
		config, err := connectivity.ResolverConfig()
		_ = encoder.Encode(struct {
			Time           time.Time `json:"time"`
			ResolverConfig string    `json:"resolver_config"`
			Readable       bool      `json:"readable"`
		}{time.Now().UTC(), config, err == nil})
		connectivity.Run(ctx, func(result connectivity.Result) { _ = encoder.Encode(result) })
		// Sleep after completing the profile: slow probes never accumulate or
		// create catch-up bursts. Reading logs cannot trigger another probe.
		timer := time.NewTimer(connectivity.Interval)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
	}
}
