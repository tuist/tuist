// Package protocol holds the JSON frames exchanged between sandboxd and the
// Tuist server over the node WebSocket, plus the command argument and result
// shapes. See infra/sandboxd/AGENTS.md "Node to server: WebSocket".
package protocol

import (
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

const (
	FrameHello   = "hello"
	FrameResult  = "result"
	FrameStream  = "stream"
	FrameEvent   = "event"
	FrameReport  = "report"
	FrameCommand = "command"
)

const (
	OpCreate      = "create"
	OpResume      = "resume"
	OpPause       = "pause"
	OpDelete      = "delete"
	OpExec        = "exec"
	OpStartWorker = "start_worker"
	OpStopWorker  = "stop_worker"
	OpStatus      = "status"
)

const (
	EventWorkerExited  = "worker_exited"
	EventSandboxDied   = "sandbox_died"
	EventTemplateReady = "template_ready"
)

const (
	StateRunning = "running"
	StatePaused  = "paused"
	StateError   = "error"
)

// Envelope is the minimal decode of any frame: enough to route on type.
type Envelope struct {
	Type string `json:"type"`
}

type Capacity struct {
	MemoryBytes uint64 `json:"memory_bytes"`
	CPUs        int    `json:"cpus"`
}

// TemplateInfo advertises a template. Ready means the kernel and rootfs are
// on the node so a create can use it (building the shape snapshot lazily if
// needed); Shapes lists the shapes whose snapshot is already built.
type TemplateInfo struct {
	Name   string   `json:"name"`
	Tag    string   `json:"tag"`
	Ready  bool     `json:"ready"`
	Shapes []string `json:"shapes"`
}

type SandboxInfo struct {
	ID            string    `json:"id"`
	State         string    `json:"state"`
	Template      string    `json:"template"`
	TemplateTag   string    `json:"template_tag"`
	VCPUs         int       `json:"vcpus"`
	MemoryMB      int       `json:"memory_mb"`
	WorkspaceGB   int       `json:"workspace_gb"`
	Hostname      string    `json:"hostname"`
	WorkerRunning bool      `json:"worker_running"`
	Generation    int       `json:"generation"`
	CreatedAt     time.Time `json:"created_at"`
	Error         string    `json:"error,omitempty"`
}

type Hello struct {
	Type               string         `json:"type"`
	Node               string         `json:"node"`
	DaemonVersion      string         `json:"daemon_version"`
	FirecrackerVersion string         `json:"firecracker_version"`
	Capacity           Capacity       `json:"capacity"`
	Templates          []TemplateInfo `json:"templates"`
	Sandboxes          []SandboxInfo  `json:"sandboxes"`
}

type Result struct {
	Type  string `json:"type"`
	ID    string `json:"id"`
	OK    bool   `json:"ok"`
	Data  any    `json:"data,omitempty"`
	Error string `json:"error,omitempty"`
}

type Stream struct {
	Type    string `json:"type"`
	ID      string `json:"id"`
	Stream  string `json:"stream"`
	DataB64 string `json:"data_b64"`
}

type Event struct {
	Type       string `json:"type"`
	Event      string `json:"event"`
	SandboxID  string `json:"sandbox_id,omitempty"`
	ExitCode   *int   `json:"exit_code,omitempty"`
	DurationMs int64  `json:"duration_ms,omitempty"`
	Reason     string `json:"reason,omitempty"`
	Name       string `json:"name,omitempty"`
	Tag        string `json:"tag,omitempty"`
	Shape      string `json:"shape,omitempty"`
}

type MemoryReport struct {
	UsedBytes uint64 `json:"used_bytes"`
}

type Report struct {
	Type      string        `json:"type"`
	Sandboxes []SandboxInfo `json:"sandboxes"`
	Memory    MemoryReport  `json:"memory"`
}

type Command struct {
	Type string          `json:"type"`
	ID   string          `json:"id"`
	Op   string          `json:"op"`
	Args json.RawMessage `json:"args"`
}

type CreateArgs struct {
	SandboxID   string `json:"sandbox_id"`
	Template    string `json:"template"`
	TemplateTag string `json:"template_tag,omitempty"`
	VCPUs       int    `json:"vcpus"`
	MemoryMB    int    `json:"memory_mb"`
	WorkspaceGB int    `json:"workspace_gb"`
	Hostname    string `json:"hostname"`
}

type SandboxArgs struct {
	SandboxID string `json:"sandbox_id"`
}

type ExecArgs struct {
	SandboxID string            `json:"sandbox_id"`
	Cmd       []string          `json:"cmd"`
	Env       map[string]string `json:"env"`
	Cwd       string            `json:"cwd"`
	TimeoutMs int64             `json:"timeout_ms"`
}

type StartWorkerArgs struct {
	SandboxID string            `json:"sandbox_id"`
	Env       map[string]string `json:"env"`
}

type CreateResult struct {
	BootMs int64 `json:"boot_ms"`
}

type ResumeResult struct {
	RestoreMs int64 `json:"restore_ms"`
}

type PauseResult struct {
	SnapshotMs int64 `json:"snapshot_ms"`
	MemBytes   int64 `json:"mem_bytes"`
}

type ExecResult struct {
	ExitCode   int   `json:"exit_code"`
	DurationMs int64 `json:"duration_ms"`
}

type StartWorkerResult struct {
	ExecID string `json:"exec_id"`
}

func OKResult(id string, data any) Result {
	return Result{Type: FrameResult, ID: id, OK: true, Data: data}
}

func ErrorResult(id string, err error) Result {
	return Result{Type: FrameResult, ID: id, OK: false, Error: err.Error()}
}

// Decode parses one text frame into its typed struct. The returned value is
// one of *Hello, *Result, *Stream, *Event, *Report or *Command.
func Decode(data []byte) (any, error) {
	var env Envelope
	if err := json.Unmarshal(data, &env); err != nil {
		return nil, fmt.Errorf("decoding frame envelope: %w", err)
	}
	var target any
	switch env.Type {
	case FrameHello:
		target = &Hello{}
	case FrameResult:
		target = &Result{}
	case FrameStream:
		target = &Stream{}
	case FrameEvent:
		target = &Event{}
	case FrameReport:
		target = &Report{}
	case FrameCommand:
		target = &Command{}
	case "":
		return nil, errors.New("frame has no type")
	default:
		return nil, fmt.Errorf("unknown frame type %q", env.Type)
	}
	if err := json.Unmarshal(data, target); err != nil {
		return nil, fmt.Errorf("decoding %s frame: %w", env.Type, err)
	}
	return target, nil
}
