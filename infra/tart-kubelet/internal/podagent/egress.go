package podagent

import (
	"context"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/egress"
)

const egressArmedMessagePrefix = "armed "

var (
	egressTunnelHealthy = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tart_kubelet_runner_egress_tunnel_healthy",
		Help: "1 when the gateway's tunnel can arm a VM on this host.",
	}, []string{"gateway"})
	egressHandshakeAgeSeconds = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tart_kubelet_runner_egress_handshake_age_seconds",
		Help: "Seconds since the last WireGuard handshake with the gateway.",
	}, []string{"gateway"})
	egressTunnelBytes = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "tart_kubelet_runner_egress_tunnel_bytes",
		Help: "Bytes carried by the gateway's tunnel since the tunnel daemon started.",
	}, []string{"gateway", "direction"})
	egressSyncErrorsTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "tart_kubelet_runner_egress_sync_errors_total",
		Help: "Failed syncs of the egress pf anchor and tables.",
	})
)

func init() {
	metrics.Registry.MustRegister(egressTunnelHealthy, egressHandshakeAgeSeconds, egressTunnelBytes, egressSyncErrorsTotal)
}

// syncEgress converges the egress pf tables to the labelled Pods on this
// host. A VM whose `tart run` has exited, or whose teardown has started, is
// dropped here before its address can be handed to another VM.
func (r *Reconciler) syncEgress(ctx context.Context) error {
	if r.Egress == nil {
		return nil
	}
	r.egressMu.Lock()
	defer r.egressMu.Unlock()
	return r.syncEgressLocked(ctx)
}

func (r *Reconciler) syncEgressLocked(ctx context.Context) error {
	pods := &corev1.PodList{}
	if err := r.CachedClient.List(ctx, pods, client.HasLabels{egress.PodLabel}); err != nil {
		egressSyncErrorsTotal.Inc()
		return err
	}
	states := make([]egress.PodState, 0, len(pods.Items))
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Spec.NodeName != r.NodeName {
			continue
		}
		entry := r.Store.Get(pod.Namespace, pod.Name)
		if entry == nil || entry.EgressReleased {
			continue
		}
		if entry.Run != nil {
			if _, exited := entry.Run.Exited(); exited {
				continue
			}
		}
		state := egress.PodState{Key: key(pod.Namespace, pod.Name), Gateway: pod.Labels[egress.PodLabel]}
		if condition := egressCondition(pod); condition != nil && condition.Status == corev1.ConditionTrue {
			state.ArmedIP = strings.TrimPrefix(condition.Message, egressArmedMessagePrefix)
			state.ArmedSince = condition.LastTransitionTime.Time
		} else if ip, err := r.Tart.IP(ctx, entry.VMName); err == nil {
			state.IP = ip
		}
		states = append(states, state)
	}
	err := r.Egress.Sync(ctx, states)
	if err != nil {
		egressSyncErrorsTotal.Inc()
	}
	r.recordEgressMetrics()
	return err
}

func (r *Reconciler) recordEgressMetrics() {
	now := time.Now()
	for name, status := range r.Egress.TunnelStatuses() {
		healthy := 0.0
		if r.Egress.GatewayReady(name) {
			healthy = 1
		}
		egressTunnelHealthy.WithLabelValues(name).Set(healthy)
		if status.LastHandshakeUnix > 0 {
			egressHandshakeAgeSeconds.WithLabelValues(name).Set(now.Sub(time.Unix(status.LastHandshakeUnix, 0)).Seconds())
		}
		egressTunnelBytes.WithLabelValues(name, "rx").Set(float64(status.RxBytes))
		egressTunnelBytes.WithLabelValues(name, "tx").Set(float64(status.TxBytes))
	}
}

// releaseEgress drops a stopped VM from the egress tables and kills its pf
// states before teardown deletes it, so the address can't stay routed for
// whatever VM gets it next.
func (r *Reconciler) releaseEgress(ctx context.Context, entry *Entry) {
	if r.Egress == nil {
		return
	}
	r.egressMu.Lock()
	defer r.egressMu.Unlock()
	entry.EgressReleased = true
	if err := r.syncEgressLocked(ctx); err != nil {
		log.FromContext(ctx).Error(err, "release VM from egress tables", "vm", entry.VMName)
	}
}

func egressCondition(pod *corev1.Pod) *corev1.PodCondition {
	for i := range pod.Status.Conditions {
		if string(pod.Status.Conditions[i].Type) == egress.ReadyCondition {
			return &pod.Status.Conditions[i]
		}
	}
	return nil
}

// egressReadyCondition is the condition published for a labelled Pod. An
// armed condition is never withdrawn: it is the durable record of which
// address is routed, which a restarted kubelet reads back.
func (r *Reconciler) egressReadyCondition(pod *corev1.Pod) (corev1.PodCondition, bool) {
	gateway, labelled := pod.Labels[egress.PodLabel]
	if !labelled {
		return corev1.PodCondition{}, false
	}
	if existing := egressCondition(pod); existing != nil && existing.Status == corev1.ConditionTrue {
		return *existing, true
	}
	if r.Egress != nil {
		if arm, ok := r.Egress.Armed(key(pod.Namespace, pod.Name)); ok {
			return corev1.PodCondition{
				Type:               corev1.PodConditionType(egress.ReadyCondition),
				Status:             corev1.ConditionTrue,
				Reason:             "Armed",
				Message:            egressArmedMessagePrefix + arm.IP,
				LastTransitionTime: metav1.NewTime(arm.Since),
			}, true
		}
	}
	reason := "GatewayNotReady"
	if r.Egress == nil {
		reason = "EgressDisabled"
	}
	since := metav1.Now()
	if existing := egressCondition(pod); existing != nil {
		since = existing.LastTransitionTime
	}
	return corev1.PodCondition{
		Type:               corev1.PodConditionType(egress.ReadyCondition),
		Status:             corev1.ConditionFalse,
		Reason:             reason,
		Message:            "gateway " + gateway + " cannot route this VM",
		LastTransitionTime: since,
	}, true
}

// EgressSyncer re-runs the egress sync on an interval, so a tunnel that
// recovers or a table that drifted converges without a Pod event.
type EgressSyncer struct {
	Reconciler *Reconciler
	Interval   time.Duration
}

func (s *EgressSyncer) NeedLeaderElection() bool { return false }

func (s *EgressSyncer) Start(ctx context.Context) error {
	interval := s.Interval
	if interval <= 0 {
		interval = 5 * time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		if err := s.Reconciler.syncEgress(ctx); err != nil {
			log.FromContext(ctx).Error(err, "egress sync")
		}
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}
