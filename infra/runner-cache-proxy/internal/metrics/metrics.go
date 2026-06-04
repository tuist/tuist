// Package metrics declares the proxy's Prometheus instrumentation.
package metrics

import "github.com/prometheus/client_golang/prometheus"

var (
	Connections = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "runner_cache_proxy_connections_total",
		Help: "Connections by routing decision.",
	}, []string{"decision"})

	DNATLookupFailures = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "runner_cache_proxy_dnat_lookup_failures_total",
		Help: "Failures recovering the original destination after DNAT.",
	})

	SNIParseFailures = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "runner_cache_proxy_sni_parse_failures_total",
		Help: "ClientHello SNI parse failures (connection blind-spliced).",
	})

	MITMHandshakes = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "runner_cache_proxy_mitm_handshakes_total",
		Help: "MITM handshakes by result.",
	}, []string{"result"})

	TokenRegistrySize = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "runner_cache_proxy_token_registry_size",
		Help: "Number of staged guest cache tokens.",
	})

	TokenLookups = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "runner_cache_proxy_token_lookups_total",
		Help: "Token registry lookups by result.",
	}, []string{"result"})

	GatewayRequestDuration = prometheus.NewHistogram(prometheus.HistogramOpts{
		Name:    "runner_cache_proxy_gateway_request_duration_seconds",
		Help:    "Latency of requests forwarded to the cache-gateway.",
		Buckets: []float64{0.001, 0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5},
	})

	BreakerState = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "runner_cache_proxy_breaker_state",
		Help: "Breaker state: 0 closed, 1 half-open, 2 open.",
	})

	FailOpen = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "runner_cache_proxy_fail_open_total",
		Help: "Fail-open events by reason.",
	}, []string{"reason"})

	BytesProxied = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "runner_cache_proxy_bytes_proxied_total",
		Help: "Bytes proxied by direction and decision.",
	}, []string{"direction", "decision"})
)

func init() {
	prometheus.MustRegister(
		Connections,
		DNATLookupFailures,
		SNIParseFailures,
		MITMHandshakes,
		TokenRegistrySize,
		TokenLookups,
		GatewayRequestDuration,
		BreakerState,
		FailOpen,
		BytesProxied,
	)
}
