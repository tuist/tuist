package provider

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/api/resource"
)

// NodeProvider implements virtual-kubelet's NodeProvider interface. The VK
// runtime calls this to publish the virtual Node's status to the cluster.
type NodeProvider struct {
	provider *Provider
	notify   func(*corev1.Node)
}

// NewNodeProvider returns a NodeProvider tied to the given Provider's
// Orchard client (so capacity reflects the live worker fleet).
func NewNodeProvider(p *Provider) *NodeProvider {
	return &NodeProvider{provider: p}
}

// Ping is the runtime's "is the provider healthy?" check. We ping
// Orchard's worker list — if the controller's reachable and reports any
// online workers, we're healthy.
func (n *NodeProvider) Ping(ctx context.Context) error {
	workers, err := n.provider.Client.ListWorkers(ctx)
	if err != nil {
		return fmt.Errorf("orchard ping: %w", err)
	}
	for _, w := range workers {
		if w.Status == "online" || w.Status == "" {
			return nil
		}
	}
	return fmt.Errorf("no online Orchard workers")
}

// NotifyNodeStatus registers the callback the VK runtime calls when our
// status changes. We also kick off a periodic refresh so capacity stays
// fresh as the worker pool scales.
func (n *NodeProvider) NotifyNodeStatus(ctx context.Context, notify func(*corev1.Node)) {
	n.notify = notify
	go n.statusLoop(ctx)
}

func (n *NodeProvider) statusLoop(ctx context.Context) {
	tick := time.NewTicker(60 * time.Second)
	defer tick.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			if n.notify == nil {
				continue
			}
			node, err := n.buildNode(ctx)
			if err != nil {
				continue
			}
			n.notify(node)
		}
	}
}

// buildNode computes the current virtual Node spec + status. Capacity is
// the sum across online Orchard workers; allocatable subtracts the VMs we
// already track. K8s scheduler uses these to decide where to place new
// Pods that target this Node.
func (n *NodeProvider) buildNode(ctx context.Context) (*corev1.Node, error) {
	workers, err := n.provider.Client.ListWorkers(ctx)
	if err != nil {
		return nil, err
	}
	vms, err := n.provider.Client.ListVMs(ctx)
	if err != nil {
		return nil, err
	}

	var totalCPU, totalMemory int64
	var workerCount int
	for _, w := range workers {
		if w.Status != "" && w.Status != "online" {
			continue
		}
		totalCPU += int64(w.CPU)
		totalMemory += int64(w.Memory) * 1024 * 1024 // MiB → bytes
		workerCount++
	}

	var usedCPU, usedMemory int64
	for _, vm := range vms {
		usedCPU += int64(vm.CPU)
		usedMemory += int64(vm.Memory) * 1024 * 1024
	}

	allocatableCPU := totalCPU - usedCPU
	if allocatableCPU < 0 {
		allocatableCPU = 0
	}
	allocatableMemory := totalMemory - usedMemory
	if allocatableMemory < 0 {
		allocatableMemory = 0
	}

	// Conservative pod count: assume the smallest realistic workload is
	// 1 CPU / 1 GiB. Real placement is gated by CPU/Memory anyway.
	const maxPodsPerCPU = 1
	totalPods := totalCPU * maxPodsPerCPU

	now := metav1.NewTime(time.Now())

	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Name: n.provider.NodeName,
			Labels: map[string]string{
				"kubernetes.io/role":                  "agent",
				"kubernetes.io/os":                    "darwin",
				"kubernetes.io/arch":                  "arm64",
				"node.kubernetes.io/exclude-from-external-load-balancers": "true",
				"type":                                "virtual-kubelet",
				"tuist.dev/orchard-fleet":             "true",
			},
		},
		Spec: corev1.NodeSpec{
			Taints: []corev1.Taint{
				// Workloads must explicitly tolerate this to land on the
				// macOS fleet. Stops kube-scheduler from placing arbitrary
				// Linux Pods here just because the Node has capacity.
				{Key: "tuist.dev/macos", Value: "true", Effect: corev1.TaintEffectNoSchedule},
				{Key: "virtual-kubelet.io/provider", Value: "vk-orchard", Effect: corev1.TaintEffectNoSchedule},
			},
		},
		Status: corev1.NodeStatus{
			Capacity: corev1.ResourceList{
				corev1.ResourceCPU:    *resource.NewQuantity(totalCPU, resource.DecimalSI),
				corev1.ResourceMemory: *resource.NewQuantity(totalMemory, resource.BinarySI),
				corev1.ResourcePods:   *resource.NewQuantity(totalPods, resource.DecimalSI),
			},
			Allocatable: corev1.ResourceList{
				corev1.ResourceCPU:    *resource.NewQuantity(allocatableCPU, resource.DecimalSI),
				corev1.ResourceMemory: *resource.NewQuantity(allocatableMemory, resource.BinarySI),
				corev1.ResourcePods:   *resource.NewQuantity(totalPods, resource.DecimalSI),
			},
			Conditions: nodeConditions(workerCount, now),
			Addresses: []corev1.NodeAddress{
				{Type: corev1.NodeHostName, Address: n.provider.NodeName},
			},
			DaemonEndpoints: corev1.NodeDaemonEndpoints{
				KubeletEndpoint: corev1.DaemonEndpoint{Port: 10250},
			},
			NodeInfo: corev1.NodeSystemInfo{
				OperatingSystem: "darwin",
				Architecture:    "arm64",
				KubeletVersion:  "v1.0.0-vk-orchard",
			},
		},
	}
	return node, nil
}

func nodeConditions(workerCount int, now metav1.Time) []corev1.NodeCondition {
	ready := corev1.ConditionTrue
	reason := "OrchardOnline"
	message := fmt.Sprintf("%d Orchard workers online", workerCount)
	if workerCount == 0 {
		ready = corev1.ConditionFalse
		reason = "NoWorkers"
		message = "No Orchard workers are reporting online"
	}
	return []corev1.NodeCondition{
		{
			Type:               corev1.NodeReady,
			Status:             ready,
			Reason:             reason,
			Message:            message,
			LastHeartbeatTime:  now,
			LastTransitionTime: now,
		},
		{Type: corev1.NodeMemoryPressure, Status: corev1.ConditionFalse, LastHeartbeatTime: now, LastTransitionTime: now},
		{Type: corev1.NodeDiskPressure, Status: corev1.ConditionFalse, LastHeartbeatTime: now, LastTransitionTime: now},
		{Type: corev1.NodePIDPressure, Status: corev1.ConditionFalse, LastHeartbeatTime: now, LastTransitionTime: now},
		{Type: corev1.NodeNetworkUnavailable, Status: corev1.ConditionFalse, LastHeartbeatTime: now, LastTransitionTime: now},
	}
}
