package sandbox

import (
	"github.com/prometheus/client_golang/prometheus"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

type Metrics struct {
	Create        prometheus.Histogram
	Resume        prometheus.Histogram
	Pause         prometheus.Histogram
	TemplateBuild *prometheus.HistogramVec
	Sandboxes     *prometheus.GaugeVec
	Workers       prometheus.Gauge
	Operations    *prometheus.CounterVec
	Phases        *prometheus.HistogramVec
	// Capacity as the server sees it in reports: the cgroup's memory
	// limit and usage, and the data directory's disk budget, occupancy
	// and the filesystem's free space.
	MemoryBudgetBytes  prometheus.Gauge
	MemoryUsedBytes    prometheus.Gauge
	DiskBudgetBytes    prometheus.Gauge
	DiskSandboxesBytes prometheus.Gauge
	DiskAvailableBytes prometheus.Gauge
	// Running VMs' guest memory against what their processes hold, summed
	// per node (sandbox IDs are never labels), and each VM's resident share
	// of its guest memory per report.
	VMReservedBytes prometheus.Gauge
	VMAnonBytes     prometheus.Gauge
	VMFileBytes     prometheus.Gauge
	VMCurrentBytes  prometheus.Gauge
	VMResidentShare prometheus.Histogram
}

func NewMetrics(registry prometheus.Registerer) *Metrics {
	fast := prometheus.ExponentialBuckets(0.05, 2, 12)
	slow := prometheus.ExponentialBuckets(0.25, 2, 12)
	m := &Metrics{
		Phases: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name: "sandboxd_lifecycle_phase_seconds", Help: "Time spent in sandbox lifecycle phases.",
			Buckets: prometheus.ExponentialBuckets(0.001, 2, 14),
		}, []string{"phase"}),
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
		VMReservedBytes: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "sandboxd_vm_reserved_bytes", Help: "Guest memory of the running VMs, as their shapes reserve it.",
		}),
		VMAnonBytes: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "sandboxd_vm_anon_bytes", Help: "Anonymous memory the running VMs' processes hold (Pss): what their guests wrote.",
		}),
		VMFileBytes: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "sandboxd_vm_file_bytes", Help: "File-backed memory the running VMs' processes hold (Pss): pages still mapped from the memory file they restored from.",
		}),
		VMCurrentBytes: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "sandboxd_vm_cgroup_bytes", Help: "Memory charged to the running VMs' own cgroups (memory.current): their processes' memory plus the page cache their disks filled.",
		}),
		VMResidentShare: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name: "sandboxd_vm_resident_share", Help: "Each running VM's resident memory (anonymous and file, Pss) over its guest memory, observed per report.",
			Buckets: []float64{0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1, 1.1},
		}),
	}
	if registry != nil {
		registry.MustRegister(
			m.Create, m.Resume, m.Pause, m.TemplateBuild, m.Sandboxes, m.Workers, m.Operations, m.Phases,
			m.MemoryBudgetBytes, m.MemoryUsedBytes, m.DiskBudgetBytes, m.DiskSandboxesBytes, m.DiskAvailableBytes,
			m.VMReservedBytes, m.VMAnonBytes, m.VMFileBytes, m.VMCurrentBytes, m.VMResidentShare,
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

// ObserveVMs records the running VMs' memory from a report's sandbox list.
// VMs whose memory could not be read are left out of every figure.
func (m *Metrics) ObserveVMs(infos []protocol.SandboxInfo) {
	if m == nil {
		return
	}
	var reserved, anon, file, current uint64
	for _, info := range infos {
		if info.State != protocol.StateRunning || info.MemoryMB <= 0 || info.MemoryAnonBytes+info.MemoryFileBytes == 0 {
			continue
		}
		guest := uint64(info.MemoryMB) << 20
		reserved += guest
		anon += info.MemoryAnonBytes
		file += info.MemoryFileBytes
		current += info.MemoryCurrentBytes
		m.VMResidentShare.Observe(float64(info.MemoryAnonBytes+info.MemoryFileBytes) / float64(guest))
	}
	m.VMReservedBytes.Set(float64(reserved))
	m.VMAnonBytes.Set(float64(anon))
	m.VMFileBytes.Set(float64(file))
	m.VMCurrentBytes.Set(float64(current))
}
