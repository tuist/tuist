// Package vkprovider implements virtual-kubelet's PodLifecycleHandler
// + NodeProvider interfaces, mapping each scheduled Pod to a Tart VM
// on a Mac mini in the fleet.
//
// Mapping: one Pod = one Tart VM = one slot on a Mac mini.
// Multi-Pod-per-Mac-mini is supported (each Pod gets its own VM
// cloned from the Pod's container image), capped by the host's
// memory budget.
package vkprovider

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/tuist/tuist/infra/vk-applesilicon/internal/tart"
)

// Provider is the VK Pod + Node implementation.
type Provider struct {
	// NodeName is the virtual Node's name in the cluster.
	NodeName string

	// Hosts returns the current set of bootstrapped Mac minis the
	// provider can schedule onto. Called on every Pod placement.
	// Returning an empty set causes the Pod to stay Pending.
	Hosts func(context.Context) ([]Host, error)

	// AdvertisedCapacity is the {CPU, MemoryMB} the virtual Node
	// reports to the scheduler regardless of how many Mac minis are
	// currently Ready. Pods schedule onto our Node based on this;
	// CreatePod still fails if no host is actually reachable, but
	// the Pod gets a real reason instead of "Insufficient cpu" from
	// the scheduler.
	AdvertisedCapacity Host

	// SSHKey is the per-fleet Ed25519 private key used to dial Mac
	// minis. PEM-encoded.
	SSHKey []byte

	mu       sync.RWMutex
	pods     map[string]*placedPod // key: <namespace>/<name>
	upTime   time.Time
	stopCh   chan struct{}
	stopOnce sync.Once
}

// Host is a Mac mini the provider can place Pods onto.
type Host struct {
	IP      string // public IPv4
	SSHUser string // typically "m1"

	// CPU + MemoryMB describe the host's total capacity, used for the
	// virtual Node's `Capacity` field.
	CPU      int
	MemoryMB int
}

type placedPod struct {
	pod      *corev1.Pod
	hostIP   string // which Mac mini it's running on
	vmName   string // Tart VM name (== <namespace>-<name>)
	startTS  metav1.Time
	finalTS  *metav1.Time // set when DeletePod has run
	finished bool
}

// New constructs a provider. Caller must call Start before any
// PodLifecycleHandler / NodeProvider methods are invoked.
func New(nodeName string, sshKey []byte, hosts func(ctx context.Context) ([]Host, error)) *Provider {
	return &Provider{
		NodeName: nodeName,
		Hosts:    hosts,
		SSHKey:   sshKey,
		pods:     map[string]*placedPod{},
		upTime:   time.Now(),
		stopCh:   make(chan struct{}),
	}
}

func (p *Provider) Stop() {
	p.stopOnce.Do(func() { close(p.stopCh) })
}

// === PodLifecycleHandler ====================================================

// CreatePod picks an idle Mac mini, dials it, and starts a Tart VM
// from the Pod's first container image. Multi-container Pods are
// rejected (one Pod = one VM).
func (p *Provider) CreatePod(ctx context.Context, pod *corev1.Pod) error {
	if len(pod.Spec.Containers) != 1 {
		return fmt.Errorf("vk-applesilicon: pod %s has %d containers; expected exactly 1",
			podKey(pod), len(pod.Spec.Containers))
	}

	hosts, err := p.Hosts(ctx)
	if err != nil {
		return fmt.Errorf("list hosts: %w", err)
	}
	if len(hosts) == 0 {
		return errors.New("vk-applesilicon: no Mac minis available; Pod will requeue")
	}

	// MVP: pick the first host. Future: track per-host slot
	// utilization, prefer hosts with the image already cached, etc.
	host := hosts[0]

	client, err := tart.Dial(ctx, host.IP+":22", host.SSHUser, p.SSHKey)
	if err != nil {
		return fmt.Errorf("ssh dial %s: %w", host.IP, err)
	}
	defer client.Close()

	c := pod.Spec.Containers[0]
	vmName := vmNameForPod(pod)

	if err := client.Pull(ctx, c.Image); err != nil {
		return fmt.Errorf("tart pull %s: %w", c.Image, err)
	}
	// Clone is idempotent only if the VM doesn't already exist; if a
	// previous CreatePod attempt left a half-baked VM behind, delete
	// it first.
	if vm, _ := client.Get(ctx, vmName); vm != nil {
		_ = client.Stop(ctx, vmName, 5*time.Second)
		_ = client.Delete(ctx, vmName)
	}
	if err := client.Clone(ctx, c.Image, vmName); err != nil {
		return fmt.Errorf("tart clone: %w", err)
	}

	// Stage user-data file in a per-VM directory. Tart 2.32 dropped
	// the --user-data flag; instead we share a directory into the
	// guest as `env` so the VM's launchd can mount and read
	// /Volumes/My Shared Files/env/tuist.env at boot.
	envDir := "/var/lib/tart-userdata/" + vmName
	if err := client.MkdirP(ctx, envDir, "/var/log/tart-vms", true); err != nil {
		return fmt.Errorf("mkdir userdata: %w", err)
	}
	if err := client.WriteFile(ctx, envDir+"/tuist.env", renderEnvFile(c.Env), true); err != nil {
		return fmt.Errorf("write userdata: %w", err)
	}

	if err := client.Run(ctx, vmName, tart.RunOptions{
		SharedDirs: []string{"env:" + envDir + ":ro"},
	}); err != nil {
		return fmt.Errorf("tart run: %w", err)
	}

	p.mu.Lock()
	p.pods[podKey(pod)] = &placedPod{
		pod:     pod,
		hostIP:  host.IP,
		vmName:  vmName,
		startTS: metav1.Now(),
	}
	p.mu.Unlock()
	return nil
}

func (p *Provider) UpdatePod(ctx context.Context, pod *corev1.Pod) error {
	// VK calls UpdatePod when Pod metadata/spec changes. For our use
	// case (immutable Pods running an image), there's nothing to do.
	return nil
}

func (p *Provider) DeletePod(ctx context.Context, pod *corev1.Pod) error {
	p.mu.Lock()
	pp, ok := p.pods[podKey(pod)]
	p.mu.Unlock()
	if !ok {
		return nil
	}

	client, err := tart.Dial(ctx, pp.hostIP+":22", "m1", p.SSHKey)
	if err != nil {
		return fmt.Errorf("ssh dial %s: %w", pp.hostIP, err)
	}
	defer client.Close()

	_ = client.Stop(ctx, pp.vmName, 30*time.Second)
	if err := client.Delete(ctx, pp.vmName); err != nil {
		return fmt.Errorf("tart delete: %w", err)
	}

	now := metav1.Now()
	p.mu.Lock()
	pp.finalTS = &now
	pp.finished = true
	delete(p.pods, podKey(pod))
	p.mu.Unlock()
	return nil
}

func (p *Provider) GetPod(ctx context.Context, namespace, name string) (*corev1.Pod, error) {
	key := namespace + "/" + name
	p.mu.RLock()
	defer p.mu.RUnlock()
	pp, ok := p.pods[key]
	if !ok {
		return nil, nil
	}
	return pp.pod.DeepCopy(), nil
}

func (p *Provider) GetPodStatus(ctx context.Context, namespace, name string) (*corev1.PodStatus, error) {
	pod, err := p.GetPod(ctx, namespace, name)
	if err != nil || pod == nil {
		return nil, err
	}

	p.mu.RLock()
	pp, ok := p.pods[namespace+"/"+name]
	p.mu.RUnlock()
	if !ok {
		return nil, nil
	}

	client, err := tart.Dial(ctx, pp.hostIP+":22", "m1", p.SSHKey)
	if err != nil {
		// Treat unreachable host as unknown — kubelet will retry.
		return &corev1.PodStatus{
			Phase: corev1.PodUnknown,
		}, nil
	}
	defer client.Close()

	vm, err := client.Get(ctx, pp.vmName)
	if err != nil {
		return &corev1.PodStatus{Phase: corev1.PodUnknown}, nil
	}
	return tartStateToPodStatus(vm, pp), nil
}

func (p *Provider) GetPods(ctx context.Context) ([]*corev1.Pod, error) {
	p.mu.RLock()
	defer p.mu.RUnlock()
	out := make([]*corev1.Pod, 0, len(p.pods))
	for _, pp := range p.pods {
		out = append(out, pp.pod.DeepCopy())
	}
	return out, nil
}

// === NodeProvider ===========================================================

// ConfigureNode populates the virtual Node object the provider
// registers. Called once at startup by the VK runtime.
func (p *Provider) ConfigureNode(ctx context.Context, node *corev1.Node) {
	if node.Labels == nil {
		node.Labels = map[string]string{}
	}
	node.Labels["kubernetes.io/os"] = "darwin"
	node.Labels["kubernetes.io/arch"] = "arm64"
	node.Labels["tuist.dev/runtime"] = "tart"
	node.Labels["type.node.kubernetes.io"] = "virtual-kubelet"

	node.Spec.Taints = append(node.Spec.Taints, corev1.Taint{
		Key:    "tuist.dev/macos",
		Value:  "true",
		Effect: corev1.TaintEffectNoSchedule,
	})

	// Capacity is the configured pool size, NOT the count of currently-
	// Ready Mac minis. Reporting 0 when no host has been bootstrapped
	// yet causes the scheduler to reject Pods with "Insufficient
	// cpu/memory" before they ever reach our virtual Node — which
	// removes our ability to surface the real reason (no host).
	cpu := p.AdvertisedCapacity.CPU
	mem := p.AdvertisedCapacity.MemoryMB
	if cpu == 0 {
		cpu = 8
	}
	if mem == 0 {
		mem = 16384
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
		list[corev1.ResourcePods] = resource.MustParse("100")
	}

	node.Status.Conditions = []corev1.NodeCondition{
		{Type: corev1.NodeReady, Status: corev1.ConditionTrue, Reason: "TartFleetReady",
			LastHeartbeatTime: metav1.Now(), LastTransitionTime: metav1.Now()},
	}
	node.Status.NodeInfo.OperatingSystem = "darwin"
	node.Status.NodeInfo.Architecture = "arm64"
	node.Status.NodeInfo.KubeletVersion = "vk-applesilicon-v0"
	node.Status.NodeInfo.ContainerRuntimeVersion = "tart"
}

// === helpers ================================================================

func podKey(pod *corev1.Pod) string {
	return pod.Namespace + "/" + pod.Name
}

// vmNameForPod produces a Tart-safe VM name. Tart accepts alphanum +
// dashes; pod names are already DNS-1123 (lowercase alphanum + dashes)
// so we just join namespace + name.
func vmNameForPod(pod *corev1.Pod) string {
	name := pod.Namespace + "-" + pod.Name
	if len(name) > 63 {
		name = name[:63]
	}
	return strings.TrimRight(name, "-")
}

// renderEnvFile builds /etc/tuist.env content from Pod env. We don't
// support valueFrom yet; those resolve to empty strings.
func renderEnvFile(env []corev1.EnvVar) string {
	var b strings.Builder
	for _, e := range env {
		val := e.Value
		// Quote to survive shell-source semantics.
		val = strings.ReplaceAll(val, `\`, `\\`)
		val = strings.ReplaceAll(val, `"`, `\"`)
		fmt.Fprintf(&b, "export %s=\"%s\"\n", e.Name, val)
	}
	return b.String()
}

func totalCapacity(hosts []Host) (cpu int, memMB int) {
	for _, h := range hosts {
		cpu += h.CPU
		memMB += h.MemoryMB
	}
	return cpu, memMB
}

func tartStateToPodStatus(vm *tart.VM, pp *placedPod) *corev1.PodStatus {
	status := &corev1.PodStatus{
		StartTime: &pp.startTS,
		HostIP:    pp.hostIP,
	}
	switch vm.State {
	case "running":
		status.Phase = corev1.PodRunning
		ready := corev1.ConditionTrue
		status.Conditions = []corev1.PodCondition{{Type: corev1.PodReady, Status: ready}}
	case "stopped":
		// Tart "stopped" means the VM has shut down. Treat as Succeeded
		// for one-shot Pods (xcresult-processor restarts via Deployment;
		// runners exit cleanly when the job is done).
		status.Phase = corev1.PodSucceeded
	case "failed":
		status.Phase = corev1.PodFailed
	default:
		status.Phase = corev1.PodPending
	}
	return status
}
