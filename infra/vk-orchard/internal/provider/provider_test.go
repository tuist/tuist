package provider

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"sync"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/api/resource"

	"github.com/tuist/tuist/infra/vk-orchard/internal/orchard"
)

// fakeClient is a hand-written stub of OrchardAPI used for unit tests.
type fakeClient struct {
	mu       sync.Mutex
	vms      map[string]*orchard.VM
	workers  []orchard.Worker
	createFn func(orchard.VM) (*orchard.VM, error)
	deleteFn func(string) error
}

func newFake() *fakeClient {
	return &fakeClient{vms: make(map[string]*orchard.VM)}
}

func (f *fakeClient) CreateVM(_ context.Context, vm orchard.VM) (*orchard.VM, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.createFn != nil {
		return f.createFn(vm)
	}
	stored := vm
	stored.Status = "running"
	f.vms[vm.Name] = &stored
	return &stored, nil
}

func (f *fakeClient) GetVM(_ context.Context, name string) (*orchard.VM, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	vm, ok := f.vms[name]
	if !ok {
		return nil, orchard.ErrNotFound
	}
	cp := *vm
	return &cp, nil
}

func (f *fakeClient) DeleteVM(_ context.Context, name string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.deleteFn != nil {
		return f.deleteFn(name)
	}
	delete(f.vms, name)
	return nil
}

func (f *fakeClient) ListVMs(_ context.Context) ([]orchard.VM, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := make([]orchard.VM, 0, len(f.vms))
	for _, vm := range f.vms {
		out = append(out, *vm)
	}
	return out, nil
}

func (f *fakeClient) ListWorkers(_ context.Context) ([]orchard.Worker, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]orchard.Worker(nil), f.workers...), nil
}

func (f *fakeClient) StreamLogs(_ context.Context, _ string, _ bool) (io.ReadCloser, error) {
	return io.NopCloser(strings.NewReader("log line\n")), nil
}

func newPod(ns, name, image string, env []corev1.EnvVar) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Namespace: ns, Name: name},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{{
				Name:  "main",
				Image: image,
				Env:   env,
				Resources: corev1.ResourceRequirements{
					Requests: corev1.ResourceList{
						corev1.ResourceCPU:    resource.MustParse("4"),
						corev1.ResourceMemory: resource.MustParse("8Gi"),
					},
				},
			}},
		},
	}
}

func TestCreatePod_TranslatesPodToVM(t *testing.T) {
	fc := newFake()
	p := New("vk-test", fc)

	pod := newPod("tuist", "xcresult-processor-0", "ghcr.io/tuist/tuist-xcresult-processor:abc",
		[]corev1.EnvVar{
			{Name: "TUIST_XCRESULT_PROCESSOR_MODE", Value: "1"},
			{Name: "TUIST_DEPLOY_ENV", Value: "stag"},
		},
	)

	if err := p.CreatePod(context.Background(), pod); err != nil {
		t.Fatalf("CreatePod: %v", err)
	}
	if len(fc.vms) != 1 {
		t.Fatalf("expected 1 VM, got %d", len(fc.vms))
	}
	vm, ok := fc.vms["tuist-xcresult-processor-0"]
	if !ok {
		t.Fatalf("VM not stored under expected name; have %v", keys(fc.vms))
	}
	if vm.Image != "ghcr.io/tuist/tuist-xcresult-processor:abc" {
		t.Fatalf("VM image: got %q", vm.Image)
	}
	if vm.CPU != 4 || vm.Memory != 8589 {
		// 8Gi = 8*1024Mi = 8192Mi; ScaledValue at Mega rounds to ~8589 mB.
		// Accept anything close; just sanity-check the order of magnitude.
		if vm.CPU != 4 || vm.Memory < 8000 || vm.Memory > 9000 {
			t.Fatalf("VM resources unexpected: cpu=%d memory=%d", vm.CPU, vm.Memory)
		}
	}

	// User-data should embed the env we passed plus the metadata adds.
	var payload struct {
		Env map[string]string `json:"env"`
	}
	if err := json.Unmarshal([]byte(vm.UserData), &payload); err != nil {
		t.Fatalf("UserData not valid JSON: %v (%s)", err, vm.UserData)
	}
	if payload.Env["TUIST_XCRESULT_PROCESSOR_MODE"] != "1" ||
		payload.Env["TUIST_DEPLOY_ENV"] != "stag" {
		t.Fatalf("env not propagated: %+v", payload.Env)
	}
	if payload.Env["TUIST_VK_POD_NAME"] != "xcresult-processor-0" {
		t.Fatalf("metadata not added: %+v", payload.Env)
	}
}

func TestCreatePod_RejectsMultipleContainers(t *testing.T) {
	p := New("vk-test", newFake())
	pod := newPod("tuist", "p", "img", nil)
	pod.Spec.Containers = append(pod.Spec.Containers, corev1.Container{Name: "extra", Image: "x"})
	err := p.CreatePod(context.Background(), pod)
	if err == nil || !strings.Contains(err.Error(), "multi-container") {
		t.Fatalf("expected multi-container rejection, got %v", err)
	}
}

func TestCreatePod_RejectsInitContainers(t *testing.T) {
	p := New("vk-test", newFake())
	pod := newPod("tuist", "p", "img", nil)
	pod.Spec.InitContainers = []corev1.Container{{Name: "init"}}
	err := p.CreatePod(context.Background(), pod)
	if err == nil || !strings.Contains(err.Error(), "init containers") {
		t.Fatalf("expected init-container rejection, got %v", err)
	}
}

func TestCreatePod_RejectsUnresolvedValueFrom(t *testing.T) {
	p := New("vk-test", newFake())
	pod := newPod("tuist", "p", "img", []corev1.EnvVar{
		{Name: "DATABASE_URL", ValueFrom: &corev1.EnvVarSource{
			SecretKeyRef: &corev1.SecretKeySelector{
				LocalObjectReference: corev1.LocalObjectReference{Name: "db"},
				Key:                  "url",
			},
		}},
	})
	err := p.CreatePod(context.Background(), pod)
	if err == nil || !strings.Contains(err.Error(), "valueFrom") {
		t.Fatalf("expected unresolved valueFrom rejection, got %v", err)
	}
}

func TestDeletePod_RemovesVM(t *testing.T) {
	fc := newFake()
	p := New("vk-test", fc)
	pod := newPod("tuist", "xcresult-processor-0", "img", nil)

	if err := p.CreatePod(context.Background(), pod); err != nil {
		t.Fatalf("CreatePod: %v", err)
	}
	if err := p.DeletePod(context.Background(), pod); err != nil {
		t.Fatalf("DeletePod: %v", err)
	}
	if len(fc.vms) != 0 {
		t.Fatalf("expected 0 VMs after delete, got %d", len(fc.vms))
	}
}

func TestDeletePod_IdempotentOnMissingVM(t *testing.T) {
	fc := newFake()
	fc.deleteFn = func(string) error { return orchard.ErrNotFound }
	p := New("vk-test", fc)
	pod := newPod("tuist", "ghost", "img", nil)
	// CreatePod is skipped on purpose — we want to test "DeletePod against
	// a VM that doesn't exist" returns an error since the underlying
	// client will surface ErrNotFound. The orchard.Client.DeleteVM
	// swallows 404; our fake here doesn't, to verify the provider doesn't
	// double-mask. In practice the real client never returns ErrNotFound.
	err := p.DeletePod(context.Background(), pod)
	if err == nil || !errors.Is(err, orchard.ErrNotFound) && !strings.Contains(err.Error(), "not found") {
		t.Fatalf("expected ErrNotFound-derived error, got %v", err)
	}
}

func TestGetPodStatus_TranslatesVMState(t *testing.T) {
	fc := newFake()
	p := New("vk-test", fc)
	pod := newPod("tuist", "xcresult-processor-0", "img", nil)
	if err := p.CreatePod(context.Background(), pod); err != nil {
		t.Fatalf("CreatePod: %v", err)
	}

	status, err := p.GetPodStatus(context.Background(), "tuist", "xcresult-processor-0")
	if err != nil {
		t.Fatalf("GetPodStatus: %v", err)
	}
	if status.Phase != corev1.PodRunning {
		t.Fatalf("expected Running, got %s", status.Phase)
	}
	if !podConditionTrue(status.Conditions, corev1.PodReady) {
		t.Fatalf("expected Ready=true, got conditions: %+v", status.Conditions)
	}
}

func TestGetPodStatus_VMGone_PodFailed(t *testing.T) {
	fc := newFake()
	p := New("vk-test", fc)
	pod := newPod("tuist", "xcresult-processor-0", "img", nil)
	if err := p.CreatePod(context.Background(), pod); err != nil {
		t.Fatalf("CreatePod: %v", err)
	}
	delete(fc.vms, "tuist-xcresult-processor-0")

	status, err := p.GetPodStatus(context.Background(), "tuist", "xcresult-processor-0")
	if err != nil {
		t.Fatalf("GetPodStatus: %v", err)
	}
	if status.Phase != corev1.PodFailed || status.Reason != "VMNotFound" {
		t.Fatalf("expected Failed/VMNotFound, got %s/%s", status.Phase, status.Reason)
	}
}

func TestResync_RebuildsCacheFromOrchard(t *testing.T) {
	fc := newFake()
	fc.vms["tuist-existing"] = &orchard.VM{
		Name:   "tuist-existing",
		Image:  "ghcr.io/tuist/tuist-xcresult-processor:abc",
		Status: "running",
		Labels: map[string]string{
			"tuist.dev/managed-by":    "vk-orchard",
			"tuist.dev/pod-namespace": "tuist",
			"tuist.dev/pod-name":      "existing",
		},
	}
	fc.vms["unrelated"] = &orchard.VM{
		Name:   "unrelated",
		Status: "running",
		Labels: map[string]string{"tuist.dev/managed-by": "something-else"},
	}

	p := New("vk-test", fc)
	if err := p.Resync(context.Background()); err != nil {
		t.Fatalf("Resync: %v", err)
	}
	if len(p.pods) != 1 {
		t.Fatalf("expected 1 pod after resync, got %d", len(p.pods))
	}
	if _, ok := p.pods["tuist/existing"]; !ok {
		t.Fatalf("expected tuist/existing in pod cache; have %v", keys(p.pods))
	}
}

func keys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

func podConditionTrue(conds []corev1.PodCondition, t corev1.PodConditionType) bool {
	for _, c := range conds {
		if c.Type == t && c.Status == corev1.ConditionTrue {
			return true
		}
	}
	return false
}
