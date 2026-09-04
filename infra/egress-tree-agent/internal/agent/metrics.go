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
	LinkAttaches         prometheus.Counter
	LinkReattaches       prometheus.Counter
	SiblingOverflow      prometheus.Counter
	NodeBudgetMbps       prometheus.Gauge
	ClassSentBytes       *prometheus.GaugeVec
	ClassDrops           *prometheus.GaugeVec
	ClassBacklogBytes    *prometheus.GaugeVec
	ClassLendedPackets   *prometheus.GaugeVec
	ClassBorrowedPackets *prometheus.GaugeVec
	ClassRateBytes       *prometheus.GaugeVec
	ClassCeilBytes       *prometheus.GaugeVec
	DirectPackets        prometheus.Gauge
	PodRedirected        *prometheus.GaugeVec
	PodGuardPass         *prometheus.GaugeVec
	PodSiblingBypass     *prometheus.GaugeVec
	Returned             prometheus.Gauge
	ReturnDropped        prometheus.Gauge
}

// classLabels identify a tenant class. The account handle is carried
// alongside the classid because the classid alone does not identify a tenant
// over time: the controller frees a minor when an account's last instance
// goes and can hand the same one to another account later, splicing two
// tenants into one series.
var classLabels = []string{"classid", "account"}

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
		LinkAttaches: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kura_egress_tree_link_attach_total",
			Help: "First tcx link attaches on new pod devices; one per pod creation.",
		}),
		LinkReattaches: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kura_egress_tree_link_reattach_total",
			Help: "tcx links put back after being stripped or displaced from the head of a pod device's chain.",
		}),
		SiblingOverflow: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kura_egress_tree_sibling_overflow_total",
			Help: "Sibling allowlist entries not installed because the map was full.",
		}),
		NodeBudgetMbps: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "kura_egress_tree_node_budget_mbps",
			Help: "Root ceiling of the tree in Mbit/s.",
		}),
		ClassSentBytes: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_class_sent_bytes",
			Help: "Bytes sent by a tenant class (kernel counter).",
		}, classLabels),
		ClassDrops: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_class_drops",
			Help: "Packets dropped in a tenant class (kernel counter).",
		}, classLabels),
		ClassBacklogBytes: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_class_backlog_bytes",
			Help: "Bytes queued in a tenant class.",
		}, classLabels),
		ClassLendedPackets: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_class_lended_packets",
			Help: "Packets a tenant class sent within its own rate (HTB kernel counter).",
		}, classLabels),
		ClassBorrowedPackets: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_class_borrowed_packets",
			Help: "Packets a tenant class sent by borrowing from the root class (HTB kernel counter).",
		}, classLabels),
		ClassRateBytes: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_class_rate_bytes_per_second",
			Help: "Rate a tenant class is guaranteed by the kernel, in bytes per second.",
		}, classLabels),
		ClassCeilBytes: prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "kura_egress_tree_class_ceil_bytes_per_second",
			Help: "Ceiling a tenant class may borrow up to in the kernel, in bytes per second.",
		}, classLabels),
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
		m.SkippedPods,
		m.LinkAttaches, m.LinkReattaches, m.SiblingOverflow, m.NodeBudgetMbps, m.ClassSentBytes, m.ClassDrops,
		m.ClassBacklogBytes, m.ClassLendedPackets, m.ClassBorrowedPackets,
		m.ClassRateBytes, m.ClassCeilBytes,
		m.DirectPackets, m.PodRedirected, m.PodGuardPass,
		m.PodSiblingBypass, m.Returned, m.ReturnDropped,
	)
	return m
}
