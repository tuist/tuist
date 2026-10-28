package macosandbox

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/sandboxd/pkg/server"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/satoken"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

const (
	Namespace        = "tuist-sandboxes"
	ServiceAccount   = "tuist-macos-sandboxd"
	ConfigAnnotation = "tuist.dev/macos-sandbox-config"
)

type Config struct {
	URL      string `json:"url"`
	Image    string `json:"image"`
	Template string `json:"template"`
}

// Service runs on the host, not in a guest. The control Pod provides a
// revocable, Pod-bound identity and declarative configuration only.
type Service struct {
	Kube              kubernetes.Interface
	Node, Root, Tools string
	mu                sync.Mutex
	manager           *Manager
	capacity          *KubeCapacity
	ready             bool
	err               error
}

func (s *Service) NeedLeaderElection() bool { return false }
func (s *Service) Start(ctx context.Context) error {
	if err := os.MkdirAll(s.Root, 0700); err != nil {
		return err
	}
	// Kubernetes operations and VM transitions run here, independently of the
	// single CI Pod reconcile worker.
	lock, err := os.OpenFile(filepath.Join(s.Root, "owner.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	if err = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return errors.New("another sandbox host service owns this store")
	}
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	var cancel context.CancelFunc
	var controlUID string
	defer func() {
		if cancel != nil {
			cancel()
		}
	}()
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		opCtx, done := context.WithTimeout(ctx, 30*time.Minute)
		err := s.tick(opCtx, ctx, &controlUID, &cancel)
		done()
		if err != nil {
			slog.Warn("macOS sandbox reconcile", "error", err)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}
func (s *Service) tick(ctx, parent context.Context, controlUID *string, cancel *context.CancelFunc) error {
	node, err := s.Kube.CoreV1().Nodes().Get(ctx, s.Node, metav1.GetOptions{})
	if err != nil {
		return err
	}
	pods, err := s.Kube.CoreV1().Pods(Namespace).List(ctx, metav1.ListOptions{FieldSelector: "spec.nodeName=" + s.Node})
	if err != nil {
		return err
	}
	var control *corev1.Pod
	for i := range pods.Items {
		p := &pods.Items[i]
		if p.Labels[RoleLabel] == "control" && p.Spec.ServiceAccountName == ServiceAccount && p.DeletionTimestamp.IsZero() {
			if control != nil {
				return errors.New("multiple sandbox control Pods")
			}
			control = p
		}
	}
	s.mu.Lock()
	m := s.manager
	s.mu.Unlock()
	if m == nil {
		// With no control Pod and no durable records, this host keeps its existing
		// CI-only behavior. Existing records always require recovery before launches.
		entries, readErr := os.ReadDir(filepath.Join(s.Root, "records"))
		if control == nil && (os.IsNotExist(readErr) || readErr == nil && len(entries) == 0) {
			s.mu.Lock()
			s.ready = true
			s.mu.Unlock()
			return nil
		}
		var cfg Config
		configData, configErr := os.ReadFile(filepath.Join(s.Root, "config.json"))
		if control != nil {
			configData, configErr = []byte(control.Annotations[ConfigAnnotation]), nil
		}
		if configErr != nil {
			return configErr
		}
		if err = json.Unmarshal(configData, &cfg); err != nil {
			return err
		}
		parsed, err := url.Parse(cfg.URL)
		if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
			return errors.New("sandbox server requires HTTPS")
		}
		if cfg.Template == "" || (!strings.Contains(cfg.Image, "@sha256:") && (!strings.Contains(cfg.Image, ":") || strings.HasSuffix(cfg.Image, ":latest"))) {
			return errors.New("sandbox requires a named template and versioned image")
		}
		if err = atomicFile(filepath.Join(s.Root, "config.json"), configData); err != nil {
			return err
		}
		if os.IsNotExist(readErr) || readErr == nil && len(entries) == 0 {
			s.mu.Lock()
			s.ready = true
			s.mu.Unlock()
		}
		binary, err := BuildRuntime(ctx, filepath.Join(s.Root, "runtimes"))
		if err != nil {
			return err
		}
		if s.Tools == "" {
			s.Tools, err = installTools(filepath.Join(s.Root, "guest-tools"))
			if err != nil {
				return err
			}
		}
		for _, name := range []string{"sbx-macos", "sbx-worker"} {
			info, err := os.Stat(filepath.Join(s.Tools, name))
			if err != nil {
				return err
			}
			if info.Mode()&0111 == 0 {
				return errors.New("guest bridge is not executable")
			}
		}
		c := &tart.Client{Binary: binary, HomeDir: filepath.Join(s.Root, "tart"), UserDataDir: filepath.Join(s.Root, "env"), LogDir: filepath.Join(s.Root, "logs"), EnsureGUISession: tart.EnsureRealGUISession, ExtraEnv: []string{"TART_NO_AUTO_PRUNE=1"}, BackgroundPull: []string{"/usr/sbin/taskpolicy", "-b"}}
		if err = os.MkdirAll(c.HomeDir, 0700); err != nil {
			return err
		}
		if err = os.MkdirAll(c.UserDataDir, 0700); err != nil {
			return err
		}
		if control != nil {
			if err = ensureImage(ctx, c, cfg.Image); err != nil {
				return err
			}
		}
		controlID := ""
		if control != nil {
			controlID = string(control.UID)
		}
		cap := &KubeCapacity{Kube: s.Kube, Node: s.Node, NodeUID: string(node.UID), Namespace: Namespace, ControlUID: controlID}
		m = &Manager{Root: filepath.Join(s.Root, "records"), NodeUID: string(node.UID), TemplateTag: cfg.Image, RuntimePath: binary, ToolsPath: s.Tools, Capacity: cap, Runtime: &TartRuntime{Client: c, Image: cfg.Image, Template: cfg.Template, Tools: s.Tools}}
		if err = m.Load(ctx); err != nil {
			return err
		}
		vms, err := c.List(ctx)
		if err != nil {
			return err
		}
		for _, vm := range vms {
			if strings.HasPrefix(vm.Name, "sbx-") && m.records[strings.TrimPrefix(vm.Name, "sbx-")] == nil {
				return errors.New("orphan sandbox VM requires ownership reconciliation")
			}
		}
		// Recreate reservations from durable local ownership before admitting CI,
		// including errors whose runtime state remains uncertain.
		for _, r := range m.records {
			if r.Resident || r.Operation != "" {
				if err = cap.Hold(ctx, r); err != nil {
					return err
				}
			}
		}
		s.mu.Lock()
		s.manager = m
		s.capacity = cap
		s.ready = true
		s.mu.Unlock()
	}
	if control == nil || *controlUID != string(control.UID) {
		if *cancel != nil {
			(*cancel)()
			*cancel = nil
		}
		*controlUID = ""
	}
	if control != nil && *cancel == nil {
		var cfg Config
		if err = json.Unmarshal([]byte(control.Annotations[ConfigAnnotation]), &cfg); err != nil {
			return err
		}
		// A new control Pod revokes old grants, while VM ownership stays bound to
		// the Node UID and its journal. No process is stopped for a socket restart.
		if err = validateConfig(cfg); err != nil {
			return err
		}
		if runtime, ok := m.Runtime.(*TartRuntime); ok {
			if err = ensureImage(ctx, runtime.Client, cfg.Image); err != nil {
				return err
			}
		}
		if err = atomicFile(filepath.Join(s.Root, "config.json"), []byte(control.Annotations[ConfigAnnotation])); err != nil {
			return err
		}
		m.Gate.Lock()
		m.TemplateTag = cfg.Image
		s.capacity.ControlUID = string(control.UID)
		if runtime, ok := m.Runtime.(*TartRuntime); ok {
			runtime.Image = cfg.Image
			runtime.Template = cfg.Template
		}
		m.Gate.Unlock()
		clientCtx, stop := context.WithCancel(parent)
		*cancel = stop
		*controlUID = string(control.UID)
		minter := &satoken.ClientMinter{Client: s.Kube, Audiences: []string{"tuist-sandboxes"}, ExpirationSeconds: 600}
		templates := []protocol.TemplateInfo{{Name: cfg.Template, Tag: cfg.Image, Ready: true}}
		capacity := protocol.Capacity{CPUs: int(node.Status.Allocatable.Cpu().Value()), MemoryBytes: uint64(node.Status.Allocatable.Memory().Value())}
		client := server.New(server.Config{URL: cfg.URL, NodeName: s.Node, Token: func(ctx context.Context) (string, error) { return minter.Mint(ctx, control) }, ReportInterval: 5 * time.Second,
			Hello: func() protocol.Hello {
				return protocol.Hello{Platform: "darwin", Generation: m.NodeUID, ControlUID: string(control.UID), Admission: s.grant(), Capacity: capacity, Templates: templates, Sandboxes: m.Snapshot()}
			},
			Report: func() protocol.Report {
				return protocol.Report{Platform: "darwin", Generation: m.NodeUID, ControlUID: string(control.UID), Admission: s.grant(), Capacity: capacity, Sandboxes: m.Snapshot()}
			},
			Handler: m.Dispatch})
		m.Gate.Lock()
		m.Emit = client.Emit
		m.Gate.Unlock()
		go client.Run(clientCtx)
	}
	if err = m.Reconcile(ctx); err != nil {
		return err
	}
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Labels[RoleLabel] == "execution" {
			id := pod.Labels[IDLabel]
			if pod.Annotations[NodeUIDAnnotation] != m.NodeUID {
				return errors.New("reservation belongs to another Node incarnation")
			}
			if !pod.DeletionTimestamp.IsZero() {
				if err = m.Delete(ctx, id); err != nil {
					return err
				}
				continue
			}
			// A forged/stranded Pod does not become a VM. Only a journal owns a VM.
			m.Gate.Lock()
			r := m.records[id]
			ready := r != nil && r.Resident && r.Operation == "" && (r.State == "running" || r.State == "paused")
			m.Gate.Unlock()
			if r == nil {
				return errors.New("reservation missing its durable journal")
			}
			if !ready {
				continue
			}
		}
		if pod.Labels[RoleLabel] == "control" || pod.Labels[RoleLabel] == "execution" {
			if pod.Status.Phase != corev1.PodRunning && pod.DeletionTimestamp.IsZero() {
				copy := pod.DeepCopy()
				copy.Status.Phase = corev1.PodRunning
				copy.Status.Conditions = []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue, LastTransitionTime: metav1.Now()}}
				if _, err = s.Kube.CoreV1().Pods(Namespace).UpdateStatus(ctx, copy, metav1.UpdateOptions{}); err != nil {
					return err
				}
			}
		}
	}
	m.Gate.Lock()
	defer m.Gate.Unlock()
	return s.repairReservations(ctx, m)
}

// repairReservations runs under the launch gate, including immediately before
// every CI launch. A force-deleted Pod cannot erase a live VM's charge.
func (s *Service) repairReservations(ctx context.Context, m *Manager) error {
	for _, r := range m.records {
		if r.Resident || r.Operation != "" {
			if err := s.capacity.Hold(ctx, r); err != nil {
				return err
			}
		}
	}
	return nil
}

// LaunchGuard is installed on the CI Tart client. It never checkpoints inline.
func (s *Service) LaunchGuard(ctx context.Context, _ string) (func(), error) {
	s.mu.Lock()
	ready, m, cap := s.ready, s.manager, s.capacity
	s.mu.Unlock()
	if !ready {
		return nil, errors.New("sandbox ownership recovery pending")
	}
	if m == nil {
		return func() {}, nil
	}
	if !m.Gate.TryLock() {
		return nil, ErrCapacity
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	if err := s.repairReservations(ctx, m); err != nil {
		m.Gate.Unlock()
		return nil, err
	}
	if err := cap.Fits(ctx); err != nil {
		m.Gate.Unlock()
		return nil, err
	}
	return m.Gate.Unlock, nil
}
func (m *Manager) Dispatch(ctx context.Context, cmd protocol.Command, out func(protocol.Stream)) protocol.Result {
	var args struct {
		protocol.CreateArgs
		Env       map[string]string `json:"env"`
		Cmd       []string          `json:"cmd"`
		Cwd       string            `json:"cwd"`
		TimeoutMs int64             `json:"timeout_ms"`
		NodeUID   string            `json:"node_uid"`
	}
	if err := json.Unmarshal(cmd.Args, &args); err != nil {
		return protocol.ErrorResult(cmd.ID, errors.New("invalid command"))
	}
	if args.NodeUID != m.NodeUID {
		return protocol.ErrorResult(cmd.ID, errors.New("sandbox owner generation changed"))
	}
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 2*time.Minute)
	defer cancel()
	started := time.Now()
	var err error
	var data any
	switch cmd.Op {
	case protocol.OpCreate:
		err = m.Create(ctx, args.CreateArgs)
		data = map[string]any{"boot_ms": time.Since(started).Milliseconds()}
		for _, info := range m.Snapshot() {
			if info.ID == args.SandboxID {
				data = map[string]any{"boot_ms": time.Since(started).Milliseconds(), "template_tag": info.TemplateTag}
			}
		}
	case protocol.OpResume:
		err = m.Resume(ctx, args.SandboxID)
		data = protocol.ResumeResult{RestoreMs: time.Since(started).Milliseconds()}
	case protocol.OpPause:
		err = m.Pause(ctx, args.SandboxID)
		data = map[string]any{"resident": true, "snapshot_ms": time.Since(started).Milliseconds()}
	case protocol.OpDelete:
		err = m.Delete(ctx, args.SandboxID)
	case protocol.OpExec:
		data, err = m.Exec(ctx, protocol.ExecArgs{SandboxID: args.SandboxID, Cmd: args.Cmd, Env: args.Env, Cwd: args.Cwd, TimeoutMs: args.TimeoutMs}, out)
	case protocol.OpStartWorker:
		var status WorkerStatus
		status, err = m.Worker(ctx, args.SandboxID, "start", args.Env)
		data = protocol.StartWorkerResult{ExecID: status.ID}
	case protocol.OpStopWorker:
		_, err = m.Worker(ctx, args.SandboxID, "stop", nil)
	case protocol.OpStatus:
		for _, info := range m.Snapshot() {
			if info.ID == args.SandboxID {
				data = info
				break
			}
		}
		if data == nil {
			err = errors.New("sandbox not found")
		}
	default:
		err = fmt.Errorf("unsupported macOS sandbox operation %q", cmd.Op)
	}
	if err != nil {
		return protocol.ErrorResult(cmd.ID, err)
	}
	return protocol.OKResult(cmd.ID, data)
}
func (s *Service) grant() Grant {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	node, err := s.Kube.CoreV1().Nodes().Get(ctx, s.Node, metav1.GetOptions{})
	if err != nil {
		return Grant{}
	}
	var grant Grant
	if json.Unmarshal([]byte(node.Annotations[GrantAnnotation]), &grant) != nil {
		return Grant{}
	}
	return grant
}

func validateConfig(cfg Config) error {
	parsed, err := url.Parse(cfg.URL)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
		return errors.New("sandbox server requires HTTPS")
	}
	if cfg.Template == "" || (!strings.Contains(cfg.Image, "@sha256:") && (!strings.Contains(cfg.Image, ":") || strings.HasSuffix(cfg.Image, ":latest"))) {
		return errors.New("sandbox requires a named template and versioned image")
	}
	return nil
}
