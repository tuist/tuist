package controllers

import (
	"context"
	"fmt"
	"sync"
	"time"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/metrics"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// Both reconcilers run under the same manager leader. Serialize the allocation
// snapshot/publish with revoke/taint so a pre-reservation snapshot cannot reopen
// a node after its grant was revoked. The server also rejects older timestamps.
var sandboxAllocationMu sync.Mutex

// Sandboxes and queued CI compete for uncommitted capacity. Host reservations
// still protect a waiting CI shape; a queue elsewhere does not revoke all grants.
func (r *AutoscalerReconciler) publishSandboxAllocations(ctx context.Context, pool *tuistv1.RunnerPool, fleet *fleetAllocation) error {
	if pool.Spec.OS != "linux" || r.SandboxesNamespace == "" || fleet == nil {
		return nil
	}
	// One reporter per fleet; all members still compute the same CI decision.
	for name := range fleet.members {
		if name < pool.Name {
			return nil
		}
	}
	sandboxAllocationMu.Lock()
	defer sandboxAllocationMu.Unlock()
	observed := time.Now().UTC()
	var reader client.Reader = r.Client
	if r.APIReader != nil {
		reader = r.APIReader
	}
	var nodes corev1.NodeList
	if err := reader.List(ctx, &nodes, fleetNodeSelector(pool)); err != nil {
		return err
	}
	// Include every Pod, not just runners: pending resizes and RuntimeClass
	// overhead consume scheduling capacity too. This read must be uncached.
	var pods corev1.PodList
	if err := reader.List(ctx, &pods); err != nil {
		return err
	}
	daemons, err := listSandboxDaemons(ctx, reader, r.SandboxesNamespace)
	if err != nil {
		return err
	}
	for i := range nodes.Items {
		node := &nodes.Items[i]
		for _, daemon := range daemons {
			if daemon.node != node.Name {
				continue
			}
			allocation := planSandboxAllocation(node, daemon, pods.Items, fleet)
			allocation.ObservedAt = observed
			if err := r.SignalsClient.PublishSandboxAllocation(ctx, allocation); err != nil {
				return fmt.Errorf("publish sandbox allocation for %s: %w", node.Name, err)
			}
			metrics.RecordSandboxAllocation(node.Name, daemon.memory, allocation.MemoryBytes, allocation.FreeBytes, float64(observed.Unix()))
		}
	}
	return nil
}

func planSandboxAllocation(node *corev1.Node, daemon sandboxDaemon, pods []corev1.Pod, fleet *fleetAllocation) scaling.SandboxAllocation {
	allocation := scaling.SandboxAllocation{Node: node.Name, Pod: daemon.name, Reclaim: fleet == nil || isReserved(node) || node.Spec.Unschedulable || daemon.terminating}
	ready := false
	for _, condition := range node.Status.Conditions {
		if condition.Type == corev1.NodeReady && condition.Status == corev1.ConditionTrue {
			ready = true
		}
		if (condition.Type == corev1.NodeMemoryPressure || condition.Type == corev1.NodeDiskPressure || condition.Type == corev1.NodePIDPressure) && condition.Status == corev1.ConditionTrue {
			allocation.Reclaim = true
		}
	}
	if !ready {
		allocation.Reclaim = true
	}
	if allocation.Reclaim {
		return allocation
	}
	capacity := node.Status.Allocatable.Memory().Value()
	var used, reclaimable int64
	for i := range pods {
		pod := &pods[i]
		if pod.Spec.NodeName != node.Name || pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed {
			continue
		}
		memory := allocationPodMemory(pod)
		// The target daemon is counted separately using max(requested,
		// allocated, applied). Other daemon Pods remain ordinary occupancy.
		if pod.Name == daemon.name && pod.Labels[sandboxdLabel] == "true" {
			memory = daemon.memory
		}
		used += memory
		member, ok := fleet.members[pod.Labels["tuist.dev/runner-pool"]]
		if ok && pod.DeletionTimestamp.IsZero() && isIdle(pod) && isWarmCapacity(pod, member.pool) && !isStaleRunner(pod, member.pool) {
			reclaimable += memory
		}
	}
	allocation.FreeBytes = max(capacity-used, 0)
	allocation.MemoryBytes = max(capacity-used+daemon.memory+reclaimable, 0)
	return allocation
}

// A shrink is not free memory until both allocated and applied resources
// have fallen. Copy before adjusting; never mutate the informer objects.
func allocationPodMemory(pod *corev1.Pod) int64 {
	copy := pod.DeepCopy()
	statuses := append(append([]corev1.ContainerStatus(nil), pod.Status.ContainerStatuses...), pod.Status.InitContainerStatuses...)
	for _, containers := range [][]corev1.Container{copy.Spec.Containers, copy.Spec.InitContainers} {
		for i := range containers {
			container := &containers[i]
			for _, status := range statuses {
				if status.Name != container.Name {
					continue
				}
				requests := []corev1.ResourceList{status.AllocatedResources}
				if status.Resources != nil {
					requests = append(requests, status.Resources.Requests)
				}
				for _, resources := range requests {
					if memory, ok := resources[corev1.ResourceMemory]; ok && memory.Cmp(container.Resources.Requests[corev1.ResourceMemory]) > 0 {
						if container.Resources.Requests == nil {
							container.Resources.Requests = corev1.ResourceList{}
						}
						container.Resources.Requests[corev1.ResourceMemory] = memory.DeepCopy()
					}
				}
			}
		}
	}
	var app, sidecars, initPeak int64
	for _, container := range copy.Spec.Containers {
		app += container.Resources.Requests.Memory().Value()
	}
	for _, container := range copy.Spec.InitContainers {
		memory := container.Resources.Requests.Memory().Value()
		if container.RestartPolicy != nil && *container.RestartPolicy == corev1.ContainerRestartPolicyAlways {
			sidecars += memory
			initPeak = max(initPeak, sidecars)
		} else {
			initPeak = max(initPeak, sidecars+memory)
		}
	}
	return max(app+sidecars, initPeak) + copy.Spec.Overhead.Memory().Value()
}
