// Package metrics declares the gateway's Prometheus instrumentation. The
// pass-through fallback rate is the first-class SLI: in steady state
// effectively all cache traffic is handled by the gateway, so any
// sustained fallback is the strongest signal of protocol drift or
// backend ill health.
package metrics

import (
	"strconv"

	"github.com/prometheus/client_golang/prometheus"
)

var (
	// PassthroughFallback is the first-class SLI. reason is one of
	// breaker, unknown_shape, schema, timeout.
	PassthroughFallback = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "cache_gateway_passthrough_fallback_total",
		Help: "Cache interactions that fell back to GitHub's hosted cache.",
	}, []string{"reason"})

	ProtocolShape = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "cache_gateway_protocol_shape_total",
		Help: "Observed coordination protocol shapes.",
	}, []string{"service", "method", "version", "schema_valid"})

	Coordination = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "cache_gateway_coordination_total",
		Help: "Coordination (Twirp) calls by method and result.",
	}, []string{"method", "result"})

	BlobUpload = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "cache_gateway_blob_upload_total",
		Help: "Blob upload operations by op and result.",
	}, []string{"op", "result"})

	BlobDownload = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "cache_gateway_blob_download_total",
		Help: "Blob download operations by op and result.",
	}, []string{"op", "result"})

	TranslationErrors = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "cache_gateway_translation_errors_total",
		Help: "Azure-to-S3 translation errors.",
	}, []string{"op", "kind"})

	CacheHit = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "cache_gateway_cache_hit_total",
		Help: "Cache lookups by match type (exact, restore, miss).",
	}, []string{"match"})

	BlobThroughput = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "cache_gateway_blob_throughput_bytes",
		Help:    "Bytes transferred per blob operation.",
		Buckets: prometheus.ExponentialBuckets(64*1024, 4, 8),
	}, []string{"direction"})

	FirstByteSeconds = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "cache_gateway_first_byte_seconds",
		Help:    "Time to first byte for blob operations.",
		Buckets: []float64{0.001, 0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5},
	}, []string{"direction"})

	TenantBandwidth = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "cache_gateway_tenant_bandwidth_bytes_total",
		Help: "Per-tenant bytes transferred through the gateway.",
	}, []string{"account_id", "direction"})
)

func init() {
	prometheus.MustRegister(
		PassthroughFallback,
		ProtocolShape,
		Coordination,
		BlobUpload,
		BlobDownload,
		TranslationErrors,
		CacheHit,
		BlobThroughput,
		FirstByteSeconds,
		TenantBandwidth,
	)
}

// AccountLabel renders an account id as a metric label value.
func AccountLabel(accountID uint64) string {
	return strconv.FormatUint(accountID, 10)
}
