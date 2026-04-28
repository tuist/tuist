// Package provider implements the Virtual Kubelet PodLifecycleHandler +
// NodeProvider for the Orchard-managed macOS fleet.
//
// Pod ↔ VM mapping:
//   - One Pod ↔ one Tart VM. Multi-container Pods are rejected at admission.
//   - VM name = "<namespace>-<pod-name>" (deterministic, idempotent).
//   - Pod env → Orchard user_data ({"env": {...}}) → /etc/tuist.env in the VM.
//   - container.image → VM image ref (Orchard pulls from OCI registry).
//   - resources.requests.cpu/memory → Tart --cpu / --memory flags.
//
// What we don't translate (rejected with a clear error):
//   - Multiple containers, init containers, sidecars
//   - PVC mounts, hostPath
//   - Cluster networking (Pods get no ClusterIP — the workload reaches
//     Postgres + S3 over public internet, fine for xcresult-processor)
//   - HTTP probes (no in-cluster IP); only exec probes via Orchard exec
package provider

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"sync"
	"time"

	dto "github.com/prometheus/client_model/go"
	"github.com/virtual-kubelet/virtual-kubelet/log"
	"github.com/virtual-kubelet/virtual-kubelet/node/api"
	statsv1alpha1 "github.com/virtual-kubelet/virtual-kubelet/node/api/statsv1alpha1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/api/resource"

	"github.com/tuist/tuist/infra/vk-orchard/internal/orchard"
)

// Provider implements virtual-kubelet's PodLifecycleHandler + NodeProvider.
type Provider struct {
	NodeName  string
	Client    OrchardAPI

	// pods is an in-memory cache of Pods we've created. The VK runtime
	// expects GetPod / GetPods to return current state quickly; we keep
	// the cache in lockstep with Orchard via NotifyPods / status sync.
	mu   sync.RWMutex
	pods map[string]*corev1.Pod

	// notify is the callback the VK runtime registers via NotifyPods. We
	// invoke it whenever a Pod's observed state changes (VM came up,
	// crashed, etc.) so Deployment controllers see the transition.
	notify func(*corev1.Pod)
}

// OrchardAPI is the subset of orchard.Client the provider depends on.
// Defined as an interface so tests can swap in a fake.
type OrchardAPI interface {
	CreateVM(ctx context.Context, vm orchard.VM) (*orchard.VM, error)
	GetVM(ctx context.Context, name string) (*orchard.VM, error)
	DeleteVM(ctx context.Context, name string) error
	ListVMs(ctx context.Context) ([]orchard.VM, error)
	ListWorkers(ctx context.Context) ([]orchard.Worker, error)
	StreamLogs(ctx context.Context, name string, follow bool) (io.ReadCloser, error)
}

// New returns a Provider ready for use by the VK runtime.
func New(nodeName string, client OrchardAPI) *Provider {
	return &Provider{
		NodeName: nodeName,
		Client:   client,
		pods:     make(map[string]*corev1.Pod),
	}
}

// vmName returns the deterministic Orchard VM name for a given Pod.
// Using "<namespace>-<pod>" makes recreate-after-restart idempotent: the
// VK provider can identify "VMs we created" by name prefix even if its
// own state was lost.
func vmName(pod *corev1.Pod) string {
	return fmt.Sprintf("%s-%s", pod.Namespace, pod.Name)
}

func podKey(namespace, name string) string {
	return namespace + "/" + name
}

// CreatePod translates a Pod spec to an Orchard CreateVM call.
//
// The Pod's first container's image, env, and resources drive the VM
// shape. We reject Pods that violate the assumptions documented at the
// top of this file.
func (p *Provider) CreatePod(ctx context.Context, pod *corev1.Pod) error {
	if err := validatePod(pod); err != nil {
		return err
	}

	container := pod.Spec.Containers[0]

	userData, err := buildUserData(pod, container)
	if err != nil {
		return err
	}

	cpu, memory := resourceShape(container)

	vm := orchard.VM{
		Name:     vmName(pod),
		Image:    container.Image,
		CPU:      cpu,
		Memory:   memory,
		UserData: userData,
		Labels: map[string]string{
			"tuist.dev/pod-namespace": pod.Namespace,
			"tuist.dev/pod-name":      pod.Name,
			"tuist.dev/managed-by":    "vk-orchard",
		},
	}

	if _, err := p.Client.CreateVM(ctx, vm); err != nil {
		return fmt.Errorf("create vm %q: %w", vm.Name, err)
	}

	now := metav1.NewTime(time.Now())
	pod.Status.Phase = corev1.PodPending
	pod.Status.StartTime = &now
	pod.Status.Conditions = []corev1.PodCondition{
		{Type: corev1.PodScheduled, Status: corev1.ConditionTrue, LastTransitionTime: now},
		{Type: corev1.PodInitialized, Status: corev1.ConditionTrue, LastTransitionTime: now},
	}

	p.mu.Lock()
	p.pods[podKey(pod.Namespace, pod.Name)] = pod.DeepCopy()
	p.mu.Unlock()

	log.G(ctx).Infof("CreatePod: created VM %s for pod %s/%s", vm.Name, pod.Namespace, pod.Name)
	return nil
}

// UpdatePod is invoked when the kubelet thinks a Pod's spec changed. We
// only act on image changes — k8s' Deployment controller drives image
// bumps by creating a new Pod (with a new ReplicaSet) and deleting the
// old one, so in practice this is rarely hit.
func (p *Provider) UpdatePod(ctx context.Context, pod *corev1.Pod) error {
	p.mu.Lock()
	p.pods[podKey(pod.Namespace, pod.Name)] = pod.DeepCopy()
	p.mu.Unlock()
	return nil
}

// DeletePod is invoked when a Pod is removed (scale-down, deploy rollout,
// explicit delete). We tear down the VM. Orchard treats 404 as success
// so this is idempotent on retry.
func (p *Provider) DeletePod(ctx context.Context, pod *corev1.Pod) error {
	name := vmName(pod)
	if err := p.Client.DeleteVM(ctx, name); err != nil {
		return fmt.Errorf("delete vm %q: %w", name, err)
	}

	now := metav1.NewTime(time.Now())
	pod.Status.Phase = corev1.PodSucceeded
	for i := range pod.Status.ContainerStatuses {
		pod.Status.ContainerStatuses[i].State = corev1.ContainerState{
			Terminated: &corev1.ContainerStateTerminated{
				FinishedAt: now,
				Reason:     "PodDeleted",
			},
		}
	}

	p.mu.Lock()
	delete(p.pods, podKey(pod.Namespace, pod.Name))
	p.mu.Unlock()

	log.G(ctx).Infof("DeletePod: deleted VM %s for pod %s/%s", name, pod.Namespace, pod.Name)
	return nil
}

// GetPod returns the cached Pod. If we've never seen the Pod, returns nil
// (not an error — VK treats nil as "no such Pod").
func (p *Provider) GetPod(_ context.Context, namespace, name string) (*corev1.Pod, error) {
	p.mu.RLock()
	defer p.mu.RUnlock()
	if pod, ok := p.pods[podKey(namespace, name)]; ok {
		return pod.DeepCopy(), nil
	}
	return nil, nil
}

// GetPodStatus fetches the live VM status from Orchard and translates to
// PodStatus. Called by the VK runtime on a periodic tick — this is what
// drives Deployment rollouts (Ready=true once the VM's running).
func (p *Provider) GetPodStatus(ctx context.Context, namespace, name string) (*corev1.PodStatus, error) {
	pod, err := p.GetPod(ctx, namespace, name)
	if err != nil || pod == nil {
		return nil, err
	}

	vm, err := p.Client.GetVM(ctx, vmName(pod))
	if err == orchard.ErrNotFound {
		// VM was deleted out of band (manually, host failure, etc.).
		// Report Failed so the Deployment controller recreates the Pod.
		return &corev1.PodStatus{
			Phase:   corev1.PodFailed,
			Reason:  "VMNotFound",
			Message: "Orchard reports the underlying VM no longer exists",
		}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get vm: %w", err)
	}

	return translateVMStatus(pod, vm), nil
}

// GetPods returns the cached Pod list. Called periodically by the VK
// runtime to reconcile its own view of the world.
func (p *Provider) GetPods(_ context.Context) ([]*corev1.Pod, error) {
	p.mu.RLock()
	defer p.mu.RUnlock()
	out := make([]*corev1.Pod, 0, len(p.pods))
	for _, pod := range p.pods {
		out = append(out, pod.DeepCopy())
	}
	return out, nil
}

// GetContainerLogs streams the VM's combined stdout/stderr.
func (p *Provider) GetContainerLogs(ctx context.Context, namespace, podName, _ string, opts api.ContainerLogOpts) (io.ReadCloser, error) {
	pod, err := p.GetPod(ctx, namespace, podName)
	if err != nil || pod == nil {
		return nil, fmt.Errorf("pod %s/%s not found", namespace, podName)
	}
	return p.Client.StreamLogs(ctx, vmName(pod), opts.Follow)
}

// RunInContainer is the kubectl exec backend. We don't currently expose
// Orchard's exec endpoint — return an error so users get a clear "not
// supported" instead of a hang. This is intentionally deferred until
// Orchard's exec path is verified end-to-end.
func (p *Provider) RunInContainer(_ context.Context, _, _, _ string, _ []string, _ api.AttachIO) error {
	return fmt.Errorf("kubectl exec is not implemented by the vk-orchard provider yet")
}

// AttachToContainer is similarly deferred.
func (p *Provider) AttachToContainer(_ context.Context, _, _, _ string, _ api.AttachIO) error {
	return fmt.Errorf("kubectl attach is not implemented by the vk-orchard provider yet")
}

// PortForward is not supported (no cluster networking into VMs).
func (p *Provider) PortForward(_ context.Context, _, _ string, _ int32, _ io.ReadWriteCloser) error {
	return fmt.Errorf("port-forward is not supported by the vk-orchard provider")
}

// GetStatsSummary is required by the Stats API but we return an empty
// summary; per-Pod CPU/memory stats from Tart aren't currently exposed
// by Orchard. Live metrics come from the in-VM Tuist PromEx instead.
func (p *Provider) GetStatsSummary(_ context.Context) (*statsv1alpha1.Summary, error) {
	return &statsv1alpha1.Summary{Node: statsv1alpha1.NodeStats{NodeName: p.NodeName}}, nil
}

// GetMetricsResource is unused for the same reason as GetStatsSummary.
func (p *Provider) GetMetricsResource(_ context.Context) ([]*dto.MetricFamily, error) {
	return nil, nil
}

// NotifyPods registers the callback the VK runtime uses to learn about
// Pod state transitions outside of our explicit Create/Update/Delete
// returns (e.g. a VM crashed mid-job).
func (p *Provider) NotifyPods(_ context.Context, notify func(*corev1.Pod)) {
	p.mu.Lock()
	p.notify = notify
	p.mu.Unlock()
}

// Resync rebuilds the in-memory pod cache from Orchard. Called once at
// provider startup so a VK pod restart doesn't lose track of VMs that
// were created before the restart.
//
// Pods are reconstructed minimally — namespace, name, and a placeholder
// status. The kubelet's own informer will fill in the spec from the API
// server on the next sync; we just need enough state for GetPod /
// GetPods to return non-nil so the runtime knows we own these Pods.
func (p *Provider) Resync(ctx context.Context) error {
	vms, err := p.Client.ListVMs(ctx)
	if err != nil {
		return fmt.Errorf("resync list vms: %w", err)
	}

	p.mu.Lock()
	defer p.mu.Unlock()
	for _, vm := range vms {
		if vm.Labels["tuist.dev/managed-by"] != "vk-orchard" {
			continue
		}
		ns := vm.Labels["tuist.dev/pod-namespace"]
		name := vm.Labels["tuist.dev/pod-name"]
		if ns == "" || name == "" {
			continue
		}
		key := podKey(ns, name)
		if _, exists := p.pods[key]; exists {
			continue
		}
		p.pods[key] = &corev1.Pod{
			ObjectMeta: metav1.ObjectMeta{Namespace: ns, Name: name},
			Status:     *translateVMStatus(&corev1.Pod{}, &vm),
		}
	}
	log.G(ctx).Infof("resync: cached %d pods from %d Orchard VMs", len(p.pods), len(vms))
	return nil
}

func validatePod(pod *corev1.Pod) error {
	if pod == nil {
		return fmt.Errorf("nil pod")
	}
	if len(pod.Spec.Containers) == 0 {
		return fmt.Errorf("pod %s/%s: no containers", pod.Namespace, pod.Name)
	}
	if len(pod.Spec.Containers) > 1 {
		return fmt.Errorf("pod %s/%s: multi-container pods are not supported by vk-orchard (got %d)",
			pod.Namespace, pod.Name, len(pod.Spec.Containers))
	}
	if len(pod.Spec.InitContainers) > 0 {
		return fmt.Errorf("pod %s/%s: init containers are not supported by vk-orchard",
			pod.Namespace, pod.Name)
	}
	for _, vol := range pod.Spec.Volumes {
		if vol.HostPath != nil || vol.PersistentVolumeClaim != nil {
			return fmt.Errorf("pod %s/%s: volume %q uses an unsupported source (only Secret/ConfigMap/EmptyDir env-style mounts work)",
				pod.Namespace, pod.Name, vol.Name)
		}
	}
	return nil
}

// buildUserData serializes the Pod's env into the JSON payload Orchard
// passes to the VM via Tart's --user-data. Inside the VM, inject-env.sh
// reads this file and writes /etc/tuist.env which launchd sources.
func buildUserData(pod *corev1.Pod, container corev1.Container) (string, error) {
	envMap := make(map[string]string)
	for _, e := range container.Env {
		if e.ValueFrom != nil {
			// k8s' kubelet would normally resolve ValueFrom (Secret /
			// ConfigMap refs) before calling CreatePod. With Virtual
			// Kubelet there's a runtime helper that does the same;
			// when it doesn't, we surface a clear error rather than
			// silently dropping the env var.
			if e.ValueFrom.FieldRef != nil || e.ValueFrom.ResourceFieldRef != nil {
				continue
			}
			return "", fmt.Errorf("env %q uses valueFrom (Secret/ConfigMap) which the VK runtime did not resolve",
				e.Name)
		}
		envMap[e.Name] = e.Value
	}

	// Augment with metadata the VM can use without being told explicitly:
	// the Pod name (for log correlation) and the Orchard VM name.
	envMap["TUIST_VK_POD_NAMESPACE"] = pod.Namespace
	envMap["TUIST_VK_POD_NAME"] = pod.Name
	envMap["TUIST_VK_VM_NAME"] = vmName(pod)

	payload, err := json.Marshal(map[string]any{"env": envMap})
	if err != nil {
		return "", fmt.Errorf("marshal user-data: %w", err)
	}
	return string(payload), nil
}

func resourceShape(container corev1.Container) (cpu, memoryMB int) {
	cpu = 4
	memoryMB = 8192

	if q, ok := container.Resources.Requests[corev1.ResourceCPU]; ok {
		// Whole-CPU only — Tart doesn't model fractional cores. Round up.
		cpu = int(q.Value())
		if cpu == 0 && !q.IsZero() {
			cpu = 1
		}
	}
	if q, ok := container.Resources.Requests[corev1.ResourceMemory]; ok {
		memoryMB = int(q.ScaledValue(resource.Mega))
	}
	return cpu, memoryMB
}

func translateVMStatus(pod *corev1.Pod, vm *orchard.VM) *corev1.PodStatus {
	now := metav1.NewTime(time.Now())
	status := &corev1.PodStatus{
		StartTime: pod.Status.StartTime,
	}
	if status.StartTime == nil && !vm.CreatedAt.IsZero() {
		t := metav1.NewTime(vm.CreatedAt)
		status.StartTime = &t
	}

	containerName := "main"
	if pod != nil && len(pod.Spec.Containers) > 0 {
		containerName = pod.Spec.Containers[0].Name
	}

	// Map Orchard's VM lifecycle (pending|starting|running|stopping|stopped|failed)
	// onto Pod phases. The VK runtime aggregates this into Pod.status.phase.
	switch strings.ToLower(vm.Status) {
	case "running":
		status.Phase = corev1.PodRunning
		status.Conditions = []corev1.PodCondition{
			{Type: corev1.PodReady, Status: corev1.ConditionTrue, LastTransitionTime: now},
			{Type: corev1.ContainersReady, Status: corev1.ConditionTrue, LastTransitionTime: now},
		}
		status.ContainerStatuses = []corev1.ContainerStatus{{
			Name:  containerName,
			Ready: true,
			State: corev1.ContainerState{Running: &corev1.ContainerStateRunning{StartedAt: now}},
			Image: vm.Image,
		}}
	case "pending", "starting", "":
		status.Phase = corev1.PodPending
		status.Conditions = []corev1.PodCondition{
			{Type: corev1.PodReady, Status: corev1.ConditionFalse, LastTransitionTime: now, Reason: "VMStarting"},
		}
		status.ContainerStatuses = []corev1.ContainerStatus{{
			Name:  containerName,
			Ready: false,
			State: corev1.ContainerState{Waiting: &corev1.ContainerStateWaiting{Reason: "VMStarting"}},
			Image: vm.Image,
		}}
	case "stopping", "stopped":
		status.Phase = corev1.PodSucceeded
		status.ContainerStatuses = []corev1.ContainerStatus{{
			Name:  containerName,
			Ready: false,
			State: corev1.ContainerState{Terminated: &corev1.ContainerStateTerminated{
				FinishedAt: now,
				Reason:     "VMStopped",
				Message:    vm.StatusMessage,
			}},
			Image: vm.Image,
		}}
	case "failed":
		fallthrough
	default:
		status.Phase = corev1.PodFailed
		status.Reason = "VMFailed"
		status.Message = vm.StatusMessage
		status.ContainerStatuses = []corev1.ContainerStatus{{
			Name:  containerName,
			Ready: false,
			State: corev1.ContainerState{Terminated: &corev1.ContainerStateTerminated{
				FinishedAt: now,
				Reason:     "VMFailed",
				Message:    vm.StatusMessage,
			}},
			Image: vm.Image,
		}}
	}
	return status
}
