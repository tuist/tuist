package controllers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/metrics"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// Both reconcilers run under the same manager leader. Serialize the allocation
// snapshot/publish with revoke/taint so a pre-reservation snapshot cannot reopen
// a node after its grant was revoked. The server also rejects older timestamps.
var sandboxAllocationMu sync.Mutex

// Sandboxes and queued CI compete for uncommitted capacity. Host reservations
// still protect a waiting CI shape; a queue elsewhere does not revoke all grants.
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
	// The reporter speaks for the whole fleet, so its own site pin must not
	// narrow the hosts: the alphabetically first rack pool is pinned to one
	// site, and every other site's Macs were left without a grant.
	selector := fleetNodeSelector(pool)
	delete(selector, podtemplate.RackSiteNodeLabel)
	var nodes corev1.NodeList
	if err := reader.List(ctx, &nodes, selector); err != nil {
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
	for i := range nodes.Items {
		node := &nodes.Items[i]
		for _, daemon := range daemons {
			if daemon.node != node.Name {
				continue
			}
			allocation := planSandboxAllocation(node, daemon, pods.Items, fleet)
			allocation.ObservedAt = observed
			allocation.SiblingMemoryBytes = siblingMemory(daemon, daemons)
			if err := r.SignalsClient.PublishSandboxAllocation(ctx, allocation); err != nil {
				return fmt.Errorf("publish sandbox allocation for %s: %w", node.Name, err)
			}
			metrics.RecordSandboxAllocation(daemon.grantNode(), daemon.memory, allocation.MemoryBytes, allocation.FreeBytes, float64(observed.Unix()))
		}
	}
	return nil
}

func planSandboxAllocation(node *corev1.Node, daemon sandboxDaemon, pods []corev1.Pod, fleet *fleetAllocation) scaling.SandboxAllocation {
	allocation := scaling.SandboxAllocation{Node: daemon.grantNode(), Pod: daemon.name, Reclaim: fleet == nil || isReserved(node) || node.Spec.Unschedulable || daemon.terminating}
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
	var used, reclaimable, cpuUsed, cpuReclaimable int64
	for i := range pods {
		pod := &pods[i]
		if pod.Spec.NodeName != node.Name || pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed {
			continue
		}
		memory := allocationPodMemory(pod)
		cpu := allocationPodRequest(pod, corev1.ResourceCPU)
		// The target daemon is counted separately using max(requested,
		// allocated, applied). Other daemon Pods remain ordinary occupancy.
		if pod.Name == daemon.name && isSandboxDaemon(pod) {
			memory = daemon.memory
			// Its CPU counts at what the kubelet allocated, which is what a
			// resize is admitted against: a growth it deferred does not use
			// up the room the server sizes the next request from.
			if asked, allocated := daemonCPU(pod); asked > allocated {
				cpu -= asked - allocated
			}
		}
		used += memory
		cpuUsed += cpu
		member, ok := fleet.members[pod.Labels["tuist.dev/runner-pool"]]
		if ok && pod.DeletionTimestamp.IsZero() && isIdle(pod) && isWarmCapacity(pod, member.pool) && !isStaleRunner(pod, member.pool) {
			reclaimable += memory
			cpuReclaimable += cpu
		}
		// A runner on its way off the node still holds its CPU until it is
		// gone. Counting it as reclaimable keeps the server from lowering a
		// deferred growth it was retired for, which would let a replacement
		// runner take the CPU and retire again: seen on staging.
		if ok && !pod.DeletionTimestamp.IsZero() {
			cpuReclaimable += cpu
		}
	}
	allocation.FreeBytes = max(capacity-used, 0)
	allocation.MemoryBytes = max(capacity-used+daemon.memory+reclaimable, 0)
	if slots, ok := fleet.executionWarm[daemon.grantNode()]; ok && daemon.execution && slots > 0 {
		allocation.WarmBytes = int64(slots)*fleet.slotBytes + executionDaemonReserveBytes
	}
	allocation.CPUFreeMilli = max(node.Status.Allocatable.Cpu().MilliValue()-cpuUsed, 0)
	allocation.CPUReclaimableMilli = cpuReclaimable
	return allocation
}

// siblingMemory is what the grant counted the host's other carve-out at:
// the agent daemon for a remote execution worker and the other way round;
// nil when the host runs only one.
func siblingMemory(daemon sandboxDaemon, daemons []sandboxDaemon) *int64 {
	for _, other := range daemons {
		if other.node == daemon.node && other.name != daemon.name && other.execution != daemon.execution && !other.native {
			return &other.memory
		}
	}
	return nil
}

// A shrink is not free memory until both allocated and applied resources
// have fallen. Copy before adjusting; never mutate the informer objects.
func allocationPodMemory(pod *corev1.Pod) int64 {
	return allocationPodRequest(pod, corev1.ResourceMemory)
}

// allocationPodRequest is what the Pod holds of a resource on its node, in
// bytes for memory and millicores for CPU: the larger of each container's
// requested, allocated and applied requests, as the scheduler counts them.
func allocationPodRequest(pod *corev1.Pod, name corev1.ResourceName) int64 {
	value := func(quantity resource.Quantity) int64 {
		if name == corev1.ResourceCPU {
			return quantity.MilliValue()
		}
		return quantity.Value()
	}
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
					if quantity, ok := resources[name]; ok && quantity.Cmp(container.Resources.Requests[name]) > 0 {
						if container.Resources.Requests == nil {
							container.Resources.Requests = corev1.ResourceList{}
						}
						container.Resources.Requests[name] = quantity.DeepCopy()
					}
				}
			}
		}
	}
	var app, sidecars, initPeak int64
	for _, container := range copy.Spec.Containers {
		app += value(container.Resources.Requests[name])
	}
	for _, container := range copy.Spec.InitContainers {
		request := value(container.Resources.Requests[name])
		if container.RestartPolicy != nil && *container.RestartPolicy == corev1.ContainerRestartPolicyAlways {
			sidecars += request
			initPeak = max(initPeak, sidecars)
		} else {
			initPeak = max(initPeak, sidecars+request)
		}
	}
	total := max(app+sidecars, initPeak)
	// A Pod-level budget replaces the containers' requests on the node.
	if pod.Spec.Resources != nil {
		if quantity, ok := pod.Spec.Resources.Requests[name]; ok {
			total = value(quantity)
		}
	}
	return total + value(copy.Spec.Overhead[name])
}

// MacosSandboxRoleLabel marks a macOS sandbox host's control Pod and the
// execution Pods that reserve each sandbox VM's capacity.
const MacosSandboxRoleLabel = "tuist.dev/macos-sandbox-role"

const macosSandboxRole = MacosSandboxRoleLabel
const macosSandboxGrant = "tuist.dev/macos-sandbox-grant"

// macOS shares the Linux policy above: queued CI and native sandboxes compete
// for uncommitted capacity, a host reservation still protects a waiting CI
// shape, and unknown fleet demand denies every grant.
func (r *AutoscalerReconciler) publishMacosGrants(ctx context.Context, nodes []corev1.Node, pods []corev1.Pod, fleet *fleetAllocation, observed time.Time) error {
	var errs []error
	for i := range nodes {
		node := &nodes[i]
		for j := range pods {
			pod := &pods[j]
			if pod.Namespace != r.SandboxesNamespace || pod.Spec.NodeName != node.Name || pod.Labels[macosSandboxRole] != "control" {
				continue
			}
			// One host failing must not stop the rest: a grant lives 15 s and
			// a host reports it every 5 s, so a skipped tick left every later
			// host's grant stale on the server and creates found no host.
			if err := r.publishMacosGrant(ctx, node, pod, pods, fleet, observed); err != nil {
				errs = append(errs, err)
			}
		}
	}
	return errors.Join(errs...)
}

// macosGrantConflictRetries bounds the re-reads of a Node whose patch
// conflicted. tart-kubelet updates its Node every few seconds, so a
// conflict almost always clears on the first retry.
const macosGrantConflictRetries = 3

// publishMacosGrant writes one host's grant. Optimistic locking keeps a grant
// computed before a concurrent CI reservation or taint from reopening the
// host, so on a conflict the grant is recomputed from the Node as it is now.
func (r *AutoscalerReconciler) publishMacosGrant(ctx context.Context, node *corev1.Node, control *corev1.Pod, pods []corev1.Pod, fleet *fleetAllocation, observed time.Time) error {
	var reader client.Reader = r.Client
	if r.APIReader != nil {
		reader = r.APIReader
	}
	for attempt := 0; ; attempt++ {
		before := node.DeepCopy()
		if node.Annotations == nil {
			node.Annotations = map[string]string{}
		}
		node.Annotations[macosSandboxGrant] = macosGrant(node, control, pods, fleet, observed)
		err := r.Patch(ctx, node, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
		if err == nil || !apierrors.IsConflict(err) || attempt >= macosGrantConflictRetries {
			return err
		}
		if err := reader.Get(ctx, client.ObjectKeyFromObject(node), node); err != nil {
			return err
		}
	}
}

func macosGrant(node *corev1.Node, control *corev1.Pod, pods []corev1.Pod, fleet *fleetAllocation, observed time.Time) string {
	allow := fleet != nil && nodeFilterReason(node) == "" && !isReserved(node) && control.DeletionTimestamp.IsZero()
	for _, condition := range node.Status.Conditions {
		if (condition.Type == corev1.NodeMemoryPressure || condition.Type == corev1.NodeDiskPressure || condition.Type == corev1.NodePIDPressure) && condition.Status != corev1.ConditionFalse {
			allow = false
		}
	}
	room := nativeSandboxRoom(node, pods, fleet, observed)
	allow = allow && room.cpu > 0 && room.memory > 0 && room.slots > 0
	grant, _ := json.Marshal(map[string]any{"cpu_milli": room.cpu, "memory_bytes": room.memory, "slots": room.slots, "node_uid": string(node.UID), "control_uid": string(control.UID), "observed_at": observed, "allow": allow})
	return string(grant)
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
				// A warm sandbox VM exists to be claimed or given up, so it
				// never hides the room it holds behind the CI grace period.
				reclaimable = warm && (podtemplate.IsMacosSandboxWarm(member.pool) || now.Sub(since) >= preemptionGrace)
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
