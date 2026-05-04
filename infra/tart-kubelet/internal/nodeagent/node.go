// Package nodeagent ensures the tart-kubelet's Mac mini is registered
// as a real `Node` in the cluster and refreshes its status on a
// heartbeat.
//
// The split with the Pod reconciler mirrors real kubelet: one component
// owns the Node object, another reconciles workloads that landed on
// that Node.
package nodeagent

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// Maintainer is a controller-runtime Runnable. Owns the Node object's
// lifecycle on the API server and bumps `LastHeartbeatTime` so the
// node-controller doesn't NotReady-evict workloads.
type Maintainer struct {
	Client    client.Client
	NodeName  string
	CPU       int
	MemoryMB  int
	MaxPods   int
	Heartbeat time.Duration
}

// Start blocks until ctx is cancelled. Conforms to manager.Runnable.
func (m *Maintainer) Start(ctx context.Context) error {
	if err := m.ensureNode(ctx); err != nil {
		return err
	}
	t := time.NewTicker(m.Heartbeat)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
			if err := m.refresh(ctx); err != nil {
				log.FromContext(ctx).Error(err, "node refresh")
			}
		}
	}
}

func (m *Maintainer) ensureNode(ctx context.Context) error {
	node := &corev1.Node{}
	err := m.Client.Get(ctx, types.NamespacedName{Name: m.NodeName}, node)
	if apierrors.IsNotFound(err) {
		node.Name = m.NodeName
		m.configureNode(node)
		return m.Client.Create(ctx, node)
	}
	if err != nil {
		return err
	}
	// Node already exists (kubelet restart): just refresh status.
	return m.refresh(ctx)
}

func (m *Maintainer) refresh(ctx context.Context) error {
	node := &corev1.Node{}
	if err := m.Client.Get(ctx, types.NamespacedName{Name: m.NodeName}, node); err != nil {
		return err
	}
	m.configureNode(node)
	for i, c := range node.Status.Conditions {
		if c.Type == corev1.NodeReady {
			node.Status.Conditions[i].LastHeartbeatTime = metav1.Now()
		}
	}
	return m.Client.Status().Update(ctx, node)
}

// configureNode sets labels, taints, capacity, and Node info. Mirrors
// what a real kubelet reports — minus cAdvisor metrics, which we
// don't need.
func (m *Maintainer) configureNode(node *corev1.Node) {
	if node.Labels == nil {
		node.Labels = map[string]string{}
	}
	node.Labels["kubernetes.io/os"] = "darwin"
	node.Labels["kubernetes.io/arch"] = "arm64"
	node.Labels["tuist.dev/runtime"] = "tart"
	node.Labels[corev1.LabelHostname] = m.NodeName

	// Same NoSchedule taint we used for VK so stray Linux Pods don't
	// land here. Pods that actually want darwin set both the
	// nodeSelector and a matching toleration.
	if !hasTaint(node.Spec.Taints, "tuist.dev/macos") {
		node.Spec.Taints = append(node.Spec.Taints, corev1.Taint{
			Key:    "tuist.dev/macos",
			Value:  "true",
			Effect: corev1.TaintEffectNoSchedule,
		})
	}

	cpu := m.CPU
	mem := m.MemoryMB
	maxPods := m.MaxPods
	if cpu == 0 {
		cpu = 8
	}
	if mem == 0 {
		mem = 16384
	}
	if maxPods == 0 {
		// Apple's macOS SLA caps virtualized macOS instances at 2 per
		// bare-metal host; Tart refuses to start a third VM.
		maxPods = 2
	}
	if node.Status.Capacity == nil {
		node.Status.Capacity = corev1.ResourceList{}
	}
	if node.Status.Allocatable == nil {
		node.Status.Allocatable = corev1.ResourceList{}
	}
	for _, list := range []corev1.ResourceList{node.Status.Capacity, node.Status.Allocatable} {
		list[corev1.ResourceCPU] = resource.MustParse(fmt.Sprintf("%d", cpu))
		list[corev1.ResourceMemory] = resource.MustParse(fmt.Sprintf("%dMi", mem))
		list[corev1.ResourcePods] = resource.MustParse(fmt.Sprintf("%d", maxPods))
	}

	now := metav1.Now()
	if !hasCondition(node.Status.Conditions, corev1.NodeReady) {
		node.Status.Conditions = append(node.Status.Conditions, corev1.NodeCondition{
			Type:               corev1.NodeReady,
			Status:             corev1.ConditionTrue,
			Reason:             "TartKubeletReady",
			LastHeartbeatTime:  now,
			LastTransitionTime: now,
		})
	} else {
		setCondition(&node.Status.Conditions, corev1.NodeReady, corev1.ConditionTrue, "TartKubeletReady")
	}

	node.Status.NodeInfo.OperatingSystem = "darwin"
	node.Status.NodeInfo.Architecture = "arm64"
	node.Status.NodeInfo.KubeletVersion = "tart-kubelet-v0"
	node.Status.NodeInfo.ContainerRuntimeVersion = "tart"
}

func hasTaint(taints []corev1.Taint, key string) bool {
	for _, t := range taints {
		if t.Key == key {
			return true
		}
	}
	return false
}

func hasCondition(conds []corev1.NodeCondition, t corev1.NodeConditionType) bool {
	for _, c := range conds {
		if c.Type == t {
			return true
		}
	}
	return false
}

func setCondition(conds *[]corev1.NodeCondition, t corev1.NodeConditionType, s corev1.ConditionStatus, reason string) {
	now := metav1.Now()
	for i, c := range *conds {
		if c.Type == t {
			if c.Status != s {
				(*conds)[i].LastTransitionTime = now
			}
			(*conds)[i].Status = s
			(*conds)[i].Reason = reason
			(*conds)[i].LastHeartbeatTime = now
			return
		}
	}
	*conds = append(*conds, corev1.NodeCondition{
		Type:               t,
		Status:             s,
		Reason:             reason,
		LastHeartbeatTime:  now,
		LastTransitionTime: now,
	})
}
