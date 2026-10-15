package controllers

import corev1 "k8s.io/api/core/v1"

const (
	nodeFilteredUnschedulable  = "unschedulable"
	nodeFilteredNotReady       = "not_ready"
	nodeFilteredMemoryPressure = "memory_pressure"
	nodeFilteredDiskPressure   = "disk_pressure"
	nodeFilteredPIDPressure    = "pid_pressure"
	nodeFilteredPrewarming     = "prewarming"
)

// prewarmTaintKey is the taint tart-kubelet holds a joining macOS host under
// while it pulls its fleet's runner images. Runner Pods do not tolerate it, so
// the host's memory is no capacity yet.
//
// CONTRACT: must match tart-kubelet's `nodeagent.PrewarmTaintKey`. The two
// live in separate Go modules, coupled by convention.
const prewarmTaintKey = "tuist.dev/prewarming"

var nodeFilterReasons = []string{
	nodeFilteredUnschedulable,
	nodeFilteredNotReady,
	nodeFilteredMemoryPressure,
	nodeFilteredDiskPressure,
	nodeFilteredPIDPressure,
	nodeFilteredPrewarming,
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
	for _, taint := range node.Spec.Taints {
		if taint.Key == prewarmTaintKey {
			return nodeFilteredPrewarming
		}
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
