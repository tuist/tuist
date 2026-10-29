package macosandbox

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
)

const (
	RoleLabel            = "tuist.dev/macos-sandbox-role"
	IDLabel              = "tuist.dev/sandbox-id"
	NodeUIDAnnotation    = "tuist.dev/sandbox-node-uid"
	GrantAnnotation      = "tuist.dev/macos-sandbox-grant"
	ReservationFinalizer = "tuist.dev/macos-sandbox-fence"
)

type Grant struct {
	CPUMilli    int64     `json:"cpu_milli"`
	MemoryBytes int64     `json:"memory_bytes"`
	Slots       int       `json:"slots"`
	NodeUID     string    `json:"node_uid"`
	ControlUID  string    `json:"control_uid"`
	ObservedAt  time.Time `json:"observed_at"`
	Allow       bool      `json:"allow"`
}
type KubeCapacity struct {
	Kube                                 kubernetes.Interface
	Node, NodeUID, Namespace, ControlUID string
	MaxSlots                             int
}

func (k *KubeCapacity) Allow(ctx context.Context, r *Record) error {
	node, err := k.Kube.CoreV1().Nodes().Get(ctx, k.Node, metav1.GetOptions{})
	if err != nil {
		return err
	}
	if string(node.UID) != k.NodeUID || r.NodeUID != k.NodeUID || node.Spec.Unschedulable {
		return ErrCapacity
	}
	var grant Grant
	if json.Unmarshal([]byte(node.Annotations[GrantAnnotation]), &grant) != nil {
		return ErrCapacity
	}
	age := time.Since(grant.ObservedAt)
	if !grant.Allow || grant.CPUMilli < int64(r.VCPUs)*1000 || grant.MemoryBytes < int64(r.MemoryMB)*1024*1024 || grant.Slots < 1 || grant.NodeUID != k.NodeUID || grant.ControlUID != k.ControlUID || age < -time.Second || age >= 15*time.Second {
		return ErrCapacity
	}
	ready := false
	for _, taint := range node.Spec.Taints {
		if taint.Key == "tuist.dev/power-budget" || taint.Key == "tuist.dev/reserved-for" {
			return ErrCapacity
		}
	}
	for _, condition := range node.Status.Conditions {
		if condition.Type == corev1.NodeReady && condition.Status == corev1.ConditionTrue {
			ready = true
		}
		if condition.Type == corev1.NodeReady && condition.Status != corev1.ConditionTrue {
			return ErrCapacity
		}
		if (condition.Type == corev1.NodeMemoryPressure || condition.Type == corev1.NodeDiskPressure || condition.Type == corev1.NodePIDPressure) && condition.Status != corev1.ConditionFalse {
			return ErrCapacity
		}
	}
	if !ready {
		return ErrCapacity
	}
	return nil
}
func (k *KubeCapacity) Reserve(ctx context.Context, r *Record) error {
	if err := k.Allow(ctx, r); err != nil {
		return err
	}
	if err := k.Hold(ctx, r); err != nil {
		return err
	}
	for {
		if err := k.Fits(ctx); err == nil {
			return nil
		} else if !errors.Is(err, ErrCapacity) {
			return err
		}
		if err := k.Allow(ctx, r); err != nil {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Second):
		}
	}
}

// Hold recovers an existing durable charge even while CI has revoked admission.
func (k *KubeCapacity) Hold(ctx context.Context, r *Record) error {
	no := false
	name := "macos-sbx-" + r.SandboxID
	resources := corev1.ResourceList{corev1.ResourceCPU: resource.MustParse(fmt.Sprint(r.VCPUs)), corev1.ResourceMemory: resource.MustParse(fmt.Sprintf("%dMi", r.MemoryMB))}
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: k.Namespace, Labels: map[string]string{RoleLabel: "execution", IDLabel: r.SandboxID}, Annotations: map[string]string{NodeUIDAnnotation: k.NodeUID}, Finalizers: []string{ReservationFinalizer}}, Spec: corev1.PodSpec{NodeName: k.Node, RestartPolicy: corev1.RestartPolicyNever, AutomountServiceAccountToken: &no, Containers: []corev1.Container{{Name: "sandbox", Image: "tuist-macos-sandbox-reservation", Resources: corev1.ResourceRequirements{Requests: resources, Limits: resources}}}}}
	existing, err := k.Kube.CoreV1().Pods(k.Namespace).Create(ctx, pod, metav1.CreateOptions{})
	if apierrors.IsAlreadyExists(err) {
		existing, err = k.Kube.CoreV1().Pods(k.Namespace).Get(ctx, name, metav1.GetOptions{})
	}
	if err != nil {
		return err
	}
	if existing.Spec.NodeName != k.Node || existing.Annotations[NodeUIDAnnotation] != k.NodeUID || existing.Labels[IDLabel] != r.SandboxID || existing.Labels[RoleLabel] != "execution" || existing.Status.Phase == corev1.PodSucceeded || existing.Status.Phase == corev1.PodFailed || !existing.DeletionTimestamp.IsZero() {
		return errors.New("execution reservation ownership changed")
	}
	if len(existing.Spec.Containers) != 1 || existing.Spec.Containers[0].Resources.Requests.Cpu().Cmp(resources[corev1.ResourceCPU]) != 0 || existing.Spec.Containers[0].Resources.Requests.Memory().Cmp(resources[corev1.ResourceMemory]) != 0 {
		return errors.New("execution reservation shape changed")
	}
	foundFence := false
	for _, f := range existing.Finalizers {
		if f == ReservationFinalizer {
			foundFence = true
		}
	}
	if !foundFence {
		existing.Finalizers = append(existing.Finalizers, ReservationFinalizer)
		if _, err = k.Kube.CoreV1().Pods(k.Namespace).Update(ctx, existing, metav1.UpdateOptions{}); err != nil {
			return err
		}
	}
	return nil
}

// Fits reads all bound Pods, including Pending and Terminating ones. It is
// called with the host launch gate held by both CI and sandbox launches.
func (k *KubeCapacity) Fits(ctx context.Context) error {
	node, err := k.Kube.CoreV1().Nodes().Get(ctx, k.Node, metav1.GetOptions{})
	if err != nil {
		return err
	}
	if string(node.UID) != k.NodeUID {
		return ErrCapacity
	}
	pods, err := k.Kube.CoreV1().Pods("").List(ctx, metav1.ListOptions{FieldSelector: "spec.nodeName=" + k.Node})
	if err != nil {
		return err
	}
	var cpu, memory int64
	slots := 0
	for _, pod := range pods.Items {
		if pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed || pod.Labels[RoleLabel] == "control" {
			continue
		}
		// Mirrors the Pod shape tart-kubelet can execute; system DaemonSets with
		// init/ephemeral containers never become VMs on these Nodes.
		if len(pod.Spec.Containers) != 1 || len(pod.Spec.InitContainers) != 0 || len(pod.Spec.EphemeralContainers) != 0 {
			continue
		}
		slots++
		c := pod.Spec.Containers[0]
		cpu += max(c.Resources.Requests.Cpu().MilliValue(), c.Resources.Limits.Cpu().MilliValue())
		memory += max(c.Resources.Requests.Memory().Value(), c.Resources.Limits.Memory().Value())
	}
	maxSlots := k.MaxSlots
	if maxSlots == 0 {
		maxSlots = 2
	}
	if slots > maxSlots || cpu > node.Status.Allocatable.Cpu().MilliValue() || memory > node.Status.Allocatable.Memory().Value() {
		return ErrCapacity
	}
	return nil
}
func (k *KubeCapacity) Release(ctx context.Context, r *Record) error {
	name := "macos-sbx-" + r.SandboxID
	pod, err := k.Kube.CoreV1().Pods(k.Namespace).Get(ctx, name, metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if pod.Spec.NodeName != k.Node || pod.Annotations[NodeUIDAnnotation] != r.NodeUID || pod.Labels[IDLabel] != r.SandboxID {
		return errors.New("refusing to release another owner's Pod")
	}
	// ResourceVersion and UID prevent a stale release from deleting a recreated
	// reservation with the same name.
	finalizers := []string{}
	for _, f := range pod.Finalizers {
		if f != ReservationFinalizer {
			finalizers = append(finalizers, f)
		}
	}
	patch, _ := json.Marshal(map[string]any{"metadata": map[string]any{"resourceVersion": pod.ResourceVersion, "uid": pod.UID, "finalizers": finalizers}})
	if _, err = k.Kube.CoreV1().Pods(k.Namespace).Patch(ctx, name, types.MergePatchType, patch, metav1.PatchOptions{}); err != nil {
		return err
	}
	// The caller has already fenced the VM. No ordinary kubelet services this
	// reservation, so a graceful API delete would leave it Terminating forever.
	zero := int64(0)
	err = k.Kube.CoreV1().Pods(k.Namespace).Delete(ctx, name, metav1.DeleteOptions{GracePeriodSeconds: &zero, Preconditions: &metav1.Preconditions{UID: &pod.UID}})
	if apierrors.IsNotFound(err) {
		return nil
	}
	return err
}
