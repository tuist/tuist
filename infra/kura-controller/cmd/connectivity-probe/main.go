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
	// Only a reviewed environment profile is accepted, never a destination URL.
	if len(os.Args) != 2 {
		os.Exit(2)
	}
	environment := os.Args[1]
	if _, err := connectivity.ProfileHost(environment); err != nil {
		os.Exit(2)
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	encoder := json.NewEncoder(os.Stdout)
	var resolver resolverRecordState
	for {
		config, err := connectivity.ResolverConfig()
		if resolver.changed(config, err == nil) {
			_ = encoder.Encode(struct {
				Time           time.Time `json:"time"`
				ResolverConfig string    `json:"resolver_config"`
				Readable       bool      `json:"readable"`
			}{time.Now().UTC(), config, err == nil})
		}
		_ = connectivity.Run(ctx, environment, func(result connectivity.Result) { _ = encoder.Encode(result) })
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

type resolverRecordState struct {
	seen     bool
	config   string
	readable bool
}

func (s *resolverRecordState) changed(config string, readable bool) bool {
	if s.seen && s.config == config && s.readable == readable {
		return false
	}
	s.seen, s.config, s.readable = true, config, readable
	return true
}
