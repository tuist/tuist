// Package macosandbox owns persistent macOS sandbox VMs on one Kubernetes Node.
// Journals and execution Pods survive control-plane and kubelet restarts. A
// paused resident keeps its Pod and full charge until a checkpoint is fenced.
package macosandbox

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/google/uuid"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

var ErrCapacity = errors.New("macOS sandbox capacity unavailable")

// Runtime must fence its process before Save or Delete succeeds. Recover must
// never cold boot or accept an old checkpoint for a disk that has since run.
type Runtime interface {
	Create(context.Context, *Record) error
	Busy(context.Context, *Record) (bool, error)
	Resume(context.Context, *Record) error
	Pause(context.Context, *Record) error
	Save(context.Context, *Record) error
	Delete(context.Context, *Record) error
	Recover(context.Context, *Record) error
	Exec(context.Context, *Record, protocol.ExecArgs, func(protocol.Stream)) (protocol.ExecResult, error)
	Worker(context.Context, *Record, string, map[string]string) (WorkerStatus, error)
}

type WorkerStatus struct {
	Running  bool   `json:"running"`
	ID       string `json:"id"`
	ExitCode int    `json:"exit_code"`
}

// Capacity owns durable Kubernetes reservations. Release requires an already
// fenced VM; a failed API write retains the Pod and is retried during recovery.
type Capacity interface {
	Reserve(context.Context, *Record) error
	Allow(context.Context, *Record) error
	Release(context.Context, *Record) error
}

type Record struct {
	protocol.CreateArgs
	NodeUID        string    `json:"node_uid"`
	State          string    `json:"state"`
	Resident       bool      `json:"resident"`
	Instance       string    `json:"instance,omitempty"`
	RuntimePath    string    `json:"runtime_path,omitempty"`
	ToolsPath      string    `json:"tools_path,omitempty"`
	PID            int       `json:"pid,omitempty"`
	WorkerID       string    `json:"worker_id,omitempty"`
	FinishedWorkID string    `json:"finished_work_id,omitempty"`
	IdleAt         time.Time `json:"idle_at"`
	CreatedAt      time.Time `json:"created_at"`
	Error          string    `json:"error,omitempty"`
	// Operation is persisted before side effects. Uncertain saves/restores are
	// reconciled against the runtime, never optimistically released.
	Operation string `json:"operation,omitempty"`
}

func (r *Record) VMName() string { return "sbx-" + r.SandboxID }
func (r *Record) Info() protocol.SandboxInfo {
	return protocol.SandboxInfo{ID: r.SandboxID, State: r.State, Resident: r.Resident || r.Operation != "", Template: r.Template,
		TemplateTag: r.TemplateTag, VCPUs: r.VCPUs, MemoryMB: r.MemoryMB, WorkspaceGB: r.WorkspaceGB,
		Hostname: r.Hostname, WorkerRunning: r.WorkerID != "", FinishedWorkID: r.FinishedWorkID, CreatedAt: r.CreatedAt, Error: r.Error}
}

type Manager struct {
	Root, NodeUID string
	RuntimePath   string
	ToolsPath     string
	TemplateTag   string
	published     atomic.Value
	Runtime       Runtime
	Capacity      Capacity
	Emit          func(protocol.Event)
	Grace         time.Duration
	// The same gate is used by the CI launcher. TryLock there avoids putting
	// a slow checkpoint or restore on the single Pod reconcile worker.
	Gate    sync.Mutex
	records map[string]*Record
	active  map[string]int
}

func (m *Manager) Load(ctx context.Context) error {
	m.Gate.Lock()
	defer m.Gate.Unlock()
	if m.NodeUID == "" {
		return errors.New("node UID is required")
	}
	if err := os.MkdirAll(m.Root, 0700); err != nil {
		return err
	}
	m.records = map[string]*Record{}
	m.active = map[string]int{}
	entries, err := os.ReadDir(m.Root)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}
		data, err := os.ReadFile(filepath.Join(m.Root, entry.Name()))
		if err != nil {
			return err
		}
		var r Record
		if err = json.Unmarshal(data, &r); err != nil {
			return fmt.Errorf("invalid sandbox journal %s: %w", entry.Name(), err)
		}
		if !validID(r.SandboxID) || entry.Name() != r.SandboxID+".json" || r.NodeUID != m.NodeUID {
			return errors.New("sandbox journal ownership mismatch; operator reconciliation required")
		}
		m.records[r.SandboxID] = &r
		if r.Operation == "delete" || r.Operation == "release" {
			m.publish()
			continue
		}
		if err = m.Runtime.Recover(ctx, &r); err != nil {
			r.State = "error"
			r.Error = err.Error()
		}
		// A reservation is removed only when the runtime positively recovered a
		// fenced checkpoint. Unknown/error VMs keep their previous Pod charge.
		if r.State == "paused" && !r.Resident {
			if err = m.Capacity.Release(ctx, &r); err != nil {
				return err
			}
		}
		if err = m.persist(&r); err != nil {
			return err
		}
	}
	return nil
}

func validID(id string) bool {
	parsed, err := uuid.Parse(id)
	return err == nil && parsed.String() == id
}
func (m *Manager) persist(r *Record) error {
	defer m.publish()
	data, err := json.Marshal(r)
	if err != nil {
		return err
	}
	return atomicFile(filepath.Join(m.Root, r.SandboxID+".json"), data)
}
func atomicFile(path string, data []byte) error {
	f, err := os.CreateTemp(filepath.Dir(path), ".journal-")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if err = f.Chmod(0600); err == nil {
		_, err = f.Write(data)
	}
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	if err = os.Rename(f.Name(), path); err != nil {
		return err
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}
func (m *Manager) begin(r *Record, op string) error {
	r.Operation = op
	r.Error = ""
	return m.persist(r)
}
func (m *Manager) finish(r *Record, err error) error {
	if err != nil {
		r.State = "error"
		r.Error = err.Error()
	} else {
		r.Error = ""
		r.Operation = ""
	}
	return errors.Join(err, m.persist(r))
}
func (m *Manager) get(id string) (*Record, error) {
	if !validID(id) {
		return nil, errors.New("invalid sandbox id")
	}
	r := m.records[id]
	if r == nil {
		return nil, errors.New("sandbox not found")
	}
	return r, nil
}
func (m *Manager) Create(ctx context.Context, a protocol.CreateArgs) error {
	m.Gate.Lock()
	defer m.Gate.Unlock()
	if !validID(a.SandboxID) || a.VCPUs != 8 || (a.MemoryMB != 8192 && a.MemoryMB != 16384 && a.MemoryMB != 24576) || a.WorkspaceGB < 1 || a.WorkspaceGB > 100 {
		return errors.New("invalid macOS sandbox shape")
	}
	if a.TemplateTag == "" {
		a.TemplateTag = m.TemplateTag
	}
	if r := m.records[a.SandboxID]; r != nil {
		if r.CreateArgs != a {
			return errors.New("sandbox already exists with different configuration")
		}
		if r.State == "running" && r.Operation == "" {
			return nil
		}
		return errors.New("sandbox already exists; reconcile its recorded operation")
	}
	r := &Record{RuntimePath: m.RuntimePath, ToolsPath: m.ToolsPath, CreateArgs: a, NodeUID: m.NodeUID, State: "creating", CreatedAt: time.Now().UTC(), IdleAt: time.Now().UTC()}
	if err := m.begin(r, "create"); err != nil {
		return err
	}
	m.records[a.SandboxID] = r
	if err := m.Capacity.Reserve(ctx, r); err != nil {
		// No runtime side effect has happened yet. A failed reservation can be
		// released without touching a VM, so queued CI is never blocked by it.
		releaseErr := m.Capacity.Release(ctx, r)
		r.State = "error"
		r.Operation = ""
		if releaseErr != nil {
			r.Operation = "release"
		}
		return m.finish(r, errors.Join(err, releaseErr))
	}
	r.Resident = true // An uncertain start must retain its reservation.
	if err := m.persist(r); err != nil {
		return err
	}
	err := m.Runtime.Create(ctx, r)
	if err == nil {
		r.State = "running"
		r.IdleAt = time.Now().UTC()
	}
	return m.finish(r, err)
}
func (m *Manager) Resume(ctx context.Context, id string) error {
	m.Gate.Lock()
	defer m.Gate.Unlock()
	r, err := m.get(id)
	if err != nil {
		return err
	}
	return m.resume(ctx, r)
}

// Called under the host gate, including when a new command races a report of
// an idle eviction. Reservations are reacquired before any guest instruction.
func (m *Manager) resume(ctx context.Context, r *Record) error {
	var err error
	if r.Operation != "" || r.State == "error" {
		return errors.New("sandbox requires reconciliation")
	}
	if err = m.Capacity.Allow(ctx, r); err != nil {
		return err
	}
	if r.State == "running" {
		return nil
	}
	if r.State != "paused" {
		return errors.New("sandbox is not paused")
	}
	if err = m.Capacity.Reserve(ctx, r); err != nil {
		if !r.Resident {
			return errors.Join(err, m.Capacity.Release(ctx, r))
		}
		return err
	}
	if err = m.begin(r, "resume"); err != nil {
		return err
	}
	// Runtime.Resume distinguishes a retained process from a saved checkpoint.
	err = m.Runtime.Resume(ctx, r)
	if err == nil {
		r.State = "running"
		r.Resident = true
		r.IdleAt = time.Now().UTC()
	}
	return m.finish(r, err)
}
func (m *Manager) Pause(ctx context.Context, id string) error {
	m.Gate.Lock()
	defer m.Gate.Unlock()
	r, err := m.get(id)
	if err != nil {
		return err
	}
	if r.State == "paused" && r.Operation == "" {
		return nil
	}
	if r.WorkerID != "" || m.active[id] > 0 {
		return errors.New("sandbox has active work")
	}
	if r.State != "running" || r.Operation != "" {
		return errors.New("sandbox is not running")
	}
	if err = m.begin(r, "pause"); err != nil {
		return err
	}
	err = m.Runtime.Pause(ctx, r)
	if err == nil {
		r.State = "paused"
		r.Resident = true
		r.IdleAt = time.Now().UTC()
	}
	return m.finish(r, err)
}
func (m *Manager) evict(ctx context.Context, r *Record) error {
	if !r.Resident || r.WorkerID != "" || m.active[r.SandboxID] > 0 {
		return nil
	}
	if err := m.begin(r, "evict"); err != nil {
		return err
	}
	if err := m.Runtime.Save(ctx, r); err != nil {
		return m.finish(r, err)
	}
	r.State = "paused"
	r.Resident = false
	r.PID = 0
	r.Instance = ""
	if err := m.finish(r, nil); err != nil {
		return err
	}
	return m.Capacity.Release(ctx, r)
}
func (m *Manager) Delete(ctx context.Context, id string) error {
	m.Gate.Lock()
	defer m.Gate.Unlock()
	if !validID(id) {
		return errors.New("invalid sandbox id")
	}
	r := m.records[id]
	if r == nil {
		return nil
	}
	if err := m.begin(r, "delete"); err != nil {
		return err
	}
	if err := m.Runtime.Delete(ctx, r); err != nil {
		return m.finish(r, err)
	}
	if err := m.Capacity.Release(ctx, r); err != nil {
		return m.finish(r, err)
	}
	if err := removeJournal(filepath.Join(m.Root, id+".json")); err != nil {
		return err
	}
	delete(m.records, id)
	m.publish()
	return nil
}

// Reports use a published copy, so a slow checkpoint cannot block WebSocket
// heartbeats or hide an in-flight reservation from the server.
func (m *Manager) publish() {
	out := make([]protocol.SandboxInfo, 0, len(m.records))
	for _, r := range m.records {
		out = append(out, r.Info())
	}
	m.published.Store(out)
}
func (m *Manager) Snapshot() []protocol.SandboxInfo {
	if snapshot := m.published.Load(); snapshot != nil {
		return append([]protocol.SandboxInfo{}, snapshot.([]protocol.SandboxInfo)...)
	}
	return []protocol.SandboxInfo{}
}

// Reconcile retries interrupted operations and checkpoints idle residents when
// CI demand is queued, unknown, stale, or their bounded grace expires.
func (m *Manager) Reconcile(ctx context.Context) error {
	m.Gate.Lock()
	defer m.Gate.Unlock()
	var errs []error
	grace := m.Grace
	if grace <= 0 || grace > time.Minute {
		grace = 30 * time.Second
	}
	for _, r := range m.records {
		if r.Operation == "release" {
			if err := m.Capacity.Release(ctx, r); err != nil {
				errs = append(errs, err)
				continue
			}
			r.Operation = ""
			if err := m.persist(r); err != nil {
				errs = append(errs, err)
			}
			continue
		}
		if r.State == "error" && !r.Resident && r.Operation == "" {
			continue
		}
		if r.Operation == "delete" {

			if err := m.Runtime.Delete(ctx, r); err != nil {
				errs = append(errs, err)
				continue
			}
			if err := m.Capacity.Release(ctx, r); err != nil {
				errs = append(errs, err)
				continue
			}
			if err := removeJournal(filepath.Join(m.Root, r.SandboxID+".json")); err != nil {
				errs = append(errs, err)
				continue
			}
			delete(m.records, r.SandboxID)
			m.publish()
			continue
		}
		if r.Operation != "" || r.State == "error" {

			if err := m.Runtime.Recover(ctx, r); err != nil {
				errs = append(errs, err)
				continue
			}
			if err := m.finish(r, nil); err != nil {
				errs = append(errs, err)
				continue
			}
		}
		if r.WorkerID != "" {
			status, err := m.Runtime.Worker(ctx, r, "status", nil)
			if err != nil {
				errs = append(errs, err)
				continue
			}
			if !status.Running && status.ID == r.WorkerID {
				r.FinishedWorkID = r.WorkerID
				r.WorkerID = ""
				r.IdleAt = time.Now().UTC()
				if err = m.persist(r); err != nil {
					errs = append(errs, err)
					continue
				}
				if m.Emit != nil {
					code := status.ExitCode
					m.Emit(protocol.Event{Event: protocol.EventWorkerExited, SandboxID: r.SandboxID, WorkID: status.ID, Generation: m.NodeUID, ExitCode: &code})
				}
			}
		}
		if r.Resident && r.WorkerID == "" && m.active[r.SandboxID] == 0 && (time.Since(r.IdleAt) >= grace || m.Capacity.Allow(ctx, r) != nil) {
			if err := m.evict(ctx, r); err != nil {
				errs = append(errs, err)
			}
		} else if r.State == "paused" && !r.Resident {
			if err := m.Capacity.Release(ctx, r); err != nil {
				errs = append(errs, err)
			}
		}
	}
	return errors.Join(errs...)
}
func (m *Manager) Exec(ctx context.Context, a protocol.ExecArgs, out func(protocol.Stream)) (protocol.ExecResult, error) {
	m.Gate.Lock()
	r, err := m.get(a.SandboxID)
	if err == nil && r.State == "paused" && r.Operation == "" {
		err = m.resume(ctx, r)
	}
	if err == nil && (r.State != "running" || r.Operation != "") {
		err = errors.New("sandbox is not running")
	}
	if err == nil {
		err = m.Capacity.Allow(ctx, r)
	}
	if err != nil {
		m.Gate.Unlock()
		return protocol.ExecResult{}, err
	}
	m.active[a.SandboxID]++
	copy := *r
	m.Gate.Unlock()
	defer func() {
		m.Gate.Lock()
		defer m.Gate.Unlock()
		m.active[a.SandboxID]--
		if m.records[a.SandboxID] != r {
			return
		}
		r.IdleAt = time.Now().UTC()
		_ = m.persist(r)
	}()
	return m.Runtime.Exec(ctx, &copy, a, out)
}
func (m *Manager) Worker(ctx context.Context, id, action string, env map[string]string) (WorkerStatus, error) {
	m.Gate.Lock()
	defer m.Gate.Unlock()
	r, err := m.get(id)
	if err != nil {
		return WorkerStatus{}, err
	}
	if action == "start" {
		if r.State == "paused" && r.Operation == "" {
			if err = m.resume(ctx, r); err != nil {
				return WorkerStatus{}, err
			}
		}
		if r.State != "running" || r.Operation != "" {
			return WorkerStatus{}, errors.New("sandbox is not running")
		}
		if err = m.Capacity.Allow(ctx, r); err != nil {
			return WorkerStatus{}, err
		}
		work := env["ANTHROPIC_WORK_ID"]
		if work == "" {
			return WorkerStatus{}, errors.New("worker identity is required")
		}
		if r.WorkerID != "" && r.WorkerID != work {
			return WorkerStatus{}, errors.New("another worker owns the sandbox")
		}
		r.WorkerID = work // Persist before sending credentials; retries use the same identity.
		if err = m.persist(r); err != nil {
			return WorkerStatus{}, err
		}
	}
	status, err := m.Runtime.Worker(ctx, r, action, env)
	// An uncertain start remains charged and busy until guest status proves exit.
	return status, err
}

func removeJournal(path string) error {
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}
