package controllers

import (
	"sort"
	"time"

	corev1 "k8s.io/api/core/v1"
)

type nativeFootprint struct {
	cpu, memory int64
	slots       int
}

func nativePodFootprint(pod *corev1.Pod) nativeFootprint {
	if pod.Labels[macosSandboxRole] == "control" || pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed || len(pod.Spec.Containers) != 1 || len(pod.Spec.InitContainers) != 0 || len(pod.Spec.EphemeralContainers) != 0 {
		return nativeFootprint{}
	}
	c := pod.Spec.Containers[0]
	return nativeFootprint{max(c.Resources.Requests.Cpu().MilliValue(), c.Resources.Limits.Cpu().MilliValue()), max(c.Resources.Requests.Memory().Value(), c.Resources.Limits.Memory().Value()), 1}
}
func (f *nativeFootprint) subtract(other nativeFootprint) {
	f.cpu -= other.cpu
	f.memory -= other.memory
	f.slots -= other.slots
}

// macOS has independent CPU, RAM and VM-slot bounds. Retiring enough bytes
// alone may leave a pending sandbox unable to fit, even on a mostly empty host.
func planNativeSandboxPreemption(nodes []corev1.Node, pods []corev1.Pod, pending map[string]int64, candidates map[string][]sandboxCandidate, now time.Time) []sandboxCandidate {
	sort.Slice(nodes, func(i, j int) bool { return nodes[i].Name < nodes[j].Name })
	var result []sandboxCandidate
	for _, node := range nodes {
		if pending[node.Name] <= 0 {
			continue
		}
		used := nativeFootprint{}
		for i := range pods {
			p := &pods[i]
			if p.Spec.NodeName != node.Name {
				continue
			}
			footprint := nativePodFootprint(p)
			// A marked/terminating CI runner is already yielding. Native reservations
			// remain charged, including while their own deletion is being fenced.
			if p.Labels[macosSandboxRole] != "execution" {
				_, marked := preemptionMark(p, now)
				if !p.DeletionTimestamp.IsZero() || marked {
					continue
				}
			}
			used.cpu += footprint.cpu
			used.memory += footprint.memory
			used.slots += footprint.slots
		}
		fits := func() bool {
			return used.cpu <= node.Status.Allocatable.Cpu().MilliValue() && used.memory <= node.Status.Allocatable.Memory().Value() && used.slots <= 2
		}
		eligible := append([]sandboxCandidate(nil), candidates[node.Name]...)
		sort.SliceStable(eligible, func(i, j int) bool {
			if !eligible[i].since.Equal(eligible[j].since) {
				return eligible[i].since.Before(eligible[j].since)
			}
			return eligible[i].pod.Name < eligible[j].pod.Name
		})
		var chosen []sandboxCandidate
		for _, candidate := range eligible {
			if fits() {
				break
			}
			used.subtract(nativePodFootprint(candidate.pod))
			chosen = append(chosen, candidate)
		}
		if fits() {
			result = append(result, chosen...)
		}
	}
	return result
}
