package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/tuist/tuist/infra/runners-controller/internal/cachevolumes"
)

type volumeMetrics struct {
	registry    *prometheus.Registry
	operations  *prometheus.CounterVec
	duration    *prometheus.HistogramVec
	free        prometheus.Gauge
	capacity    prometheus.Gauge
	reserve     prometheus.Gauge
	maintenance prometheus.Gauge
	logger      *slog.Logger
}

func newVolumeMetrics(logger *slog.Logger, reserve uint64) *volumeMetrics {
	m := &volumeMetrics{
		registry: prometheus.NewRegistry(), logger: logger,
		operations:  prometheus.NewCounterVec(prometheus.CounterOpts{Name: "tuist_runner_cache_volume_operations_total", Help: "Cache volume operations by phase, source and result."}, []string{"operation", "source", "result"}),
		duration:    prometheus.NewHistogramVec(prometheus.HistogramOpts{Name: "tuist_runner_cache_volume_operation_duration_seconds", Help: "Cache volume phase duration, including unsuccessful attempts.", Buckets: []float64{0.1, 1, 5, 10, 25, 60, 300}}, []string{"operation", "source"}),
		free:        prometheus.NewGauge(prometheus.GaugeOpts{Name: "tuist_runner_cache_volume_filesystem_available_bytes", Help: "Space available on the dedicated cache filesystem."}),
		capacity:    prometheus.NewGauge(prometheus.GaugeOpts{Name: "tuist_runner_cache_volume_filesystem_capacity_bytes", Help: "Capacity of the dedicated cache filesystem."}),
		reserve:     prometheus.NewGauge(prometheus.GaugeOpts{Name: "tuist_runner_cache_volume_filesystem_reserve_bytes", Help: "Free-space reserve required for new allocations."}),
		maintenance: prometheus.NewGauge(prometheus.GaugeOpts{Name: "tuist_runner_cache_volume_maintenance_last_success_timestamp_seconds", Help: "Last successful reconciliation, or zero before the first success."}),
	}
	m.registry.MustRegister(m.operations, m.duration, m.free, m.capacity, m.reserve, m.maintenance)
	m.reserve.Set(float64(reserve))
	return m
}
func (m *volumeMetrics) observe(o cachevolumes.Observation) {
	result := cachevolumes.Result(o.Err)
	m.operations.WithLabelValues(o.Operation, o.Source, result).Inc()
	m.duration.WithLabelValues(o.Operation, o.Source).Observe(o.Duration.Seconds())
	if o.Operation == "maintenance" && o.Err == nil {
		m.maintenance.Set(float64(time.Now().Unix()))
	}
	// Successful maintenance runs every 30s; only lifecycle operations and failures need logs.
	if o.Operation != "maintenance" || o.Err != nil {
		level := slog.LevelInfo
		if o.Err != nil {
			level = slog.LevelWarn
		}
		fields := []any{"operation", o.Operation, "source", o.Source, "result", result, "duration_ms", o.Duration.Milliseconds()}
		var remote *cachevolumes.RemoteError
		if errors.As(o.Err, &remote) {
			fields = append(fields, "remote_operation", remote.Operation, "http_status", remote.StatusCode)
		}
		m.logger.Log(context.Background(), level, "cache volume operation", fields...)
	}
}
func (m *volumeMetrics) handler() http.Handler {
	return promhttp.HandlerFor(m.registry, promhttp.HandlerOpts{})
}
