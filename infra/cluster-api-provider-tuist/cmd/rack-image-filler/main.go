// Command rack-image-filler keeps a rack's VM image cache filled
// (internal/rackimagefiller). It runs beside the cache's registry, on the
// rack's storage node, with host networking.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"golang.org/x/sys/unix"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackimagefiller"
)

func main() {
	ctrl.SetLogger(zap.New())
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "rack-image-filler: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	var cfg rackimagefiller.Config
	var images, volume, metricsAddress string
	var reserveGiB, budgetGiB int64
	var interval time.Duration
	flag.StringVar(&images, "images", "", "comma-separated upstream image references the cache holds, in priority order")
	flag.StringVar(&cfg.Registry, "registry", "", "the cache's registry, host:port, spoken to over plain HTTP")
	flag.StringVar(&cfg.StateFile, "state-file", "", "where the day's downloaded bytes and each image's backoff are kept")
	flag.StringVar(&volume, "volume", "", "a path on the cache's volume, whose free space bounds every copy")
	flag.Int64Var(&reserveGiB, "reserve-gib", 2, "GiB left free on the volume beyond any copy")
	flag.Int64Var(&budgetGiB, "daily-budget-gib", 300, "GiB the filler may download per UTC day")
	flag.DurationVar(&cfg.MinBackoff, "min-backoff", 10*time.Minute, "how long an image waits after its first failure")
	flag.DurationVar(&cfg.MaxBackoff, "max-backoff", 6*time.Hour, "the longest an image waits after repeated failures")
	flag.DurationVar(&interval, "interval", 10*time.Minute, "how often a pass runs")
	flag.StringVar(&metricsAddress, "metrics-address", "", "address to serve Prometheus metrics on; empty serves none")
	flag.Parse()
	for flagName, value := range map[string]string{"images": images, "registry": cfg.Registry, "state-file": cfg.StateFile, "volume": volume} {
		if value == "" {
			return fmt.Errorf("--%s is required", flagName)
		}
	}
	for _, image := range strings.Split(images, ",") {
		if image = strings.TrimSpace(image); image != "" {
			cfg.Images = append(cfg.Images, image)
		}
	}
	cfg.Reserve = reserveGiB << 30
	cfg.DailyBudget = budgetGiB << 30
	cfg.FreeBytes = func() (int64, error) {
		var st unix.Statfs_t
		if err := unix.Statfs(volume, &st); err != nil {
			return 0, err
		}
		return int64(st.Bavail) * int64(st.Bsize), nil
	}

	outcomes := prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "rack_image_filler_image_outcome",
		Help: "1 for the outcome of each wanted image's last pass (held, copied, no_space, evicting, over_budget, backing_off, failed).",
	}, []string{"image", "outcome"})
	passes := prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "rack_image_filler_passes_total",
		Help: "Filler passes, by whether the pass itself (not an image) failed.",
	}, []string{"result"})
	registry := prometheus.NewRegistry()
	registry.MustRegister(outcomes, passes)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	log := ctrl.Log.WithName("rack-image-filler")
	if metricsAddress != "" {
		server := &http.Server{Addr: metricsAddress, Handler: promhttp.HandlerFor(registry, promhttp.HandlerOpts{}), ReadHeaderTimeout: 10 * time.Second}
		go func() {
			if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				log.Error(err, "serve metrics")
			}
		}()
		defer server.Close()
	}

	filler := &rackimagefiller.Filler{Config: cfg, Log: log}
	log.Info("filling the rack's image cache", "registry", cfg.Registry, "images", cfg.Images, "dailyBudgetGiB", budgetGiB, "interval", interval.String())
	for {
		result, err := filler.Pass(ctx)
		if err != nil {
			passes.WithLabelValues("error").Inc()
			log.Error(err, "fill pass")
		} else {
			passes.WithLabelValues("ok").Inc()
		}
		outcomes.Reset()
		for image, outcome := range result {
			outcomes.WithLabelValues(image, string(outcome)).Set(1)
		}
		log.Info("fill pass done", "outcomes", result)
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(interval):
		}
	}
}
