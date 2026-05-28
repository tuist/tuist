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
	"strings"
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
	Client   client.Client
	NodeName string
	// NodeIP is the address advertised as the Node's InternalIP so
	// in-cluster scrapers (alloy-metrics) targeting the Node role
	// (host-level node_exporter at :9100, or any future host-bound
	// endpoint) land on the right host. Same value tart-kubelet
	// rewrites Pod.Status.PodIP to for the per-Pod metrics
	// forwarder; surfacing it on the Node object too lets cluster-
	// wide Node discovery use it without having to peek at a Pod.
	// Empty leaves Node.Status.Addresses untouched.
	NodeIP string
	// NodeLabels are operator-set labels published on the Node at
	// registration time. The chart populates this with at least
	// `tuist.dev/fleet=<name>` so workloads (xcresult-processor,
	// runner Pods) can target a specific fleet via nodeSelector;
	// callers can add arbitrary labels (e.g. instance-type) by
	// passing additional entries.
	//
	// Labels NOT in this map but previously set by us are deleted
	// on the next reconcile, giving operators a clean retire path
	// — flip `--node-labels` and the Node loses the labels next
	// heartbeat.
	NodeLabels map[string]string
	CPU        int
	MemoryMB   int
	MaxPods    int
	Heartbeat  time.Duration
	// DiskPressure, when non-nil, is evaluated each heartbeat to set
	// the Node's DiskPressure condition. A real kubelet always reports
	// this condition; leaving it unset surfaces as Unknown, which hides
	// a full guest disk from the scheduler and from alerting. nil keeps
	// the condition at its False default.
	DiskPressure DiskPressureProbe
}

// DiskPressureProbe reports whether the node is under disk pressure plus
// a human-readable detail for the condition message. A non-nil error
// means the probe itself failed (e.g. a guest agent was unreachable);
// the maintainer then leaves the existing condition untouched rather
// than flapping it to False on a transient failure.
type DiskPressureProbe func(ctx context.Context) (pressured bool, detail string, err error)

// operatorOwnedLabelPrefix is the prefix tart-kubelet treats as
// "I own this label." Labels with this prefix that aren't in the
// current NodeLabels map get pruned. We don't prune all unknown
// labels — kube-system DaemonSets, the cluster admin, and other
// agents may stamp legitimate labels we shouldn't touch.
const operatorOwnedLabelPrefix = "tuist.dev/"

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
	m.applyDiskPressure(ctx, node)
	for i, c := range node.Status.Conditions {
		if c.Type == corev1.NodeReady {
			node.Status.Conditions[i].LastHeartbeatTime = metav1.Now()
		}
	}
	return m.Client.Status().Update(ctx, node)
}

// applyDiskPressure refreshes the DiskPressure condition from the probe.
// configureNode has already seeded the condition at False, so a nil
// probe leaves it False and a probe error leaves the prior value in
// place (logged, not flapped).
func (m *Maintainer) applyDiskPressure(ctx context.Context, node *corev1.Node) {
	if m.DiskPressure == nil {
		return
	}
	pressured, detail, err := m.DiskPressure(ctx)
	if err != nil {
		log.FromContext(ctx).Error(err, "disk pressure probe")
		return
	}
	if pressured {
		setCondition(&node.Status.Conditions, corev1.NodeDiskPressure, corev1.ConditionTrue, "TartKubeletHasDiskPressure", detail)
	} else {
		setCondition(&node.Status.Conditions, corev1.NodeDiskPressure, corev1.ConditionFalse, "TartKubeletHasSufficientDisk", detail)
	}
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
	node.Labels[corev1.LabelHostname] = m.NodeName
	// `tuist.dev/runtime=tart` is intrinsic to a tart-kubelet Node
	// (not operator-tunable), so it's stamped unconditionally and
	// excluded from the prune below.
	node.Labels["tuist.dev/runtime"] = "tart"

	// Apply operator-set labels. Any tuist.dev/* label not in the
	// current NodeLabels map gets dropped — gives the operator a
	// clean retire path: flip --node-labels and the Node sheds
	// the old labels on the next heartbeat. The runtime label is
	// excluded from prune (intrinsic, not operator-tunable).
	for k, v := range m.NodeLabels {
		node.Labels[k] = v
	}
	for k := range node.Labels {
		if !strings.HasPrefix(k, operatorOwnedLabelPrefix) {
			continue
		}
		if k == "tuist.dev/runtime" {
			continue
		}
		if _, kept := m.NodeLabels[k]; !kept {
			delete(node.Labels, k)
		}
	}

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
		setCondition(&node.Status.Conditions, corev1.NodeReady, corev1.ConditionTrue, "TartKubeletReady", "")
	}

	// Seed DiskPressure at False so the node never sits at Unknown (which
	// hides a full guest disk). The heartbeat's probe — see
	// applyDiskPressure — flips it to True when a guest volume fills.
	if !hasCondition(node.Status.Conditions, corev1.NodeDiskPressure) {
		setCondition(&node.Status.Conditions, corev1.NodeDiskPressure, corev1.ConditionFalse, "TartKubeletHasSufficientDisk", "")
	}

	node.Status.NodeInfo.OperatingSystem = "darwin"
	node.Status.NodeInfo.Architecture = "arm64"
	node.Status.NodeInfo.KubeletVersion = "tart-kubelet-v0"
	node.Status.NodeInfo.ContainerRuntimeVersion = "tart"

	if m.NodeIP != "" {
		// Replace, not merge: a kubelet restart with a new NodeIP
		// (Tailscale daemon reassigns the CGNAT slot, operator flips
		// --node-ip-source, etc.) must overwrite the stale entry so
		// kube-state-metrics + Node-role scrapers don't keep dialing
		// the previous address.
		node.Status.Addresses = []corev1.NodeAddress{
			{Type: corev1.NodeInternalIP, Address: m.NodeIP},
			{Type: corev1.NodeHostName, Address: m.NodeName},
		}
	}
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

func setCondition(conds *[]corev1.NodeCondition, t corev1.NodeConditionType, s corev1.ConditionStatus, reason, message string) {
	now := metav1.Now()
	for i, c := range *conds {
		if c.Type == t {
			if c.Status != s {
				(*conds)[i].LastTransitionTime = now
			}
			(*conds)[i].Status = s
			(*conds)[i].Reason = reason
			(*conds)[i].Message = message
			(*conds)[i].LastHeartbeatTime = now
			return
		}
	}
	*conds = append(*conds, corev1.NodeCondition{
		Type:               t,
		Status:             s,
		Reason:             reason,
		Message:            message,
		LastHeartbeatTime:  now,
		LastTransitionTime: now,
	})
}
