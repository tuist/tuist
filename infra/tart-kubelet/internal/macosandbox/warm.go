package macosandbox

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sort"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
)

// Warm sandbox VMs are Pods of a runner pool (see "Warm VMs" in
// macos-sandboxes.md), so the runners-controller budgets, preempts and drains
// them like idle warm CI runners. This host service, not the CI Pod
// reconciler, boots each one as a sandbox-mode VM on the private runtime,
// keeps it in memory only, and hands it to a sandbox create.
const (
	WarmLabel     = "tuist.dev/macos-sandbox-warm"
	WarmFinalizer = "tuist.dev/macos-sandbox-warm"
	// WarmHostLabel is advertised by kubelets that own warm Pods, so an older
	// kubelet is never given one to boot as a CI VM.
	WarmHostLabel = "tuist.dev/macos-sandbox-warm-host"
)

type warmVM struct {
	pod       types.UID
	namespace string
	name      string
	rec       *Record
	ready     bool
	readyAt   time.Time
}

func (s *Service) reconcileWarm(ctx context.Context) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		opCtx, cancel := context.WithTimeout(ctx, time.Minute)
		if err := s.warmTick(opCtx, ctx); err != nil {
			slog.Warn("macOS sandbox warm VMs", "error", err)
		}
		cancel()
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (s *Service) warmTick(ctx, parent context.Context) error {
	pods, err := s.Kube.CoreV1().Pods("").List(ctx, metav1.ListOptions{LabelSelector: WarmLabel + "=true", FieldSelector: "spec.nodeName=" + s.Node})
	if err != nil {
		return err
	}
	s.mu.Lock()
	m, ready := s.manager, s.ready
	s.mu.Unlock()
	seen := map[types.UID]bool{}
	var errs []error
	for i := range pods.Items {
		pod := &pods.Items[i]
		seen[pod.UID] = true
		if !pod.DeletionTimestamp.IsZero() {
			errs = append(errs, s.retireWarm(ctx, m, pod))
			continue
		}
		if pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed {
			continue
		}
		if m == nil || !ready {
			errs = append(errs, s.failWarm(ctx, pod, "SandboxHostNotReady", "the host's macOS sandbox service is not ready"))
			continue
		}
		m.Gate.Lock()
		w, booting := m.warm[pod.UID], m.warmBooting
		m.Gate.Unlock()
		if w != nil {
			continue
		}
		if pod.Status.Phase == corev1.PodRunning {
			// Warm VMs live in memory only: a restart deleted this one.
			errs = append(errs, s.failWarm(ctx, pod, "WarmVMLost", "the host restarted and deleted the warm VM"))
			continue
		}
		if booting {
			continue
		}
		rec, reason := m.warmRecord(pod)
		if reason != "" {
			errs = append(errs, s.failWarm(ctx, pod, "WarmVMUnsupported", reason))
			continue
		}
		w = &warmVM{pod: pod.UID, namespace: pod.Namespace, name: pod.Name, rec: rec}
		if err := s.admitWarm(ctx, m, w); err != nil {
			errs = append(errs, s.failWarm(ctx, pod, "WarmVMNoCapacity", err.Error()))
			continue
		}
		go s.bootWarm(context.WithoutCancel(parent), m, w, pod)
	}
	// A Pod force-deleted without its finalizer still leaves a VM behind.
	if m != nil {
		m.Gate.Lock()
		var gone []*warmVM
		for uid, w := range m.warm {
			if !seen[uid] && w.ready {
				delete(m.warm, uid)
				gone = append(gone, w)
			}
		}
		m.Gate.Unlock()
		for _, w := range gone {
			errs = append(errs, m.Runtime.Delete(ctx, w.rec))
		}
	}
	return errors.Join(errs...)
}

// warmRecord describes the VM a warm Pod asks for. It must match what a
// sandbox create would boot: the manager's template image and a supported
// shape. Anything else cold-creates, so the Pod fails instead of booting.
func (m *Manager) warmRecord(pod *corev1.Pod) (*Record, string) {
	if len(pod.Spec.Containers) != 1 {
		return nil, "a warm Pod has exactly one container"
	}
	c := pod.Spec.Containers[0]
	if c.Image != m.TemplateTag {
		return nil, fmt.Sprintf("image %q is not the host's sandbox template %q", c.Image, m.TemplateTag)
	}
	cpu, memory := c.Resources.Requests.Cpu().MilliValue(), c.Resources.Requests.Memory().Value()
	vcpus, memoryMB := int(cpu/1000), int(memory/(1024*1024))
	if cpu%1000 != 0 || vcpus != 8 || (memoryMB != 8192 && memoryMB != 16384 && memoryMB != 24576) || memory%(1024*1024) != 0 {
		return nil, "unsupported warm VM shape"
	}
	runtime, ok := m.Runtime.(*TartRuntime)
	template := ""
	if ok {
		template = runtime.Template
	}
	return &Record{VM: warmVMPrefix + string(pod.UID), RuntimePath: m.RuntimePath, ToolsPath: m.ToolsPath, NodeUID: m.NodeUID,
		CreateArgs: protocol.CreateArgs{Template: template, TemplateTag: m.TemplateTag, VCPUs: vcpus, MemoryMB: memoryMB}}, ""
}

// admitWarm charges the warm Pod like a CI launch: under the launch gate,
// after repairing sandbox reservations, every bound Pod (this one included)
// must fit. A warm Pod never waits for capacity.
func (s *Service) admitWarm(ctx context.Context, m *Manager, w *warmVM) error {
	m.Gate.Lock()
	defer m.Gate.Unlock()
	if err := s.repairReservations(ctx, m); err != nil {
		return err
	}
	if err := s.capacity.Fits(ctx); err != nil {
		return err
	}
	m.warm[w.pod] = w
	m.warmBooting = true
	return nil
}

func (s *Service) bootWarm(ctx context.Context, m *Manager, w *warmVM, pod *corev1.Pod) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	err := s.addWarmFinalizer(ctx, pod)
	if err == nil {
		err = m.Runtime.Warm(ctx, w.rec)
	}
	m.Gate.Lock()
	m.warmBooting = false
	if err == nil {
		w.ready, w.readyAt = true, time.Now().UTC()
	} else {
		delete(m.warm, w.pod)
	}
	m.Gate.Unlock()
	if err != nil {
		slog.Warn("macOS sandbox warm VM boot", "pod", w.name, "error", err)
		_ = m.Runtime.Delete(ctx, w.rec)
		_ = s.failWarm(ctx, pod, "WarmVMBootFailed", err.Error())
		return
	}
	if err = s.publishWarm(ctx, pod, w.readyAt); err != nil {
		slog.Warn("macOS sandbox warm VM status", "pod", w.name, "error", err)
	}
}

// claimWarm hands a ready warm VM of the requested shape to a sandbox. The
// caller holds the launch gate.
func (m *Manager) claimWarm(a protocol.CreateArgs) *warmVM {
	for uid, w := range m.warm {
		if w.ready && w.rec.Template == a.Template && w.rec.TemplateTag == a.TemplateTag && w.rec.VCPUs == a.VCPUs && w.rec.MemoryMB == a.MemoryMB {
			delete(m.warm, uid)
			return w
		}
	}
	return nil
}

// retireWarm deletes a warm Pod's VM, then lets the Pod go. A VM still
// booting finishes first; a claimed one belongs to its sandbox.
func (s *Service) retireWarm(ctx context.Context, m *Manager, pod *corev1.Pod) error {
	if m != nil {
		m.Gate.Lock()
		w := m.warm[pod.UID]
		if w != nil && !w.ready {
			m.Gate.Unlock()
			return nil
		}
		delete(m.warm, pod.UID)
		m.Gate.Unlock()
		if w != nil {
			if err := m.Runtime.Delete(ctx, w.rec); err != nil {
				return err
			}
		}
	}
	return s.removeWarmFinalizer(ctx, pod)
}

func (s *Service) addWarmFinalizer(ctx context.Context, pod *corev1.Pod) error {
	for _, f := range pod.Finalizers {
		if f == WarmFinalizer {
			return nil
		}
	}
	patch, _ := json.Marshal(map[string]any{"metadata": map[string]any{"uid": pod.UID, "resourceVersion": pod.ResourceVersion, "finalizers": append(append([]string{}, pod.Finalizers...), WarmFinalizer)}})
	_, err := s.Kube.CoreV1().Pods(pod.Namespace).Patch(ctx, pod.Name, types.MergePatchType, patch, metav1.PatchOptions{})
	return err
}

func (s *Service) removeWarmFinalizer(ctx context.Context, pod *corev1.Pod) error {
	finalizers := []string{}
	found := false
	for _, f := range pod.Finalizers {
		if f == WarmFinalizer {
			found = true
			continue
		}
		finalizers = append(finalizers, f)
	}
	if !found {
		return nil
	}
	patch, _ := json.Marshal(map[string]any{"metadata": map[string]any{"uid": pod.UID, "finalizers": finalizers}})
	_, err := s.Kube.CoreV1().Pods(pod.Namespace).Patch(ctx, pod.Name, types.MergePatchType, patch, metav1.PatchOptions{})
	if apierrors.IsNotFound(err) {
		return nil
	}
	return err
}

// publishWarm reports a booted warm VM as the runners-controller reads idle
// warm macOS capacity: Running and Ready, warm since the guest was ready.
func (s *Service) publishWarm(ctx context.Context, pod *corev1.Pod, readyAt time.Time) error {
	current, err := s.Kube.CoreV1().Pods(pod.Namespace).Get(ctx, pod.Name, metav1.GetOptions{})
	if err != nil {
		return err
	}
	if current.UID != pod.UID {
		return errors.New("warm Pod was replaced")
	}
	at := metav1.NewTime(readyAt)
	current.Status.Phase = corev1.PodRunning
	current.Status.StartTime = &at
	current.Status.Conditions = []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue, LastTransitionTime: at}}
	current.Status.ContainerStatuses = []corev1.ContainerStatus{{Name: current.Spec.Containers[0].Name, Image: current.Spec.Containers[0].Image, Ready: true, Started: ptr(true), State: corev1.ContainerState{Running: &corev1.ContainerStateRunning{StartedAt: at}}}}
	_, err = s.Kube.CoreV1().Pods(pod.Namespace).UpdateStatus(ctx, current, metav1.UpdateOptions{})
	return err
}

func (s *Service) failWarm(ctx context.Context, pod *corev1.Pod, reason, message string) error {
	current, err := s.Kube.CoreV1().Pods(pod.Namespace).Get(ctx, pod.Name, metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if current.UID != pod.UID || current.Status.Phase == corev1.PodFailed {
		return nil
	}
	current.Status.Phase = corev1.PodFailed
	current.Status.Reason = reason
	current.Status.Message = message
	_, err = s.Kube.CoreV1().Pods(pod.Namespace).UpdateStatus(ctx, current, metav1.UpdateOptions{})
	return err
}

func ptr[T any](v T) *T { return &v }

// onWarmVM reports whether a sandbox runs on a claimed warm VM.
func (m *Manager) onWarmVM(id string) bool {
	m.Gate.Lock()
	defer m.Gate.Unlock()
	r := m.records[id]
	return r != nil && strings.HasPrefix(r.VM, warmVMPrefix)
}

// warmShapes lists the ready warm VMs for the server's placement.
func (m *Manager) warmShapes() []string {
	m.Gate.Lock()
	defer m.Gate.Unlock()
	shapes := []string{}
	for _, w := range m.warm {
		if w.ready {
			shapes = append(shapes, fmt.Sprintf("%dx%d", w.rec.VCPUs, w.rec.MemoryMB))
		}
	}
	sort.Strings(shapes)
	return shapes
}
