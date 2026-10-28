package macosandbox

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

type fakeRuntime struct {
	states                   map[string]string
	memory                   map[string]string
	busy                     bool
	worker                   WorkerStatus
	saveErr, errorRecovery   error
	saveStarted, saveRelease chan struct{}
	creates                  int
}

func (f *fakeRuntime) Create(_ context.Context, r *Record) error {
	f.creates++
	f.states[r.SandboxID] = "running"
	f.memory[r.SandboxID] = "in-memory-session"
	return nil
}
func (f *fakeRuntime) Resume(_ context.Context, r *Record) error {
	if f.states[r.SandboxID] != "paused" && f.states[r.SandboxID] != "evicted" {
		return errors.New("not paused")
	}
	f.states[r.SandboxID] = "running"
	return nil
}
func (f *fakeRuntime) Pause(_ context.Context, r *Record) error {
	if f.busy {
		return errors.New("busy")
	}
	f.states[r.SandboxID] = "paused"
	return nil
}
func (f *fakeRuntime) Save(ctx context.Context, r *Record) error {
	if f.saveStarted != nil {
		close(f.saveStarted)
		select {
		case <-f.saveRelease:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	if f.saveErr != nil {
		return f.saveErr
	}
	f.states[r.SandboxID] = "evicted"
	return nil
}
func (f *fakeRuntime) Delete(_ context.Context, r *Record) error {
	delete(f.states, r.SandboxID)
	delete(f.memory, r.SandboxID)
	return nil
}
func (f *fakeRuntime) Recover(_ context.Context, r *Record) error {
	if f.errorRecovery != nil {
		return f.errorRecovery
	}
	state, ok := f.states[r.SandboxID]
	if !ok {
		return errors.New("missing VM")
	}
	r.State = state
	r.Resident = true
	if state == "evicted" {
		r.State = "paused"
		r.Resident = false
	}
	return nil
}
func (f *fakeRuntime) Busy(context.Context, *Record) (bool, error) { return f.busy, nil }
func (f *fakeRuntime) Exec(_ context.Context, r *Record, _ protocol.ExecArgs, _ func(protocol.Stream)) (protocol.ExecResult, error) {
	if f.memory[r.SandboxID] != "in-memory-session" {
		return protocol.ExecResult{}, errors.New("memory lost")
	}
	return protocol.ExecResult{}, nil
}
func (f *fakeRuntime) Worker(_ context.Context, r *Record, action string, _ map[string]string) (WorkerStatus, error) {
	if action == "start" {
		f.worker = WorkerStatus{Running: true, ID: r.WorkerID}
	}
	if action == "stop" {
		f.worker.Running = false
	}
	return f.worker, nil
}

type fakeCapacity struct {
	allow      bool
	held       map[string]bool
	releaseErr error
}

func (f *fakeCapacity) Reserve(ctx context.Context, r *Record) error {
	if err := f.Allow(ctx, r); err != nil {
		return err
	}
	if len(f.held) >= 1 && !f.held[r.SandboxID] {
		return ErrCapacity
	}
	f.held[r.SandboxID] = true
	return nil
}
func (f *fakeCapacity) Allow(context.Context, *Record) error {
	if !f.allow {
		return ErrCapacity
	}
	return nil
}
func (f *fakeCapacity) Release(_ context.Context, r *Record) error {
	if f.releaseErr != nil {
		return f.releaseErr
	}
	delete(f.held, r.SandboxID)
	return nil
}
func harness(t *testing.T) (*Manager, *fakeRuntime, *fakeCapacity, protocol.CreateArgs) {
	t.Helper()
	runtime := &fakeRuntime{states: map[string]string{}, memory: map[string]string{}}
	capacity := &fakeCapacity{allow: true, held: map[string]bool{}}
	manager := &Manager{Root: t.TempDir(), NodeUID: "node-1", RuntimePath: "/runtime/pinned", ToolsPath: "/tools/pinned", Runtime: runtime, Capacity: capacity}
	if err := manager.Load(context.Background()); err != nil {
		t.Fatal(err)
	}
	return manager, runtime, capacity, protocol.CreateArgs{SandboxID: uuid.NewString(), Template: "macos", VCPUs: 8, MemoryMB: 8192, WorkspaceGB: 10}
}
func TestResidentPauseRetainsCapacityAndMemoryAcrossRecovery(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if err := m.Pause(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	if !c.held[a.SandboxID] || !m.Snapshot()[0].Resident {
		t.Fatal("pause released resident charge")
	}
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c}
	if err := recovered.Load(ctx); err != nil {
		t.Fatal(err)
	}
	if err := recovered.Resume(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	if _, err := recovered.Exec(ctx, protocol.ExecArgs{SandboxID: a.SandboxID}, nil); err != nil {
		t.Fatal(err)
	}
	if r.creates != 1 {
		t.Fatal("recovery cold booted the sandbox")
	}
	if err := recovered.Delete(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	if len(c.held) != 0 || len(recovered.Snapshot()) != 0 {
		t.Fatal("delete leaked ownership")
	}
}
func TestCIRevocationEvictsOnlyIdleAndRetainsFailedFence(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Worker(ctx, a.SandboxID, "start", map[string]string{"ANTHROPIC_WORK_ID": "work-1"}); err != nil {
		t.Fatal(err)
	}
	c.allow = false
	if err := m.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if !c.held[a.SandboxID] {
		t.Fatal("CI interrupted active work")
	}
	r.worker.Running = false
	r.saveErr = errors.New("checkpoint failed")
	if err := m.Reconcile(ctx); err == nil {
		t.Fatal("expected save failure")
	}
	if !c.held[a.SandboxID] {
		t.Fatal("failed checkpoint freed capacity")
	}
	r.saveErr = nil
	if err := m.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if c.held[a.SandboxID] || m.Snapshot()[0].Resident {
		t.Fatal("successful eviction kept charge")
	}
	if err := m.Resume(ctx, a.SandboxID); !errors.Is(err, ErrCapacity) {
		t.Fatalf("resume admitted while CI queued: %v", err)
	}
}
func TestConcurrentCreatesCannotOverbookLastSlot(t *testing.T) {
	m, r, c, a := harness(t)
	var wg sync.WaitGroup
	success := make(chan string, 2)
	for i := 0; i < 2; i++ {
		a := a
		a.SandboxID = uuid.NewString()
		wg.Add(1)
		go func() {
			defer wg.Done()
			if m.Create(context.Background(), a) == nil {
				success <- a.SandboxID
			}
		}()
	}
	wg.Wait()
	if len(success) != 1 || r.creates != 1 || len(c.held) != 1 {
		t.Fatalf("overbooked: successes %d creates %d charges %d", len(success), r.creates, len(c.held))
	}
}
func TestReportsAndCILaunchDoNotWaitForCheckpoint(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	c.allow = false
	r.saveStarted = make(chan struct{})
	r.saveRelease = make(chan struct{})
	done := make(chan error, 1)
	go func() { done <- m.Reconcile(ctx) }()
	<-r.saveStarted
	s := &Service{manager: m, ready: true}
	started := time.Now()
	if _, err := s.LaunchGuard(ctx, "ci"); !errors.Is(err, ErrCapacity) {
		t.Fatal(err)
	}
	if len(m.Snapshot()) != 1 || time.Since(started) > 100*time.Millisecond {
		t.Fatal("slow checkpoint blocked CI worker or heartbeat")
	}
	close(r.saveRelease)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}
func TestRecoveryRefusesWrongOwnerAndNeverFreesUnknownVM(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	wrong := &Manager{Root: m.Root, NodeUID: "replacement", Runtime: r, Capacity: c}
	if wrong.Load(ctx) == nil {
		t.Fatal("accepted previous Node incarnation")
	}
	r.errorRecovery = errors.New("runtime unreachable")
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c}
	if err := recovered.Load(ctx); err != nil {
		t.Fatal(err)
	}
	if !c.held[a.SandboxID] || recovered.Snapshot()[0].State != "error" {
		t.Fatal("unknown VM became free capacity")
	}
}
func TestInterruptedDeleteIsRetriedAfterRestart(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	c.releaseErr = errors.New("API unavailable")
	if m.Delete(ctx, a.SandboxID) == nil {
		t.Fatal("expected failure")
	}
	c.releaseErr = nil
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c}
	if err := recovered.Load(ctx); err != nil {
		t.Fatal(err)
	}
	if err := recovered.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if len(c.held) != 0 {
		t.Fatal("reservation leaked")
	}
	if _, err := os.Stat(filepath.Join(m.Root, a.SandboxID+".json")); !os.IsNotExist(err) {
		t.Fatal("journal leaked")
	}
}
func TestDispatchFencesOwnerAndKeepsCredentialsOutOfJournal(t *testing.T) {
	m, _, _, a := harness(t)
	ctx := context.Background()
	data, _ := json.Marshal(a)
	result := m.Dispatch(ctx, protocol.Command{Op: protocol.OpCreate, Args: data}, nil)
	if result.OK {
		t.Fatal("missing generation accepted")
	}
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Worker(ctx, a.SandboxID, "start", map[string]string{"ANTHROPIC_WORK_ID": "work-1", "ANTHROPIC_WORK_SECRET": "never-store-me"}); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(m.Root, a.SandboxID+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var journal map[string]any
	if err = json.Unmarshal(data, &journal); err != nil {
		t.Fatal(err)
	}
	if journal["env"] != nil {
		t.Fatal("credentials persisted")
	}
	if journal["runtime_path"] != "/runtime/pinned" || journal["tools_path"] != "/tools/pinned" {
		t.Fatal("runtime compatibility was not pinned")
	}
}

func TestFailedPrelaunchReservationReleaseRetriesWithoutVM(t *testing.T) {
	m, r, c, a := harness(t)
	c.allow = false
	c.releaseErr = errors.New("API unavailable")
	if m.Create(context.Background(), a) == nil {
		t.Fatal("expected admission failure")
	}
	if r.creates != 0 || !m.Snapshot()[0].Resident {
		t.Fatal("unresolved reservation not retained")
	}
	c.releaseErr = nil
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c}
	if err := recovered.Load(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := recovered.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	if recovered.Snapshot()[0].Resident || recovered.records[a.SandboxID].Operation != "" {
		t.Fatal("release did not settle")
	}
}
func TestEmptyReportIsAnArraySoMissingVMsAreReconciled(t *testing.T) {
	m, _, _, _ := harness(t)
	data, err := json.Marshal(m.Snapshot())
	if err != nil || string(data) != "[]" {
		t.Fatalf("missing ownership report: %s %v", data, err)
	}
}
