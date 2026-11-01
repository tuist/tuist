package podagent

import (
	"log/slog"

	"github.com/go-logr/logr"
	"github.com/prometheus/client_golang/prometheus"
	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

var customCacheOperations = prometheus.NewCounterVec(prometheus.CounterOpts{
	Name: "tuist_runner_cache_volume_operations_total", Help: "Custom cache volume operations by phase, source and result.",
}, []string{"operation", "source", "result"})
var customCacheDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
	Name: "tuist_runner_cache_volume_operation_duration_seconds", Help: "Custom cache volume phase duration, including unsuccessful attempts.", Buckets: []float64{0.1, 1, 5, 10, 25, 60, 300},
}, []string{"operation", "source"})

// customCachePrefetchedBytes adds up the saved heads' measured used bytes, which bound
// what their compressed archives moved over the network.
var customCachePrefetchedBytes = prometheus.NewCounterVec(prometheus.CounterOpts{
	Name: "tuist_runner_cache_volume_prefetched_bytes_total", Help: "Used bytes of the saved heads background prefetch installed, by why: job (a job started without it), refresh (a newer head of a master here), prewarm or recent (the server's listing).",
}, []string{"reason"})

func init() {
	metrics.Registry.MustRegister(customCacheOperations, customCacheDuration, customCachePrefetchedBytes)
}

// The result category bounds the metric. The log line also carries the volume's
// subject and the error, which runner-cache keeps free of signed URLs and
// command output; the subject never becomes a label.
func observeCustomCache(o cachevolumes.Observation) {
	result := cachevolumes.Result(o.Err)
	customCacheOperations.WithLabelValues(o.Operation, o.Source, result).Inc()
	customCacheDuration.WithLabelValues(o.Operation, o.Source).Observe(o.Duration.Seconds())
	values := append([]any{"operation", o.Operation, "source", o.Source, "result", result, "duration", o.Duration}, o.Subject.Fields()...)
	if o.Err != nil {
		values = append(values, "error", o.Err.Error())
	}
	log.Log.WithName("custom-cache-volumes").Info("cache phase", values...)
}

// customCacheLog is the custom-cache-volumes logger for runner-cache's own lines.
func customCacheLog() *slog.Logger {
	return slog.New(logr.ToSlogHandler(log.Log.WithName("custom-cache-volumes")))
}
