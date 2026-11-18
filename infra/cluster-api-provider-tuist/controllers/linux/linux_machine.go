package linux

import (
	corev1 "k8s.io/api/core/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/core/v1beta1"
)

// linuxNodeIdentityClusterRole binds a Linux node's kubelet identity to the
// built-in system:node ClusterRole — the complete, canonical kubelet
// permission set — instead of the chart's scoped tart-kubelet role (which
// only covers what the macOS shim exercises). A real Linux kubelet needs the
// full set (leases, services, PVCs, CSI, ...), and discovering those one
// forbidden error at a time is its own kind of outage.
const linuxNodeIdentityClusterRole = "system:node"

// NodeReadyCondition is set True once the self-joined Node reports Ready. The
// Provisioned/Bootstrapped conditions are declared in controllers/shared; the
// Linux kinds reuse Provisioned and add NodeReady.
const NodeReadyCondition clusterv1.ConditionType = "NodeReady"

// truncate caps oversized SSH output so a failed bootstrap's error stays a
// readable event rather than dumping the whole apt log.
func truncate(b []byte, max int) string {
	if len(b) <= max {
		return string(b)
	}
	return string(b[:max]) + "…(truncated)"
}

func nodeReady(node *corev1.Node) bool {
	for _, c := range node.Status.Conditions {
		if c.Type == corev1.NodeReady && c.Status == corev1.ConditionTrue {
			return true
		}
	}
	return false
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
