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
	}
	if registry != nil {
		registry.MustRegister(m.Create, m.Resume, m.Pause, m.TemplateBuild, m.Sandboxes, m.Workers, m.Operations)
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
