package controllers

import corev1 "k8s.io/api/core/v1"

const (
	nodeFilteredUnschedulable  = "unschedulable"
	nodeFilteredNotReady       = "not_ready"
	nodeFilteredMemoryPressure = "memory_pressure"
	nodeFilteredDiskPressure   = "disk_pressure"
	nodeFilteredPIDPressure    = "pid_pressure"
)

var nodeFilterReasons = []string{
	nodeFilteredUnschedulable,
	nodeFilteredNotReady,
	nodeFilteredMemoryPressure,
	nodeFilteredDiskPressure,
	nodeFilteredPIDPressure,
}

// corev1LocalRef is the obvious shorthand. We refer to the pool by
// name from the assignment; same namespace, no kind ambiguity.
func corev1LocalRef(name string) corev1.LocalObjectReference {
	return corev1.LocalObjectReference{Name: name}
}

// nodeFilterReason returns why a node must not contribute runner-fleet
// capacity. An empty result means the node is Ready, schedulable, and free
// from the pressure conditions that make starting another virtual machine
// unsafe. Ready must be explicitly true: an absent or unknown condition is
// not usable capacity.
func nodeFilterReason(node *corev1.Node) string {
	if node.Spec.Unschedulable {
		return nodeFilteredUnschedulable
	}

	ready := false
	for _, condition := range node.Status.Conditions {
		switch condition.Type {
		case corev1.NodeReady:
			ready = condition.Status == corev1.ConditionTrue
		case corev1.NodeMemoryPressure:
			if condition.Status == corev1.ConditionTrue {
				return nodeFilteredMemoryPressure
			}
		case corev1.NodeDiskPressure:
			if condition.Status == corev1.ConditionTrue {
				return nodeFilteredDiskPressure
			}
		case corev1.NodePIDPressure:
			if condition.Status == corev1.ConditionTrue {
				return nodeFilteredPIDPressure
			}
		}
	}
	if !ready {
		return nodeFilteredNotReady
	}
	return ""
}

func summarizeFleetNodes(nodes []corev1.Node) (int, map[string]int) {
	ready := 0
	filtered := make(map[string]int, len(nodeFilterReasons))
	for i := range nodes {
		reason := nodeFilterReason(&nodes[i])
		if reason == "" {
			ready++
			continue
		}
		filtered[reason]++
	}
	return ready, filtered
}
