// Package runtimeservice implements CRI's RuntimeService — the gRPC
// service kubelet calls to manage Pod sandboxes, containers, and
// container exec/log lifecycle.
//
// In tart-cri's one-VM-per-Pod model:
//   - PodSandbox = a state record holding the Pod's metadata. No real
//     sandbox container exists; we don't have netns concepts on macOS.
//   - Container = a Tart VM, named with the CRI container ID.
//   - Logs = the VM's stdout/stderr written to a file kubelet tails.
package runtimeservice

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	runtimeapi "k8s.io/cri-api/pkg/apis/runtime/v1"

	"github.com/tuist/tuist/infra/tart-cri/internal/state"
	"github.com/tuist/tuist/infra/tart-cri/internal/tart"
)

// Service implements runtimeapi.RuntimeServiceServer.
type Service struct {
	runtimeapi.UnimplementedRuntimeServiceServer

	Tart   *tart.Runtime
	Store  *state.Store
	LogDir string
}

// New constructs a Service. LogDir is the per-container log root; CRI
// requires individual log files at <LogDir>/<container-id>.log so the
// kubelet's log-reader can tail them.
func New(t *tart.Runtime, s *state.Store, logDir string) *Service {
	return &Service{Tart: t, Store: s, LogDir: logDir}
}

// === Identity =============================================================

func (s *Service) Version(_ context.Context, _ *runtimeapi.VersionRequest) (*runtimeapi.VersionResponse, error) {
	return &runtimeapi.VersionResponse{
		Version:           "0.1.0",
		RuntimeName:       "tart-cri",
		RuntimeVersion:    "0.1.0",
		RuntimeApiVersion: "v1",
	}, nil
}

func (s *Service) Status(_ context.Context, _ *runtimeapi.StatusRequest) (*runtimeapi.StatusResponse, error) {
	conds := []*runtimeapi.RuntimeCondition{
		{Type: "RuntimeReady", Status: true},
		// NetworkReady is reported true even though we don't run a
		// CNI for pod networking — kubelet's contract requires the
		// condition. The CNI plugin populates Pod.Status.PodIP via
		// a separate path.
		{Type: "NetworkReady", Status: true},
	}
	return &runtimeapi.StatusResponse{Status: &runtimeapi.RuntimeStatus{Conditions: conds}}, nil
}

// === Pod sandboxes ========================================================

func (s *Service) RunPodSandbox(ctx context.Context, req *runtimeapi.RunPodSandboxRequest) (*runtimeapi.RunPodSandboxResponse, error) {
	cfg := req.GetConfig()
	id := newID()

	logDir := cfg.GetLogDirectory()
	if logDir == "" {
		logDir = filepath.Join(s.LogDir, id)
	}
	if err := os.MkdirAll(logDir, 0o755); err != nil {
		return nil, fmt.Errorf("create log dir: %w", err)
	}

	sb := &state.Sandbox{
		ID:          id,
		Metadata:    cfg.GetMetadata(),
		State:       runtimeapi.PodSandboxState_SANDBOX_READY,
		CreatedAt:   time.Now(),
		Labels:      cfg.GetLabels(),
		Annotations: cfg.GetAnnotations(),
		Hostname:    cfg.GetHostname(),
		LogDir:      logDir,
	}
	if err := s.Store.PutSandbox(sb); err != nil {
		return nil, err
	}
	return &runtimeapi.RunPodSandboxResponse{PodSandboxId: id}, nil
}

func (s *Service) StopPodSandbox(ctx context.Context, req *runtimeapi.StopPodSandboxRequest) (*runtimeapi.StopPodSandboxResponse, error) {
	sb := s.Store.GetSandbox(req.GetPodSandboxId())
	if sb == nil {
		return &runtimeapi.StopPodSandboxResponse{}, nil
	}

	// Stop every Tart VM still running in this sandbox.
	for _, c := range s.Store.ListContainers(sb.ID) {
		if c.State == runtimeapi.ContainerState_CONTAINER_RUNNING {
			if err := s.Tart.Stop(ctx, c.ID, 30*time.Second); err != nil {
				// Log and keep going — at worst the next reconcile
				// will catch a leaked VM.
				fmt.Fprintf(os.Stderr, "stop container %s: %v\n", c.ID, err)
			}
			c.State = runtimeapi.ContainerState_CONTAINER_EXITED
			c.FinishedAt = time.Now()
			c.Reason = "PodSandboxStopped"
			_ = s.Store.PutContainer(c)
		}
	}

	sb.State = runtimeapi.PodSandboxState_SANDBOX_NOTREADY
	_ = s.Store.PutSandbox(sb)
	return &runtimeapi.StopPodSandboxResponse{}, nil
}

func (s *Service) RemovePodSandbox(ctx context.Context, req *runtimeapi.RemovePodSandboxRequest) (*runtimeapi.RemovePodSandboxResponse, error) {
	sb := s.Store.GetSandbox(req.GetPodSandboxId())
	if sb == nil {
		return &runtimeapi.RemovePodSandboxResponse{}, nil
	}
	for _, c := range s.Store.ListContainers(sb.ID) {
		_ = s.Tart.Delete(ctx, c.ID)
	}
	if err := s.Store.DeleteSandbox(sb.ID); err != nil {
		return nil, err
	}
	return &runtimeapi.RemovePodSandboxResponse{}, nil
}

func (s *Service) PodSandboxStatus(_ context.Context, req *runtimeapi.PodSandboxStatusRequest) (*runtimeapi.PodSandboxStatusResponse, error) {
	sb := s.Store.GetSandbox(req.GetPodSandboxId())
	if sb == nil {
		return nil, fmt.Errorf("sandbox %s not found", req.GetPodSandboxId())
	}
	return &runtimeapi.PodSandboxStatusResponse{Status: sandboxStatus(sb)}, nil
}

func (s *Service) ListPodSandbox(_ context.Context, req *runtimeapi.ListPodSandboxRequest) (*runtimeapi.ListPodSandboxResponse, error) {
	out := []*runtimeapi.PodSandbox{}
	for _, sb := range s.Store.ListSandboxes() {
		if !matchSandboxFilter(sb, req.GetFilter()) {
			continue
		}
		out = append(out, &runtimeapi.PodSandbox{
			Id:          sb.ID,
			Metadata:    sb.Metadata,
			State:       sb.State,
			CreatedAt:   sb.CreatedAt.UnixNano(),
			Labels:      sb.Labels,
			Annotations: sb.Annotations,
		})
	}
	return &runtimeapi.ListPodSandboxResponse{Items: out}, nil
}

// === Containers ===========================================================

func (s *Service) CreateContainer(ctx context.Context, req *runtimeapi.CreateContainerRequest) (*runtimeapi.CreateContainerResponse, error) {
	sb := s.Store.GetSandbox(req.GetPodSandboxId())
	if sb == nil {
		return nil, fmt.Errorf("sandbox %s not found", req.GetPodSandboxId())
	}

	cfg := req.GetConfig()
	id := newID()
	image := cfg.GetImage().GetImage()

	if err := s.Tart.Clone(ctx, image, id); err != nil {
		return nil, fmt.Errorf("tart clone: %w", err)
	}

	cpu, mem := resourceShape(cfg)
	if err := s.Tart.SetParameters(ctx, id, cpu, mem); err != nil {
		return nil, fmt.Errorf("tart set: %w", err)
	}

	logPath := filepath.Join(sb.LogDir, id+".log")
	if cfg.GetLogPath() != "" {
		logPath = filepath.Join(sb.LogDir, cfg.GetLogPath())
	}

	c := &state.Container{
		ID:          id,
		SandboxID:   sb.ID,
		Metadata:    cfg.GetMetadata(),
		Image:       image,
		State:       runtimeapi.ContainerState_CONTAINER_CREATED,
		CreatedAt:   time.Now(),
		Labels:      cfg.GetLabels(),
		Annotations: cfg.GetAnnotations(),
		LogPath:     logPath,
		Envs:        formatEnvs(cfg.GetEnvs()),
		CPU:         cpu,
		MemoryMB:    mem,
	}
	if err := s.Store.PutContainer(c); err != nil {
		return nil, err
	}
	return &runtimeapi.CreateContainerResponse{ContainerId: id}, nil
}

func (s *Service) StartContainer(ctx context.Context, req *runtimeapi.StartContainerRequest) (*runtimeapi.StartContainerResponse, error) {
	c := s.Store.GetContainer(req.GetContainerId())
	if c == nil {
		return nil, fmt.Errorf("container %s not found", req.GetContainerId())
	}

	// Inject env as user-data JSON so the Tart guest can read it via
	// /private/var/db/vmctl/user-data — same path the xcresult image
	// expects.
	userDataPath, err := writeUserData(c)
	if err != nil {
		return nil, fmt.Errorf("write user-data: %w", err)
	}

	if err := s.Tart.Run(ctx, c.ID, tart.RunOptions{UserData: userDataPath}); err != nil {
		c.State = runtimeapi.ContainerState_CONTAINER_EXITED
		c.FinishedAt = time.Now()
		c.Reason = "StartFailed"
		c.Message = err.Error()
		_ = s.Store.PutContainer(c)
		return nil, err
	}

	c.State = runtimeapi.ContainerState_CONTAINER_RUNNING
	c.StartedAt = time.Now()
	if err := s.Store.PutContainer(c); err != nil {
		return nil, err
	}
	return &runtimeapi.StartContainerResponse{}, nil
}

func (s *Service) StopContainer(ctx context.Context, req *runtimeapi.StopContainerRequest) (*runtimeapi.StopContainerResponse, error) {
	c := s.Store.GetContainer(req.GetContainerId())
	if c == nil {
		return &runtimeapi.StopContainerResponse{}, nil
	}
	timeout := time.Duration(req.GetTimeout()) * time.Second
	if timeout == 0 {
		timeout = 30 * time.Second
	}
	if err := s.Tart.Stop(ctx, c.ID, timeout); err != nil {
		// Continue even on error — the next reconcile will catch
		// orphans.
		fmt.Fprintf(os.Stderr, "stop container %s: %v\n", c.ID, err)
	}
	c.State = runtimeapi.ContainerState_CONTAINER_EXITED
	c.FinishedAt = time.Now()
	c.Reason = "Stopped"
	if err := s.Store.PutContainer(c); err != nil {
		return nil, err
	}
	return &runtimeapi.StopContainerResponse{}, nil
}

func (s *Service) RemoveContainer(ctx context.Context, req *runtimeapi.RemoveContainerRequest) (*runtimeapi.RemoveContainerResponse, error) {
	c := s.Store.GetContainer(req.GetContainerId())
	if c == nil {
		return &runtimeapi.RemoveContainerResponse{}, nil
	}
	if err := s.Tart.Delete(ctx, c.ID); err != nil {
		fmt.Fprintf(os.Stderr, "delete container %s: %v\n", c.ID, err)
	}
	if err := s.Store.DeleteContainer(c.ID); err != nil {
		return nil, err
	}
	return &runtimeapi.RemoveContainerResponse{}, nil
}

func (s *Service) ListContainers(_ context.Context, req *runtimeapi.ListContainersRequest) (*runtimeapi.ListContainersResponse, error) {
	out := []*runtimeapi.Container{}
	for _, c := range s.Store.ListContainers("") {
		if !matchContainerFilter(c, req.GetFilter()) {
			continue
		}
		out = append(out, &runtimeapi.Container{
			Id:           c.ID,
			PodSandboxId: c.SandboxID,
			Metadata:     c.Metadata,
			Image:        &runtimeapi.ImageSpec{Image: c.Image},
			ImageRef:     c.Image,
			State:        c.State,
			CreatedAt:    c.CreatedAt.UnixNano(),
			Labels:       c.Labels,
			Annotations:  c.Annotations,
		})
	}
	return &runtimeapi.ListContainersResponse{Containers: out}, nil
}

func (s *Service) ContainerStatus(ctx context.Context, req *runtimeapi.ContainerStatusRequest) (*runtimeapi.ContainerStatusResponse, error) {
	c := s.Store.GetContainer(req.GetContainerId())
	if c == nil {
		return nil, fmt.Errorf("container %s not found", req.GetContainerId())
	}

	// Live-check the VM state from Tart — it's the source of truth.
	// We update our cache opportunistically.
	if vm, err := s.Tart.Get(ctx, c.ID); err == nil {
		switch vm.State {
		case "running":
			c.State = runtimeapi.ContainerState_CONTAINER_RUNNING
		case "stopped":
			if c.State == runtimeapi.ContainerState_CONTAINER_RUNNING {
				c.State = runtimeapi.ContainerState_CONTAINER_EXITED
				c.FinishedAt = time.Now()
				c.Reason = "VMStopped"
			}
		}
		_ = s.Store.PutContainer(c)
	}

	return &runtimeapi.ContainerStatusResponse{Status: containerStatus(c)}, nil
}

// === Logs =================================================================

func (s *Service) ReopenContainerLog(_ context.Context, req *runtimeapi.ReopenContainerLogRequest) (*runtimeapi.ReopenContainerLogResponse, error) {
	c := s.Store.GetContainer(req.GetContainerId())
	if c == nil {
		return nil, fmt.Errorf("container %s not found", req.GetContainerId())
	}
	if c.LogPath == "" {
		return &runtimeapi.ReopenContainerLogResponse{}, nil
	}
	// Touch the file so kubelet's log reader picks up the rotation.
	f, err := os.OpenFile(c.LogPath, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o644)
	if err != nil {
		return nil, err
	}
	_ = f.Close()
	return &runtimeapi.ReopenContainerLogResponse{}, nil
}

// === Helpers ==============================================================

func newID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func resourceShape(cfg *runtimeapi.ContainerConfig) (cpu, memoryMB int) {
	cpu = 4
	memoryMB = 8192
	if cfg == nil {
		return
	}
	res := cfg.GetLinux().GetResources()
	if res == nil {
		return
	}
	if res.GetCpuQuota() > 0 && res.GetCpuPeriod() > 0 {
		c := int(res.GetCpuQuota() / res.GetCpuPeriod())
		if c > 0 {
			cpu = c
		}
	}
	if res.GetMemoryLimitInBytes() > 0 {
		memoryMB = int(res.GetMemoryLimitInBytes() / (1024 * 1024))
	}
	return
}

func formatEnvs(envs []*runtimeapi.KeyValue) []string {
	out := make([]string, 0, len(envs))
	for _, kv := range envs {
		out = append(out, kv.Key+"="+kv.Value)
	}
	return out
}

// writeUserData materializes the container's env as a JSON file the
// guest reads at boot. Returns the path.
func writeUserData(c *state.Container) (string, error) {
	dir := filepath.Join("/var/lib/tart-cri/user-data", c.ID)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	envMap := make(map[string]string, len(c.Envs))
	for _, kv := range c.Envs {
		if i := strings.Index(kv, "="); i > 0 {
			envMap[kv[:i]] = kv[i+1:]
		}
	}
	payload, err := json.Marshal(map[string]any{"env": envMap})
	if err != nil {
		return "", err
	}
	path := filepath.Join(dir, "user-data.json")
	if err := os.WriteFile(path, payload, 0o600); err != nil {
		return "", err
	}
	return path, nil
}

func sandboxStatus(sb *state.Sandbox) *runtimeapi.PodSandboxStatus {
	return &runtimeapi.PodSandboxStatus{
		Id:          sb.ID,
		Metadata:    sb.Metadata,
		State:       sb.State,
		CreatedAt:   sb.CreatedAt.UnixNano(),
		Network:     &runtimeapi.PodSandboxNetworkStatus{Ip: sb.IP},
		Linux:       &runtimeapi.LinuxPodSandboxStatus{},
		Labels:      sb.Labels,
		Annotations: sb.Annotations,
	}
}

func containerStatus(c *state.Container) *runtimeapi.ContainerStatus {
	return &runtimeapi.ContainerStatus{
		Id:          c.ID,
		Metadata:    c.Metadata,
		State:       c.State,
		CreatedAt:   c.CreatedAt.UnixNano(),
		StartedAt:   nano(c.StartedAt),
		FinishedAt:  nano(c.FinishedAt),
		ExitCode:    c.ExitCode,
		Image:       &runtimeapi.ImageSpec{Image: c.Image},
		ImageRef:    c.Image,
		Reason:      c.Reason,
		Message:     c.Message,
		Labels:      c.Labels,
		Annotations: c.Annotations,
		LogPath:     c.LogPath,
	}
}

func nano(t time.Time) int64 {
	if t.IsZero() {
		return 0
	}
	return t.UnixNano()
}

func matchSandboxFilter(sb *state.Sandbox, f *runtimeapi.PodSandboxFilter) bool {
	if f == nil {
		return true
	}
	if f.GetId() != "" && f.GetId() != sb.ID {
		return false
	}
	if st := f.GetState(); st != nil && st.GetState() != sb.State {
		return false
	}
	for k, v := range f.GetLabelSelector() {
		if sb.Labels[k] != v {
			return false
		}
	}
	return true
}

func matchContainerFilter(c *state.Container, f *runtimeapi.ContainerFilter) bool {
	if f == nil {
		return true
	}
	if f.GetId() != "" && f.GetId() != c.ID {
		return false
	}
	if f.GetPodSandboxId() != "" && f.GetPodSandboxId() != c.SandboxID {
		return false
	}
	if st := f.GetState(); st != nil && st.GetState() != c.State {
		return false
	}
	for k, v := range f.GetLabelSelector() {
		if c.Labels[k] != v {
			return false
		}
	}
	return true
}
