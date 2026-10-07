package podagent

import (
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

func init() { metrics.Registry.MustRegister(customCacheOperations, customCacheDuration) }
func observeCustomCache(o cachevolumes.Observation) {
	result := cachevolumes.Result(o.Err)
	customCacheOperations.WithLabelValues(o.Operation, o.Source, result).Inc()
	customCacheDuration.WithLabelValues(o.Operation, o.Source).Observe(o.Duration.Seconds())
	log.Log.WithName("custom-cache-volumes").Info("cache phase", "operation", o.Operation, "source", o.Source, "result", result, "duration", o.Duration)
}
