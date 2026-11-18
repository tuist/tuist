package driver

import (
	"context"
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// thinMetrics publishes the thin pool's counters from the observations the
// capacity advertiser already takes, so a scrape never runs LVM itself. Every
// series carries only node, vg and pool.
type thinMetrics struct {
	registry                                    *prometheus.Registry
	dataSize, dataUsed, metadataSize, metaUsed  *prometheus.GaugeVec
	readOnly, outOfDataSpace, healthy, observed *prometheus.GaugeVec
}

func newThinMetrics() *thinMetrics {
	labels := []string{"node", "vg", "pool"}
	gauge := func(name, help string) *prometheus.GaugeVec {
		return prometheus.NewGaugeVec(prometheus.GaugeOpts{Namespace: "kura_volumes", Subsystem: "thin_pool", Name: name, Help: help}, labels)
	}
	m := &thinMetrics{
		registry:       prometheus.NewRegistry(),
		dataSize:       gauge("data_size_bytes", "Physical data capacity of the thin pool."),
		dataUsed:       gauge("data_used_bytes", "Physical data the thin pool has mapped."),
		metadataSize:   gauge("metadata_size_bytes", "Metadata capacity of the thin pool."),
		metaUsed:       gauge("metadata_used_bytes", "Metadata the thin pool uses."),
		readOnly:       gauge("read_only", "1 when the pool is read-only, failed or needs a metadata check."),
		outOfDataSpace: gauge("out_of_data_space", "1 when the pool ran out of data space and errors new allocations."),
		healthy:        gauge("healthy", "1 when the last observation admits new volumes."),
		observed:       gauge("last_observation_timestamp_seconds", "Unix time of the last successful pool observation."),
	}
	m.registry.MustRegister(m.dataSize, m.dataUsed, m.metadataSize, m.metaUsed, m.readOnly, m.outOfDataSpace, m.healthy, m.observed)
	return m
}

// MetricsHandler serves the node's thin pool metrics. It serves an empty
// exposition on nodes without a thin pool.
func (d *Driver) MetricsHandler() http.Handler {
	if d.metrics == nil {
		return promhttp.HandlerFor(prometheus.NewRegistry(), promhttp.HandlerOpts{})
	}
	return promhttp.HandlerFor(d.metrics.registry, promhttp.HandlerOpts{})
}

// poolMode reads the read-only and out-of-data-space states from a thin-pool
// status line. A failed pool reports only "Fail" (or "Error") after the
// target name.
func poolMode(fields []string) (readOnly, outOfDataSpace, ok bool) {
	if len(fields) >= 4 && fields[2] == "thin-pool" && (fields[3] == "Fail" || fields[3] == "Error") {
		return true, false, true
	}
	if len(fields) < 11 || fields[2] != "thin-pool" {
		return false, false, false
	}
	return fields[7] == "ro" || fields[10] == "needs_check", fields[7] == "out_of_data_space", true
}

// recordThin is called with the pool lock held. A failed observation removes
// the usage series rather than leaving stale values, so absence alerting sees
// it, but still reports the pool's mode whenever device-mapper can.
func (d *Driver) recordThin(ctx context.Context, s *ThinSnapshot, observeErr error) {
	m := d.metrics
	if m == nil {
		return
	}
	labels := prometheus.Labels{"node": d.nodeID, "vg": d.volumeGroup, "pool": d.thin.Pool}
	boolean := func(v bool) float64 {
		if v {
			return 1
		}
		return 0
	}
	if observeErr == nil {
		m.dataSize.With(labels).Set(float64(s.DataTotal))
		m.dataUsed.With(labels).Set(float64(s.DataUsed))
		m.metadataSize.With(labels).Set(float64(s.MetadataTotal))
		m.metaUsed.With(labels).Set(float64(s.MetadataUsed))
		m.healthy.With(labels).Set(boolean(s.Healthy))
		m.readOnly.With(labels).Set(boolean(s.poolReadOnly))
		m.outOfDataSpace.With(labels).Set(boolean(s.poolOutOfDataSpace))
		m.observed.With(labels).Set(float64(s.ObservedAt.UnixNano()) / 1e9)
		return
	}
	for _, g := range []*prometheus.GaugeVec{m.dataSize, m.dataUsed, m.metadataSize, m.metaUsed, m.healthy} {
		g.Delete(labels)
	}
	fields, err := d.poolStatus(ctx)
	readOnly, outOfDataSpace, ok := poolMode(fields)
	if err != nil || !ok {
		m.readOnly.Delete(labels)
		m.outOfDataSpace.Delete(labels)
		return
	}
	m.readOnly.With(labels).Set(boolean(readOnly))
	m.outOfDataSpace.With(labels).Set(boolean(outOfDataSpace))
}
