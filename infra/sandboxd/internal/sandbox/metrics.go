package sandbox

import (
	"github.com/prometheus/client_golang/prometheus"
)

type Metrics struct {
	Create        prometheus.Histogram
	Resume        prometheus.Histogram
	Pause         prometheus.Histogram
	TemplateBuild *prometheus.HistogramVec
	Sandboxes     *prometheus.GaugeVec
	Workers       prometheus.Gauge
	Operations    *prometheus.CounterVec
	// Capacity as the server sees it in reports: the cgroup's memory
	// limit and usage, and the data directory's disk budget, occupancy
	// and the filesystem's free space.
	MemoryBudgetBytes  prometheus.Gauge
	MemoryUsedBytes    prometheus.Gauge
	DiskBudgetBytes    prometheus.Gauge
	DiskSandboxesBytes prometheus.Gauge
	DiskAvailableBytes prometheus.Gauge
}

func NewMetrics(registry prometheus.Registerer) *Metrics {
	fast := prometheus.ExponentialBuckets(0.05, 2, 12)
	slow := prometheus.ExponentialBuckets(0.25, 2, 12)
	m := &Metrics{
		Create: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name: "sandboxd_create_seconds", Help: "Time to create a sandbox (template restore, workspace format), including a lazy template build.", Buckets: fast,
		}),
		Resume: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name: "sandboxd_resume_seconds", Help: "Time to resume a paused sandbox.", Buckets: fast,
		}),
		Pause: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name: "sandboxd_pause_seconds", Help: "Time to pause a sandbox (full snapshot to disk).", Buckets: slow,
		}),
		TemplateBuild: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name: "sandboxd_template_build_seconds", Help: "Time to boot and snapshot a template shape.", Buckets: slow,
		}, []string{"shape"}),
		Sandboxes: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "sandboxd_sandboxes", Help: "Sandboxes on the node by state.",
		}, []string{"state"}),
		Workers: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "sandboxd_workers_running", Help: "sbx-worker processes running in guests.",
		}),
		Operations: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "sandboxd_operations_total", Help: "Sandbox operations by op and outcome.",
		}, []string{"op", "result"}),
		MemoryBudgetBytes: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "sandboxd_memory_budget_bytes", Help: "Memory limit of the daemon's cgroup, shared by every guest on the node.",
		}),
		MemoryUsedBytes: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "sandboxd_memory_used_bytes", Help: "Memory the daemon's cgroup currently uses.",
		}),
		DiskBudgetBytes: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "sandboxd_disk_budget_bytes", Help: "Bytes of the data filesystem sandboxes may occupy; zero when unset.",
		}),
		DiskSandboxesBytes: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "sandboxd_disk_sandboxes_bytes", Help: "Bytes jails hold exclusively (rootfs deltas, workspaces, their own memory images).",
		}),
		DiskAvailableBytes: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "sandboxd_disk_available_bytes", Help: "Free space on the filesystem behind the data directory.",
		}),
	}
	if registry != nil {
		registry.MustRegister(
			m.Create, m.Resume, m.Pause, m.TemplateBuild, m.Sandboxes, m.Workers, m.Operations,
			m.MemoryBudgetBytes, m.MemoryUsedBytes, m.DiskBudgetBytes, m.DiskSandboxesBytes, m.DiskAvailableBytes,
		)
	}
	return m
}

func (m *Metrics) observe(op string, err error) {
	if m == nil {
		return
	}
	result := "ok"
	if err != nil {
		result = "error"
	}
	m.Operations.WithLabelValues(op, result).Inc()
}
