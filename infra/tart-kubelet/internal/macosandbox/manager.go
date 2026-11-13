// Package macosandbox owns persistent macOS sandbox VMs on one Kubernetes Node.
// Journals and execution Pods survive control-plane and kubelet restarts. A
// paused resident keeps its Pod and full charge until a checkpoint is fenced.
package macosandbox

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"sync"
	"sync/atomic"
	"time"

	"github.com/google/uuid"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"k8s.io/apimachinery/pkg/types"
)

var ErrCapacity = errors.New("macOS sandbox capacity unavailable")

// Runtime must fence its process before Save or Delete succeeds. Recover must
// never cold boot or accept an old checkpoint for a disk that has since run.
type Runtime interface {
	Create(context.Context, *Record) error
	// Warm boots a VM no sandbox owns yet; Claim finishes one for its
	// sandbox. Create is Warm followed by Claim.
	Warm(context.Context, *Record) error
	Claim(context.Context, *Record) error
	Busy(context.Context, *Record) (bool, error)
	Resume(context.Context, *Record) error
	Pause(context.Context, *Record) error
	Save(context.Context, *Record) error
	Delete(context.Context, *Record) error
	Recover(context.Context, *Record) error
	Exec(context.Context, *Record, protocol.ExecArgs, func(protocol.Stream)) (protocol.ExecResult, error)
	Worker(context.Context, *Record, string, map[string]string) (WorkerStatus, error)
	// GuestCPU is the guest's recent CPU use by its sandbox user, in
	// thousandths of one core.
	GuestCPU(context.Context, *Record) (int64, error)
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
	// Transfer moves a warm Pod's charge to the sandbox's execution
	// reservation: the reservation exists before the warm Pod is deleted.
	Transfer(ctx context.Context, r *Record, namespace, name string, uid types.UID) error
}

type Record struct {
	protocol.CreateArgs
	NodeUID     string `json:"node_uid"`
	State       string `json:"state"`
	Resident    bool   `json:"resident"`
	Instance    string `json:"instance,omitempty"`
	RuntimePath string `json:"runtime_path,omitempty"`
	ToolsPath   string `json:"tools_path,omitempty"`
	PID         int    `json:"pid,omitempty"`
	WorkerID    string `json:"worker_id,omitempty"`
	// HoldID is detached guest work the host cannot observe, such as an Amp
	// Orb's turn. It protects the running VM from idle eviction until a pause
	// or a release with the same ID, or until HoldUntil when that is set.
	HoldID         string    `json:"hold_id,omitempty"`
	HoldUntil      time.Time `json:"hold_until"`
	FinishedWorkID string    `json:"finished_work_id,omitempty"`
	IdleAt         time.Time `json:"idle_at"`
	CreatedAt      time.Time `json:"created_at"`
	Error          string    `json:"error,omitempty"`
	// Operation is persisted before side effects. Uncertain saves/restores are
	// reconciled against the runtime, never optimistically released.
	Operation string `json:"operation,omitempty"`
	// VM names a claimed warm VM (`sbw-<pod UID>`), which keeps the name and
	// env share it booted with. Cold-created sandboxes leave it empty.
	VM string `json:"vm,omitempty"`
	// WorkspaceVolumeGB is the quota of the workspace volume the VM already
	// has, 0 before it has one. Warm VMs add it before a sandbox claims them.
	WorkspaceVolumeGB int `json:"workspace_volume_gb,omitempty"`
	// CheckoutShare is the VM's checkout share, bound when it first boots, or
	// empty for a VM that booted without one (checkout.go).
	CheckoutShare string `json:"checkout_share,omitempty"`
	// Checkout is the grant of the session whose export the host takes at the
	// VM's next fence.
	Checkout *protocol.CheckoutGrant `json:"checkout,omitempty"`
}

// Warm VMs carry their own prefix: a host restart deletes the unclaimed ones
// instead of treating them as orphaned sandboxes.
const sandboxVMPrefix, warmVMPrefix = "sbx-", "sbw-"

func (r *Record) VMName() string {
	if r.VM != "" {
		return r.VM
	}
	return sandboxVMPrefix + r.SandboxID
}

// envName is the VM's env share directory, bound when it first boots.
func (r *Record) envName() string {
	if r.VM != "" {
		return r.VM
	}
	return r.SandboxID
}
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
	// Checkouts is nil on a host without the runner cache.
	Checkouts Checkouts
	// The same gate is used by the CI launcher. TryLock there avoids putting
	// a slow checkpoint or restore on the single Pod reconcile worker.
	Gate    sync.Mutex
	records map[string]*Record
	active  map[string]int
	// Ready and booting warm VMs by Pod UID, and whether one is booting.
	warm        map[types.UID]*warmVM
	warmBooting bool

	cpuMu sync.Mutex
	cpu   map[string]cpuReading
}

// cpuReading integrates sampled guest CPU use into a monotonic total, the
// `cpu_ms` the server compares between reports to tell an idle guest.
type cpuReading struct {
	ms int64
	at time.Time
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
	m.warm = map[types.UID]*warmVM{}
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
	if a.FromDiskSnapshot == "" && a.FromArchive == nil {
		if w := m.claimWarm(a); w != nil {
			return m.createOnWarm(ctx, a, w)
		}
	}
	r := &Record{RuntimePath: m.RuntimePath, ToolsPath: m.ToolsPath, CreateArgs: a, NodeUID: m.NodeUID, State: "creating", CreatedAt: time.Now().UTC(), IdleAt: time.Now().UTC()}
	// Recorded before the journal publishes it, so reports sent while the
	// reservation waits for CI list the sandbox.
	m.records[a.SandboxID] = r
	if err := m.begin(r, "create"); err != nil {
		delete(m.records, a.SandboxID)
		m.publish()
		return err
	}
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

// createOnWarm gives a sandbox a booted warm VM under the same
// grant as a cold create. Once the claim is journaled the VM is the
// sandbox's: a failure keeps its charge until Reconcile deletes the VM.
func (m *Manager) createOnWarm(ctx context.Context, a protocol.CreateArgs, w *warmVM) error {
	if err := m.Capacity.Allow(ctx, &Record{CreateArgs: a, NodeUID: m.NodeUID}); err != nil {
		m.warm[w.pod] = w
		return err
	}
	now := time.Now().UTC()
	r := &Record{RuntimePath: w.rec.RuntimePath, ToolsPath: w.rec.ToolsPath, CheckoutShare: w.rec.CheckoutShare, CreateArgs: a, NodeUID: m.NodeUID, State: "creating", VM: w.rec.VM, WorkspaceVolumeGB: w.rec.WorkspaceVolumeGB, Resident: true, CreatedAt: now, IdleAt: now}
	m.records[a.SandboxID] = r
	if err := m.begin(r, "claim"); err != nil {
		delete(m.records, a.SandboxID)
		m.publish()
		m.warm[w.pod] = w
		return err
	}
	if err := m.Capacity.Transfer(ctx, r, w.namespace, w.name, w.pod); err != nil {
		return m.finish(r, err)
	}
	err := m.Runtime.Claim(ctx, r)
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
	// A running VM already holds its charge; only a paused one asks for it.
	if r.State == "running" {
		return nil
	}
	if err = m.Capacity.Allow(ctx, r); err != nil {
		return err
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
		r.HoldID = "" // The held work paused with the VM; its owner asked for this pause.
		r.HoldUntil = time.Time{}
		r.IdleAt = time.Now().UTC()
	}
	return m.finish(r, err)
}
func (m *Manager) evict(ctx context.Context, r *Record) error {
	if !r.Resident || r.WorkerID != "" || r.HoldID != "" || m.active[r.SandboxID] > 0 {
		return nil
	}
	if err := m.begin(r, "evict"); err != nil {
		return err
	}
	if err := m.Runtime.Save(ctx, r); err != nil {
		return m.finish(r, err)
	}
	m.collectCheckout(r)
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
	out := []protocol.SandboxInfo{}
	if snapshot := m.published.Load(); snapshot != nil {
		out = append(out, snapshot.([]protocol.SandboxInfo)...)
	}
	m.cpuMu.Lock()
	defer m.cpuMu.Unlock()
	for i := range out {
		if reading, ok := m.cpu[out[i].ID]; ok && out[i].State == "running" {
			out[i].CPUMs = reading.ms
		}
	}
	return out
}

// The server's residency work ID, such as `amp:<orb id>`.
var holdIDPattern = regexp.MustCompile(`^[A-Za-z0-9_.:-]{1,255}$`)

// Hold protects a running sandbox from idle eviction for detached guest work,
// resuming it first like a worker start. A positive ttl ends the hold that
// long from now unless it is renewed; zero keeps it until a release or pause.
// A hold on a running VM takes no capacity it does not already hold, so it
// needs no grant; only resuming a paused one does.
func (m *Manager) Hold(ctx context.Context, id, work string, ttl time.Duration) error {
	m.Gate.Lock()
	defer m.Gate.Unlock()
	r, err := m.get(id)
	if err != nil {
		return err
	}
	if !holdIDPattern.MatchString(work) {
		return errors.New("invalid hold identity")
	}
	if r.State == "paused" && r.Operation == "" {
		if err = m.resume(ctx, r); err != nil {
			return err
		}
	}
	if r.State != "running" || r.Operation != "" {
		return errors.New("sandbox is not running")
	}
	until := time.Time{}
	if ttl > 0 {
		until = time.Now().UTC().Add(ttl)
	}
	r.HoldID = work
	r.HoldUntil = until
	return m.persist(r)
}

// Release ends a hold. Another ID, or none, is left alone, so a late release
// cannot end a newer turn's hold.
func (m *Manager) Release(id, work string) error {
	m.Gate.Lock()
	defer m.Gate.Unlock()
	r, err := m.get(id)
	if err != nil || r.HoldID != work {
		return err
	}
	r.HoldID = ""
	r.HoldUntil = time.Time{}
	r.IdleAt = time.Now().UTC()
	return m.persist(r)
}

// SampleCPU probes each running guest outside the host gate, so a slow guest
// never delays CI launch checks or pauses. A failed probe keeps the previous
// total: the server then sees no activity, as for a quiet guest.
func (m *Manager) SampleCPU(ctx context.Context) {
	m.Gate.Lock()
	running := []Record{}
	for _, r := range m.records {
		if r.State == "running" && r.Operation == "" {
			running = append(running, *r)
		}
	}
	m.Gate.Unlock()
	live := map[string]bool{}
	for i := range running {
		r := &running[i]
		live[r.SandboxID] = true
		probeCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
		permille, err := m.Runtime.GuestCPU(probeCtx, r)
		cancel()
		if err != nil {
			continue
		}
		now := time.Now()
		m.cpuMu.Lock()
		if m.cpu == nil {
			m.cpu = map[string]cpuReading{}
		}
		reading, ok := m.cpu[r.SandboxID]
		if ok {
			reading.ms += permille * now.Sub(reading.at).Milliseconds() / 1000
		}
		reading.at = now
		m.cpu[r.SandboxID] = reading
		m.cpuMu.Unlock()
	}
	m.cpuMu.Lock()
	for id := range m.cpu {
		if !live[id] {
			delete(m.cpu, id)
		}
	}
	m.cpuMu.Unlock()
}

// Reconcile retries interrupted operations and checkpoints idle residents once
// their bounded grace expires. CI and sandboxes are first come, first served:
// CI demand arriving later does not checkpoint a VM before its grace is up.
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
		// A create or claim still journaled here failed, and the server saw it
		// fail, so no one has used its guest. Delete it like an explicit delete
		// rather than holding its charge for one: a server that keeps the failed
		// row, or that this host cannot reach, never sends it.
		if r.Operation == "create" || r.Operation == "claim" {
			slog.Warn("deleting a macOS sandbox whose create did not finish", "sandbox", r.SandboxID, "operation", r.Operation, "error", r.Error)
			if err := m.begin(r, "delete"); err != nil {
				errs = append(errs, err)
				continue
			}
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
		// The server ends a timed hold itself; this only covers a server that
		// never does. The VM then waits out the idle grace like any other.
		if r.HoldID != "" && !r.HoldUntil.IsZero() && !time.Now().Before(r.HoldUntil) {
			slog.Info("a macOS sandbox hold expired", "sandbox", r.SandboxID, "hold", r.HoldID)
			r.HoldID = ""
			r.HoldUntil = time.Time{}
			r.IdleAt = time.Now().UTC()
			if err := m.persist(r); err != nil {
				errs = append(errs, err)
				continue
			}
		}
		if r.Resident && r.WorkerID == "" && r.HoldID == "" && m.active[r.SandboxID] == 0 && time.Since(r.IdleAt) >= grace {
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
	// Only a resume takes capacity, and resume asks for the grant. A running VM
	// already holds its charge, so its commands work while CI holds the grant;
	// eviction waits for them (active work).
	if err == nil && r.State == "paused" && r.Operation == "" {
		err = m.resume(ctx, r)
	}
	if err == nil && (r.State != "running" || r.Operation != "") {
		err = errors.New("sandbox is not running")
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
	return m.worker(ctx, id, action, env, nil)
}

// StartWorker starts a worker whose session has a checkout grant (checkout.go).
func (m *Manager) StartWorker(ctx context.Context, id string, env map[string]string, checkout *protocol.CheckoutGrant) (WorkerStatus, error) {
	return m.worker(ctx, id, "start", env, checkout)
}

func (m *Manager) worker(ctx context.Context, id, action string, env map[string]string, checkout *protocol.CheckoutGrant) (WorkerStatus, error) {
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
		work := env["ANTHROPIC_WORK_ID"]
		if work == "" {
			return WorkerStatus{}, errors.New("worker identity is required")
		}
		if r.WorkerID != "" && r.WorkerID != work {
			return WorkerStatus{}, errors.New("another worker owns the sandbox")
		}
		r.WorkerID = work // Persist before sending credentials; retries use the same identity.
		env = m.checkoutEnv(ctx, r, env, checkout)
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
