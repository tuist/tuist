package agent

import (
	"github.com/prometheus/client_golang/prometheus"
)

// Metrics for the tree and its datapath. Kernel counters (tc class stats,
// BPF map counters) are exported as gauges carrying the raw kernel value:
// they reset with the device or map, and rate() over a gauge of a
// monotonically increasing kernel counter is the intended query shape.
type Metrics struct {
	ReconcileTotal       prometheus.Counter
	ReconcileErrors      prometheus.Counter
	AttachedPods         prometheus.Gauge
	ReturnAttachFailures prometheus.Counter
	SkippedPods          prometheus.Gauge
	BetaExcludedPods     prometheus.Gauge
	LinkReattaches       prometheus.Counter
	NodeBudgetMbps       prometheus.Gauge
	ClassSentBytes       *prometheus.GaugeVec
	ClassDrops           *prometheus.GaugeVec
	ClassBacklogBytes    *prometheus.GaugeVec
	DirectPackets        prometheus.Gauge
	PodRedirected        *prometheus.GaugeVec
	PodGuardPass         *prometheus.GaugeVec
	PodSiblingBypass     *prometheus.GaugeVec
	Returned             prometheus.Gauge
	ReturnDropped        prometheus.Gauge
}

func NewMetrics(registry prometheus.Registerer) *Metrics {
	m := &Metrics{
		ReconcileTotal: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kura_egress_tree_reconcile_total",
			Help: "Reconcile loop iterations.",
		}),
		ReconcileErrors: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kura_egress_tree_reconcile_errors_total",
			Help: "Reconcile loop iterations that ended with an error.",
		}),
		AttachedPods: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "kura_egress_tree_attached_pods",
			Help: "Pod devices with the shaper program attached.",
		}),
		ReturnAttachFailures: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kura_egress_tree_return_attach_failures_total",
			Help: "Failed attempts to attach the return program.",
		}),
		SkippedPods: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "kura_egress_tree_skipped_pods",
			Help: "Annotated pods not attached this cycle (unresolvable device or malformed annotation).",
		}),
		BetaExcludedPods: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "kura_egress_tree_beta_excluded_pods",
			Help: "Annotated pods excluded from attachment by the BETA_POD_PREFIX gate.",
		}),
		LinkReattaches: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kura_egress_tree_link_reattach_total",
			Help: "tcx link attach or reattach operations on pod devices.",
		}),
		NodeBudgetMbps: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "kura_egress_tree_node_budget_mbps",
			Help: "Root ceiling of the tree in Mbit/s.",
		}),
		ClassSentBytes: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_class_sent_bytes",
			Help: "Bytes sent by a tenant class (kernel counter).",
		}, []string{"classid"}),
		ClassDrops: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_class_drops",
			Help: "Packets dropped in a tenant class (kernel counter).",
		}, []string{"classid"}),
		ClassBacklogBytes: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_class_backlog_bytes",
			Help: "Bytes queued in a tenant class.",
		}, []string{"classid"}),
		DirectPackets: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "kura_egress_tree_direct_packets",
			Help: "Packets that reached the tree unclassified (kernel counter).",
		}),
		PodRedirected: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_pod_redirected_packets",
			Help: "Packets redirected into the tree from a pod device (kernel counter).",
		}, []string{"namespace", "pod"}),
		PodGuardPass: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_pod_guard_pass_packets",
			Help: "Shaped packets handed back to Cilium on a pod device (kernel counter).",
		}, []string{"namespace", "pod"}),
		PodSiblingBypass: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_pod_sibling_bypass_packets",
			Help: "Packets that took the sibling bypass on a pod device (kernel counter).",
		}, []string{"namespace", "pod"}),
		Returned: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "kura_egress_tree_returned_packets",
			Help: "Shaped packets sent back to a pod device's ingress hook (kernel counter).",
		}),
		ReturnDropped: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "kura_egress_tree_return_dropped_packets",
			Help: "Packets dropped on the trampoline peer for missing shaping metadata (kernel counter).",
		}),
	}
	registry.MustRegister(
		m.ReconcileTotal, m.ReconcileErrors, m.AttachedPods, m.ReturnAttachFailures,
		m.SkippedPods, m.BetaExcludedPods,
		m.LinkReattaches, m.NodeBudgetMbps, m.ClassSentBytes, m.ClassDrops,
		m.ClassBacklogBytes, m.DirectPackets, m.PodRedirected, m.PodGuardPass,
		m.PodSiblingBypass, m.Returned, m.ReturnDropped,
	)
	return m
}
