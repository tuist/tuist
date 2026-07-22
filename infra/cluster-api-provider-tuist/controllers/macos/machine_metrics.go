package macos

import (
	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// machinePhaseGauge publishes each ScalewayAppleSiliconMachine's current
// lifecycle phase as a 1-valued series. Exactly one series exists per
// machine (recordMachinePhase clears the machine's prior series before
// setting the new one), so a transition — e.g. Failed -> Running after a
// recovery — never leaves a stale Failed series alerting forever.
//
// The operator's `/metrics` (:8080) is scraped into Grafana Cloud via the
// pod's prometheus.io/scrape annotation; the "machine stuck Failed" alert
// keys off `phase="Failed"` persisting for a machine (which is how a host
// stuck in terminal TartKubeletUpdateExceededRetries surfaces — the CR
// status is otherwise only visible via `kubectl get machine`).
var machinePhaseGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
	Name: "capt_scaleway_applesilicon_machine_phase",
	Help: "Current lifecycle phase of each ScalewayAppleSiliconMachine as a 1-valued series. Labels: machine, fleet, phase (Pending|Adopting|Provisioning|Bootstrapping|Ready|Deleting|Failed), failure_reason (set on terminal Failed, e.g. TartKubeletUpdateExceededRetries). Exactly one series per machine.",
}, []string{"machine", "fleet", "phase", "failure_reason"})

func init() {
	metrics.Registry.MustRegister(machinePhaseGauge)
}

// recordMachinePhase publishes exactly one 1-valued series for the
// machine's current phase, first clearing any prior phase series for it so
// a transition doesn't strand a stale series (a recovered machine would
// otherwise keep alerting on its old Failed series). Called from a deferred
// hook in Reconcile so it reflects the phase set by this reconcile pass.
func recordMachinePhase(m *infrav1.ScalewayAppleSiliconMachine) {
	machinePhaseGauge.DeletePartialMatch(prometheus.Labels{"machine": m.Name})
	phase := m.Status.Phase
	if phase == "" {
		phase = "Pending"
	}
	reason := ""
	if m.Status.FailureReason != nil {
		reason = *m.Status.FailureReason
	}
	machinePhaseGauge.WithLabelValues(m.Name, m.Spec.FleetName, phase, reason).Set(1)
}

// forgetMachinePhase drops a machine's phase series once its CR is gone, so
// a deleted machine stops emitting a phantom phase.
func forgetMachinePhase(name string) {
	machinePhaseGauge.DeletePartialMatch(prometheus.Labels{"machine": name})
}
