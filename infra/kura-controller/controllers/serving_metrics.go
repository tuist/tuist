package controllers

import (
	"github.com/prometheus/client_golang/prometheus"
	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

var authorityState = prometheus.NewGaugeVec(prometheus.GaugeOpts{Name: "kura_serving_authority_state", Help: "Current managed serving-authority phase."}, []string{"namespace", "kura_instance", "phase"})
var authorityHolderValid = prometheus.NewGaugeVec(prometheus.GaugeOpts{Name: "kura_serving_authority_holder_valid", Help: "Latest fresh holder report acknowledges valid serving authority."}, []string{"namespace", "kura_instance"})
var recoveryState = prometheus.NewGaugeVec(prometheus.GaugeOpts{Name: "kura_replica_recovery_state", Help: "Current persisted single-replica recovery phase."}, []string{"namespace", "kura_instance", "phase"})

func init() { metrics.Registry.MustRegister(authorityState, authorityHolderValid, recoveryState) }

func observeAuthority(instance *kurav1alpha1.KuraInstance, grant servingGrant, report servingReport) {
	for _, phase := range []string{"Preparing", "Serving", "Quiescing", "Revoking", "Fencing"} {
		value := 0.0
		if grant.Phase == phase {
			value = 1
		}
		authorityState.WithLabelValues(instance.Namespace, instance.Name, phase).Set(value)
	}
	valid := 0.0
	if report.Valid && report.Identity == grant.Holder && report.Epoch == grant.Epoch {
		valid = 1
	}
	authorityHolderValid.WithLabelValues(instance.Namespace, instance.Name).Set(valid)
}

func observeRecovery(instance *kurav1alpha1.KuraInstance) {
	for _, phase := range []string{"Quarantining", "DeletingClaim", "DeletingPod", "Rebuilding", "Verified"} {
		value := 0.0
		if instance.Status.ReplicaRecovery != nil && instance.Status.ReplicaRecovery.Phase == phase {
			value = 1
		}
		recoveryState.WithLabelValues(instance.Namespace, instance.Name, phase).Set(value)
	}
}

func forgetServingMetrics(namespace, name string) {
	labels := prometheus.Labels{"namespace": namespace, "kura_instance": name}
	authorityState.DeletePartialMatch(labels)
	authorityHolderValid.DeletePartialMatch(labels)
	recoveryState.DeletePartialMatch(labels)
}
