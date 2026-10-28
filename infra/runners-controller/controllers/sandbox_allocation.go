package controllers

import (
	"context"
	"encoding/json"
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

func ciQueued(fleet *fleetAllocation) bool {
	if fleet == nil {
		return true
	} // Unknown demand never grants sandbox capacity.
	for _, member := range fleet.members {
		if member.queued > 0 {
			return true
		}
	}
	return false
}

// Conservative CI-first admission: wait until all dispatchable CI has claimed
// its runners before starting another turn. This also avoids treating a
// fleet-wide byte grant as proof that a particular CI shape can fit a host.
func (r *AutoscalerReconciler) publishSandboxAllocations(ctx context.Context, pool *tuistv1.RunnerPool, fleet *fleetAllocation) error {
	if (pool.Spec.OS != "linux" && pool.Spec.OS != "darwin") || r.SandboxesNamespace == "" || fleet == nil {
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
	if pool.Spec.OS == "darwin" {
		return r.publishMacosGrants(ctx, nodes.Items, pods.Items, fleet, observed)
	}
	daemons, err := listSandboxDaemons(ctx, reader, r.SandboxesNamespace)
	if err != nil {
		return err
	}
	pressure := ciQueued(fleet)
	for i := range nodes.Items {
		node := &nodes.Items[i]
		for _, daemon := range daemons {
			if daemon.node != node.Name {
				continue
			}
			allocation := planSandboxAllocation(node, daemon, pods.Items, fleet, pressure)
			allocation.ObservedAt = observed
			if err := r.SignalsClient.PublishSandboxAllocation(ctx, allocation); err != nil {
				return fmt.Errorf("publish sandbox allocation for %s: %w", node.Name, err)
			}
			metrics.RecordSandboxAllocation(node.Name, daemon.memory, allocation.MemoryBytes, allocation.FreeBytes, float64(observed.Unix()))
		}
	}
	return nil
}

func planSandboxAllocation(node *corev1.Node, daemon sandboxDaemon, pods []corev1.Pod, fleet *fleetAllocation, pressure bool) scaling.SandboxAllocation {
	allocation := scaling.SandboxAllocation{Node: node.Name, Pod: daemon.name, Reclaim: pressure || isReserved(node) || node.Spec.Unschedulable || daemon.terminating}
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

const macosSandboxRole = "tuist.dev/macos-sandbox-role"
const macosSandboxGrant = "tuist.dev/macos-sandbox-grant"

func (r *AutoscalerReconciler) publishMacosGrants(ctx context.Context, nodes []corev1.Node, pods []corev1.Pod, fleet *fleetAllocation, observed time.Time) error {
	for i := range nodes {
		node := &nodes[i]
		for j := range pods {
			pod := &pods[j]
			if pod.Namespace != r.SandboxesNamespace || pod.Spec.NodeName != node.Name || pod.Labels[macosSandboxRole] != "control" {
				continue
			}
			allow := !ciQueued(fleet) && nodeFilterReason(node) == "" && !isReserved(node) && pod.DeletionTimestamp.IsZero()
			for _, condition := range node.Status.Conditions {
				if (condition.Type == corev1.NodeMemoryPressure || condition.Type == corev1.NodeDiskPressure || condition.Type == corev1.NodePIDPressure) && condition.Status != corev1.ConditionFalse {
					allow = false
				}
			}
			room := nativeSandboxRoom(node, pods, fleet, observed)
			allow = allow && room.cpu > 0 && room.memory > 0 && room.slots > 0
			grant, _ := json.Marshal(map[string]any{"cpu_milli": room.cpu, "memory_bytes": room.memory, "slots": room.slots, "node_uid": string(node.UID), "control_uid": string(pod.UID), "observed_at": observed, "allow": allow})
			before := node.DeepCopy()
			if node.Annotations == nil {
				node.Annotations = map[string]string{}
			}
			node.Annotations[macosSandboxGrant] = string(grant)
			// Optimistic locking cannot overwrite a concurrent CI reservation/taint.
			if err := r.Patch(ctx, node, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{})); err != nil {
				return err
			}
		}
	}
	return nil
}

// Grants include native capacity only: busy CI and other bound workloads are
// excluded, while reclaimable warm runners may yield. Server placement then
// subtracts its existing native reservations from this per-host envelope.
func nativeSandboxRoom(node *corev1.Node, pods []corev1.Pod, fleet *fleetAllocation, now time.Time) nativeFootprint {
	room := nativeFootprint{node.Status.Allocatable.Cpu().MilliValue(), node.Status.Allocatable.Memory().Value(), 2}
	for i := range pods {
		pod := &pods[i]
		if pod.Spec.NodeName != node.Name || pod.Labels[macosSandboxRole] == "execution" {
			continue
		}
		reclaimable := false
		if fleet != nil && pod.DeletionTimestamp.IsZero() {
			member, ok := fleet.members[pod.Labels["tuist.dev/runner-pool"]]
			if ok && member.pool != nil && isIdle(pod) && !isStaleRunner(pod, member.pool) && isWarmCapacity(pod, member.pool) {
				since, warm := warmSince(pod)
				reclaimable = warm && now.Sub(since) >= preemptionGrace
			}
		}
		if !reclaimable {
			room.subtract(nativePodFootprint(pod))
		}
	}
	room.cpu = max(room.cpu, 0)
	room.memory = max(room.memory, 0)
	room.slots = max(room.slots, 0)
	return room
}
