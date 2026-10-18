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
	OpReclaim     = "reclaim"
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

// Capacity is what the server budgets sandboxes against: the memory limit
// of the daemon's own cgroup (every guest lives inside it) and the node's
// CPU count.
type Capacity struct {
	MemoryBytes uint64 `json:"memory_bytes"`
	CPUs        int    `json:"cpus"`
}

// Elastic describes how far the server may resize the daemon's Pod: from
// the floor the chart requests up to the ceiling, in place, through the
// Pod's resize subresource. A zero ceiling, or one not above the floor,
// keeps the memory limit fixed.
type Elastic struct {
	PodName            string `json:"pod_name,omitempty"`
	MemoryFloorBytes   uint64 `json:"memory_floor_bytes,omitempty"`
	MemoryCeilingBytes uint64 `json:"memory_ceiling_bytes,omitempty"`
}

type ReclaimArgs struct {
	TargetBytes uint64 `json:"target_bytes"`
}

// ReclaimResult is the cgroup after a reclaim: its limit and what it still
// charges, page cache included.
type ReclaimResult struct {
	MemoryBytes uint64 `json:"memory_bytes"`
	UsedBytes   uint64 `json:"used_bytes"`
}

// DiskReport describes the filesystem behind the data directory and what
// the daemon holds on it. SandboxesBytes counts only what jails own
// exclusively (rootfs deltas, workspaces, their own memory images);
// hardlinked and reflinked template bytes count under TemplatesBytes.
// BudgetBytes is the share of the filesystem sandboxes may occupy, zero
// when the node sets none.
type DiskReport struct {
	TotalBytes     uint64 `json:"total_bytes"`
	AvailableBytes uint64 `json:"available_bytes"`
	SandboxesBytes uint64 `json:"sandboxes_bytes"`
	TemplatesBytes uint64 `json:"templates_bytes"`
	BudgetBytes    uint64 `json:"budget_bytes"`
}

// TemplateInfo advertises a template. Ready means the kernel and rootfs are
// on the node so a create can use it (building the shape snapshot lazily if
// needed); Shapes lists the shapes whose snapshot is already built.
type TemplateInfo struct {
	Name   string   `json:"name"`
	Tag    string   `json:"tag"`
	Ready  bool     `json:"ready"`
	Shapes []string `json:"shapes"`
	// RootfsBytes is the size of the rootfs image every sandbox of this
	// template gets a clone of: the most a sandbox's rootfs can ever take on
	// the node, which the server reserves against the disk budget.
	RootfsBytes int64 `json:"rootfs_bytes"`
}

type SandboxInfo struct {
	ID            string `json:"id"`
	State         string `json:"state"`
	Template      string `json:"template"`
	TemplateTag   string `json:"template_tag"`
	VCPUs         int    `json:"vcpus"`
	MemoryMB      int    `json:"memory_mb"`
	WorkspaceGB   int    `json:"workspace_gb"`
	Hostname      string `json:"hostname"`
	WorkerRunning bool   `json:"worker_running"`
	// ColdBoot marks a paused sandbox whose next resume boots the kernel on
	// its own disks instead of restoring memory, because the daemon lost the
	// VM while it was running and the disks moved on since the last snapshot.
	ColdBoot   bool      `json:"cold_boot,omitempty"`
	Generation int       `json:"generation"`
	CreatedAt  time.Time `json:"created_at"`
	Error      string    `json:"error,omitempty"`
}

type Hello struct {
	Type               string         `json:"type"`
	Node               string         `json:"node"`
	DaemonVersion      string         `json:"daemon_version"`
	FirecrackerVersion string         `json:"firecracker_version"`
	Capacity           Capacity       `json:"capacity"`
	Elastic            Elastic        `json:"elastic"`
	Disk               DiskReport     `json:"disk"`
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

// Report is sent periodically and as soon as the daemon's memory limit
// changes, so a resize reaches the server's budget without waiting out the
// interval.
type Report struct {
	Type      string        `json:"type"`
	Capacity  Capacity      `json:"capacity"`
	Sandboxes []SandboxInfo `json:"sandboxes"`
	Memory    MemoryReport  `json:"memory"`
	Disk      DiskReport    `json:"disk"`
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
