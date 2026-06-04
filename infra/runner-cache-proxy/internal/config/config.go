// Package config holds the runner-cache-proxy runtime configuration.
package config

import (
	"fmt"
	"net/url"
	"time"
)

// Config is the proxy's runtime configuration.
type Config struct {
	// ListenAddr is where the proxy accepts DNAT'd guest connections.
	ListenAddr string
	// MetricsAddr serves /metrics and /healthz.
	MetricsAddr string
	// CACertPath / CAKeyPath are the baked MITM CA (key is host-only).
	CACertPath string
	CAKeyPath  string
	// TokenDir is the watched source-IP -> cache-token staging directory.
	TokenDir string
	// GatewayURL is the cache-gateway base URL CacheService calls are
	// diverted to. Empty disables diversion (proxy fails fully open).
	GatewayURL string
	// AllowedSNIs overrides the default GitHub-Actions cache allowlist.
	AllowedSNIs []string

	// DialTimeout / ResponseHeaderTimeout bound gateway calls.
	DialTimeout           time.Duration
	ResponseHeaderTimeout time.Duration
	// HealthProbeInterval is how often the gateway /healthz is probed.
	HealthProbeInterval time.Duration
	// DecisionTTL is the per-(srcIP,sni) routing-decision stickiness.
	DecisionTTL time.Duration
	// BreakerFailureThreshold / BreakerCooldown tune the breaker.
	BreakerFailureThreshold int
	BreakerCooldown         time.Duration
}

// Default returns a config with sensible defaults applied.
func Default() Config {
	return Config{
		ListenAddr:              "127.0.0.1:8443",
		MetricsAddr:             ":9092",
		TokenDir:                "/var/lib/tuist-cache-proxy/tokens",
		DialTimeout:             2 * time.Second,
		ResponseHeaderTimeout:   3 * time.Second,
		HealthProbeInterval:     5 * time.Second,
		DecisionTTL:             30 * time.Second,
		BreakerFailureThreshold: 5,
		BreakerCooldown:         10 * time.Second,
	}
}

// Validate checks required fields and value sanity.
func (c Config) Validate() error {
	if c.ListenAddr == "" {
		return fmt.Errorf("config: listen address is required")
	}
	if c.CACertPath == "" || c.CAKeyPath == "" {
		return fmt.Errorf("config: CA cert and key paths are required")
	}
	if c.GatewayURL != "" {
		u, err := url.Parse(c.GatewayURL)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
			return fmt.Errorf("config: invalid gateway URL %q", c.GatewayURL)
		}
	}
	return nil
}
